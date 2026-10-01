extends SceneTree

const Support = preload("res://modules/liberty_character/tests/liberty_test_support.gd")
const CourseScene = preload("res://modules/liberty_character/tests/test_camera.tscn")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var course := CourseScene.instantiate() as Node3D
	root.add_child(course)
	var character := course.get_node("LibertyCharacter") as LibertyCharacter
	var pivot := character.get_node("CameraPivot") as LibertyCameraPivot
	var spring_arm := pivot.get_node("SpringArm3D") as SpringArm3D
	var camera := spring_arm.get_node("Camera3D") as Camera3D
	_test_course_contract(course)

	await _wait_physics(8)
	var blocked_length := spring_arm.get_hit_length()
	Support.expect_true(blocked_length < 3.0, "close wall must retract the spring arm")
	Support.expect_true(camera.global_position.distance_to(pivot.global_position) <= blocked_length + 0.05, "camera must stay at the collision-limited arm endpoint")
	Support.expect_false(_camera_sphere_overlaps_world(camera), "camera collision sphere must remain outside world geometry")

	character.teleport_to(Transform3D(Basis.IDENTITY, Vector3(-12.0, 0.0, 0.0)))
	await _wait_physics(6)
	var restored_length := spring_arm.get_hit_length()
	Support.expect_true(restored_length > 4.45, "spring arm must restore its full length in open space")

	character.teleport_to(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, -2.5)))
	Support.expect_false(_camera_sphere_overlaps_world(camera), "open-to-blocked teleport must resolve camera collision immediately")
	Support.expect_true(camera.global_position.distance_to(pivot.global_position) < 4.45, "blocked teleport must retract the camera before returning")

	var corner_overlap_frames := await _measure_corner_overlap_frames(character, camera)
	Support.expect_equal(corner_overlap_frames, 0, "damped follow must keep the camera clear while rounding a solid corner")
	character.set_physics_process(true)
	character.teleport_to(Transform3D(Basis.IDENTITY, Vector3(-12.0, 0.0, 0.0)))
	await _wait_physics(6)

	var orbit := InputEventMouseMotion.new()
	orbit.relative = Vector2(-750.0, 0.0)
	pivot._unhandled_input(orbit)
	var expected_forward := -pivot.global_basis.z
	expected_forward.y = 0.0
	expected_forward = expected_forward.normalized()
	var movement_start := character.global_position
	Input.action_press(&"liberty_move_forward")
	await _wait_physics(45)
	Input.action_release(&"liberty_move_forward")
	var displacement := character.global_position - movement_start
	displacement.y = 0.0
	Support.expect_true(displacement.length() > 1.0, "camera course must allow forward movement")
	Support.expect_true(displacement.normalized().dot(expected_forward) > 0.8, "forward movement must follow camera yaw")

	print("PHASE2_METRICS blocked_arm=%.3f restored_arm=%.3f movement_alignment=%.3f" % [
		blocked_length,
		restored_length,
		displacement.normalized().dot(expected_forward),
	])
	course.free()
	quit(Support.exit_code())


func _measure_corner_overlap_frames(character: LibertyCharacter, camera: Camera3D) -> int:
	character.set_physics_process(false)
	character.teleport_to(Transform3D(Basis.IDENTITY, Vector3(-6.65, 0.0, -6.0)))
	await _wait_physics(4)
	var overlap_frames := 0
	for step in 22:
		character.global_position.z = -6.0 - 0.125 * (step + 1)
		await physics_frame
		if _camera_sphere_overlaps_world(camera):
			overlap_frames += 1
	for step in 32:
		character.global_position.x = -6.65 + 0.125 * (step + 1)
		await physics_frame
		if _camera_sphere_overlaps_world(camera):
			overlap_frames += 1
	return overlap_frames


func _test_course_contract(course: Node3D) -> void:
	for required_name in [
		"Floor",
		"CloseWall",
		"CorridorLeft",
		"CorridorRight",
		"PillarLeft",
		"PillarRight",
		"LowCeiling",
		"CornerWallA",
		"CornerWallB",
		"TightPocketBack",
		"TightPocketLeft",
		"TightPocketRight",
	]:
		Support.expect_true(course.get_node_or_null(required_name) is StaticBody3D, "camera course must contain %s" % required_name)


func _camera_sphere_overlaps_world(camera: Camera3D) -> bool:
	var sphere := SphereShape3D.new()
	sphere.radius = 0.29
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, camera.global_position)
	query.collision_mask = 1
	return not root.world_3d.direct_space_state.intersect_shape(query, 8).is_empty()



func _wait_physics(frames: int) -> void:
	for _frame in frames:
		await physics_frame
