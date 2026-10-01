extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var scene: PackedScene = load("res://example/scenes/main.tscn")
	root.add_child(scene.instantiate())
	await process_frame
	await process_frame
	var world: Node = root.get_node("World")
	var neighborhood: Node = world.scenes.get_active_world_root()
	if world.load_game(&"missing_example_slot_999") != OK:
		quit(1)
		return
	await world.events.load_failed
	await process_frame
	if not "Load failed" in neighborhood.status.text:
		quit(2)
		return
	if not neighborhood.get_node("ErrandCoordinator").pick_up_package():
		quit(3)
		return
	print("EXAMPLE_FAILURE_PASS")
	quit()
