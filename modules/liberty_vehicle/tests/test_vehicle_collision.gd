extends SceneTree
const S = preload("res://modules/liberty_character/tests/liberty_test_support.gd")
const Character = preload("res://modules/liberty_character/character/liberty_character.tscn")
const Sedan = preload("res://modules/liberty_vehicle/vehicle/liberty_vehicle.tscn")
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var character := Character.instantiate() as LibertyCharacter
	character.position = Vector3(12, 0, 0)
	root.add_child(character)
	character.set_physics_process(false)
	await frames(3)
	var ragdoll := character.get_node("Ragdoll") as LibertyRagdoll
	check_masks(ragdoll, false)
	S.expect_true(ragdoll.begin_active_simulation([&"LeftUpperArm", &"LeftLowerArm"]), "partial reaction starts")
	await frames(1)
	for bone in ragdoll.get_physical_bones():
		var active := bone.is_simulating_physics()
		S.expect_equal(PhysicsServer3D.body_get_collision_layer(bone.get_rid()), 4 if active else 0, "partial layer " + bone.bone_name)
		S.expect_equal(PhysicsServer3D.body_get_collision_mask(bone.get_rid()), 17 if active else 0, "partial mask " + bone.bone_name)
	ragdoll.end_active_simulation()
	await frames(1)
	check_masks(ragdoll, false)
	character.activate_ragdoll(Vector3.ZERO, 0.0, &"test")
	await frames(1)
	check_masks(ragdoll, true)
	ragdoll.cancel_ragdoll()
	await frames(1)
	check_masks(ragdoll, false)
	character.set_body_suspended(true)
	var car := Sedan.instantiate() as LibertyVehicle
	car.position = Vector3(12, 0.3, 0)
	car.gravity_scale = 0.0
	root.add_child(car)
	var start := car.global_position
	await frames(20)
	S.expect_true(car.global_position.distance_to(start) < 0.01, "standby skeleton does not shove overlapping sedan")
	var ray := PhysicsRayQueryParameters3D.create(Vector3(12, 2.2, 0), Vector3(12, 0, 0), 7, [car.get_rid(), character.get_rid()])
	var hit := root.world_3d.direct_space_state.intersect_ray(ray)
	S.expect_true(hit.is_empty(), "vehicle wheel mask cannot hit standby skeleton")
	check_masks(ragdoll, false)
	car.free()
	character.free()
	print("vehicle collision matrix PASS")
	quit(S.exit_code())
func check_masks(ragdoll: LibertyRagdoll, simulating: bool) -> void:
	for bone in ragdoll.get_physical_bones():
		S.expect_equal(bone.collision_layer, 4, "node stays ragdoll layer")
		S.expect_equal(bone.collision_mask, 1, "node keeps WORLD_MASK")
		S.expect_equal(PhysicsServer3D.body_get_collision_layer(bone.get_rid()), 4 if simulating else 0, "RID layer " + bone.bone_name)
		S.expect_equal(PhysicsServer3D.body_get_collision_mask(bone.get_rid()), 17 if simulating else 0, "RID mask " + bone.bone_name)
func frames(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame
