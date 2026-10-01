extends SceneTree
const Support = preload("res://modules/liberty_character/tests/liberty_test_support.gd")
const Candidate = preload("res://modules/liberty_character/traversal/liberty_traversal_candidate.gd")
var started: Array[StringName] = []
func _initialize() -> void: call_deferred("run")
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
func tick(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame
func run() -> void:
	var fixture := Node3D.new()
	root.add_child(fixture)
	box(fixture, Vector3(0, -.2, 0), Vector3(30, .4, 30), 1)
	box(fixture, Vector3(0, 3, -1.15), Vector3(20, 6, .6), 9)
	var character = load("res://modules/liberty_character/character/liberty_character.tscn").instantiate()
	fixture.add_child(character)
	await tick(2)
	var coordinator = character.get_node("Traversal")
	var ragdoll: LibertyRagdoll = character.get_node("Ragdoll")
	var events: LibertyEvents = character.get_node("Events")
	events.ragdoll_started.connect(func(reason: StringName): started.append(reason))
	coordinator.set_physics_process(false)
	var hold: LibertyTraversalCandidate
	for c in coordinator.probe.sample(character.global_transform, true):
		if c.kind == Candidate.Kind.HANG: hold = c; break
	Support.expect_true(hold != null and coordinator.begin_action(hold, false), "fixture enters a traversal action")
	await tick(65)
	Support.expect_true(character.is_traversal_locked(), "fixture hangs before knockout")
	Support.expect_true(coordinator.ik.left_arm_ik.active, "hang uses limb IK")
	var skeleton: Skeleton3D = character.find_child("Skeleton3D", true, false)
	var captured := {}
	for body in ragdoll.get_physical_bones():
		captured[body] = skeleton.global_transform * ragdoll.pose_capture.get_captured_pose(body.get_bone_id()) * body.body_offset
	var direction := Vector3(1, 0, 2).normalized()
	var force := 180.0
	Support.expect_true(character.activate_ragdoll(direction, force, &"test_knockout"), "activation succeeds")
	# Same-tick assertions: one call clears traversal, movement and IK.
	Support.expect_false(character.is_traversal_locked(), "traversal lock cleared")
	Support.expect_equal(coordinator.controller.selected_candidate, null, "traversal candidate cleared")
	Support.expect_false(coordinator.ik.left_arm_ik.active, "IK cleared")
	Support.expect_true(character.is_movement_locked(), "ordinary movement disabled")
	Support.expect_true((character.get_node("CollisionShape3D") as CollisionShape3D).disabled, "capsule collision disabled")
	Support.expect_true(ragdoll.simulator.is_simulating_physics(), "simulation started")
	Support.expect_equal(started, [&"test_knockout"], "ragdoll_started emitted once with reason")
	var max_start_error := 0.0
	for body in ragdoll.get_physical_bones():
		var server: Transform3D = PhysicsServer3D.body_get_state(body.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM)
		max_start_error = maxf(max_start_error, server.origin.distance_to((captured[body] as Transform3D).origin))
	print("max body start error from captured pose = ", max_start_error)
	Support.expect_true(max_start_error < .01, "bodies start at the captured IK pose")
	var momentum := Vector3.ZERO
	for body in ragdoll.get_physical_bones():
		# Node velocity lags one step; the server reflects the impulse immediately.
		momentum += (PhysicsServer3D.body_get_state(body.get_rid(), PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY) as Vector3) * body.mass
	var horizontal := Vector3(momentum.x, 0, momentum.z)
	print("horizontal momentum after activation = ", horizontal.length(), " requested ", force)
	Support.expect_true(absf(horizontal.length() - force) < force * .01, "total impulse equals requested force")
	Support.expect_true(horizontal.normalized().dot(direction) > .999, "impulse follows requested direction")
	var start: Vector3 = character.global_position
	await tick(30)
	Support.expect_true(character.global_position.distance_to(start) < .001, "suspended character body never moves")
	Support.expect_equal(character.movement_state_name, &"movement_locked", "state reports movement lock")
	Support.expect_false(character.is_traversal_locked(), "traversal cannot reengage while ragdolled")
	character.queue_free()
	quit(Support.exit_code())
