extends SceneTree

const Support = preload("res://modules/liberty_character/tests/liberty_test_support.gd")
const CharacterScene = preload("res://modules/liberty_character/character/liberty_character.tscn")

const ACTIONS: Array[StringName] = [
	&"liberty_move_forward",
	&"liberty_move_back",
	&"liberty_move_left",
	&"liberty_move_right",
	&"liberty_walk",
	&"liberty_sprint",
	&"liberty_jump",
]

var _world: Node3D
var _character: LibertyCharacter
var _landing_count := 0
var _last_impact_speed := 0.0
var _lock_transitions: Array[Array] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_build_world()
	await _wait_physics(8)
	await _test_grounded_jump_and_midair_rejection()
	await _test_air_control_and_speed_cap()
	await _test_locked_airborne_gravity()
	_release_actions()
	_world.free()
	quit(Support.exit_code())


func _build_world() -> void:
	_world = Node3D.new()
	root.add_child(_world)
	var floor := StaticBody3D.new()
	floor.collision_layer = 1
	floor.collision_mask = 0
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(50.0, 1.0, 50.0)
	collision.shape = shape
	collision.position.y = -0.5
	floor.add_child(collision)
	_world.add_child(floor)
	_character = CharacterScene.instantiate() as LibertyCharacter
	_world.add_child(_character)
	var events := _character.get_node("Events") as LibertyEvents
	events.landed.connect(_on_landed)
	events.movement_state_changed.connect(_on_lock_state_changed)


func _reset_character() -> void:
	_release_actions()
	_character.set_movement_locked(false)
	_character.global_position = Vector3.ZERO
	_character.rotation = Vector3.ZERO
	_character.velocity = Vector3.ZERO
	_character.reset_physics_interpolation()
	_landing_count = 0
	_last_impact_speed = 0.0
	await _wait_physics(5)


func _test_grounded_jump_and_midair_rejection() -> void:
	await _reset_character()
	Input.action_press(&"liberty_move_forward")
	await _wait_physics(45)
	var horizontal_speed_before_jump := _character.planar_speed
	Input.action_press(&"liberty_jump")
	await _wait_physics(2)
	Input.action_release(&"liberty_jump")
	Support.expect_true(_character.velocity.y > 6.0, "grounded jump must apply upward velocity")
	Support.expect_equal(_character.movement_state, LibertyCharacter.MovementState.AIRBORNE, "jump must enter AIRBORNE")
	Support.expect_true(absf(_character.planar_speed - horizontal_speed_before_jump) < 0.25, "jump must preserve horizontal momentum")

	await _wait_physics(8)
	var velocity_before_second_jump := _character.velocity.y
	Input.action_press(&"liberty_jump")
	await _wait_physics(2)
	Input.action_release(&"liberty_jump")
	Support.expect_true(_character.velocity.y < velocity_before_second_jump, "midair jump input must not reset vertical velocity")

	_release_actions()
	for _frame in 180:
		await physics_frame
		if _character.is_on_floor():
			break
	Support.expect_true(_character.is_on_floor(), "jump must return to the floor")
	Support.expect_equal(_landing_count, 1, "landing transition must emit exactly once")
	Support.expect_true(_last_impact_speed > 0.0, "landing event must report positive impact speed")


func _test_air_control_and_speed_cap() -> void:
	await _reset_character()
	Input.action_press(&"liberty_move_forward")
	Input.action_press(&"liberty_sprint")
	await _wait_physics(90)
	Input.action_press(&"liberty_jump")
	await _wait_physics(2)
	Input.action_release(&"liberty_jump")
	Input.action_release(&"liberty_move_forward")
	Support.expect_equal(_character.movement_state, LibertyCharacter.MovementState.AIRBORNE, "air-control case must be airborne")
	Input.action_press(&"liberty_move_right")
	var initial_x_velocity := _character.velocity.x
	await _wait_physics(20)
	Support.expect_true(_character.velocity.x > initial_x_velocity + 0.5, "air input must steer horizontal velocity")
	Support.expect_true(_character.planar_speed <= _character.sprint_speed + 0.05, "air control must respect sprint speed cap")


func _test_locked_airborne_gravity() -> void:
	await _reset_character()
	Input.action_press(&"liberty_jump")
	await _wait_physics(2)
	Input.action_release(&"liberty_jump")
	_character.set_movement_locked(true)
	var vertical_velocity_before := _character.velocity.y
	await _wait_physics(5)
	Support.expect_equal(_character.movement_state, LibertyCharacter.MovementState.MOVEMENT_LOCKED, "lock must retain state priority in air")
	Support.expect_true(_character.velocity.y < vertical_velocity_before, "gravity must continue while movement is locked")
	_lock_transitions.clear()
	_character.set_movement_locked(false)
	Support.expect_equal(_character.movement_state, LibertyCharacter.MovementState.AIRBORNE, "unlocking in air must transition directly to AIRBORNE")
	Support.expect_equal(_lock_transitions, [[&"movement_locked", &"airborne"]], "airborne unlock must not emit an intermediate IDLE state")


func _on_lock_state_changed(old_state: StringName, new_state: StringName) -> void:
	_lock_transitions.append([old_state, new_state])


func _on_landed(impact_speed: float) -> void:
	_landing_count += 1
	_last_impact_speed = impact_speed


func _wait_physics(frames: int) -> void:
	for _frame in frames:
		await physics_frame


func _release_actions() -> void:
	for action in ACTIONS:
		Input.action_release(action)
