class_name LibertyMobileControls
extends CanvasLayer

@export_range(24.0, 200.0, 1.0) var joystick_radius := 90.0
@export_range(0.0, 0.9, 0.01) var joystick_deadzone := 0.15
@export_range(0.0, 80.0, 1.0) var safe_margin := 24.0
@export var camera_pivot_path: NodePath = ^"../CameraPivot"
@export var force_visible := false:
	set(value):
		force_visible = value
		if is_node_ready():
			_update_visibility()

var _suspended := false
var _movement_touch := -1
var _movement_origin := Vector2.ZERO
var _look_touch := -1
var _jump_touch := -1
var _sprint_touch := -1
var _traverse_touch := -1
var _drop_touch := -1
var _drop_pending := false
var _jump_center := Vector2.ZERO
var _sprint_center := Vector2.ZERO
var _traverse_center := Vector2.ZERO
var _drop_center := Vector2.ZERO
var _overlay: Control
var _joystick_base: Panel
var _joystick_knob: Panel
var _jump_button: Panel
var _sprint_button: Panel
var _traverse_button: Panel
var _drop_button: Panel
## Extra buttons: {title, panel, callback, center, touch}.
var _custom_buttons: Array[Dictionary] = []


func _ready() -> void:
	_build_overlay()
	get_viewport().size_changed.connect(_layout_controls)
	_layout_controls()
	_update_visibility()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	var touch := event as InputEventScreenTouch
	if touch != null:
		_handle_touch(touch)
		get_viewport().set_input_as_handled()
		return
	var drag := event as InputEventScreenDrag
	if drag == null:
		return
	if drag.index == _movement_touch:
		_apply_movement_drag(drag.position)
	elif drag.index == _look_touch:
		_apply_look_drag(drag.relative)
	get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what in [NOTIFICATION_WM_WINDOW_FOCUS_OUT, NOTIFICATION_APPLICATION_FOCUS_OUT]:
		_release_all_touches()


func _exit_tree() -> void:
	_release_all_touches()


func _handle_touch(touch: InputEventScreenTouch) -> void:
	if touch.pressed:
		if _try_press_action_button(touch):
			return
		if _movement_touch < 0 and touch.position.x < get_viewport().get_visible_rect().size.x * 0.5:
			_movement_touch = touch.index
			_movement_origin = touch.position
			_apply_movement(Vector2.ZERO)
			_move_joystick_visual(touch.position, Vector2.ZERO)
			_joystick_base.show()
		elif (
			_look_touch < 0
			and touch.position.x >= get_viewport().get_visible_rect().size.x * 0.5
		):
			_look_touch = touch.index
	elif touch.index == _jump_touch:
		_jump_touch = -1
		Input.action_release(&"liberty_touch_jump")
		_set_button_pressed(_jump_button, false)
	elif touch.index == _sprint_touch:
		_sprint_touch = -1
		Input.action_release(&"liberty_touch_sprint")
		_set_button_pressed(_sprint_button, false)
	elif touch.index == _traverse_touch:
		_traverse_touch = -1
		Input.action_release(&"liberty_touch_traverse")
		_set_button_pressed(_traverse_button, false)
	elif touch.index == _drop_touch:
		_drop_touch = -1
		Input.action_release(&"liberty_touch_drop")
		_set_button_pressed(_drop_button, false)
	elif _release_custom_touch(touch.index):
		pass
	elif touch.index == _movement_touch:
		_release_movement()
	elif touch.index == _look_touch:
		_look_touch = -1


func _apply_movement_drag(position: Vector2) -> void:
	var offset := position - _movement_origin
	var raw := offset / maxf(joystick_radius, 1.0)
	_move_joystick_visual(_movement_origin, offset.limit_length(joystick_radius))
	if raw.length() <= joystick_deadzone:
		_apply_movement(Vector2.ZERO)
		return
	var strength := clampf(
		(raw.length() - joystick_deadzone) / maxf(1.0 - joystick_deadzone, 0.001),
		0.0,
		1.0
	)
	_apply_movement(raw.normalized() * strength)


func _apply_movement(value: Vector2) -> void:
	_set_action_strength(&"liberty_touch_move_left", maxf(-value.x, 0.0))
	_set_action_strength(&"liberty_touch_move_right", maxf(value.x, 0.0))
	_set_action_strength(&"liberty_touch_move_forward", maxf(-value.y, 0.0))
	_set_action_strength(&"liberty_touch_move_back", maxf(value.y, 0.0))


func _apply_look_drag(relative: Vector2) -> void:
	var camera_pivot := get_node_or_null(camera_pivot_path) as LibertyCameraPivot
	if camera_pivot != null:
		camera_pivot.apply_look_delta(relative)


func _set_action_strength(action: StringName, strength: float) -> void:
	if strength > 0.0:
		Input.action_press(action, strength)
	else:
		Input.action_release(action)


func _release_movement() -> void:
	_movement_touch = -1
	_movement_origin = Vector2.ZERO
	_apply_movement(Vector2.ZERO)
	if _joystick_base != null:
		_joystick_base.hide()


func _try_press_action_button(touch: InputEventScreenTouch) -> bool:
	if _traverse_touch < 0 and touch.position.distance_to(_traverse_center) <= 46.0:
		_traverse_touch = touch.index
		Input.action_press(&"liberty_touch_traverse")
		_set_button_pressed(_traverse_button, true)
		return true
	if _drop_touch < 0 and touch.position.distance_to(_drop_center) <= 46.0:
		_drop_touch = touch.index
		_drop_pending = true
		Input.action_press(&"liberty_touch_drop")
		_set_button_pressed(_drop_button, true)
		return true
	if _jump_touch < 0 and touch.position.distance_to(_jump_center) <= 46.0:
		_jump_touch = touch.index
		Input.action_press(&"liberty_touch_jump")
		_set_button_pressed(_jump_button, true)
		return true
	if _sprint_touch < 0 and touch.position.distance_to(_sprint_center) <= 46.0:
		_sprint_touch = touch.index
		Input.action_press(&"liberty_touch_sprint")
		_set_button_pressed(_sprint_button, true)
		return true
	for button in _custom_buttons:
		if button.touch < 0 and touch.position.distance_to(button.center) <= 46.0:
			button.touch = touch.index
			_set_button_pressed(button.panel, true)
			(button.callback as Callable).call()
			return true
	return false


## Adds a touch button to the top-right row that calls callback when pressed.
## Screen touches are consumed here and never reach GUI Buttons, so scenes that
## need touch controls (such as test courses) register them through this.
func add_custom_button(title: String, color: Color, callback: Callable) -> Panel:
	var panel := _make_action_button(title.to_pascal_case() + "Button", title, color)
	_custom_buttons.append({"title": title, "panel": panel, "callback": callback, "center": Vector2.ZERO, "touch": -1})
	_layout_controls()
	return panel


func get_custom_button(title: String) -> Panel:
	for button in _custom_buttons:
		if button.title == title:
			return button.panel
	return null


func _release_custom_touch(touch_index: int) -> bool:
	for button in _custom_buttons:
		if button.touch == touch_index:
			button.touch = -1
			_set_button_pressed(button.panel, false)
			return true
	return false


func _release_action_touch(action: StringName, touch_index: int) -> void:
	if touch_index >= 0:
		Input.action_release(action)


func _build_overlay() -> void:
	_overlay = Control.new()
	_overlay.name = "Overlay"
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay)

	_joystick_base = _make_circle("JoystickBase", _overlay, joystick_radius * 2.0, Color(0.08, 0.12, 0.18, 0.42))
	_joystick_knob = _make_circle("JoystickKnob", _joystick_base, 64.0, Color(0.74, 0.86, 1.0, 0.72))
	_joystick_base.hide()
	_jump_button = _make_action_button("JumpButton", "JUMP", Color(0.18, 0.58, 0.95, 0.72))
	_sprint_button = _make_action_button("SprintButton", "RUN", Color(0.96, 0.50, 0.16, 0.72))
	_traverse_button = _make_action_button("TraverseButton", "CLIMB", Color(0.18, 0.75, 0.42, 0.72))
	_drop_button = _make_action_button("DropButton", "DROP", Color(0.8, 0.25, 0.25, 0.72))


func _make_circle(node_name: String, parent: Node, diameter: float, color: Color) -> Panel:
	var panel := Panel.new()
	panel.name = node_name
	panel.size = Vector2.ONE * diameter
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = color
	var radius := int(diameter * 0.5)
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	panel.add_theme_stylebox_override(&"panel", style)
	parent.add_child(panel)
	return panel


func _make_action_button(node_name: String, text: String, color: Color) -> Panel:
	var panel := _make_circle(node_name, _overlay, 92.0, color)
	var label := Label.new()
	label.name = "Label"
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override(&"font_size", 17)
	panel.add_child(label)
	return panel


func _layout_controls() -> void:
	if _overlay == null:
		return
	var safe_rect := _safe_viewport_rect().grow(-safe_margin)
	_jump_center = safe_rect.end - Vector2(68.0, 108.0)
	_sprint_center = safe_rect.end - Vector2(170.0, 60.0)
	_place_centered(_jump_button, _jump_center)
	_place_centered(_sprint_button, _sprint_center)
	_traverse_center = safe_rect.end - Vector2(170.0, 164.0)
	_drop_center = safe_rect.end - Vector2(68.0, 212.0)
	_place_centered(_traverse_button, _traverse_center)
	_place_centered(_drop_button, _drop_center)
	for index in _custom_buttons.size():
		var button := _custom_buttons[index]
		button.center = Vector2(safe_rect.end.x - 50.0 - index * 104.0, safe_rect.position.y + 50.0)
		_place_centered(button.panel, button.center)


func _safe_viewport_rect() -> Rect2:
	var viewport_rect := get_viewport().get_visible_rect()
	if DisplayServer.get_name() == "headless":
		return viewport_rect
	var screen_size := Vector2(DisplayServer.screen_get_size())
	var safe_area := DisplayServer.get_display_safe_area()
	if screen_size.x <= 0.0 or screen_size.y <= 0.0 or safe_area.size.x <= 0:
		return viewport_rect
	var scale := viewport_rect.size / screen_size
	var scaled_safe := Rect2(Vector2(safe_area.position) * scale, Vector2(safe_area.size) * scale)
	return viewport_rect.intersection(scaled_safe)


func _move_joystick_visual(center: Vector2, knob_offset: Vector2) -> void:
	if _joystick_base == null:
		return
	var safe_rect := _safe_viewport_rect().grow(-safe_margin)
	var clamped_center := Vector2(
		_clamp_axis_to_safe_bound(center.x, safe_rect.position.x, safe_rect.end.x, joystick_radius),
		_clamp_axis_to_safe_bound(center.y, safe_rect.position.y, safe_rect.end.y, joystick_radius)
	)
	_place_centered(_joystick_base, clamped_center)
	_place_centered(_joystick_knob, Vector2.ONE * joystick_radius + knob_offset)


func _clamp_axis_to_safe_bound(value: float, min_bound: float, max_bound: float, radius: float) -> float:
	var midpoint := (min_bound + max_bound) * 0.5
	if value <= midpoint:
		return maxf(value, min_bound + radius)
	return minf(value, max_bound - radius)


func _place_centered(control: Control, center: Vector2) -> void:
	if control != null:
		control.position = center - control.size * 0.5


func _set_button_pressed(button: Control, pressed: bool) -> void:
	if button != null:
		button.modulate = Color(0.78, 0.86, 1.0) if pressed else Color.WHITE



func _update_visibility() -> void:
	var should_be_visible := not _suspended and (force_visible or DisplayServer.is_touchscreen_available())
	if visible and not should_be_visible:
		_release_all_touches()
	visible = should_be_visible


func _release_all_touches() -> void:
	_drop_pending = false
	_release_movement()
	_release_action_touch(&"liberty_touch_jump", _jump_touch)
	_release_action_touch(&"liberty_touch_sprint", _sprint_touch)
	_release_action_touch(&"liberty_touch_traverse", _traverse_touch)
	_release_action_touch(&"liberty_touch_drop", _drop_touch)
	_jump_touch = -1
	_sprint_touch = -1
	_traverse_touch = -1
	_drop_touch = -1
	_look_touch = -1
	for button in _custom_buttons:
		button.touch = -1
		_set_button_pressed(button.panel, false)
	_set_button_pressed(_jump_button, false)
	_set_button_pressed(_sprint_button, false)
	_set_button_pressed(_traverse_button, false)
	_set_button_pressed(_drop_button, false)


## A quick tap is retained until the owning traversal physics tick consumes it.
func consume_drop_press() -> bool:
	var pending := _drop_pending
	_drop_pending = false
	return pending

## Possession handoff: release before hiding; restore platform visibility on exit.
func is_suspended() -> bool:
	return _suspended


func set_suspended(value: bool) -> void:
	if value: _release_all_touches()
	_suspended = value
	_update_visibility()
