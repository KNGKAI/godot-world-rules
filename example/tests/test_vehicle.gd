extends SceneTree

const Settle := preload("res://example/tests/settle_cinematic.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var scene: PackedScene = load("res://example/scenes/main.tscn")
	root.add_child(scene.instantiate())
	await process_frame
	await process_frame
	var neighborhood: Node = root.get_node("World").scenes.get_active_world_root()
	var character: LibertyCharacter = neighborhood.get_node("Player")
	var sedan: LibertyVehicle = neighborhood.get_node("Sedan")
	var adapter: LibertyEventAdapter = character.get_node("EventAdapter")
	character.teleport_to(Transform3D(Basis.IDENTITY, Vector3(6, 0.1, -6)))
	for i in 12:
		await physics_frame
	adapter.interact()
	if adapter.mounted_vehicle != null:
		quit(1)
		return
	var coordinator: Node = neighborhood.get_node("ErrandCoordinator")
	coordinator.pick_up_package()
	coordinator.deliver_package()
	await Settle.settle(self)
	for i in 12:
		await physics_frame
	adapter.interact()
	if adapter.mounted_vehicle != sedan:
		quit(2)
		return
	var initial_position := sedan.global_position
	Input.action_press(&"liberty_vehicle_throttle")
	for i in 120:
		await physics_frame
	Input.action_release(&"liberty_vehicle_throttle")
	if sedan.global_position.distance_to(initial_position) < 0.5:
		quit(3)
		return
	print("EXAMPLE_VEHICLE_PASS")
	quit()
