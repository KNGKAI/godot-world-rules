extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var scene: PackedScene = load("res://example/scenes/main.tscn")
	var app: Node = scene.instantiate()
	root.add_child(app)
	await process_frame
	await process_frame
	var world: Node = root.get_node("World")
	var neighborhood: Node = world.scenes.get_active_world_root()
	var seat: Area3D = neighborhood.get_node("Sedan/DriverSeat")
	await process_frame
	if seat.monitoring:
		push_error("Sedan is mountable before unlock")
		quit(1)
		return
	var errand: Node = neighborhood.get_node("ErrandCoordinator")
	if not errand.pick_up_package() or not errand.deliver_package():
		push_error("Errand did not unlock sedan")
		quit(2)
		return
	await process_frame
	if not seat.monitoring:
		push_error("Sedan remained locked")
		quit(3)
		return
	if world.save_game(&"example_test") != OK:
		quit(4)
		return
	await world.events.save_completed
	await process_frame
	if world.travel_to(&"home", &"home_entry") != OK:
		quit(5)
		return
	await world.events.transition_completed
	await process_frame
	if world.scenes.get_active_world_id() != &"home":
		quit(6)
		return
	if world.travel_to(&"neighborhood", &"home_return") != OK:
		quit(7)
		return
	await world.events.transition_completed
	await process_frame
	if world.scenes.get_active_world_id() != &"neighborhood":
		quit(8)
		return
	if world.load_game(&"example_test") != OK:
		quit(9)
		return
	await world.events.load_completed
	if not bool(world.state.get_value(&"errand.vehicle_unlocked", false)):
		quit(10)
		return
	var restored: Node = world.scenes.get_active_world_root()
	if not (restored.get_node("Sedan/DriverSeat") as Area3D).monitoring:
		quit(11)
		return
	if not "Delivery complete" in restored.status.text:
		quit(12)
		return
	print("EXAMPLE_FLOW_PASS")
	quit()
