extends SceneTree
const S = preload("res://modules/liberty_character/tests/liberty_test_support.gd")
const Sedan = preload("res://modules/liberty_vehicle/vehicle/liberty_vehicle.tscn")
const Character = preload("res://modules/liberty_character/character/liberty_character.tscn")
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var floor_body := StaticBody3D.new()
	floor_body.position.y = -0.5
	var shape := CollisionShape3D.new()
	var cube := BoxShape3D.new()
	cube.size = Vector3(100, 1, 100)
	shape.shape = cube
	floor_body.add_child(shape)
	root.add_child(floor_body)
	var vehicle := Sedan.instantiate() as LibertyVehicle
	vehicle.freeze = true
	root.add_child(vehicle)
	var character := Character.instantiate() as LibertyCharacter
	character.position = Vector3(-1.35, 0.02, -0.4)
	root.add_child(character)
	await frames(15)
	var adapter := character.get_node("EventAdapter") as LibertyEventAdapter
	var onfoot := character.get_node("MobileControls") as LibertyMobileControls
	onfoot.force_visible = true
	S.expect_true(onfoot.get_custom_button("ENTER") != null, "on-foot mobile mount path is shipped")
	key(KEY_Q, true)
	await frames(1)
	key(KEY_Q, false)
	S.expect_true(adapter.mounted_vehicle == vehicle, "Q mounts once")
	var mount_position := character.global_position
	key(KEY_W, true)
	key(KEY_SPACE, true)
	await frames(5)
	S.expect_true(character.global_position.distance_to(mount_position) < 0.001, "overlapping movement/jump keys do not move character")
	S.expect_true(vehicle.controls.throttle > 0 and vehicle.controls.handbrake, "shared keys route only to driver control")
	key(KEY_W, false)
	key(KEY_SPACE, false)
	await frames(1)
	key(KEY_C, true)
	await frames(1)
	key(KEY_C, false)
	S.expect_true(vehicle.camera_rig.hood_mode and vehicle.camera_rig.hood_camera.current, "C toggles owned hood camera once")
	key(KEY_Q, true)
	await frames(1)
	key(KEY_Q, false)
	S.expect_false(character.is_body_suspended(), "Q dismounts once")
	character.teleport_to(Transform3D(Basis.IDENTITY, mount_position))
	await frames(5)
	var enter := InputEventScreenTouch.new()
	enter.index = 1
	enter.pressed = true
	enter.position = onfoot.get_custom_button("ENTER").get_global_rect().get_center()
	onfoot._input(enter)
	await frames(1)
	S.expect_true(adapter.mounted_vehicle == vehicle, "touch ENTER mounts")
	var drive := character.get_node("VehicleMobileControls") as LibertyVehicleMobileControls
	S.expect_true(drive.visible and not onfoot.visible, "vehicle layer owns touch while mounted")
	var gas := InputEventScreenTouch.new()
	gas.index = 2
	gas.pressed = true
	gas.position = drive.buttons["GAS"].get_global_rect().get_center()
	drive._input(gas)
	await frames(5)
	S.expect_true(vehicle.engine_force < 0.0, "touch GAS drives reference forward sign")
	var exit := InputEventScreenTouch.new()
	exit.index = 3
	exit.pressed = true
	exit.position = drive.buttons["EXIT"].get_global_rect().get_center()
	drive._input(exit)
	await frames(1)
	S.expect_false(character.is_body_suspended(), "touch EXIT dismounts through vehicle layer")
	S.expect_false(Input.is_action_pressed(&"liberty_vehicle_throttle"), "exit releases held GAS before hiding")
	S.expect_false(Input.is_action_pressed(&"liberty_interact"), "exit releases interact too")
	S.expect_true(onfoot.visible and not drive.visible, "on-foot overlay restored")
	S.expect_true(is_zero_approx(vehicle.engine_force), "dismount clears drive force immediately")
	character.free()
	vehicle.free()
	floor_body.free()
	print("keyboard and touch possession PASS")
	quit(S.exit_code())
func key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
func frames(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame
