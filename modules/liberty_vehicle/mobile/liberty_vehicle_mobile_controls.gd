class_name LibertyVehicleMobileControls
extends CanvasLayer
signal interact_pressed
@export var force_visible := false
@export var safe_margin := 24.0
var active := false
var buttons: Dictionary = {}
var _pointers: Dictionary = {}
var _custom_buttons: Array[Dictionary] = []
var _custom_touches: Dictionary = {}
var _overlay: Control
const ACTIONS := {
	"LEFT": &"liberty_vehicle_steer_left", "RIGHT": &"liberty_vehicle_steer_right",
	"GAS": &"liberty_vehicle_throttle", "BRAKE": &"liberty_vehicle_brake",
	"HANDBRAKE": &"liberty_vehicle_handbrake", "CAMERA": &"liberty_vehicle_toggle_camera",
	"EXIT": &"liberty_interact",
}

func _ready() -> void:
	layer = 2
	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay)
	for title: String in ACTIONS:
		var button := Panel.new()
		button.name = title
		button.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.08, 0.24, 0.36, 0.8)
		style.set_corner_radius_all(12)
		button.add_theme_stylebox_override(&"panel", style)
		_overlay.add_child(button)
		var label := Label.new()
		label.text = title
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(label)
		buttons[title] = button
	get_viewport().size_changed.connect(_layout)
	_layout()
	set_active(false)

func set_active(enabled: bool) -> void:
	if not enabled: release_all_touches()
	active = enabled
	visible = active and (force_visible or DisplayServer.is_touchscreen_available())

func _input(event: InputEvent) -> void:
	if not visible: return
	if event is InputEventScreenTouch:
		if event.pressed:
			if not _press_custom(event.index, event.position):
				for title: String in buttons:
					if buttons[title].get_global_rect().has_point(event.position):
						press_pointer(event.index, ACTIONS[title])
						break
		else:
			_custom_touches.erase(event.index)
			release_pointer(event.index)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		get_viewport().set_input_as_handled()

## Extra actions that are not driving inputs. The driving overlay consumes every
## screen touch, so a scene registers these instead of adding its own buttons.
func add_custom_button(title: String, color: Color, callback: Callable) -> Panel:
	var button := Panel.new()
	button.name = title.to_pascal_case()
	button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(12)
	button.add_theme_stylebox_override(&"panel", style)
	_overlay.add_child(button)
	var label := Label.new()
	label.text = title
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(label)
	_custom_buttons.append({"title": title, "panel": button, "callback": callback})
	_layout()
	return button

func get_custom_button(title: String) -> Panel:
	for button in _custom_buttons:
		if button.title == title:
			return button.panel
	return null

func _press_custom(pointer: int, at: Vector2) -> bool:
	if _custom_touches.has(pointer): return true
	for button in _custom_buttons:
		var panel := button.panel as Panel
		if panel.get_global_rect().has_point(at):
			_custom_touches[pointer] = button.title
			(button.callback as Callable).call()
			return true
	return false

func press_pointer(pointer: int, action: StringName) -> void:
	if not active or _pointers.has(pointer): return
	_pointers[pointer] = action
	Input.action_press(action)
	if action == &"liberty_interact": interact_pressed.emit()

func release_pointer(pointer: int) -> void:
	if not _pointers.has(pointer): return
	var action: StringName = _pointers[pointer]
	_pointers.erase(pointer)
	if not _pointers.values().has(action): Input.action_release(action)

func release_all_touches() -> void:
	_custom_touches.clear()
	for pointer: int in _pointers.keys(): release_pointer(pointer)

func _notification(what: int) -> void:
	if what in [NOTIFICATION_WM_WINDOW_FOCUS_OUT, NOTIFICATION_APPLICATION_FOCUS_OUT]: release_all_touches()

func _exit_tree() -> void: release_all_touches()

func _safe_rect() -> Rect2:
	var rect := get_viewport().get_visible_rect()
	if DisplayServer.get_name() != "headless":
		var screen := Vector2(DisplayServer.screen_get_size())
		var area := DisplayServer.get_display_safe_area()
		if screen.x > 0.0 and screen.y > 0.0 and area.size.x > 0:
			var scale := rect.size / screen
			rect = rect.intersection(Rect2(Vector2(area.position) * scale, Vector2(area.size) * scale))
	return rect.grow(-minf(safe_margin, minf(rect.size.x, rect.size.y) * 0.1))

func _layout() -> void:
	var safe := _safe_rect()
	var size := Vector2(minf(112.0, safe.size.x / 4.0), minf(80.0, safe.size.y / 3.0))
	var index := 0
	for title: String in buttons:
		var button: Panel = buttons[title]
		button.size = size
		var column := index % 4
		var row := index / 4
		button.position = Vector2(safe.position.x + column * (safe.size.x - size.x) / 3.0, safe.end.y - size.y * (row + 1))
		index += 1
	var custom_size := Vector2(minf(112.0, safe.size.x / 4.0), minf(72.0, safe.size.y / 5.0))
	for custom_index in _custom_buttons.size():
		var custom: Panel = _custom_buttons[custom_index].panel
		custom.size = custom_size
		custom.position = Vector2(safe.end.x - custom_size.x * (custom_index + 1) - 8.0 * custom_index, safe.position.y)
