extends Node3D

const CHARACTER: PackedScene = preload("res://modules/liberty_character/character/liberty_character.tscn")
const SAVE_TOUCH: Script = preload("res://example/integration/save_touch.gd")
var player: LibertyCharacter
var status: Label
var travel_pending := false


func _ready() -> void:
	_add_room()
	player = CHARACTER.instantiate() as LibertyCharacter
	player.name = "Player"
	player.position = Vector3(0, 0.1, 2)
	add_child(player)
	var mobile := player.get_node("MobileControls") as LibertyMobileControls
	mobile.add_custom_button("USE", Color(0.85, 0.62, 0.18, 0.85), _interact)
	SAVE_TOUCH.attach(player, _save, _load)
	call_deferred("_attach_driving_save")
	World.events.save_completed.connect(_on_save_completed)
	World.events.save_failed.connect(_on_save_failed)
	World.events.load_completed.connect(_on_load_completed)
	World.events.load_failed.connect(_on_load_failed)
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var panel := ColorRect.new()
	panel.position = Vector2(12, 12)
	panel.size = Vector2(720, 96)
	panel.color = Color(0.08, 0.06, 0.05, 0.72)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(panel)
	status = Label.new()
	status.position = Vector2(24, 22)
	status.size = Vector2(690, 72)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.add_theme_font_size_override(&"font_size", 18)
	status.add_theme_color_override(&"font_color", Color(0.96, 0.93, 0.86))
	status.text = "Home interior. Press F or USE near the doorway to return. F5 / SAVE stores the world, F9 / LOAD restores it."
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(status)
	World.events.transition_failed.connect(_on_travel_failed)


func _unhandled_input(event: InputEvent) -> void:
	if event is not InputEventKey or not event.pressed or event.echo:
		return
	match event.physical_keycode:
		KEY_F:
			_interact()
		KEY_F5:
			_save()
		KEY_F9:
			_load()


func _attach_driving_save() -> void:
	if player != null:
		SAVE_TOUCH.attach(player, _save, _load)


func _save() -> void:
	var director := _cinematic_director()
	if director != null and director.is_sequence_active():
		status.text = "Save rejected during cinematic"
		return
	var err := World.save_game(&"example_01")
	if err == OK and director != null:
		director.notify_guard_accepted(&"save_game")
	status.text = "Saving..." if err == OK else "Save rejected: %s" % error_string(err)


func _load() -> void:
	var director := _cinematic_director()
	if director != null and director.is_sequence_active():
		status.text = "Load rejected during cinematic"
		return
	var err := World.load_game(&"example_01")
	if err == OK and director != null:
		director.notify_guard_accepted(&"load_game")
	status.text = "Loading..." if err == OK else "Load rejected: %s" % error_string(err)


func _cinematic_director() -> CinematicDirector:
	var app := get_tree().root.get_node_or_null("NeighborhoodErrand")
	if app == null:
		return null
	return app.get_node_or_null("CinematicDirector") as CinematicDirector


func _on_save_completed(_context: Dictionary) -> void:
	status.text = "Saved to example_01."


func _on_save_failed(reason: Error, _context: Dictionary) -> void:
	status.text = "Save failed: %s" % error_string(reason)


func _on_load_completed(_context: Dictionary) -> void:
	status.text = "Loaded example_01."


func _on_load_failed(reason: Error, _context: Dictionary) -> void:
	status.text = "Load failed: %s" % error_string(reason)


func _interact() -> void:
	if player.is_body_suspended() or travel_pending:
		return
	if player.global_position.distance_to(Vector3(0, 0, 4)) >= 3.0:
		status.text = "Move near the doorway and press F or USE."
		return
	var err := World.travel_to(&"neighborhood", &"home_return")
	if err == OK:
		travel_pending = true
	else:
		status.text = "Return rejected: %s" % error_string(err)


func _on_travel_failed(reason: Error, _context: Dictionary) -> void:
	travel_pending = false
	status.text = "Travel failed: %s. Press F or USE to retry." % error_string(reason)


func _add_room() -> void:
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-65, -30, 0)
	light.light_color = Color(1.0, 0.92, 0.8)
	light.light_energy = 0.45
	add_child(light)
	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.16, 0.14, 0.12)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(1.0, 0.86, 0.7)
	environment.ambient_light_energy = 0.7
	world_environment.environment = environment
	add_child(world_environment)
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0, 2.8, -0.4)
	lamp.light_color = Color(1.0, 0.84, 0.62)
	lamp.light_energy = 1.1
	lamp.omni_range = 8.0
	add_child(lamp)
	_box(Vector3(0, -0.5, 0), Vector3(12, 1, 12), Color(0.45, 0.32, 0.22))
	_box(Vector3(-3.2, 2, -5.8), Vector3(5.2, 4, 0.4), Color(0.78, 0.72, 0.62))
	_box(Vector3(3.2, 2, -5.8), Vector3(5.2, 4, 0.4), Color(0.78, 0.72, 0.62))
	_box(Vector3(0, 2, -5.8), Vector3(1.4, 4, 0.4), Color(0.78, 0.72, 0.62))
	_visual(Vector3(0, 1.7, -5.55), Vector3(1.5, 1.4, 0.06), Color(0.55, 0.72, 0.78))
	_box(Vector3(5.8, 2, 0), Vector3(0.4, 4, 12), Color(0.78, 0.72, 0.62))
	_box(Vector3(-5.8, 2, 0), Vector3(0.4, 4, 12), Color(0.78, 0.72, 0.62))
	_box(Vector3(0, 3.85, -0.6), Vector3(12, 0.2, 10.8), Color(0.86, 0.82, 0.74))
	_visual(Vector3(0, 0.02, 0.2), Vector3(3.4, 0.03, 2.4), Color(0.55, 0.22, 0.2))
	_box(Vector3(0, 0.48, -1.2), Vector3(1.5, 0.1, 0.85), Color(0.42, 0.28, 0.18))
	_box(Vector3(-4.2, 0.45, -1), Vector3(0.9, 0.7, 2.2), Color(0.4, 0.32, 0.38))
	_visual(Vector3(0, 0.02, 4.3), Vector3(1.8, 0.03, 0.9), Color(0.62, 0.5, 0.32))
	var doorway := Label3D.new()
	doorway.text = "STREET"
	doorway.font_size = 40
	doorway.modulate = Color(0.95, 0.9, 0.75)
	doorway.position = Vector3(0, 1.8, 4.6)
	doorway.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(doorway)


func _box(at: Vector3, size_value: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	body.position = at
	body.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size_value
	shape.shape = box_shape
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = size_value
	mesh.mesh = box_mesh
	mesh.material_override = _material(color)
	body.add_child(mesh)
	add_child(body)


func _visual(at: Vector3, size_value: Vector3, color: Color) -> void:
	var mesh := MeshInstance3D.new()
	mesh.position = at
	var box_mesh := BoxMesh.new()
	box_mesh.size = size_value
	mesh.mesh = box_mesh
	mesh.material_override = _material(color)
	add_child(mesh)


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.8
	return material
