extends Node3D

const CHARACTER: PackedScene = preload("res://modules/liberty_character/character/liberty_character.tscn")
const SEDAN: PackedScene = preload("res://modules/liberty_vehicle/vehicle/liberty_vehicle.tscn")
const COORDINATOR: Script = preload("res://example/integration/errand_coordinator.gd")
const BLOCK: Script = preload("res://example/integration/neighborhood_block.gd")
const SAVE_TOUCH: Script = preload("res://example/integration/save_touch.gd")

const PACKAGE_AT := Vector3(2, 0, 7)
const CONTACT_AT := Vector3(0, 0, -7)
const HOME_DOOR_AT := Vector3(-8, 0, 7)
const PARK_BAY := Vector3(-8, 0, -24)
const INTERACT_REACH := 2.2
const PARK_REACH := 4.5

var player: LibertyCharacter
var sedan: LibertyVehicle
var coordinator: ErrandCoordinator
var status: Label
var objectives: Label
var travel_pending := false
var park_bay := PARK_BAY


func _ready() -> void:
	_add_environment()
	BLOCK.build(self)
	player = CHARACTER.instantiate() as LibertyCharacter
	player.name = "Player"
	player.position = Vector3(0, 0.1, 9)
	add_child(player)
	var mobile := player.get_node("MobileControls") as LibertyMobileControls
	mobile.add_custom_button("USE", Color(0.85, 0.62, 0.18, 0.85), _interact)
	SAVE_TOUCH.attach(player, _save, _load)
	call_deferred("_attach_driving_save")
	sedan = SEDAN.instantiate() as LibertyVehicle
	sedan.name = "Sedan"
	sedan.position = Vector3(7, 0.1, -6)
	add_child(sedan)
	_add_cinematic_markers()
	coordinator = COORDINATOR.new() as ErrandCoordinator
	coordinator.name = "ErrandCoordinator"
	add_child(coordinator)
	coordinator.progress_changed.connect(_sync_sedan_gate)
	coordinator.status_changed.connect(_set_status)
	_sync_sedan_gate()
	_add_hud()
	World.events.transition_completed.connect(_on_travel_terminal)
	World.events.transition_failed.connect(_on_travel_failed)
	World.events.save_completed.connect(_on_save_completed)
	World.events.save_failed.connect(_on_save_failed)
	World.events.load_completed.connect(_on_load_completed)
	World.events.load_failed.connect(_on_load_failed)


func _attach_driving_save() -> void:
	if player != null:
		SAVE_TOUCH.attach(player, _save, _load)


func _physics_process(_delta: float) -> void:
	if sedan == null or coordinator == null:
		return
	if bool(World.state.get_value(&"errand.tour_complete", false)):
		return
	var flat := sedan.global_position
	flat.y = 0.0
	if flat.distance_to(park_bay) <= PARK_REACH:
		coordinator.park_sedan()


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


func _interact() -> void:
	if player.is_body_suspended():
		return
	var position_value := player.global_position
	if position_value.distance_to(PACKAGE_AT) < INTERACT_REACH:
		if not coordinator.pick_up_package():
			_set_status("Package already collected.")
	elif position_value.distance_to(CONTACT_AT) < INTERACT_REACH:
		if not coordinator.deliver_package():
			_set_status("Collect the package first.")
	elif position_value.distance_to(HOME_DOOR_AT) < INTERACT_REACH and not travel_pending:
		_enter_home()
	else:
		_set_status("Move closer to a colored marker and press F or USE.")


func _sync_sedan_gate() -> void:
	var unlocked := bool(World.state.get_value(&"errand.vehicle_unlocked", false))
	if sedan != null:
		var seat := sedan.get_node("DriverSeat") as Area3D
		seat.set_deferred("monitoring", unlocked)
		seat.set_deferred("monitorable", unlocked)
	if status != null:
		_update_progress_status()


func _update_progress_status() -> void:
	if bool(World.state.get_value(&"errand.tour_complete", false)):
		_set_status("Delivery complete. The sedan is parked. Tour finished.")
	elif bool(World.state.get_value(&"errand.delivered", false)):
		_set_status("Delivery complete. The blue sedan is unlocked. Drive it to the amber bay.")
	elif bool(World.state.get_value(&"errand.package_collected", false)):
		_set_status("Package collected. Cross the wall and deliver it.")
	else:
		_set_status("Pick up the package at the gold marker.")
	_refresh_objectives()


func _enter_home() -> void:
	var director := _cinematic_director()
	var cinematic := _cinematic_coordinator()
	if cinematic != null and director != null:
		var err := cinematic.play_direct(&"home_door")
		if err == OK:
			# A refused travel_to finishes inside play() and leaves the travel id at 0.
			if World.current_travel_id() != 0:
				travel_pending = true
			return
		if director.is_sequence_active():
			return
	var travel_err := World.travel_to(&"home", &"home_entry")
	if travel_err == OK:
		travel_pending = true
	else:
		_set_status("Home travel rejected: %s" % error_string(travel_err))


func _save() -> void:
	var director := _cinematic_director()
	if director != null and director.is_sequence_active():
		_set_status("Save rejected during cinematic")
		return
	var err := World.save_game(&"example_01")
	if err == OK and director != null:
		director.notify_guard_accepted(&"save_game")
	_set_status("Saving..." if err == OK else "Save rejected: %s" % error_string(err))


func _load() -> void:
	var director := _cinematic_director()
	if director != null and director.is_sequence_active():
		_set_status("Load rejected during cinematic")
		return
	var err := World.load_game(&"example_01")
	if err == OK and director != null:
		director.notify_guard_accepted(&"load_game")
	_set_status("Loading..." if err == OK else "Load rejected: %s" % error_string(err))


func _on_travel_terminal(_context: Dictionary) -> void:
	travel_pending = false


func _on_travel_failed(reason: Error, _context: Dictionary) -> void:
	travel_pending = false
	_set_status("Travel failed: %s" % error_string(reason))


func _on_save_completed(_context: Dictionary) -> void:
	_set_status("Saved to example_01.")


func _on_save_failed(reason: Error, _context: Dictionary) -> void:
	_set_status("Save failed: %s" % error_string(reason))


func _on_load_completed(_context: Dictionary) -> void:
	_sync_sedan_gate()
	_set_status("Loaded example_01. " + status.text)


func _on_load_failed(reason: Error, _context: Dictionary) -> void:
	_set_status("Load failed: %s" % error_string(reason))


func _set_status(message: String) -> void:
	if status != null:
		status.text = message


func _refresh_objectives() -> void:
	if objectives == null:
		return
	var collected := bool(World.state.get_value(&"errand.package_collected", false))
	var delivered := bool(World.state.get_value(&"errand.delivered", false))
	var parked := bool(World.state.get_value(&"errand.tour_complete", false))
	objectives.text = "%s Gold marker: pick up the package\n%s Vault the brown wall and deliver at the green marker\n%s Drive the sedan into the amber bay\n[ ] Blue marker: optional home visit" % [
		_box_mark(collected), _box_mark(delivered), _box_mark(parked),
	]


func _box_mark(done: bool) -> String:
	return "[x]" if done else "[ ]"


func _add_hud() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var panel := ColorRect.new()
	panel.position = Vector2(12, 12)
	panel.size = Vector2(760, 148)
	panel.color = Color(0.05, 0.07, 0.09, 0.74)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(panel)
	status = Label.new()
	status.position = Vector2(24, 18)
	status.size = Vector2(730, 28)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.add_theme_font_size_override(&"font_size", 18)
	status.add_theme_color_override(&"font_color", Color(0.96, 0.94, 0.88))
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(status)
	objectives = Label.new()
	objectives.position = Vector2(24, 48)
	objectives.size = Vector2(730, 72)
	objectives.add_theme_font_size_override(&"font_size", 15)
	objectives.add_theme_color_override(&"font_color", Color(0.86, 0.88, 0.9))
	objectives.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(objectives)
	var help := Label.new()
	help.position = Vector2(24, 122)
	help.text = "F / USE interact   Q / ENTER sedan   WASD drive   E / CLIMB vault   Space handbrake   C camera   F5 / SAVE   F9 / LOAD   Esc skip"
	help.add_theme_font_size_override(&"font_size", 14)
	help.add_theme_color_override(&"font_color", Color(0.78, 0.8, 0.84))
	help.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(help)
	_update_progress_status()


func _cinematic_director() -> CinematicDirector:
	var app := get_tree().root.get_node_or_null("NeighborhoodErrand")
	if app == null:
		return null
	return app.get_node_or_null("CinematicDirector") as CinematicDirector


func _cinematic_coordinator() -> CinematicCoordinator:
	var app := get_tree().root.get_node_or_null("NeighborhoodErrand")
	if app == null:
		return null
	return app.get_node_or_null("CinematicCoordinator") as CinematicCoordinator


func _add_cinematic_markers() -> void:
	_marker("Package", PACKAGE_AT)
	_marker("Contact", CONTACT_AT)
	_marker("HomeDoor", HOME_DOOR_AT)
	_marker("ParkBay", PARK_BAY)
	var view := _marker("SedanView", Vector3(7, 1.6, -2))
	view.look_at(Vector3(7, 0.8, -6), Vector3.UP)


func _marker(marker_name: String, at: Vector3) -> Marker3D:
	var marker := Marker3D.new()
	marker.name = marker_name
	marker.position = at
	add_child(marker)
	return marker


func _add_environment() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -32, 0)
	sun.shadow_enabled = true
	sun.light_energy = 1.15
	add_child(sun)
	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.32, 0.5, 0.78)
	sky_material.sky_horizon_color = Color(0.74, 0.8, 0.84)
	sky_material.ground_bottom_color = Color(0.28, 0.34, 0.24)
	sky_material.ground_horizon_color = Color(0.52, 0.56, 0.5)
	sky.sky_material = sky_material
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.72
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.72, 0.78, 0.82)
	environment.fog_density = 0.0035
	world_environment.environment = environment
	add_child(world_environment)
