extends SceneTree
## Non-fatal hit: bone mapping, capped impulse, chain loosening and recovery, fade-out,
## single hit_received, live movement, and rejection of invalid hits.
const Support = preload("res://modules/liberty_character/tests/liberty_test_support.gd")
const PA = preload("res://modules/liberty_character/ragdoll/liberty_physical_animation.gd")
var hits: Array = []

func _initialize() -> void: call_deferred("run")

func tick(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame

func velocity(body: PhysicalBone3D) -> Vector3:
	return PhysicsServer3D.body_get_state(body.get_rid(), PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)

func gravity_restored(ragdoll: LibertyRagdoll) -> bool:
	for body in ragdoll.get_physical_bones():
		if not is_equal_approx(PhysicsServer3D.body_get_param(body.get_rid(), PhysicsServer3D.BODY_PARAM_GRAVITY_SCALE), 1.0): return false
	return true

func run() -> void:
	var fixture := Node3D.new()
	root.add_child(fixture)
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(100, .4, 100)
	shape.shape = box
	floor_body.add_child(shape)
	fixture.add_child(floor_body)
	floor_body.position = Vector3(0, -.2, 0)
	var character = load("res://modules/liberty_character/character/liberty_character.tscn").instantiate()
	fixture.add_child(character)
	await tick(4)
	var ragdoll: LibertyRagdoll = character.get_node("Ragdoll")
	var stage: LibertyPhysicalAnimation = ragdoll.physical_animation
	var events: LibertyEvents = character.get_node("Events")
	events.hit_received.connect(func(bone: StringName, direction: Vector3, force: float, fatal: bool): hits.append([bone, direction, force, fatal]))

	# Invalid hits are rejected silently.
	Support.expect_false(character.receive_hit(&"Tail", Vector3.FORWARD, 20.0, false), "unknown bone is rejected")
	Support.expect_false(character.receive_hit(&"LeftHand", Vector3(NAN, 0, 0), 20.0, false), "non-finite direction is rejected")
	Support.expect_false(character.receive_hit(&"LeftHand", Vector3.FORWARD, INF, false), "non-finite force is rejected")
	Support.expect_true(hits.is_empty() and not ragdoll.is_reacting(), "rejected hits emit nothing and start nothing")

	# Hand hit: the left arm chain loosens, the forearm takes a capped push.
	var forearm := ragdoll.get_physical_bone(&"LeftLowerArm")
	var direction := Vector3(1, 0, -1).normalized()
	Support.expect_true(character.receive_hit(&"LeftHand", direction, 30.0, false), "non-fatal hit accepted")
	Support.expect_equal(ragdoll.get_reaction_bones(), PA.simulated_bodies([&"left_arm"]), "hand hit simulates the left arm subtree")
	Support.expect_true(is_equal_approx(stage.chain_strength[&"left_arm"], stage.hit_strength), "hit chain drops to hit strength")
	for chain: StringName in [&"core", &"right_arm", &"left_leg", &"right_leg"]:
		Support.expect_equal(stage.chain_strength[chain], 1.0, "%s stays at full strength" % chain)
	var push := velocity(forearm).dot(direction)
	print("forearm push %.3f m/s (cap %.1f)" % [push, stage.max_hit_delta_v])
	Support.expect_true(absf(push - stage.max_hit_delta_v) < .2, "impulse is capped at mass * max_hit_delta_v")
	Support.expect_equal(hits, [[&"LeftHand", direction, 30.0, false]], "hit_received emitted once with the requested values")
	Support.expect_false(character.is_movement_locked(), "a hit reaction does not lock movement")
	await tick(18)
	var mid: float = stage.chain_strength[&"left_arm"]
	await tick(18)
	var late: float = stage.chain_strength[&"left_arm"]
	print("strength at 0.3 s %.3f, 0.6 s %.3f" % [mid, late])
	Support.expect_true(absf(mid - PA.strength_at(.3, stage.hit_strength, stage.hit_recovery_time)) < .05, "strength follows the recovery curve")
	Support.expect_true(is_equal_approx(late, 1.0), "strength is full after hit_recovery_time")
	var stopped_at := -1
	for i in 40:
		await tick(1)
		if not ragdoll.is_reacting():
			stopped_at = i
			break
	print("reaction ended %.3f s after full strength" % (stopped_at / 60.0))
	Support.expect_true(stopped_at >= 0 and stopped_at <= int(ceil(stage.fade_out_time * 60.0)) + 2, "influence fades out and the reaction ends")
	Support.expect_false(ragdoll.simulator.is_simulating_physics(), "simulation stopped after the fade")
	Support.expect_equal(ragdoll.simulator.influence, 0.0, "influence at zero")
	Support.expect_true(gravity_restored(ragdoll), "gravity scale restored")
	for bone: StringName in PA.simulated_bodies([&"left_arm"]):
		Support.expect_false(stage.is_drive_enabled(bone), "%s drive disabled after the reaction" % bone)
	Support.expect_equal(hits.size(), 1, "no further hit events")

	# Hip hit loosens the core; movement keeps working; a leg hit extends the reaction.
	hits.clear()
	var spine := ragdoll.get_physical_bone(&"Spine")
	Support.expect_true(character.receive_hit(&"Hips", Vector3.RIGHT, 500.0, false), "hip hit accepted")
	Support.expect_equal(ragdoll.get_reaction_bones(), PA.simulated_bodies([&"core"]), "hip hit simulates the core subtree")
	Support.expect_true(is_equal_approx(stage.chain_strength[&"core"], stage.hit_strength), "core loosened")
	Support.expect_true(absf(velocity(spine).dot(Vector3.RIGHT) - stage.max_hit_delta_v) < .2, "hip impulse lands on Spine")
	Input.action_press(&"liberty_move_forward")
	await tick(10)
	Support.expect_true(character.receive_hit(&"RightToes", Vector3.BACK, 10.0, false), "second hit accepted")
	Support.expect_equal(ragdoll.get_reaction_bones(), PA.simulated_bodies([&"core", &"right_leg"]), "second chain extends the reaction")
	await tick(20)
	Support.expect_true(character.planar_speed > 1.5, "the capsule keeps moving during a reaction (%.2f m/s)" % character.planar_speed)
	Support.expect_equal(hits.size(), 2, "one event per hit")
	Input.action_release(&"liberty_move_forward")
	for i in 90:
		await tick(1)
		if not ragdoll.is_reacting(): break
	Support.expect_false(ragdoll.is_reacting(), "multi-chain reaction ends")
	Support.expect_equal(stage.last_guard_trip, "", "no instability during hits")
	character.queue_free()
	quit(Support.exit_code())
