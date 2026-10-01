extends SceneTree

const Support = preload("res://modules/liberty_character/tests/liberty_test_support.gd")
const CharacterScene = preload("res://modules/liberty_character/character/liberty_character.tscn")
const Controller = preload("res://modules/liberty_character/traversal/liberty_traversal_controller.gd")

const ACTIONS: Array[StringName] = [
	&"liberty_move_forward",
	&"liberty_move_back",
	&"liberty_move_left",
	&"liberty_move_right",
	&"liberty_walk",
	&"liberty_sprint",
	&"liberty_jump",
	&"liberty_traverse",
]

var _world: Node3D
var _character: LibertyCharacter
var _hits: Array[StringName] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_build_world()
	await _wait_physics(8)
	await _test_accelerates_to_gait_cap()
	await _test_airborne_yaw_uses_air_rate()
	await _test_facing_yaws_and_accelerates_in_world()
	await _test_player_actions_do_not_add()
	await _test_movement_lock_brakes()
	await _test_rejected_intent_leaves_mode()
	await _test_hit_suppression()
	await _test_scripted_blocks_traversal_start()
	_release_actions()
	_world.free()
	quit(Support.exit_code())


func _build_world() -> void:
	_world = Node3D.new()
	root.add_child(_world)
	_add_floor(_world, Vector3(100.0, 1.0, 100.0))
	_character = CharacterScene.instantiate() as LibertyCharacter
	_world.add_child(_character)
	_character.input_basis_source = null
	(_character.get_node("Events") as LibertyEvents).hit_received.connect(_on_hit)


func _add_floor(parent: Node3D, size: Vector3) -> void:
	var floor := StaticBody3D.new()
	floor.collision_layer = 1
	floor.collision_mask = 0
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	collision.position.y = -0.5
	floor.add_child(collision)
	parent.add_child(floor)


func _reset_character() -> void:
	_release_actions()
	_character.clear_scripted_locomotion()
	_character.set_movement_locked(false)
	_character.input_basis_source = null
	_character.teleport_to(Transform3D(Basis.IDENTITY, Vector3.ZERO))
	_character.velocity = Vector3.ZERO
	await _wait_physics(5)


func _test_accelerates_to_gait_cap() -> void:
	await _reset_character()
	var cap := 5.0
	Support.expect_equal(
		_character.set_scripted_locomotion(Vector3(0.0, 4.0, -1.0), cap),
		OK,
		"finite scripted intent arms"
	)
	var step := _character.ground_acceleration / float(Engine.physics_ticks_per_second)
	await _wait_physics(1)
	Support.expect_true(
		absf(_character.planar_speed - step) < 0.05,
		"first scripted tick accelerates (%.3f) instead of teleporting to the cap" % _character.planar_speed
	)
	Support.expect_true(_character.global_position.z < 0.0, "scripted travel moves along -Z")
	Support.expect_true(absf(_character.global_position.z) < 0.05, "first tick does not teleport")
	await _wait_physics(90)
	Support.expect_true(
		absf(_character.planar_speed - cap) < 0.2,
		"scripted walk reaches the gait cap (%.3f)" % _character.planar_speed
	)
	Support.expect_true(_character.planar_speed <= cap + 0.05, "scripted walk does not pass the gait cap")

	await _reset_character()
	Support.expect_equal(_character.set_scripted_locomotion(Vector3(0.0, 0.0, -1.0), 100.0), OK, "over-cap intent arms")
	await _wait_physics(120)
	Support.expect_true(
		absf(_character.planar_speed - _character.sprint_speed) < 0.2,
		"gait cap clamps to sprint speed (%.3f)" % _character.planar_speed
	)
	Support.expect_true(_character.planar_speed <= _character.sprint_speed + 0.05, "clamped cap does not exceed sprint")


func _test_airborne_yaw_uses_air_rate() -> void:
	await _reset_character()
	await _lift_airborne()
	_character.velocity = Vector3.ZERO
	_character.rotation = Vector3.ZERO
	Support.expect_equal(_character.set_scripted_locomotion(Vector3.RIGHT, 5.0), OK, "airborne scripted intent arms")
	await _wait_physics(1)
	var step := deg_to_rad(_character.high_speed_turn_rate_degrees) / float(Engine.physics_ticks_per_second)
	var grounded_step := deg_to_rad(_character.grounded_turn_rate_degrees) / float(Engine.physics_ticks_per_second)
	var yaw := _character.global_rotation.y
	Support.expect_true(
		absf(absf(yaw) - step) < 0.01,
		"one airborne scripted tick yaws at the 120 deg/s air rate (yaw %.4f, step %.4f)" % [yaw, step]
	)
	Support.expect_true(yaw < 0.0, "airborne yaw turns toward +X travel")
	Support.expect_true(absf(yaw) < grounded_step * 0.5, "airborne scripted yaw is slower than the grounded rate")


func _test_facing_yaws_and_accelerates_in_world() -> void:
	await _reset_character()
	await _lift_airborne()
	_character.velocity = Vector3.ZERO
	_character.rotation = Vector3.ZERO
	Support.expect_equal(
		_character.set_scripted_locomotion(Vector3(0.0, 0.0, -1.0), 5.0, Vector3.RIGHT, true),
		OK,
		"airborne facing intent arms"
	)
	await _wait_physics(1)
	var step := deg_to_rad(_character.high_speed_turn_rate_degrees) / float(Engine.physics_ticks_per_second)
	var yaw := _character.global_rotation.y
	Support.expect_true(
		absf(absf(yaw) - step) < 0.01,
		"airborne facing yaws at the air rate (yaw %.4f)" % yaw
	)
	Support.expect_true(yaw < 0.0, "airborne facing yaws toward the facing vector, not the -Z travel")
	Support.expect_true(_character.velocity.z < -0.01, "airborne facing still accelerates along travel")
	Support.expect_true(absf(_character.velocity.x) < 0.02, "airborne facing does not accelerate along the facing vector")

	await _reset_character()
	_character.velocity = Vector3.ZERO
	_character.rotation = Vector3.ZERO
	Support.expect_equal(
		_character.set_scripted_locomotion(Vector3.RIGHT, 5.0, Vector3(0.0, 3.0, -1.0), true),
		OK,
		"grounded facing intent arms"
	)
	await _wait_physics(1)
	var ground_step := _character.ground_acceleration / float(Engine.physics_ticks_per_second)
	Support.expect_true(absf(_character.global_rotation.y) < 0.01, "grounded facing that already matches yaw does not turn toward travel")
	Support.expect_true(
		absf(_character.velocity.x - ground_step) < 0.05,
		"grounded facing accelerates in world space along travel (vx %.3f)" % _character.velocity.x
	)
	Support.expect_true(absf(_character.velocity.z) < 0.02, "grounded facing does not accelerate along forward")


func _test_player_actions_do_not_add() -> void:
	await _reset_character()
	Support.expect_equal(_character.set_scripted_locomotion(Vector3.RIGHT, 5.0), OK, "player-input case arms")
	Input.action_press(&"liberty_move_forward")
	Input.action_press(&"liberty_sprint")
	Input.action_press(&"liberty_jump")
	await _wait_physics(2)
	Support.expect_true(_character.is_on_floor(), "scripted locomotion suppresses jump")
	Support.expect_true(_character.velocity.y < 1.0, "jump velocity is not applied while scripted")
	var player_direction := _character.get_world_input_direction()
	Support.expect_true(player_direction.dot(Vector3.FORWARD) > 0.95, "get_world_input_direction still reports player forward")
	Support.expect_true(absf(player_direction.dot(Vector3.RIGHT)) < 0.2, "player forward is not the scripted +X direction")
	await _wait_physics(100)
	var travel := Vector3(_character.velocity.x, 0.0, _character.velocity.z).normalized()
	Support.expect_true(travel.dot(Vector3.RIGHT) > 0.95, "scripted +X is not summed with player forward")
	Support.expect_true(
		absf(_character.planar_speed - 5.0) < 0.2,
		"sprint input does not raise the scripted cap (%.3f)" % _character.planar_speed
	)


func _test_movement_lock_brakes() -> void:
	await _reset_character()
	_character.rotation = Vector3.ZERO
	_character.velocity = Vector3(0.0, 0.0, -4.0)
	Support.expect_equal(_character.set_scripted_locomotion(Vector3(0.0, 0.0, -1.0), 5.0), OK, "locked scripted intent arms")
	_character.set_movement_locked(true)
	await _wait_physics(10)
	var expected := 4.0 - _character.ground_deceleration * 10.0 / float(Engine.physics_ticks_per_second)
	Support.expect_true(
		absf(_character.planar_speed - expected) < 0.35,
		"movement lock brakes through scripted intent (%.3f, expected %.3f)" % [_character.planar_speed, expected]
	)
	Support.expect_true(_character.planar_speed < 3.7, "locked scripted intent does not accelerate toward the cap")


func _test_rejected_intent_leaves_mode() -> void:
	await _reset_character()
	Support.expect_equal(
		_character.set_scripted_locomotion(Vector3(NAN, 0.0, 0.0), 5.0),
		ERR_INVALID_PARAMETER,
		"non-finite direction is rejected"
	)
	Support.expect_false(_character.has_scripted_locomotion(), "rejected direction does not arm")
	Support.expect_equal(
		_character.set_scripted_locomotion(Vector3(0.0, 0.0, -1.0), INF),
		ERR_INVALID_PARAMETER,
		"non-finite cap is rejected"
	)
	Support.expect_false(_character.has_scripted_locomotion(), "rejected cap does not arm")
	Support.expect_equal(
		_character.set_scripted_locomotion(Vector3(0.0, 0.0, -1.0), 5.0, Vector3.ZERO, true),
		ERR_INVALID_PARAMETER,
		"zero facing is rejected"
	)
	Support.expect_equal(
		_character.set_scripted_locomotion(Vector3(0.0, 0.0, -1.0), 5.0, Vector3(0.0, 4.0, 0.0), true),
		ERR_INVALID_PARAMETER,
		"vertical facing is rejected"
	)
	Support.expect_false(_character.has_scripted_locomotion(), "rejected facing does not arm")

	Support.expect_equal(_character.set_scripted_locomotion(Vector3(0.0, 0.0, -1.0), 5.0), OK, "valid intent arms")
	Support.expect_equal(
		_character.set_scripted_locomotion(Vector3(NAN, 0.0, -1.0), 5.0),
		ERR_INVALID_PARAMETER,
		"a later bad direction is rejected"
	)
	Support.expect_equal(
		_character.set_scripted_locomotion(Vector3.RIGHT, 5.0, Vector3.ZERO, true),
		ERR_INVALID_PARAMETER,
		"a later bad facing is rejected"
	)
	Support.expect_true(_character.has_scripted_locomotion(), "rejected calls leave the armed mode")
	await _wait_physics(1)
	Support.expect_true(_character.velocity.z < -0.05, "the previous -Z intent still runs after a rejected call")
	_character.clear_scripted_locomotion()
	_character.clear_scripted_locomotion()
	Support.expect_false(_character.has_scripted_locomotion(), "clear is idempotent")


func _test_hit_suppression() -> void:
	await _reset_character()
	_hits.clear()
	var ragdoll := _character.get_node("Ragdoll") as LibertyRagdoll
	Support.expect_true(_character.physical_animation != null, "ragdoll stage is ready")
	var first := _character.acquire_hit_suppression()
	var second := _character.acquire_hit_suppression()
	Support.expect_true(first != second, "hit tokens are distinct")
	Support.expect_true(_character.is_hit_suppressed(), "a held token suppresses hits")
	Support.expect_false(
		_character.receive_hit(&"LeftHand", Vector3.FORWARD, 30.0, false),
		"receive_hit returns false while suppressed"
	)
	Support.expect_true(_hits.is_empty(), "suppressed hit does not emit hit_received")
	Support.expect_false(ragdoll.is_reacting(), "suppressed hit does not start a reaction")
	_character.release_hit_suppression(first)
	Support.expect_true(_character.is_hit_suppressed(), "the remaining token keeps suppression")
	Support.expect_false(_character.receive_hit(&"LeftHand", Vector3.FORWARD, 30.0, false), "nested hold still rejects")
	_character.release_hit_suppression(-1)
	Support.expect_true(_character.is_hit_suppressed(), "an unknown token is a no-op")
	_character.release_hit_suppression(second)
	Support.expect_false(_character.is_hit_suppressed(), "releasing the last token clears suppression")
	Support.expect_true(
		_character.receive_hit(&"LeftHand", Vector3.FORWARD, 30.0, false),
		"receive_hit returns true after release"
	)
	Support.expect_equal(_hits.size(), 1, "hit_received emits once after release")
	var held := _character.acquire_hit_suppression()
	Support.expect_true(
		_character.activate_ragdoll(Vector3.RIGHT, 180.0, &"suppressed_knockout"),
		"activate_ragdoll is not gated by hit suppression"
	)
	Support.expect_true(_character.is_ragdoll_active(), "explicit knockout still starts the ragdoll")
	_character.release_hit_suppression(held)


func _test_scripted_blocks_traversal_start() -> void:
	var fixture := Node3D.new()
	_world.add_child(fixture)
	var floor := StaticBody3D.new()
	floor.collision_layer = 1
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(30.0, 0.4, 30.0)
	floor_shape.shape = floor_box
	floor.add_child(floor_shape)
	fixture.add_child(floor)
	floor.position = Vector3(0.0, -0.2, 0.0)
	var wall := StaticBody3D.new()
	wall.collision_layer = 9
	var wall_shape := CollisionShape3D.new()
	var wall_box := BoxShape3D.new()
	wall_box.size = Vector3(20.0, 6.0, 0.6)
	wall_shape.shape = wall_box
	wall.add_child(wall_shape)
	fixture.add_child(wall)
	wall.position = Vector3(0.0, 3.0, -1.15)
	var climber := CharacterScene.instantiate() as LibertyCharacter
	fixture.add_child(climber)
	climber.input_basis_source = null
	await _wait_physics(8)
	var coordinator := climber.get_node("Traversal") as LibertyTraversalCoordinator
	Support.expect_true(coordinator != null and coordinator.configuration_error == "", "traversal coordinator is ready")
	var settled := false
	for _frame in 60:
		if climber.is_on_floor() and coordinator.controller.state == Controller.State.GROUNDED:
			settled = true
			break
		await _wait_physics(1)
	Support.expect_true(settled, "climber settles grounded before the scripted hold")
	Support.expect_equal(climber.set_scripted_locomotion(Vector3.ZERO, 0.0), OK, "zero stick still arms scripted locomotion")
	Input.action_press(&"liberty_traverse")
	Input.action_press(&"liberty_move_forward")
	await _wait_physics(45)
	Support.expect_false(climber.is_traversal_locked(), "scripted locomotion does not start a traversal")
	Support.expect_equal(coordinator.controller.state, Controller.State.GROUNDED, "scripted locomotion leaves the traversal controller grounded")
	climber.clear_scripted_locomotion()
	var started := false
	for _frame in 120:
		await _wait_physics(1)
		if climber.is_traversal_locked():
			started = true
			break
	Support.expect_true(
		started,
		"the same wall starts a traversal once scripted locomotion is cleared at %s" % climber.global_position
	)
	Input.action_release(&"liberty_traverse")
	Input.action_release(&"liberty_move_forward")
	fixture.free()


func _lift_airborne() -> void:
	_character.global_position = Vector3(0.0, 3.0, 0.0)
	_character.velocity = Vector3.ZERO
	await _wait_physics(3)
	Support.expect_false(_character.is_on_floor(), "airborne fixture leaves the floor")


func _on_hit(bone: StringName, _direction: Vector3, _force: float, _fatal: bool) -> void:
	_hits.append(bone)


func _wait_physics(frames: int) -> void:
	for _frame in frames:
		await physics_frame


func _release_actions() -> void:
	for action in ACTIONS:
		Input.action_release(action)
