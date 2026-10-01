extends SceneTree
const S = preload("res://modules/liberty_character/tests/liberty_test_support.gd")
const Sedan = preload("res://modules/liberty_vehicle/vehicle/liberty_vehicle.tscn")
const Character = preload("res://modules/liberty_character/character/liberty_character.tscn")
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var car := Sedan.instantiate() as LibertyVehicle
	car.position = Vector3(20, 0, 0)
	car.freeze = true
	root.add_child(car)
	var character := Character.instantiate() as LibertyCharacter
	character.position = Vector3(18.5, 0, 0)
	root.add_child(character)
	character.set_physics_process(false)
	await frames(3)
	S.expect_true(character.test_move(character.global_transform, Vector3.RIGHT), "capsule collides with sedan chassis")
	var ragdoll := character.get_node("Ragdoll") as LibertyRagdoll
	ragdoll.settle_time = 30.0
	S.expect_true(ragdoll._probe_floor(Vector3(20, 1.2, 0)).is_empty(), "car roof does not qualify as get-up floor")
	character.global_position = Vector3(20, 2, 0)
	S.expect_true(character.activate_ragdoll(Vector3.ZERO, 0.0, &"test"), "passive ragdoll starts above sedan")
	await frames(120)
	var hips := ragdoll.get_physical_bone(&"Hips")
	S.expect_true(hips.global_position.y > 0.85, "simulating ragdoll lands on chassis instead of falling through")
	S.expect_true(hips.global_position.y < 2.0, "ragdoll actually fell onto sedan")
	character.free()
	car.free()
	print("capsule and ragdoll vehicle contact PASS")
	quit(S.exit_code())
func frames(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame
