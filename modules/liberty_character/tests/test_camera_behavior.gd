extends SceneTree

const Support = preload("res://modules/liberty_character/tests/liberty_test_support.gd")
const CharacterScene = preload("res://modules/liberty_character/character/liberty_character.tscn")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_mouse_orbit_and_pitch_limits()
	await _test_frame_rate_independent_follow()
	await _test_recenter_conditions_and_interruption()
	await _test_orbit_hold_blocks_look_and_recenter()
	await _test_character_yaw_independence_and_discontinuity_snap()
	await _test_character_teleport()
	quit(Support.exit_code())


func _test_mouse_orbit_and_pitch_limits() -> void:
	var character := _spawn_character()
	var pivot := character.get_node("CameraPivot") as LibertyCameraPivot

	var look_up := InputEventMouseMotion.new()
	look_up.relative = Vector2(100.0, -1000.0)
	pivot._unhandled_input(look_up)
	Support.expect_true(absf(rad_to_deg(pivot.global_rotation.y) + 12.0) < 0.01, "mouse X must rotate yaw immediately")
	Support.expect_true(absf(rad_to_deg(pivot.global_rotation.x) - 70.0) < 0.01, "upward pitch must clamp at 70 degrees")

	var look_down := InputEventMouseMotion.new()
	look_down.relative = Vector2(0.0, 2000.0)
	pivot._unhandled_input(look_down)
	Support.expect_true(absf(rad_to_deg(pivot.global_rotation.x) + 50.0) < 0.01, "downward pitch must clamp at 50 degrees")
	character.free()


func _test_frame_rate_independent_follow() -> void:
	var character := _spawn_character()
	var pivot := character.get_node("CameraPivot") as LibertyCameraPivot
	pivot.set_physics_process(false)
	pivot.snap_to_target()
	character.global_position.x = 2.0
	for _step in 30:
		pivot._physics_process(1.0 / 30.0)
	var thirty_hz_x := pivot.global_position.x

	character.global_position = Vector3.ZERO
	pivot.snap_to_target()
	character.global_position.x = 2.0
	for _step in 120:
		pivot._physics_process(1.0 / 120.0)
	var one_twenty_hz_x := pivot.global_position.x

	Support.expect_true(absf(thirty_hz_x - one_twenty_hz_x) < 0.001, "follow damping must be frame-rate independent")
	Support.expect_true(absf(thirty_hz_x - 1.9938) < 0.002, "follow damping must use the configured 0.12 second half-life")
	character.free()


func _test_recenter_conditions_and_interruption() -> void:
	var ground := _spawn_ground()
	var character := _spawn_character()
	await _wait_physics(5)
	Support.expect_true(character.is_on_floor(), "recenter fixture must place the character on a floor")
	character.set_physics_process(false)
	var pivot := character.get_node("CameraPivot") as LibertyCameraPivot
	pivot.set_physics_process(false)
	character.global_rotation.y = deg_to_rad(90.0)
	character.velocity = Vector3(0.0, 0.0, -2.0)
	pivot.global_rotation = Vector3.ZERO

	for _step in 4:
		pivot._physics_process(0.25)
	Support.expect_true(absf(pivot.global_rotation.y) < 0.001, "recenter must wait through its input-free delay")
	for _step in 4:
		pivot._physics_process(0.25)
	Support.expect_true(rad_to_deg(pivot.global_rotation.y) > 35.0, "moving grounded camera must softly recenter toward character heading")

	var mouse_motion := InputEventMouseMotion.new()
	mouse_motion.relative = Vector2(50.0, 0.0)
	pivot._unhandled_input(mouse_motion)
	var interrupted_yaw := pivot.global_rotation.y
	for _step in 4:
		pivot._physics_process(0.25)
	Support.expect_true(absf(angle_difference(interrupted_yaw, pivot.global_rotation.y)) < 0.001, "mouse input must restart the recenter delay")

	character.free()
	ground.free()

	var airborne := _spawn_character()
	var airborne_pivot := airborne.get_node("CameraPivot") as LibertyCameraPivot
	airborne.set_physics_process(false)
	airborne_pivot.set_physics_process(false)
	airborne.global_rotation.y = deg_to_rad(90.0)
	airborne.velocity = Vector3(0.0, 0.0, -2.0)
	airborne_pivot.global_rotation = Vector3.ZERO
	for _step in 8:
		airborne_pivot._physics_process(0.25)
	Support.expect_true(absf(airborne_pivot.global_rotation.y) < 0.001, "airborne camera must not auto-recenter")
	airborne.free()


func _test_orbit_hold_blocks_look_and_recenter() -> void:
	var ground := _spawn_ground()
	var character := _spawn_character()
	await _wait_physics(5)
	Support.expect_true(character.is_on_floor(), "orbit-hold fixture must place the character on a floor")
	character.set_physics_process(false)
	var pivot := character.get_node("CameraPivot") as LibertyCameraPivot
	pivot.set_physics_process(false)
	character.global_rotation.y = deg_to_rad(90.0)
	character.velocity = Vector3(0.0, 0.0, -2.0)
	pivot.global_rotation = Vector3.ZERO
	var held_yaw := pivot.global_rotation.y
	pivot.set_orbit_held(true)
	Support.expect_true(pivot.is_orbit_held(), "orbit hold must report while set")

	var mouse_motion := InputEventMouseMotion.new()
	mouse_motion.relative = Vector2(100.0, -40.0)
	pivot._unhandled_input(mouse_motion)
	pivot.apply_look_delta(Vector2(-80.0, 30.0))
	Support.expect_true(absf(angle_difference(held_yaw, pivot.global_rotation.y)) < 0.001, "held orbit must ignore mouse and touch look")
	Support.expect_true(absf(pivot.global_rotation.x) < 0.001, "held orbit must ignore pitch")

	for _step in 8:
		pivot._physics_process(0.25)
	Support.expect_true(absf(angle_difference(held_yaw, pivot.global_rotation.y)) < 0.001, "held orbit must not recenter after the 1.25 s delay")

	var start := pivot.global_position
	character.global_position.x = 1.0
	pivot._physics_process(1.0 / 60.0)
	Support.expect_true(pivot.global_position.distance_to(start) > 0.01, "held orbit must keep follow damping")
	Support.expect_true(pivot.global_position.distance_to(character.global_position + Vector3.UP * 1.45) > 0.5, "a short move must follow instead of snapping")
	Support.expect_true(absf(angle_difference(held_yaw, pivot.global_rotation.y)) < 0.001, "follow while held must not change yaw")

	character.global_position = Vector3(4.0, 0.0, -3.5)
	pivot._physics_process(1.0 / 60.0)
	var expected_anchor := character.global_position + Vector3.UP * 1.45
	Support.expect_true(pivot.global_position.distance_to(expected_anchor) < 0.001, "held orbit must still snap across a large displacement")
	Support.expect_true(absf(angle_difference(held_yaw, pivot.global_rotation.y)) < 0.001, "snap while held must not change yaw")

	pivot.set_orbit_held(false)
	Support.expect_false(pivot.is_orbit_held(), "clearing the orbit hold must report clear")
	character.free()
	ground.free()


func _test_character_yaw_independence_and_discontinuity_snap() -> void:
	var character := _spawn_character()
	var pivot := character.get_node("CameraPivot") as LibertyCameraPivot
	pivot.set_physics_process(false)
	var orbit := InputEventMouseMotion.new()
	orbit.relative = Vector2(-208.333333, 0.0)
	pivot._unhandled_input(orbit)
	character.global_rotation.y = deg_to_rad(120.0)
	pivot._physics_process(1.0 / 60.0)
	Support.expect_true(absf(rad_to_deg(pivot.global_rotation.y) - 25.0) < 0.01, "camera yaw must not inherit character yaw")

	character.global_position = Vector3(4.0, 0.0, -3.5)
	pivot._physics_process(1.0 / 60.0)
	var expected_anchor := character.global_position + Vector3.UP * 1.45
	Support.expect_true(pivot.global_position.distance_to(expected_anchor) < 0.001, "large target displacement must snap instead of trailing")
	character.free()


func _test_character_teleport() -> void:
	var character := _spawn_character()
	var pivot := character.get_node("CameraPivot") as LibertyCameraPivot
	pivot.set_physics_process(false)
	var has_teleport_api := character.has_method(&"teleport_to")
	Support.expect_true(has_teleport_api, "character must expose teleport_to")
	Support.expect_equal(character.get("camera_pivot_path"), NodePath("CameraPivot"), "character must resolve its owned camera pivot")
	if not has_teleport_api:
		character.free()
		return
	character.velocity = Vector3(3.0, 4.0, 5.0)
	var destination := Transform3D(Basis(Vector3.UP, deg_to_rad(60.0)), Vector3(12.0, 5.0, -8.0))
	character.teleport_to(destination)
	Support.expect_true(character.global_transform.origin.distance_to(destination.origin) < 0.001, "teleport must apply the destination transform")
	Support.expect_true(character.velocity.is_zero_approx(), "teleport must clear velocity by default")
	Support.expect_true(pivot.global_position.distance_to(destination.origin + Vector3.UP * 1.45) < 0.001, "teleport must snap the camera to the new shoulder target")
	Support.expect_equal(character.movement_state, LibertyCharacter.MovementState.AIRBORNE, "teleport must refresh movement state")

	var preserved_velocity := Vector3(-2.0, 1.0, 4.0)
	character.velocity = preserved_velocity
	var second_destination := Transform3D(Basis.IDENTITY, Vector3(-4.0, 2.0, 7.0))
	character.teleport_to(second_destination, true)
	Support.expect_true(character.velocity.is_equal_approx(preserved_velocity), "teleport may preserve velocity explicitly")
	Support.expect_true(pivot.global_position.distance_to(second_destination.origin + Vector3.UP * 1.45) < 0.001, "preserving velocity must still snap the camera")
	character.free()

	var ground := _spawn_ground()
	var grounded := _spawn_character()
	await _wait_physics(5)
	Support.expect_true(grounded.is_on_floor(), "grounded teleport fixture must settle on the floor")
	var transitions: Array = []
	var events := grounded.get_node("Events") as LibertyEvents
	events.movement_state_changed.connect(func(old_state: StringName, new_state: StringName) -> void:
		transitions.append([old_state, new_state])
	)
	grounded.velocity = Vector3(1.0, 1.0, 0.0)
	grounded.teleport_to(Transform3D(Basis.IDENTITY, Vector3(0.0, 5.0, 0.0)), true)
	Support.expect_equal(grounded.movement_state, LibertyCharacter.MovementState.AIRBORNE, "ground-to-air teleport must invalidate cached floor state immediately")
	Support.expect_true(not transitions.is_empty() and transitions.back() == [&"idle", &"airborne"], "ground-to-air teleport must emit the airborne transition")
	await _wait_physics(2)
	Support.expect_true(grounded.velocity.y < 1.0, "first movement tick after an airborne teleport must apply gravity")
	grounded.teleport_to(Transform3D(Basis.IDENTITY, Vector3(2.0, 0.0, 0.0)))
	Support.expect_equal(grounded.movement_state, LibertyCharacter.MovementState.IDLE, "teleport onto a floor must refresh grounded state immediately")
	Support.expect_true(transitions.back() == [&"airborne", &"idle"], "air-to-ground teleport must emit the grounded transition")
	grounded.free()
	ground.free()


func _spawn_character() -> LibertyCharacter:
	var character := CharacterScene.instantiate() as LibertyCharacter
	root.add_child(character)
	return character


func _spawn_ground() -> StaticBody3D:
	var ground := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20.0, 1.0, 20.0)
	collision.position.y = -0.5
	collision.shape = box
	ground.add_child(collision)
	root.add_child(ground)
	return ground


func _wait_physics(frames: int) -> void:
	for _frame in frames:
		await physics_frame
