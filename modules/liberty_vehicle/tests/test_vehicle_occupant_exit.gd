extends SceneTree
const S = preload("res://modules/liberty_character/tests/liberty_test_support.gd")
const Sedan = preload("res://modules/liberty_vehicle/vehicle/liberty_vehicle.tscn")
const Character = preload("res://modules/liberty_character/character/liberty_character.tscn")
func _initialize() -> void: call_deferred("run")
func run() -> void:
	await exit_case(false)
	await exit_case(true)
	print("occupant detach/free cleanup PASS")
	quit(S.exit_code())
func exit_case(free_occupant: bool) -> void:
	var ground := StaticBody3D.new()
	ground.position = Vector3(20, -0.5, 0)
	var shape := CollisionShape3D.new()
	var cube := BoxShape3D.new()
	cube.size = Vector3(60, 1, 60)
	shape.shape = cube
	ground.add_child(shape)
	root.add_child(ground)
	var car := Sedan.instantiate() as LibertyVehicle
	car.position = Vector3(20, 0, 0)
	car.freeze = true
	root.add_child(car)
	var character := Character.instantiate() as LibertyCharacter
	character.position = Vector3(18.65, 0.02, -0.4)
	root.add_child(character)
	await frames(12)
	var adapter := character.get_node("EventAdapter") as LibertyEventAdapter
	S.expect_true(adapter.mount(car, &"driver_front_left").succeeded(), "fixture mounts")
	car.engine_force = -1000.0
	if free_occupant: character.free()
	else: root.remove_child(character)
	S.expect_true(car.possession.occupant == null, "departing occupant releases seat synchronously")
	S.expect_false(car.possession.control_enabled, "departing occupant disables driver")
	S.expect_true(is_zero_approx(car.engine_force), "departing occupant clears stale engine force")
	car.queue_free()
	await frames(2)
	if not free_occupant:
		S.expect_false(character.is_body_suspended(), "detached character is restored even if vehicle is removed")
		S.expect_true(character.get_node("Rig").visible, "detached Rig restored")
		root.add_child(character)
		await frames(2)
		S.expect_false(character.is_body_suspended(), "reattached character can move")
		S.expect_true(character.vehicle_possession == null, "reattached character has no stale claim")
		var pivot := character.get_node("CameraPivot") as LibertyCameraPivot
		S.expect_true(pivot.global_position.distance_to(character.global_position + Vector3.UP * pivot.target_height) < 0.001, "reattach snaps character camera")
		S.expect_true(character.get_node("CameraPivot/SpringArm3D/Camera3D").current, "reattach restores stored camera")
		character.free()
	ground.free()
	await frames(1)
func frames(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame
