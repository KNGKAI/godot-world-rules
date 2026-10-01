extends SceneTree

const Support = preload("res://modules/liberty_character/tests/liberty_test_support.gd")
const CharacterScene = preload("res://modules/liberty_character/character/liberty_character.tscn")

const MOVEMENT_ACTIONS: Array[StringName] = [
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
var _state_transitions: Array[Array] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_build_world()
	await _wait_physics(8)
	await _test_world_axis_fallback()
	await _test_yaw_basis()
	await _test_rotated_parent_world_steering()
	await _test_gait_priority_and_speed_cap()
	await _test_state_change_events()
	await _test_coasting_states()
	await _test_wide_sprint_reversal()
	await _test_movement_lock_brakes()
	await _test_unlock_state_idempotence()
	_release_actions()
	_world.free()
	quit(Support.exit_code())


func _build_world() -> void:
	_world = Node3D.new()
	root.add_child(_world)
	var floor := StaticBody3D.new()
	floor.collision_layer = 1
	floor.collision_mask = 0
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(100.0, 1.0, 100.0)
	floor_shape.shape = box
	floor_shape.position.y = -0.5
	floor.add_child(floor_shape)
	_world.add_child(floor)
	_character = CharacterScene.instantiate() as LibertyCharacter
	_world.add_child(_character)
	(_character.get_node("Events") as LibertyEvents).movement_state_changed.connect(_on_movement_state_changed)


func _reset_character() -> void:
	_release_actions()
	_character.set_movement_locked(false)
	_character.input_basis_source = null
	_character.global_position = Vector3.ZERO
	_character.rotation = Vector3.ZERO
	_character.velocity = Vector3.ZERO
	_character.reset_physics_interpolation()
	await _wait_physics(5)


func _test_world_axis_fallback() -> void:
	await _reset_character()
	Input.action_press(&"liberty_move_forward")
	await _wait_physics(60)
	Support.expect_true(_character.global_position.z < -1.0, "forward input must move along world -Z without a basis source")
	Support.expect_true(absf(_character.planar_speed - _character.run_speed) < 0.15, "default gait must reach run speed")
	Support.expect_equal(_character.movement_state, LibertyCharacter.MovementState.RUN, "run speed must report RUN")


func _test_yaw_basis() -> void:
	await _reset_character()
	var basis_source := Node3D.new()
	basis_source.rotation_degrees = Vector3(35.0, 90.0, 20.0)
	_world.add_child(basis_source)
	_character.input_basis_source = basis_source
	var expected_forward := -basis_source.global_basis.z
	expected_forward.y = 0.0
	expected_forward = expected_forward.normalized()
	Input.action_press(&"liberty_move_forward")
	await _wait_physics(60)
	var actual_direction := Vector3(_character.velocity.x, 0.0, _character.velocity.z).normalized()
	Support.expect_true(actual_direction.dot(expected_forward) > 0.95, "movement basis must use source yaw while ignoring pitch and roll")
	basis_source.free()


func _test_rotated_parent_world_steering() -> void:
	await _reset_character()
	var rotated_parent := Node3D.new()
	rotated_parent.rotation_degrees.y = 90.0
	_world.add_child(rotated_parent)
	_character.reparent(rotated_parent, true)
	await _reset_character()
	Input.action_press(&"liberty_move_forward")
	await _wait_physics(60)
	var fallback_direction := Vector3(_character.velocity.x, 0.0, _character.velocity.z).normalized()
	Support.expect_true(fallback_direction.dot(Vector3.FORWARD) > 0.95, "world-axis fallback must remain world -Z under a rotated parent")

	await _reset_character()
	var basis_source := Node3D.new()
	basis_source.rotation_degrees.y = 90.0
	_world.add_child(basis_source)
	_character.input_basis_source = basis_source
	Input.action_press(&"liberty_move_forward")
	await _wait_physics(60)
	var expected_direction := -basis_source.global_basis.z
	expected_direction.y = 0.0
	expected_direction = expected_direction.normalized()
	var based_direction := Vector3(_character.velocity.x, 0.0, _character.velocity.z).normalized()
	Support.expect_true(based_direction.dot(expected_direction) > 0.95, "camera-relative steering must remain world-correct under a rotated parent")

	_character.input_basis_source = null
	_character.reparent(_world, true)
	rotated_parent.free()
	basis_source.free()


func _test_gait_priority_and_speed_cap() -> void:
	await _reset_character()
	Input.action_press(&"liberty_move_forward")
	Input.action_press(&"liberty_walk")
	await _wait_physics(90)
	Support.expect_true(absf(_character.planar_speed - _character.walk_speed) < 0.15, "walk modifier must select walk speed")
	Support.expect_equal(_character.movement_state, LibertyCharacter.MovementState.WALK, "walk speed must report WALK")

	await _reset_character()
	Input.action_press(&"liberty_move_forward")
	Input.action_press(&"liberty_walk")
	Input.action_press(&"liberty_sprint")
	await _wait_physics(120)
	Support.expect_true(absf(_character.planar_speed - _character.sprint_speed) < 0.15, "sprint must override walk while moving")
	Support.expect_equal(_character.movement_state, LibertyCharacter.MovementState.SPRINT, "sprint speed must report SPRINT")

	await _reset_character()
	Input.action_press(&"liberty_move_forward")
	Input.action_press(&"liberty_move_right")
	Input.action_press(&"liberty_sprint")
	await _wait_physics(120)
	Support.expect_true(_character.planar_speed <= _character.sprint_speed + 0.05, "diagonal input must not exceed sprint speed")
	Support.expect_true(_character.planar_speed >= _character.sprint_speed - 0.2, "diagonal sprint must reach sprint speed")


func _test_state_change_events() -> void:
	await _reset_character()
	_state_transitions.clear()
	Input.action_press(&"liberty_move_forward")
	await _wait_physics(60)
	_release_actions()
	await _wait_physics(60)
	var new_states: Array[StringName] = []
	for transition in _state_transitions:
		Support.expect_true(transition[0] != transition[1], "state signal must not emit duplicate transitions")
		new_states.append(transition[1])
	Support.expect_true(new_states.has(&"walk"), "acceleration must emit WALK transition")
	Support.expect_true(new_states.has(&"run"), "acceleration must emit RUN transition")
	Support.expect_true(new_states.has(&"idle"), "completed coast must emit IDLE transition")


func _test_coasting_states() -> void:
	await _reset_character()
	Input.action_press(&"liberty_move_forward")
	Input.action_press(&"liberty_sprint")
	await _wait_physics(120)
	_release_actions()
	await _wait_physics(1)
	Support.expect_equal(_character.movement_state, LibertyCharacter.MovementState.SPRINT, "coasting state must initially follow sprint speed")
	var saw_run := false
	var saw_walk := false
	for _frame in 120:
		await physics_frame
		saw_run = saw_run or _character.movement_state == LibertyCharacter.MovementState.RUN
		saw_walk = saw_walk or _character.movement_state == LibertyCharacter.MovementState.WALK
		if _character.movement_state == LibertyCharacter.MovementState.IDLE:
			break
	Support.expect_true(saw_run, "sprint coast must step down through RUN")
	Support.expect_true(saw_walk, "sprint coast must step down through WALK")
	Support.expect_equal(_character.movement_state, LibertyCharacter.MovementState.IDLE, "coast must finish IDLE")


func _test_wide_sprint_reversal() -> void:
	await _reset_character()
	Input.action_press(&"liberty_move_forward")
	Input.action_press(&"liberty_sprint")
	await _wait_physics(120)
	var start := _character.global_position
	Input.action_release(&"liberty_move_forward")
	Input.action_press(&"liberty_move_back")
	var maximum_lateral_displacement := 0.0
	for _frame in 120:
		await physics_frame
		maximum_lateral_displacement = maxf(maximum_lateral_displacement, absf(_character.global_position.x - start.x))
		if (-_character.global_basis.z).dot(Vector3.BACK) > 0.985:
			break
	Support.expect_true(maximum_lateral_displacement > 1.0, "sprint reversal must form a wide arc instead of snapping velocity")


func _test_movement_lock_brakes() -> void:
	await _reset_character()
	Input.action_press(&"liberty_move_forward")
	await _wait_physics(60)
	var speed_before_lock := _character.planar_speed
	_character.set_movement_locked(true)
	Input.action_press(&"liberty_jump")
	await _wait_physics(10)
	Support.expect_equal(_character.movement_state, LibertyCharacter.MovementState.MOVEMENT_LOCKED, "lock state must have priority")
	Support.expect_true(_character.planar_speed < speed_before_lock, "movement lock must brake existing momentum")
	Support.expect_true(_character.planar_speed > 0.0, "movement lock must brake naturally rather than stop instantly")
	Support.expect_true(_character.velocity.y <= 0.1, "movement lock must reject jump input")
	await _wait_physics(60)
	Support.expect_true(_character.planar_speed < 0.1, "movement lock must eventually stop horizontal motion")


func _test_unlock_state_idempotence() -> void:
	await _reset_character()
	Input.action_press(&"liberty_move_forward")
	await _wait_physics(60)
	_state_transitions.clear()
	var state_before := _character.movement_state
	_character.set_movement_locked(false)
	Support.expect_equal(_character.movement_state, state_before, "repeating the current unlocked value must be idempotent")
	Support.expect_true(_state_transitions.is_empty(), "idempotent unlock must not emit a transition")

	_character.set_movement_locked(true)
	await _wait_physics(5)
	_state_transitions.clear()
	_character.set_movement_locked(false)
	Support.expect_equal(_character.movement_state, LibertyCharacter.MovementState.RUN, "unlocking while coasting must derive state from current speed")
	Support.expect_equal(_state_transitions, [[&"movement_locked", &"run"]], "coasting unlock must transition directly to its derived gait")


func _on_movement_state_changed(old_state: StringName, new_state: StringName) -> void:
	_state_transitions.append([old_state, new_state])


func _wait_physics(frames: int) -> void:
	for _frame in frames:
		await physics_frame


func _release_actions() -> void:
	for action in MOVEMENT_ACTIONS:
		Input.action_release(action)
