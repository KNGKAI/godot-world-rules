extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var scene: PackedScene = load("res://example/scenes/main.tscn")
	root.add_child(scene.instantiate())
	await process_frame
	await process_frame
	var world: Node = root.get_node("World")
	if world.load_game(&"example_test") != OK:
		quit(1)
		return
	await world.events.load_completed
	await process_frame
	if not bool(world.state.get_value(&"errand.vehicle_unlocked", false)):
		quit(2)
		return
	var neighborhood: Node = world.scenes.get_active_world_root()
	if not (neighborhood.get_node("Sedan/DriverSeat") as Area3D).monitoring:
		quit(3)
		return
	print("EXAMPLE_RESTART_PASS")
	quit()
