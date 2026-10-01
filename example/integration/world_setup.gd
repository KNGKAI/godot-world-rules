extends Node

const NEIGHBORHOOD: PackedScene = preload("res://example/scenes/neighborhood.tscn")
const HOME: PackedScene = preload("res://example/scenes/home.tscn")

var status: Label


func _ready() -> void:
	World.events.world_loaded.connect(_on_world_loaded)
	World.events.transition_failed.connect(_on_transition_failed)
	var director := CinematicDirector.new()
	director.name = "CinematicDirector"
	add_child(director)
	var coordinator := CinematicCoordinator.new()
	coordinator.name = "CinematicCoordinator"
	add_child(coordinator)
	coordinator.bind_director(director)
	var neighborhood := WorldDefinition.new()
	neighborhood.id = &"neighborhood"
	neighborhood.scene = NEIGHBORHOOD
	var home := WorldDefinition.new()
	home.id = &"home"
	home.scene = HOME
	if World.scenes.register_world(neighborhood) != OK or World.scenes.register_world(home) != OK:
		push_error("Could not register example worlds")
		return
	if World.scenes.load_world(&"neighborhood", &"street_start") != OK:
		push_error("Could not load neighborhood")


func _on_world_loaded(_context: Dictionary, entry: WorldEntryPointData) -> void:
	if entry is WorldEntryPoint3DData:
		var actor := World.scenes.get_active_world_root().get_node_or_null("Player") as LibertyCharacter
		if actor != null:
			actor.teleport_to((entry as WorldEntryPoint3DData).transform)


func _on_transition_failed(reason: Error, _context: Dictionary) -> void:
	push_warning("Travel failed: %s" % error_string(reason))
