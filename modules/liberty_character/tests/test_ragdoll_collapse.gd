extends SceneTree
const Support = preload("res://modules/liberty_character/tests/liberty_test_support.gd")
const Capture = preload("res://modules/liberty_character/ragdoll/liberty_pose_capture_modifier.gd")
func _initialize() -> void: call_deferred("run")
func tick(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame
## Simulated child segment direction expressed in the simulated parent bone frame.
func local_direction(ragdoll: LibertyRagdoll, parent: String, child: String, segment: Vector3) -> Vector3:
	var p := ragdoll.get_physical_bone(StringName(parent))
	var c := ragdoll.get_physical_bone(StringName(child))
	var parent_frame := p.global_transform * p.body_offset.affine_inverse()
	var child_frame := c.global_transform * c.body_offset.affine_inverse()
	return (parent_frame.basis.inverse() * (child_frame.basis * segment)).normalized()
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
	var rng := RandomNumberGenerator.new()
	rng.seed = 6006
	var worst_knee := 1.0
	var worst_elbow := 1.0
	var lowest := INF
	for trial in 8:
		var character = load("res://modules/liberty_character/character/liberty_character.tscn").instantiate()
		fixture.add_child(character)
		character.teleport_to(Transform3D(Basis(Vector3.UP, rng.randf_range(-PI, PI)), Vector3(0, 0, 0)))
		await tick(3)
		var ragdoll: LibertyRagdoll = character.get_node("Ragdoll")
		ragdoll.set_physics_process(false) # Collapse only; recovery is covered separately.
		var final_pose: LibertyPoseCaptureModifier = Capture.new()
		ragdoll.skeleton.add_child(final_pose) # Test-only: visible post-simulation pose.
		var angle := rng.randf_range(-PI, PI)
		var direction := Vector3(sin(angle), 0, cos(angle))
		var force := rng.randf_range(120.0, 320.0)
		var hips := ragdoll.get_physical_bone(&"Hips")
		await tick(1)
		var start := hips.global_position
		character.activate_ragdoll(direction, force, &"collapse_test")
		var max_speed := 0.0
		var finite := true
		for i in 90:
			await tick(1)
			max_speed = maxf(max_speed, hips.linear_velocity.length())
			finite = finite and hips.global_position.is_finite()
			if i > 30:
				for bone in ragdoll.skeleton.get_bone_count():
					lowest = minf(lowest, (ragdoll.skeleton.global_transform * final_pose.get_captured_pose(bone)).origin.y)
			for side in ["Left", "Right"]:
				# Knees fold the shin backward (+Z of the thigh), so a forward (-Z) shin is reverse
				# bend; elbows fold the hand forward (-Z), so a backward (+Z) forearm is reverse bend.
				var shin := local_direction(ragdoll, side + "UpperLeg", side + "LowerLeg", Vector3.DOWN)
				worst_knee = minf(worst_knee, shin.z)
				var forearm := local_direction(ragdoll, side + "UpperArm", side + "LowerArm", Vector3.RIGHT if side == "Left" else Vector3.LEFT)
				worst_elbow = minf(worst_elbow, -forearm.z)
		var travel := hips.global_position - start
		var along := Vector3(travel.x, 0, travel.z).dot(direction)
		print("trial %d force %.0f along %.3f m drop %.3f m max speed %.2f" % [trial, force, along, start.y - hips.global_position.y, max_speed])
		Support.expect_true(finite, "trial %d stays finite" % trial)
		Support.expect_true(along > .3, "trial %d collapses along the push" % trial)
		Support.expect_true(start.y - hips.global_position.y > .5, "trial %d falls to the floor" % trial)
		Support.expect_true(max_speed < 12.0, "trial %d hip speed stays bounded" % trial)
		Support.expect_true(hips.global_position.y > 0.0, "trial %d hips stay above the floor" % trial)
		character.queue_free()
		await tick(1)
	print("knee reverse-bend worst %.3f, elbow reverse-bend worst %.3f, lowest visible bone %.4f m" % [worst_knee, worst_elbow, lowest])
	Support.expect_true(lowest > -.03, "collapsed pose stays above the floor")
	Support.expect_true(worst_knee > -.35, "knees never hyperextend backward beyond the limit")
	Support.expect_true(worst_elbow > -.35, "elbows never hyperextend beyond the limit")
	quit(Support.exit_code())
