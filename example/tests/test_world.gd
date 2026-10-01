extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var scene: PackedScene = load("res://example/scenes/main.tscn")
	if scene == null:
		quit(1)
		return
	var app := scene.instantiate()
	root.add_child(app)
	await process_frame
	await process_frame
	var world: Node = root.get_node("World")
	if world.scenes.get_active_world_id() != &"neighborhood":
		quit(2)
		return
	var neighborhood: Node = world.scenes.get_active_world_root()
	if neighborhood.get_node_or_null("Player") == null or neighborhood.get_node_or_null("Sedan") == null:
		quit(3)
		return
	quit()
