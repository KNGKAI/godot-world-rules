extends SceneTree

const Support = preload("res://modules/liberty_character/tests/liberty_test_support.gd")
const CourseScene = preload("res://modules/liberty_character/tests/test_movement.tscn")

const ACTIONS: Array[StringName] = [
	&"liberty_move_forward",
	&"liberty_move_back",
	&"liberty_move_left",
	&"liberty_move_right",
	&"liberty_walk",
	&"liberty_sprint",
	&"liberty_jump",
]

var _course: Node3D
var _character: LibertyCharacter


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_course = CourseScene.instantiate() as Node3D
	root.add_child(_course)
	_character = _course.get_node("LibertyCharacter") as LibertyCharacter
	_test_course_contract()
	await _wait_physics(8)
	await _test_ramp_traversal()
	var metrics := await _measure_movement()
	_assert_metric_ranges(metrics)
	_print_metrics(metrics)
	_release_actions()
	_course.free()
	quit(Support.exit_code())


func _test_course_contract() -> void:
	Support.expect_true(_character != null, "movement course must contain LibertyCharacter")
	Support.expect_true(_course.get_node_or_null("FlatGround") is StaticBody3D, "movement course must contain flat ground")
	var ramp := _course.get_node_or_null("Ramp") as StaticBody3D
	Support.expect_true(ramp != null, "movement course must contain a ramp")
	if ramp != null:
		Support.expect_true(absf(rad_to_deg(ramp.rotation.x) - 30.0) < 0.01, "ramp must be 30 degrees")
	var camera := _course.get_node_or_null("FixedCamera") as Camera3D
	Support.expect_true(camera != null and camera.current, "movement course must contain a current fixed camera")
	var markers := _course.find_children("DistanceMarker_*", "MeshInstance3D", true, false)
	Support.expect_true(markers.size() >= 6, "movement course must show distance markers")
	for index in markers.size():
		if index == 0:
			continue
		var spacing := absf((markers[index] as Node3D).position.z - (markers[index - 1] as Node3D).position.z)
		Support.expect_true(absf(spacing - 2.5) < 0.01, "distance markers must be spaced 2.5 meters")


func _test_ramp_traversal() -> void:
	await _reset_character(Vector3(0.0, 0.0, 10.0))
	Input.action_press(&"liberty_move_forward")
	for _frame in 480:
		await physics_frame
		if _character.global_position.z < -26.0:
			break
	_release_actions()
	await _wait_physics(3)
	Support.expect_true(_character.global_position.z < -26.0, "character must traverse the ramp onto the upper platform")
	Support.expect_true(_character.global_position.y > 4.5, "ramp traversal must gain the expected elevation")
	Support.expect_true(_character.is_on_floor(), "character must remain grounded after ramp traversal")


func _measure_movement() -> Dictionary:
	var metrics := {}
	for gait in [&"walk", &"run", &"sprint"]:
		var target_speed := _target_speed(gait)
		await _reset_character(Vector3(0.0, 0.0, 10.0))
		_press_gait(gait, false)
		var frames_to_95 := 0
		while _character.planar_speed < target_speed * 0.95 and frames_to_95 < 180:
			await physics_frame
			frames_to_95 += 1
		metrics["%s_top_95" % gait] = frames_to_95 / 60.0
		while _character.planar_speed < target_speed - 0.02:
			await physics_frame
		var stop_start := _character.global_position
		_release_actions()
		var stop_frames := 0
		while _character.planar_speed > 0.1 and stop_frames < 180:
			await physics_frame
			stop_frames += 1
		var stop_delta := _character.global_position - stop_start
		metrics["%s_stop_distance" % gait] = Vector2(stop_delta.x, stop_delta.z).length()

	metrics["run_turn_radius"] = await _measure_turn_radius(&"run")
	metrics["sprint_turn_radius"] = await _measure_turn_radius(&"sprint")
	return metrics


func _measure_turn_radius(gait: StringName) -> float:
	await _reset_character(Vector3(0.0, 0.0, 10.0))
	_press_gait(gait, false)
	var target_speed := _target_speed(gait)
	while _character.planar_speed < target_speed - 0.02:
		await physics_frame
	var turn_start := _character.global_position
	Input.action_release(&"liberty_move_forward")
	Input.action_press(&"liberty_move_back")
	var maximum_lateral_displacement := 0.0
	for _frame in 240:
		await physics_frame
		maximum_lateral_displacement = maxf(maximum_lateral_displacement, absf(_character.global_position.x - turn_start.x))
		if (-_character.global_basis.z).dot(Vector3.BACK) > cos(deg_to_rad(10.0)):
			break
	return maximum_lateral_displacement * 0.5


func _assert_metric_ranges(metrics: Dictionary) -> void:
	Support.expect_true(metrics.walk_top_95 >= 0.15 and metrics.walk_top_95 <= 0.4, "walk acceleration time must match balanced-heavy tuning")
	Support.expect_true(metrics.run_top_95 >= 0.4 and metrics.run_top_95 <= 0.75, "run acceleration time must match balanced-heavy tuning")
	Support.expect_true(metrics.sprint_top_95 >= 0.65 and metrics.sprint_top_95 <= 1.05, "sprint acceleration time must match balanced-heavy tuning")
	Support.expect_true(metrics.walk_stop_distance >= 0.2 and metrics.walk_stop_distance <= 0.8, "walk stopping distance must match balanced-heavy tuning")
	Support.expect_true(metrics.run_stop_distance >= 1.5 and metrics.run_stop_distance <= 3.0, "run stopping distance must match balanced-heavy tuning")
	Support.expect_true(metrics.sprint_stop_distance >= 3.5 and metrics.sprint_stop_distance <= 6.0, "sprint stopping distance must match balanced-heavy tuning")
	Support.expect_true(metrics.run_turn_radius >= 0.3 and metrics.run_turn_radius <= 3.0, "run turn radius must be controlled")
	Support.expect_true(metrics.sprint_turn_radius >= 1.0 and metrics.sprint_turn_radius <= 6.0, "sprint turn radius must be controlled")
	Support.expect_true(metrics.sprint_turn_radius > metrics.run_turn_radius, "sprint turns must be wider than run turns")


func _print_metrics(metrics: Dictionary) -> void:
	print("PHASE1_METRICS walk_top_95=%.3f run_top_95=%.3f sprint_top_95=%.3f" % [metrics.walk_top_95, metrics.run_top_95, metrics.sprint_top_95])
	print("PHASE1_METRICS walk_stop=%.3f run_stop=%.3f sprint_stop=%.3f" % [metrics.walk_stop_distance, metrics.run_stop_distance, metrics.sprint_stop_distance])
	print("PHASE1_METRICS run_turn_radius=%.3f sprint_turn_radius=%.3f" % [metrics.run_turn_radius, metrics.sprint_turn_radius])


func _reset_character(position: Vector3) -> void:
	_release_actions()
	_character.set_movement_locked(false)
	_character.input_basis_source = null
	_character.global_position = position
	_character.rotation = Vector3.ZERO
	_character.velocity = Vector3.ZERO
	_character.reset_physics_interpolation()
	await _wait_physics(6)


func _press_gait(gait: StringName, reverse: bool) -> void:
	Input.action_press(&"liberty_move_back" if reverse else &"liberty_move_forward")
	if gait == &"walk":
		Input.action_press(&"liberty_walk")
	elif gait == &"sprint":
		Input.action_press(&"liberty_sprint")


func _target_speed(gait: StringName) -> float:
	if gait == &"walk":
		return _character.walk_speed
	if gait == &"sprint":
		return _character.sprint_speed
	return _character.run_speed


func _wait_physics(frames: int) -> void:
	for _frame in frames:
		await physics_frame


func _release_actions() -> void:
	for action in ACTIONS:
		Input.action_release(action)
