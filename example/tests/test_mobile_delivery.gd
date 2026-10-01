extends SceneTree

const Settle := preload("res://example/tests/settle_cinematic.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var scene: PackedScene = load("res://example/scenes/main.tscn")
	root.add_child(scene.instantiate())
	await process_frame
	await process_frame
	var world: Node = root.get_node("World")
	var neighborhood: Node = world.scenes.get_active_world_root()
	var player: LibertyCharacter = neighborhood.get_node("Player")
	var mobile: Node = player.get_node("MobileControls")
	mobile.force_visible = true
	var use_button: Panel = mobile.get_custom_button("USE")
	if use_button == null:
		push_error("Neighborhood has no USE touch button")
		quit(1)
		return
	player.teleport_to(Transform3D(Basis.IDENTITY, Vector3(2, 0.1, 7)))
	await process_frame
	_tap(use_button, 10)
	await process_frame
	if not bool(world.state.get_value(&"errand.package_collected", false)):
		quit(2)
		return
	await Settle.settle(self)
	player.teleport_to(Transform3D(Basis.IDENTITY, Vector3(0, 0.1, -7)))
	await process_frame
	_tap(use_button, 11)
	await process_frame
	if not bool(world.state.get_value(&"errand.vehicle_unlocked", false)):
		quit(3)
		return
	player.teleport_to(Transform3D(Basis.IDENTITY, Vector3(-8, 0.1, 7)))
	await process_frame
	await Settle.settle(self)
	_tap(use_button, 12)
	await world.events.transition_completed
	await process_frame
	if world.scenes.get_active_world_id() != &"home":
		quit(4)
		return
	var home: Node = world.scenes.get_active_world_root()
	var home_mobile: Node = home.get_node("Player/MobileControls")
	home_mobile.force_visible = true
	var home_use: Panel = home_mobile.get_custom_button("USE")
	if home_use == null:
		quit(5)
		return
	_tap(home_use, 13)
	await world.events.transition_completed
	await process_frame
	if world.scenes.get_active_world_id() != &"neighborhood":
		quit(6)
		return
	print("EXAMPLE_MOBILE_DELIVERY_PASS")
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
