class_name LibertyVehicleCourse
extends Node3D
const CharacterScene = preload("res://modules/liberty_character/character/liberty_character.tscn")
const SedanScene = preload("res://modules/liberty_vehicle/vehicle/liberty_vehicle.tscn")
var character: LibertyCharacter
var vehicles: Array[LibertyVehicle] = []
var _adapter: LibertyEventAdapter
var _obstruction: StaticBody3D
var _status: Label
var _course_controls: CourseTouchControls

func _ready() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -25, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.35, 0.48, 0.62)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.7, 0.76, 0.8)
	environment.environment.ambient_light_energy = 0.6
	add_child(environment)
	_box(Vector3(0, -0.5, -20), Vector3(100, 1, 140), 1, Color(0.22, 0.28, 0.23))
	for z in range(-70, 30, 10):
		_box(Vector3(0, 0.01, z), Vector3(0.12, 0.02, 4), 0, Color(0.9, 0.88, 0.72))
	# Pillars and wall exercise chase-camera collision during the drive.
	_box(Vector3(6, 2, -12), Vector3(1.5, 4, 1.5), 1, Color(0.5, 0.45, 0.4))
	_box(Vector3(-6, 2, -15), Vector3(1.5, 4, 1.5), 1, Color(0.5, 0.45, 0.4))
	_box(Vector3(9, 2, -35), Vector3(1, 4, 25), 1, Color(0.4, 0.4, 0.43))
	for position in [Vector3(0, 0.2, 0), Vector3(14, 0.05, 0)]:
		var car := SedanScene.instantiate() as LibertyVehicle
		car.position = position
		add_child(car)
		vehicles.append(car)
	vehicles[1].freeze = true
	var orange := StandardMaterial3D.new()
	orange.albedo_color = Color(0.85, 0.32, 0.07)
	vehicles[1].get_node("Body").material_override = orange
	_obstruction = _box(Vector3(14, 1.5, 0), Vector3(7, 3, 7), 16, Color(0.4, 0.2, 0.15, 0.12))
	_obstruction.get_node("CollisionShape3D").disabled = true
	_obstruction.get_node("MeshInstance3D").visible = false
	character = CharacterScene.instantiate() as LibertyCharacter
	character.position = Vector3(-1.5, 0.1, -0.4)
	add_child(character)
	_adapter = character.get_node("EventAdapter") as LibertyEventAdapter
	_adapter.allow_vehicle_reset = true
	var events := character.get_node("Events") as LibertyEvents
	events.occupancy_changed.connect(_occupancy_changed)
	var overlay := CanvasLayer.new()
	overlay.layer = 3
	add_child(overlay)
	_status = Label.new()
	_status.position = Vector2(20, 110)
	_status.add_theme_font_size_override(&"font_size", 18)
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(_status)
	call_deferred("_add_course_buttons")

func _add_course_buttons() -> void:
	_course_controls = CourseTouchControls.new()
	_course_controls.name = "CourseControls"
	add_child(_course_controls)
	_course_controls.remove_requested.connect(_remove_occupied_vehicle)
	var mobile := character.get_node("MobileControls") as LibertyMobileControls
	mobile.add_custom_button("RETURN", Color(0.8, 0.25, 0.2, 0.8), _return_character)

func _occupancy_changed(vehicle_id: int, _seat: StringName, _occupant: int, mounted: bool, _cause: StringName) -> void:
	if is_instance_valid(vehicles[1]) and vehicle_id == vehicles[1].get_instance_id():
		_obstruction.get_node("CollisionShape3D").set_deferred("disabled", not mounted)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_DELETE:
		_remove_occupied_vehicle()

func _remove_occupied_vehicle() -> void:
	if is_instance_valid(_adapter.mounted_vehicle):
		_obstruction.get_node("CollisionShape3D").set_deferred("disabled", true)
		_adapter.mounted_vehicle.queue_free()

func _process(_delta: float) -> void:
	if is_instance_valid(_course_controls):
		var mobile := character.get_node("MobileControls") as LibertyMobileControls
		_course_controls.visible = is_instance_valid(_adapter.mounted_vehicle) and (mobile.force_visible or DisplayServer.is_touchscreen_available())
	_status.text = "Q / ENTER: mount     Q / EXIT: dismount\nWASD: drive     Space: handbrake     C: camera\nR: reset sedan     Delete / REMOVE: remove occupied sedan\nBlue: open road. Orange: blocked-exit demonstration.\nRETURN resets your on-foot position."
	if _adapter.last_reason != &"": _status.text += "\n" + String(_adapter.last_reason)

func _return_character() -> void:
	if not character.is_body_suspended():
		character.teleport_to(Transform3D(Basis.IDENTITY, Vector3(-1.5, 0.1, -0.4)))

func _box(position_value: Vector3, size_value: Vector3, layer_value: int, color: Color) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = position_value
	body.collision_layer = layer_value
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	shape.name = "CollisionShape3D"
	var cube := BoxShape3D.new()
	cube.size = size_value
	shape.shape = cube
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	mesh.name = "MeshInstance3D"
	var box_mesh := BoxMesh.new()
	box_mesh.size = size_value
	mesh.mesh = box_mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	mesh.material_override = material
	body.add_child(mesh)
	add_child(body)
	return body

## Course-only touch escape, added after the character so it receives this region
## before the driver's touch layer consumes the rest of the screen.
class CourseTouchControls extends CanvasLayer:
	signal remove_requested
	var button: Panel
	func _ready() -> void:
		layer = 4
		button = Panel.new()
		button.name = "REMOVE"
		button.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.75, 0.16, 0.12, 0.9)
		button.add_theme_stylebox_override(&"panel", style)
		add_child(button)
		var label := Label.new()
		label.text = "REMOVE"
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(label)
		get_viewport().size_changed.connect(_layout)
		_layout()
		visible = false
	func _layout() -> void:
		var safe := get_viewport().get_visible_rect()
		if DisplayServer.get_name() != "headless":
			var screen := Vector2(DisplayServer.screen_get_size())
			var area := DisplayServer.get_display_safe_area()
			if screen.x > 0.0 and screen.y > 0.0 and area.size.x > 0:
				var scale := safe.size / screen
				safe = safe.intersection(Rect2(Vector2(area.position) * scale, Vector2(area.size) * scale))
		button.size = Vector2(minf(112.0, safe.size.x * 0.4), minf(64.0, safe.size.y * 0.2))
		button.position = safe.position + Vector2(24, 24)
	func _input(event: InputEvent) -> void:
		if visible and event is InputEventScreenTouch and event.pressed and button.get_global_rect().has_point(event.position):
			remove_requested.emit()
			get_viewport().set_input_as_handled()
