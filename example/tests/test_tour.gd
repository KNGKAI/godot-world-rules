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
	var coordinator: Node = neighborhood.get_node("ErrandCoordinator")
	if coordinator.park_sedan():
		push_error("Parking completed before the sedan was unlocked")
		quit(1)
		return
	if not coordinator.pick_up_package() or not coordinator.deliver_package():
		quit(2)
		return
	var sedan: Node3D = neighborhood.get_node("Sedan")
	sedan.global_position = neighborhood.park_bay + Vector3(0, 0.4, 0)
	sedan.linear_velocity = Vector3.ZERO
	for i in 8:
		await physics_frame
	if not bool(world.state.get_value(&"errand.tour_complete", false)):
		push_error("Parking the sedan in the bay did not complete the tour")
		quit(3)
		return
	if not "Tour finished" in neighborhood.status.text:
		quit(4)
		return
	if not "[x]" in neighborhood.objectives.text:
		quit(5)
		return
	print("EXAMPLE_TOUR_PASS")
	quit()
