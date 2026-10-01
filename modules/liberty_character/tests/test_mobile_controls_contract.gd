extends SceneTree

const Support = preload("res://modules/liberty_character/tests/liberty_test_support.gd")
const CharacterScene = preload("res://modules/liberty_character/character/liberty_character.tscn")


func _initialize() -> void:
	# Headless physically uses 64x64; use a stable logical phone-sized viewport.
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	call_deferred("_run")

func _run() -> void:
	await process_frame
	var character := CharacterScene.instantiate() as LibertyCharacter
	Support.expect_true(character != null, "mobile controls contract requires LibertyCharacter")
	if character == null:
		quit(Support.exit_code())
		return

	root.add_child(character)
	var controls := character.get_node_or_null("MobileControls")
	Support.expect_true(controls is CanvasLayer, "character must own a mobile controls canvas")
	Support.expect_true(
		controls != null and controls.get_script() != null,
		"mobile controls canvas must have touch input behavior"
	)
	controls.set("force_visible", true)
	await _test_joystick_drives_analog_movement(character)
	await _test_mobile_release_preserves_keyboard(character)
	await _test_left_side_second_touch_does_not_claim_camera(character)
	await _test_joystick_visual_stays_in_safe_bounds(character)
	await _test_right_drag_orbits_camera(character)
	await _test_jump_and_sprint_are_independent(character)
	_test_overlay_visuals_exist(character)
	_test_overlay_hides_without_a_touchscreen(character)
	await _test_hidden_overlay_releases_and_rejects_input(character)
	_test_force_visible_updates_live(character)

	character.free()
	quit(Support.exit_code())


func _test_joystick_drives_analog_movement(character: LibertyCharacter) -> void:
	_release_mobile_actions()
	var viewport_size := root.get_visible_rect().size
	var origin := Vector2(viewport_size.x * 0.2, viewport_size.y * 0.72)
	var camera_pivot := character.get_node("CameraPivot") as LibertyCameraPivot
	var camera_rotation := camera_pivot.rotation

	var touch := InputEventScreenTouch.new()
	touch.index = 11
	touch.position = origin
	touch.pressed = true
	_parse_window_event(touch)

	var drag := InputEventScreenDrag.new()
	drag.index = 11
	drag.position = origin + Vector2(35.0, -35.0)
	drag.relative = Vector2(35.0, -35.0)
	_parse_window_event(drag)
	await process_frame

	Support.expect_true(
		Input.get_action_strength(&"liberty_touch_move_right") > 0.25,
		"dragging the movement touch right must apply analog right input"
	)
	Support.expect_true(
		Input.get_action_strength(&"liberty_touch_move_forward") > 0.25,
		"dragging the movement touch upward must apply analog forward input"
	)
	Support.expect_false(
		character._get_world_input_direction().is_zero_approx(),
		"sub-half-strength joystick input must reach character movement"
	)
	Support.expect_true(
		character._get_world_input_direction().length() < 0.75,
		"partial joystick drag must preserve analog magnitude"
	)
	Support.expect_true(
		camera_pivot.rotation.is_equal_approx(camera_rotation),
		"movement-side touch drag must not orbit the camera"
	)

	var release := InputEventScreenTouch.new()
	release.index = touch.index
	release.pressed = false
	release.position = drag.position
	_parse_window_event(release)
	await process_frame
	Support.expect_true(Input.get_vector(
		&"liberty_touch_move_left", &"liberty_touch_move_right",
		&"liberty_touch_move_forward", &"liberty_touch_move_back", 0.0
	).is_zero_approx(), "releasing the movement touch must clear movement input")

func _release_mobile_actions() -> void:
	for action in [
		&"liberty_touch_move_left", &"liberty_touch_move_right",
		&"liberty_touch_move_forward", &"liberty_touch_move_back",
	]:
		Input.action_release(action)


func _test_right_drag_orbits_camera(character: LibertyCharacter) -> void:
	var controls = character.get_node("MobileControls")
	var pivot := character.get_node("CameraPivot") as LibertyCameraPivot
	var initial_rotation := pivot.global_rotation
	var viewport_size := root.get_visible_rect().size
	var origin := Vector2(viewport_size.x * 0.7, viewport_size.y * 0.4)

	var touch := InputEventScreenTouch.new()
	touch.index = 12
	touch.position = origin
	touch.pressed = true
	controls._input(touch)

	var drag := InputEventScreenDrag.new()
	drag.index = touch.index
	drag.position = origin + Vector2(40.0, -25.0)
	drag.relative = Vector2(40.0, -25.0)
	controls._input(drag)
	await process_frame

	Support.expect_true(
		not is_equal_approx(pivot.global_rotation.y, initial_rotation.y),
		"dragging a right-side touch horizontally must orbit camera yaw"
	)
	Support.expect_true(
		not is_equal_approx(pivot.global_rotation.x, initial_rotation.x),
		"dragging a right-side touch vertically must orbit camera pitch"
	)

	var release := InputEventScreenTouch.new()
	release.index = touch.index
	release.position = drag.position
	release.pressed = false
	controls._input(release)
	await process_frame


func _test_jump_and_sprint_are_independent(character: LibertyCharacter) -> void:
	Input.action_release(&"liberty_touch_jump")
	Input.action_release(&"liberty_touch_sprint")
	var controls = character.get_node("MobileControls")
	var viewport_size := root.get_visible_rect().size
	var jump_position := Vector2(viewport_size.x - 92.0, viewport_size.y - 132.0)
	var sprint_position := Vector2(viewport_size.x - 194.0, viewport_size.y - 84.0)

	controls._input(_touch_event(13, jump_position, true))
	controls._input(_touch_event(14, sprint_position, true))
	Support.expect_true(Input.is_action_pressed(&"liberty_touch_jump"), "jump touch must press liberty_touch_jump")
	Support.expect_true(Input.is_action_pressed(&"liberty_touch_sprint"), "sprint touch must press liberty_touch_sprint")

	controls._input(_touch_event(13, jump_position, false))
	Support.expect_false(Input.is_action_pressed(&"liberty_touch_jump"), "releasing jump touch must release liberty_touch_jump")
	Support.expect_true(Input.is_action_pressed(&"liberty_touch_sprint"), "releasing jump must not release a separate sprint touch")

	controls._input(_touch_event(14, sprint_position, false))
	Support.expect_false(Input.is_action_pressed(&"liberty_touch_sprint"), "releasing sprint touch must release liberty_touch_sprint")
	await process_frame


func _touch_event(index: int, position: Vector2, pressed: bool) -> InputEventScreenTouch:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = position
	event.pressed = pressed
	return event


func _test_overlay_visuals_exist(character: LibertyCharacter) -> void:
	var controls := character.get_node("MobileControls")
	Support.expect_true(controls.get_node_or_null("Overlay") is Control, "mobile controls must own a full-screen overlay")
	Support.expect_true(controls.get_node_or_null("Overlay/JoystickBase") is Control, "overlay must show a joystick base")
	Support.expect_true(controls.get_node_or_null("Overlay/JoystickBase/JoystickKnob") is Control, "overlay must show a joystick knob")
	Support.expect_true(controls.get_node_or_null("Overlay/JumpButton") is Control, "overlay must show a Jump button")
	Support.expect_true(controls.get_node_or_null("Overlay/SprintButton") is Control, "overlay must show a Sprint button")


func _test_overlay_hides_without_a_touchscreen(character: LibertyCharacter) -> void:
	if DisplayServer.get_name() == "headless":
		var controls := character.get_node("MobileControls") as CanvasLayer
		controls.set("force_visible", false)
		Support.expect_false(controls.visible, "mobile overlay must hide when no touchscreen is available")


func _test_force_visible_updates_live(character: LibertyCharacter) -> void:
	var controls := character.get_node("MobileControls") as CanvasLayer
	controls.set("force_visible", true)
	Support.expect_true(controls.visible, "force_visible must reveal the mobile overlay for desktop testing")


func _test_mobile_release_preserves_keyboard(character: LibertyCharacter) -> void:
	var controls = character.get_node("MobileControls")
	var origin := Vector2(root.get_visible_rect().size.x * 0.2, root.get_visible_rect().size.y * 0.72)
	Input.action_press(&"liberty_move_left")
	controls._input(_touch_event(21, origin, true))
	var drag := InputEventScreenDrag.new()
	drag.index = 21
	drag.position = origin + Vector2(60.0, 0.0)
	drag.relative = Vector2(60.0, 0.0)
	controls._input(drag)
	controls._input(_touch_event(21, drag.position, false))
	await process_frame
	Support.expect_true(
		Input.is_action_pressed(&"liberty_move_left"),
		"releasing mobile movement must not cancel a held keyboard action"
	)
	Input.action_release(&"liberty_move_left")


func _test_left_side_second_touch_does_not_claim_camera(character: LibertyCharacter) -> void:
	var controls = character.get_node("MobileControls")
	var pivot := character.get_node("CameraPivot") as LibertyCameraPivot
	var initial_rotation := pivot.rotation
	var first := Vector2(root.get_visible_rect().size.x * 0.15, root.get_visible_rect().size.y * 0.65)
	var second := Vector2(root.get_visible_rect().size.x * 0.35, root.get_visible_rect().size.y * 0.4)
	controls._input(_touch_event(31, first, true))
	controls._input(_touch_event(32, second, true))
	var drag := InputEventScreenDrag.new()
	drag.index = 32
	drag.position = second + Vector2(70.0, -30.0)
	drag.relative = Vector2(70.0, -30.0)
	controls._input(drag)
	Support.expect_true(
		pivot.rotation.is_equal_approx(initial_rotation),
		"a second touch beginning on the left half must not claim camera look"
	)
	controls._input(_touch_event(31, first, false))
	controls._input(_touch_event(32, drag.position, false))
	await process_frame


func _test_hidden_overlay_releases_and_rejects_input(character: LibertyCharacter) -> void:
	var controls = character.get_node("MobileControls")
	controls.set("force_visible", true)
	var sprint_position := Vector2(root.get_visible_rect().size.x - 194.0, root.get_visible_rect().size.y - 84.0)
	controls._input(_touch_event(41, sprint_position, true))
	Support.expect_true(Input.is_action_pressed(&"liberty_touch_sprint"), "visible overlay must accept touch input")
	controls.set("force_visible", false)
	Support.expect_false(Input.is_action_pressed(&"liberty_touch_sprint"), "hiding overlay must release owned actions")

	var origin := Vector2(root.get_visible_rect().size.x * 0.2, root.get_visible_rect().size.y * 0.7)
	controls._input(_touch_event(42, origin, true))
	var drag := InputEventScreenDrag.new()
	drag.index = 42
	drag.position = origin + Vector2(60.0, 0.0)
	drag.relative = Vector2(60.0, 0.0)
	controls._input(drag)
	Support.expect_true(Input.get_vector(
		&"liberty_touch_move_left", &"liberty_touch_move_right",
		&"liberty_touch_move_forward", &"liberty_touch_move_back", 0.0
	).is_zero_approx(), "hidden overlay must reject new touch input")
	await process_frame


func _test_joystick_visual_stays_in_safe_bounds(character: LibertyCharacter) -> void:
	var controls = character.get_node("MobileControls")
	controls.set("force_visible", true)
	var edge_touch := Vector2(1.0, root.get_visible_rect().size.y - 1.0)
	controls._input(_touch_event(51, edge_touch, true))
	var base := controls.get_node("Overlay/JoystickBase") as Control
	Support.expect_true(base.position.x >= 24.0, "joystick base must stay inside the left safe margin")
	Support.expect_true(base.position.y + base.size.y <= root.get_visible_rect().size.y - 24.0, "joystick base must stay inside the bottom safe margin")
	controls._input(_touch_event(51, edge_touch, false))
	await process_frame

## Input.parse_input_event takes physical window coordinates, whereas direct
## controls._input fixtures and get_visible_rect use logical viewport coordinates.
func _parse_window_event(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		var transform := root.get_final_transform()
		event.position = transform * event.position
		if event is InputEventScreenDrag: event.relative = transform.basis_xform(event.relative)
	Input.parse_input_event(event)
