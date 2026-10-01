extends SceneTree

const Settle := preload("res://example/tests/settle_cinematic.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var scene: PackedScene = load("res://example/scenes/main.tscn")
	root.add_child(scene.instantiate())
	await process_frame
	await process_frame
	await process_frame
	var world: Node = root.get_node("World")
	var neighborhood: Node = world.scenes.get_active_world_root()
	var player: LibertyCharacter = neighborhood.get_node("Player")
	var mobile := player.get_node("MobileControls") as LibertyMobileControls
	mobile.force_visible = true
	var save_button := mobile.get_custom_button("SAVE")
	var load_button := mobile.get_custom_button("LOAD")
	if save_button == null or load_button == null:
		push_error("Neighborhood is missing SAVE or LOAD")
		quit(1)
		return
	var driving := player.get_node_or_null("VehicleMobileControls") as LibertyVehicleMobileControls
	if driving == null or driving.get_custom_button("SAVE") == null or driving.get_custom_button("LOAD") == null:
		push_error("Driving overlay is missing SAVE or LOAD")
		quit(2)
		return
	var coordinator: Node = neighborhood.get_node("ErrandCoordinator")
	if not coordinator.pick_up_package():
		quit(3)
		return
	await Settle.settle(self)
	_tap(save_button, 20)
	await world.events.save_completed
	await process_frame
	if not "Saved" in neighborhood.status.text:
		push_error("On-foot SAVE did not report completion: %s" % neighborhood.status.text)
		quit(4)
		return
	if not coordinator.deliver_package():
		quit(5)
		return
	await Settle.settle(self)
	_tap(load_button, 21)
	await world.events.load_completed
	await process_frame
	if bool(world.state.get_value(&"errand.delivered", false)) or not bool(world.state.get_value(&"errand.package_collected", false)):
		push_error("LOAD did not restore the saved errand")
		quit(6)
		return
	var restored: Node = world.scenes.get_active_world_root()
	if not "Loaded" in restored.status.text:
		push_error("LOAD did not report completion: %s" % restored.status.text)
		quit(7)
		return
	var restored_player := restored.get_node("Player") as LibertyCharacter
	var restored_drive := restored_player.get_node_or_null("VehicleMobileControls") as LibertyVehicleMobileControls
	if restored_drive == null or restored_drive.get_custom_button("SAVE") == null:
		push_error("Restored driving overlay is missing SAVE")
		quit(8)
		return
	if not restored.get_node("ErrandCoordinator").deliver_package():
		quit(9)
		return
	await Settle.settle(self)
	for _i in 8:
		await physics_frame
	restored_player.teleport_to(Transform3D(Basis.IDENTITY, Vector3(6, 0.1, -6)))
	for _frame in 12:
		await physics_frame
	var restored_mobile := restored_player.get_node("MobileControls") as LibertyMobileControls
	restored_mobile.force_visible = true
	_tap(restored_mobile.get_custom_button("ENTER"), 22)
	var adapter := restored_player.get_node("EventAdapter") as LibertyEventAdapter
	var mounted := false
	for _i in 20:
		await physics_frame
		if adapter.mounted_vehicle != null:
			mounted = true
			break
	if not mounted:
		var seat := restored.get_node("Sedan/DriverSeat") as Area3D
		push_error("ENTER did not mount for the driving save check (suspended=%s monitoring=%s borrowed=%s at=%s)" % [
			restored_player.is_body_suspended(), seat.monitoring, adapter.is_presentation_borrowed(), restored_player.global_position,
		])
		quit(10)
		return
	_tap(restored_drive.get_custom_button("SAVE"), 23)
	await world.events.save_completed
	await process_frame
	var driving_world: Node = world.scenes.get_active_world_root()
	if not "Saved" in driving_world.status.text:
		push_error("Driving SAVE did not report completion: %s" % driving_world.status.text)
		quit(11)
		return
	adapter.dismount()
	await physics_frame
	if world.travel_to(&"home", &"home_entry") != OK:
		quit(12)
		return
	await world.events.transition_completed
	await process_frame
	var home: Node = world.scenes.get_active_world_root()
	var home_mobile := home.get_node("Player/MobileControls") as LibertyMobileControls
	home_mobile.force_visible = true
	var home_save := home_mobile.get_custom_button("SAVE")
	if home_save == null or home_mobile.get_custom_button("LOAD") == null:
		push_error("Home is missing SAVE or LOAD")
		quit(13)
		return
	_tap(home_save, 24)
	await world.events.save_completed
	await process_frame
	if not "Saved" in home.status.text:
		push_error("Home SAVE did not report completion: %s" % home.status.text)
		quit(14)
		return
	print("EXAMPLE_MOBILE_SAVE_PASS")
	quit()

func _tap(button: Panel, touch_index: int) -> void:
	var position_value := button.global_position + button.size * 0.5
	var press := InputEventScreenTouch.new()
	press.index = touch_index
	press.position = position_value
	press.pressed = true
	Input.parse_input_event(press)
	var release := InputEventScreenTouch.new()
	release.index = touch_index
	release.position = position_value
	release.pressed = false
	Input.parse_input_event(release)
