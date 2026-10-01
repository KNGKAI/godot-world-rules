extends SceneTree
const S = preload("res://modules/liberty_character/tests/liberty_test_support.gd")
const Sedan = preload("res://modules/liberty_vehicle/vehicle/liberty_vehicle.tscn")
const Character = preload("res://modules/liberty_character/character/liberty_character.tscn")
var records: Array = []
var observed_restore := false
func _initialize() -> void: call_deferred("run")
func run() -> void:
	await teardown_case(false)
	await teardown_case(true)
	print("vehicle cached teardown PASS")
	quit(S.exit_code())
func teardown_case(no_record: bool) -> void:
	records.clear()
	observed_restore = false
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	floor_body.position = Vector3(40, -0.5, 0)
	var shape := CollisionShape3D.new()
	var cube := BoxShape3D.new()
	cube.size = Vector3(60, 1, 60)
	shape.shape = cube
	floor_body.add_child(shape)
	root.add_child(floor_body)
	var vehicle := Sedan.instantiate() as LibertyVehicle
	vehicle.position = Vector3(40, 0, 0)
	vehicle.freeze = true
	root.add_child(vehicle)
	var character := Character.instantiate() as LibertyCharacter
	character.position = Vector3(38.65, 0.02, -0.4)
	root.add_child(character)
	await frames(12)
	var adapter := character.get_node("EventAdapter") as LibertyEventAdapter
	var mobile := character.get_node("MobileControls") as LibertyMobileControls
	mobile.force_visible = true
	var events := character.get_node("Events") as LibertyEvents
	events.occupancy_changed.connect(func(_v, _s, _o, mounted, cause): records.append([mounted, cause]))
	var camera := root.get_camera_3d()
	S.expect_true(adapter.mount(vehicle, &"driver_front_left").succeeded(), "fixture mounts")
	await frames(2)
	var expected := vehicle.possession.cached_exit.origin
	if no_record:
		vehicle.possession.has_cached_exit = false
		vehicle.possession.has_safe_transform = false
		expected = vehicle.possession.cached_vehicle_position
	# Observe the character state transition inside unsuspension, before camera restoration.
	events.movement_state_changed.connect(func(old_state, new_state):
		if old_state == &"movement_locked" and new_state != &"movement_locked":
			observed_restore = true
			S.expect_true(character.global_position.distance_to(expected) < 0.001, "exit transform precedes capsule enable")
			S.expect_true(character.get_node("Rig").visible, "Rig shown before unsuspend")
			S.expect_true(mobile.visible, "overlay policy restored before unsuspend")
			S.expect_false(camera.current, "stored camera is restored after unsuspend")
	)
	# Root handler runs after DriverSeat and exit marker have exited.
	vehicle.queue_free()
	await frames(2)
	S.expect_true(observed_restore, "observed ordered character restore")
	S.expect_equal(records.size(), 2, "mount and teardown emit once each")
	S.expect_equal(records[-1][1], &"teardown_best_effort" if no_record else &"teardown_grounded", "cache determines teardown cause")
	S.expect_true(character.global_position.distance_to(expected) < 0.05, "teardown uses cache, not exited child identity")
	S.expect_true(character.global_position.x > 30.0, "never relocated to world origin")
	if no_record: S.expect_true(absf(character.global_position.y) < 0.05, "no-record fallback adds no capsule-center raise")
	S.expect_true(camera.current, "stored camera restored")
	S.expect_true(character.vehicle_possession == null, "teardown clears occupancy")
	character.free()
	floor_body.free()
	await frames(1)
func frames(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame
