extends SceneTree
## Fatal hits hand over to the passive ragdoll (from idle and mid-reaction); hits while
## ragdolled; a non-fatal hit knocks a hanging character off the wall.
const Support = preload("res://modules/liberty_character/tests/liberty_test_support.gd")
const Candidate = preload("res://modules/liberty_character/traversal/liberty_traversal_candidate.gd")
var log: Array = []

func _initialize() -> void: call_deferred("run")

func tick(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame

func box(parent: Node3D, position: Vector3, size: Vector3, layer: int) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = layer
	var shape := CollisionShape3D.new()
	var resource := BoxShape3D.new()
	resource.size = size
	shape.shape = resource
	body.add_child(shape)
	parent.add_child(body)
	body.position = position
	return body

func spawn(fixture: Node3D, at: Vector3) -> LibertyCharacter:
	var character: LibertyCharacter = load("res://modules/liberty_character/character/liberty_character.tscn").instantiate()
	fixture.add_child(character)
	character.teleport_to(Transform3D(Basis.IDENTITY, at))
	var events: LibertyEvents = character.get_node("Events")
	log.clear()
	events.ragdoll_started.connect(func(reason: StringName): log.append([&"ragdoll_started", reason]))
	events.hit_received.connect(func(bone: StringName, _d: Vector3, _f: float, fatal: bool): log.append([&"hit_received", bone, fatal]))
	return character

func all_simulating(ragdoll: LibertyRagdoll) -> bool:
	for body in ragdoll.get_physical_bones():
		if not body.is_simulating_physics(): return false
	return true

func gravity_restored(ragdoll: LibertyRagdoll) -> bool:
	for body in ragdoll.get_physical_bones():
		if not is_equal_approx(PhysicsServer3D.body_get_param(body.get_rid(), PhysicsServer3D.BODY_PARAM_GRAVITY_SCALE), 1.0): return false
	return true

func run() -> void:
	var fixture := Node3D.new()
	root.add_child(fixture)
	box(fixture, Vector3(0, -.2, 0), Vector3(80, .4, 80), 1)
	box(fixture, Vector3(20, 3, -1.15), Vector3(20, 6, .6), 9) # Climbable wall (layers 1 + 4).

	# Fatal hit from idle: passive ragdoll first, then the hit event.
	var character := spawn(fixture, Vector3(-20, 0, 0))
	await tick(4)
	var ragdoll: LibertyRagdoll = character.get_node("Ragdoll")
	Support.expect_true(character.receive_hit(&"Chest", Vector3.BACK, 150.0, true), "fatal hit accepted")
	Support.expect_true(ragdoll.is_active() and character.is_body_suspended(), "fatal hit starts the passive ragdoll")
	Support.expect_equal(log, [[&"ragdoll_started", &"hit"], [&"hit_received", &"Chest", true]], "ragdoll_started then hit_received(fatal)")
	# A non-fatal hit while still collapsing pushes the body and reports it.
	log.clear()
	var chest := ragdoll.get_physical_bone(&"Chest") # Neck resolves up to the Chest body.
	var before: Vector3 = PhysicsServer3D.body_get_state(chest.get_rid(), PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
	Support.expect_true(character.receive_hit(&"Neck", Vector3.RIGHT, 100.0, false), "hit while ragdolled accepted")
	var after: Vector3 = PhysicsServer3D.body_get_state(chest.get_rid(), PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
	Support.expect_true(absf((after - before).dot(Vector3.RIGHT) - 4.0) < .2, "hit while ragdolled pushes the mapped body (capped)")
	Support.expect_false(ragdoll.is_reacting(), "no reaction starts while ragdolled")
	Support.expect_equal(log, [[&"hit_received", &"Neck", false]], "hit while ragdolled reports once")
	# During the get-up blend a hit is rejected.
	var blending := false
	for i in 900:
		await tick(1)
		if ragdoll.state == LibertyRagdoll.State.BLENDING_OUT:
			blending = true
			break
	Support.expect_true(blending, "fixture reaches the get-up blend")
	log.clear()
	Support.expect_false(character.receive_hit(&"Head", Vector3.RIGHT, 50.0, false), "hit during get-up is rejected")
	Support.expect_true(log.is_empty(), "rejected hit emits nothing")
	character.queue_free()
	await tick(2)

	# Fatal hit mid-reaction: every body goes passive without resets.
	character = spawn(fixture, Vector3(-10, 0, 0))
	await tick(4)
	ragdoll = character.get_node("Ragdoll")
	var stage: LibertyPhysicalAnimation = ragdoll.physical_animation
	Support.expect_true(character.receive_hit(&"LeftHand", Vector3.FORWARD, 20.0, false), "reaction starts")
	await tick(6)
	var arm := ragdoll.get_physical_bone(&"LeftLowerArm")
	var arm_before: Transform3D = PhysicsServer3D.body_get_state(arm.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM)
	log.clear()
	Support.expect_true(character.receive_hit(&"Spine", Vector3.FORWARD, 150.0, true), "fatal hit during a reaction")
	var arm_after: Transform3D = PhysicsServer3D.body_get_state(arm.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM)
	Support.expect_true(arm_before.origin.distance_to(arm_after.origin) < .001, "running bodies are not reset by the takeover")
	Support.expect_true(ragdoll.is_active() and all_simulating(ragdoll), "every body simulates passively")
	Support.expect_false(stage.is_tracking(), "tracking disengages")
	for bone: StringName in [&"LeftUpperArm", &"LeftLowerArm"]:
		Support.expect_false(stage.is_drive_enabled(bone), "%s drive released on takeover" % bone)
	Support.expect_true(gravity_restored(ragdoll), "gravity scale restored on takeover")
	Support.expect_equal(log, [[&"ragdoll_started", &"hit"], [&"hit_received", &"Spine", true]], "takeover event order")
	character.queue_free()
	await tick(2)

	# Knock-off: a non-fatal hit while hanging releases the wall and falls.
	character = spawn(fixture, Vector3(20, 0, 0))
	await tick(2)
	ragdoll = character.get_node("Ragdoll")
	var coordinator = character.get_node("Traversal")
	coordinator.set_physics_process(false)
	var hold: LibertyTraversalCandidate
	for c in coordinator.probe.sample(character.global_transform, true):
		if c.kind == Candidate.Kind.HANG: hold = c; break
	Support.expect_true(hold != null and coordinator.begin_action(hold, false), "fixture enters a hang")
	await tick(65)
	Support.expect_true(character.is_traversal_locked(), "fixture hangs before the hit")
	coordinator.set_physics_process(true)
	var hang_height := character.global_position.y
	log.clear()
	Support.expect_true(character.receive_hit(&"RightHand", Vector3.BACK, 10.0, false), "hit while hanging accepted")
	Support.expect_false(character.is_traversal_locked(), "the hit knocks the character off the wall")
	Support.expect_true(ragdoll.is_reacting(), "the reaction plays")
	Support.expect_false(character.is_ragdoll_active(), "a non-fatal knock-off is not a ragdoll")
	var airborne := false
	var landed := false
	for i in 120:
		await tick(1)
		airborne = airborne or character.movement_state_name == &"airborne"
		if airborne and character.is_on_floor():
			landed = true
			break
	print("knock-off: hang height %.2f m, airborne %s, landed %s, now %.2f m" % [hang_height, airborne, landed, character.global_position.y])
	Support.expect_true(airborne, "the character falls after the knock-off")
	Support.expect_true(landed and character.global_position.y < .1, "the character lands on the floor")
	Support.expect_false(character.is_traversal_locked(), "traversal does not re-catch during the fall")
	Support.expect_equal(log, [[&"hit_received", &"RightHand", false]], "knock-off reports one non-fatal hit")
	Support.expect_equal(ragdoll.physical_animation.last_guard_trip, "", "no instability")
	character.queue_free()
	quit(Support.exit_code())
