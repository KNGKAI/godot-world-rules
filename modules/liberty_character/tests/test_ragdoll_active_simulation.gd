extends SceneTree
## Owned LibertyRagdoll commands for hit-reaction (partial, non-suspending) simulation.
const Support = preload("res://modules/liberty_character/tests/liberty_test_support.gd")
const PA = preload("res://modules/liberty_character/ragdoll/liberty_physical_animation.gd")

func _initialize() -> void: call_deferred("run")

func tick(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame

func server_transform(body: PhysicalBone3D) -> Transform3D:
	return PhysicsServer3D.body_get_state(body.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM)

func gravity_scale(body: PhysicalBone3D) -> float:
	return PhysicsServer3D.body_get_param(body.get_rid(), PhysicsServer3D.BODY_PARAM_GRAVITY_SCALE)

func all_gravity_restored(ragdoll: LibertyRagdoll) -> bool:
	for body in ragdoll.get_physical_bones():
		if not is_equal_approx(gravity_scale(body), 1.0): return false
	return true

func run() -> void:
	var fixture := Node3D.new()
	root.add_child(fixture)
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60, .4, 60)
	shape.shape = box
	floor_body.add_child(shape)
	fixture.add_child(floor_body)
	floor_body.position = Vector3(0, -.2, 0)
	var character = load("res://modules/liberty_character/character/liberty_character.tscn").instantiate()
	fixture.add_child(character)
	await tick(3)
	var ragdoll: LibertyRagdoll = character.get_node("Ragdoll")
	var skeleton := ragdoll.skeleton
	var capsule := character.get_node("CollisionShape3D") as CollisionShape3D
	var core := PA.simulated_bodies([&"core"])

	# Begin: only the listed subtree simulates; the character stays live.
	var captured := {}
	for body in ragdoll.get_physical_bones():
		captured[body] = skeleton.global_transform * ragdoll.pose_capture.get_captured_pose(body.get_bone_id()) * body.body_offset
	Support.expect_true(ragdoll.begin_active_simulation(core), "reaction simulation begins")
	Support.expect_true(ragdoll.is_reacting(), "ragdoll reports a reaction")
	Support.expect_false(ragdoll.is_active(), "a reaction is not the passive ragdoll")
	Support.expect_false(character.is_ragdoll_active(), "character is not ragdolled")
	Support.expect_false(capsule.disabled, "capsule stays enabled")
	Support.expect_false(character.is_movement_locked(), "movement stays live")
	Support.expect_true(ragdoll.simulator.is_simulating_physics(), "simulator runs")
	Support.expect_equal(ragdoll.simulator.influence, 1.0, "reaction starts at full influence")
	var start_error := 0.0
	for body in ragdoll.get_physical_bones():
		var name := StringName(body.bone_name)
		Support.expect_equal(body.is_simulating_physics(), core.has(name), "%s simulation matches the core subtree" % name)
		if core.has(name):
			start_error = maxf(start_error, server_transform(body).origin.distance_to((captured[body] as Transform3D).origin))
	print("reaction body start error %.5f m" % start_error)
	Support.expect_true(start_error < .01, "reaction bodies start at the captured pose")
	Support.expect_equal(ragdoll.get_reaction_bones(), core, "reaction bones are recorded parent-first")

	# Extend: new bodies join without resetting running ones.
	await tick(5)
	var chest := ragdoll.get_physical_bone(&"Chest")
	var before := server_transform(chest)
	Support.expect_true(ragdoll.extend_active_simulation(PA.simulated_bodies([&"left_leg"])), "reaction extends")
	Support.expect_true(server_transform(chest).origin.distance_to(before.origin) < .001, "extension does not reset running bodies")
	Support.expect_true(ragdoll.get_physical_bone(&"LeftFoot").is_simulating_physics(), "extended leg simulates")
	Support.expect_false(ragdoll.get_physical_bone(&"Hips").is_simulating_physics(), "hips stay kinematic")
	Support.expect_false(ragdoll.extend_active_simulation([&"Hips"]) and ragdoll.get_physical_bone(&"Hips").is_simulating_physics(), "hips never join a reaction")

	# Influence is owned here; end restores everything.
	ragdoll.set_reaction_influence(.4)
	Support.expect_true(is_equal_approx(ragdoll.simulator.influence, .4), "reaction influence command")
	PhysicsServer3D.body_set_param(chest.get_rid(), PhysicsServer3D.BODY_PARAM_GRAVITY_SCALE, 0.0)
	ragdoll.end_active_simulation()
	Support.expect_false(ragdoll.is_reacting(), "reaction ended")
	Support.expect_false(ragdoll.simulator.is_simulating_physics(), "simulation stopped")
	Support.expect_equal(ragdoll.simulator.influence, 0.0, "influence cleared")
	Support.expect_true(all_gravity_restored(ragdoll), "gravity scale restored on end")

	# Teleport cancels a reaction.
	Support.expect_true(ragdoll.begin_active_simulation(PA.simulated_bodies([&"right_arm"])), "second reaction begins")
	PhysicsServer3D.body_set_param(ragdoll.get_physical_bone(&"RightUpperArm").get_rid(), PhysicsServer3D.BODY_PARAM_GRAVITY_SCALE, 0.0)
	character.teleport_to(Transform3D(Basis.IDENTITY, Vector3(2, 0, 0)))
	Support.expect_false(ragdoll.is_reacting(), "teleport cancels the reaction")
	Support.expect_false(ragdoll.simulator.is_simulating_physics(), "teleport stops the simulation")
	Support.expect_true(all_gravity_restored(ragdoll), "gravity scale restored on teleport")
	await tick(3)

	# Passive activation from a running reaction takes over every body without resets.
	Support.expect_true(ragdoll.begin_active_simulation(PA.simulated_bodies([&"left_arm"])), "third reaction begins")
	await tick(5)
	var arm := ragdoll.get_physical_bone(&"LeftLowerArm")
	PhysicsServer3D.body_set_param(arm.get_rid(), PhysicsServer3D.BODY_PARAM_GRAVITY_SCALE, 0.0)
	var arm_before := server_transform(arm)
	Support.expect_true(character.activate_ragdoll(Vector3.FORWARD, 60.0, &"takeover"), "passive activation during a reaction")
	Support.expect_true(server_transform(arm).origin.distance_to(arm_before.origin) < .001, "takeover keeps running bodies in place")
	Support.expect_false(ragdoll.is_reacting(), "takeover ends the reaction")
	Support.expect_true(ragdoll.is_active(), "passive ragdoll owns the bodies")
	Support.expect_true(all_gravity_restored(ragdoll), "takeover restores gravity scale")
	var simulating := 0
	for body in ragdoll.get_physical_bones():
		if body.is_simulating_physics(): simulating += 1
	Support.expect_equal(simulating, 14, "every body simulates after takeover")
	Support.expect_equal(ragdoll.simulator.influence, 1.0, "takeover runs at full influence")
	Support.expect_false(ragdoll.begin_active_simulation(core), "no reaction while ragdolled")
	ragdoll.cancel_ragdoll()
	Support.expect_false(ragdoll.simulator.is_simulating_physics(), "cancel stops everything")
	character.queue_free()
	quit(Support.exit_code())
