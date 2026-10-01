class_name LibertyCharacter
extends CharacterBody3D

enum MovementState {
	IDLE,
	WALK,
	RUN,
	SPRINT,
	AIRBORNE,
	MOVEMENT_LOCKED,
}

const STATE_NAMES: Array[StringName] = [
	&"idle",
	&"walk",
	&"run",
	&"sprint",
	&"airborne",
	&"movement_locked",
]

@export_group("Gait")
@export_range(0.0, 20.0, 0.1, "or_greater") var walk_speed := 2.2
@export_range(0.0, 20.0, 0.1, "or_greater") var run_speed := 5.0
@export_range(0.0, 20.0, 0.1, "or_greater") var sprint_speed := 7.5
@export_range(0.0, 100.0, 0.1, "or_greater") var ground_acceleration := 9.0
@export_range(0.0, 100.0, 0.1, "or_greater") var ground_deceleration := 6.0

@export_group("Steering")
@export_range(0.0, 1080.0, 1.0, "or_greater") var grounded_turn_rate_degrees := 420.0
@export_range(0.0, 1080.0, 1.0, "or_greater") var high_speed_turn_rate_degrees := 120.0
@export_range(0.0, 100.0, 0.1, "or_greater") var air_control := 3.0
@export var input_basis_source: Node3D

@export_group("Vertical Motion")
@export_range(0.0, 100.0, 0.1, "or_greater") var gravity := 24.0
@export_range(0.0, 30.0, 0.1, "or_greater") var jump_velocity := 7.2

@export_group("Camera")
@export var camera_pivot_path: NodePath = ^"CameraPivot"

@export_group("Events")
@export var events_path: NodePath = ^"Events"

var movement_state: MovementState = MovementState.IDLE

var movement_state_name: StringName:
	get:
		return STATE_NAMES[movement_state]

var planar_speed: float:
	get:
		return Vector2(velocity.x, velocity.z).length()

## Owned traversal coordinator interface: consume_motion/after_motion/interrupt.
var traversal_coordinator: Node
var traversal_motion_blocked := false
var _traversal_locked := false
var _traversal_displacement := Vector3.ZERO
var _traversal_yaw := 0.0
var _has_traversal_request := false
var _movement_locked := false
var _has_grounded_override := false
var _grounded_override := false
## Owned ragdoll interface: activate_ragdoll/is_active.
var ragdoll: Node
## Owned active-ragdoll stage interface: receive_hit/track/release.
var physical_animation: Node
var _body_suspended := false
var _scripted_active := false
var _scripted_direction := Vector3.ZERO
var _scripted_gait_cap := 0.0
var _scripted_facing := Vector3.ZERO
var _scripted_has_facing := false
var _hit_suppression: Dictionary = {}
var _next_hit_token := 0
## Claimed by LibertyVehiclePossession; prevents duplicate claims across vehicles.
var vehicle_possession: LibertyVehiclePossession


func _physics_process(delta: float) -> void:
	if _body_suspended:
		return
	if _traversal_locked:
		if is_instance_valid(traversal_coordinator):
			traversal_coordinator.consume_motion(delta)
		if _traversal_locked:
			traversal_motion_blocked = false
			var displacement := _traversal_displacement if _has_traversal_request else Vector3.ZERO
			var yaw := _traversal_yaw if _has_traversal_request else 0.0
			_has_traversal_request = false
			_traversal_displacement = Vector3.ZERO
			_traversal_yaw = 0.0
			if not displacement.is_zero_approx() and test_move(global_transform, displacement):
				traversal_motion_blocked = true
				velocity = Vector3.ZERO
			else:
				velocity = displacement / maxf(delta, 0.000001)
				global_rotation.y += yaw
			move_and_slide()
			_update_movement_state()
			if is_instance_valid(traversal_coordinator):
				traversal_coordinator.after_motion(delta)
			return
	var was_on_floor := _consume_grounded_override()
	var input_direction := _scripted_direction if _scripted_active else _get_world_input_direction()

	if _movement_locked:
		_apply_horizontal_braking(delta)
	elif was_on_floor:
		if _scripted_active and _scripted_has_facing:
			_apply_scripted_facing_ground(input_direction, delta)
		else:
			_apply_ground_movement(input_direction, delta)
		if _wants_jump():
			velocity.y = jump_velocity
	else:
		_apply_air_movement(input_direction, delta)

	if not was_on_floor:
		velocity.y -= gravity * delta

	_clamp_planar_speed()
	var impact_velocity := velocity.y
	move_and_slide()

	if not was_on_floor and is_on_floor() and impact_velocity < 0.0:
		var events := get_node_or_null(events_path) as LibertyEvents
		if events != null:
			events.landed.emit(absf(impact_velocity))
	_update_movement_state()


func _wants_jump() -> bool:
	if _scripted_active:
		return false
	return Input.is_action_just_pressed(&"liberty_jump") or Input.is_action_just_pressed(&"liberty_touch_jump")


func _get_world_input_direction() -> Vector3:
	var desktop_input := Input.get_vector(
		&"liberty_move_left",
		&"liberty_move_right",
		&"liberty_move_forward",
		&"liberty_move_back"
	)
	var touch_input := Input.get_vector(
		&"liberty_touch_move_left",
		&"liberty_touch_move_right",
		&"liberty_touch_move_forward",
		&"liberty_touch_move_back",
		0.0
	)
	var input_vector := (desktop_input + touch_input).limit_length(1.0)
	if input_vector.is_zero_approx():
		return Vector3.ZERO
	var direction := Vector3(input_vector.x, 0.0, input_vector.y)
	if input_basis_source != null:
		direction = Basis(Vector3.UP, input_basis_source.global_rotation.y) * direction
	direction.y = 0.0
	return direction.limit_length(1.0)


func _apply_ground_movement(input_direction: Vector3, delta: float) -> void:
	if input_direction.is_zero_approx():
		_apply_horizontal_braking(delta)
		return
	_rotate_toward_direction(input_direction, _current_turn_rate_degrees(), delta)
	var forward := -global_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var target_speed := _selected_gait_speed() * clampf(input_direction.length(), 0.0, 1.0)
	var current_planar := Vector2(velocity.x, velocity.z)
	var target_planar := Vector2(forward.x, forward.z) * target_speed
	current_planar = current_planar.move_toward(target_planar, ground_acceleration * delta)
	velocity.x = current_planar.x
	velocity.z = current_planar.y


func _apply_air_movement(input_direction: Vector3, delta: float) -> void:
	var yaw_direction := input_direction
	if _scripted_active and _scripted_has_facing:
		yaw_direction = _scripted_facing
	if yaw_direction.is_zero_approx():
		return
	_rotate_toward_direction(yaw_direction, high_speed_turn_rate_degrees, delta)
	if input_direction.is_zero_approx():
		return
	var current_planar := Vector2(velocity.x, velocity.z)
	var target_planar := Vector2(input_direction.x, input_direction.z) * _selected_gait_speed()
	current_planar = current_planar.move_toward(target_planar, air_control * delta)
	velocity.x = current_planar.x
	velocity.z = current_planar.y


func _apply_scripted_facing_ground(travel: Vector3, delta: float) -> void:
	if not _scripted_facing.is_zero_approx():
		_rotate_toward_direction(_scripted_facing, _current_turn_rate_degrees(), delta)
	var current_planar := Vector2(velocity.x, velocity.z)
	var target_planar := Vector2(travel.x, travel.z) * _scripted_gait_cap
	current_planar = current_planar.move_toward(target_planar, ground_acceleration * delta)
	velocity.x = current_planar.x
	velocity.z = current_planar.y


func _apply_horizontal_braking(delta: float) -> void:
	var planar := Vector2(velocity.x, velocity.z).move_toward(Vector2.ZERO, ground_deceleration * delta)
	velocity.x = planar.x
	velocity.z = planar.y


func _rotate_toward_direction(direction: Vector3, turn_rate_degrees: float, delta: float) -> void:
	var target_yaw := atan2(-direction.x, -direction.z)
	var current_global_rotation := global_rotation
	current_global_rotation.y = rotate_toward(current_global_rotation.y, target_yaw, deg_to_rad(turn_rate_degrees) * delta)
	global_rotation = current_global_rotation


func _current_turn_rate_degrees() -> float:
	var speed_ratio := clampf(planar_speed / maxf(sprint_speed, 0.001), 0.0, 1.0)
	return lerpf(grounded_turn_rate_degrees, high_speed_turn_rate_degrees, speed_ratio)


func _selected_gait_speed() -> float:
	if _scripted_active:
		return _scripted_gait_cap
	if (
		Input.is_action_pressed(&"liberty_sprint")
		or Input.is_action_pressed(&"liberty_touch_sprint")
	):
		return sprint_speed
	if Input.is_action_pressed(&"liberty_walk"):
		return walk_speed
	return run_speed


func _clamp_planar_speed() -> void:
	var planar := Vector2(velocity.x, velocity.z)
	if planar.length() <= sprint_speed:
		return
	planar = planar.normalized() * sprint_speed
	velocity.x = planar.x
	velocity.z = planar.y


func _consume_grounded_override() -> bool:
	if not _has_grounded_override:
		return is_on_floor()
	_has_grounded_override = false
	return _grounded_override


func _detect_destination_floor() -> bool:
	var probe_distance := maxf(floor_snap_length, 0.05)
	var collision := move_and_collide(Vector3.DOWN * probe_distance, true, safe_margin, true, 4)
	if collision == null:
		return false
	for index in collision.get_collision_count():
		if collision.get_normal(index).angle_to(up_direction) <= floor_max_angle:
			return true
	return false


func _update_movement_state() -> void:
	_update_movement_state_for_grounded(is_on_floor())


func _update_movement_state_for_grounded(grounded: bool) -> void:
	if _movement_locked or _traversal_locked or _body_suspended:
		_set_movement_state(MovementState.MOVEMENT_LOCKED)
		return
	if not grounded:
		_set_movement_state(MovementState.AIRBORNE)
		return
	var speed := planar_speed
	if speed <= 0.1:
		_set_movement_state(MovementState.IDLE)
	elif speed < (walk_speed + run_speed) * 0.5:
		_set_movement_state(MovementState.WALK)
	elif speed < (run_speed + sprint_speed) * 0.5:
		_set_movement_state(MovementState.RUN)
	else:
		_set_movement_state(MovementState.SPRINT)


func teleport_to(destination: Transform3D, preserve_velocity: bool = false) -> void:
	if _traversal_locked:
		interrupt_traversal(&"teleport")
	if is_instance_valid(ragdoll):
		# Also ends a hit reaction.
		ragdoll.cancel_ragdoll()
	global_transform = destination
	var destination_is_grounded := _detect_destination_floor()
	_has_grounded_override = true
	_grounded_override = destination_is_grounded
	if not preserve_velocity:
		velocity = Vector3.ZERO
	reset_physics_interpolation()
	var camera_pivot := get_node_or_null(camera_pivot_path) as LibertyCameraPivot
	if camera_pivot != null:
		camera_pivot.snap_to_target()
	_update_movement_state_for_grounded(destination_is_grounded)


func set_movement_locked(locked: bool) -> void:
	if _movement_locked == locked:
		return
	_movement_locked = locked
	if locked:
		_set_movement_state(MovementState.MOVEMENT_LOCKED)
	else:
		_update_movement_state()


func is_movement_locked() -> bool:
	return _movement_locked or _traversal_locked or _body_suspended


## Parallel locomotion intent. Player input stays on get_world_input_direction().
## A rejected call leaves an already armed mode unchanged.
func set_scripted_locomotion(planar_direction: Vector3, gait_cap: float, facing: Vector3 = Vector3.ZERO, has_facing: bool = false) -> Error:
	if not planar_direction.is_finite() or not is_finite(gait_cap):
		return ERR_INVALID_PARAMETER
	var direction := Vector3(planar_direction.x, 0.0, planar_direction.z).limit_length(1.0)
	var cap := clampf(gait_cap, 0.0, sprint_speed)
	var flat_facing := Vector3.ZERO
	if has_facing:
		if not facing.is_finite():
			return ERR_INVALID_PARAMETER
		flat_facing = Vector3(facing.x, 0.0, facing.z)
		if flat_facing.is_zero_approx():
			return ERR_INVALID_PARAMETER
		flat_facing = flat_facing.normalized()
	_scripted_direction = direction
	_scripted_gait_cap = cap
	_scripted_facing = flat_facing
	_scripted_has_facing = has_facing
	_scripted_active = true
	return OK


func clear_scripted_locomotion() -> void:
	_scripted_active = false


func has_scripted_locomotion() -> bool:
	return _scripted_active


func acquire_hit_suppression() -> int:
	_next_hit_token += 1
	_hit_suppression[_next_hit_token] = true
	return _next_hit_token


func release_hit_suppression(token: int) -> void:
	_hit_suppression.erase(token)


func is_hit_suppressed() -> bool:
	return not _hit_suppression.is_empty()


func _set_movement_state(next_state: MovementState) -> void:
	if movement_state == next_state:
		return
	var old_name := movement_state_name
	movement_state = next_state
	var events := get_node_or_null(events_path) as LibertyEvents
	if events != null:
		events.movement_state_changed.emit(old_name, movement_state_name)

## Typed owned-component command; the coordinator supplies at most one request per tick.
func submit_traversal_displacement(displacement: Vector3, yaw_delta: float) -> void:
	if not _traversal_locked or not displacement.is_finite() or not is_finite(yaw_delta):
		return
	_traversal_displacement = displacement
	_traversal_yaw = yaw_delta
	_has_traversal_request = true

func set_traversal_lock(enabled: bool) -> void:
	_traversal_locked = enabled
	_has_traversal_request = false
	_traversal_displacement = Vector3.ZERO
	_traversal_yaw = 0.0
	if enabled:
		velocity = Vector3.ZERO
	_update_movement_state()

func is_traversal_locked() -> bool:
	return _traversal_locked

func get_world_input_direction() -> Vector3:
	return _get_world_input_direction()

func interrupt_traversal(reason: StringName) -> void:
	if is_instance_valid(traversal_coordinator):
		traversal_coordinator.interrupt(reason)
	else:
		set_traversal_lock(false)

## Typed owned-component command for the ragdoll: while suspended the capsule is
## disabled and this body neither moves nor calls move_and_slide().
func set_body_suspended(suspended: bool) -> void:
	_body_suspended = suspended
	velocity = Vector3.ZERO
	var capsule := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if capsule != null:
		capsule.disabled = suspended
	if not suspended and is_inside_tree():
		_has_grounded_override = true
		_grounded_override = _detect_destination_floor()
	_update_movement_state()

func is_body_suspended() -> bool:
	return _body_suspended

func activate_ragdoll(impulse_direction: Vector3, force: float, reason: StringName) -> bool:
	if is_instance_valid(vehicle_possession):
		return false
	if not is_instance_valid(ragdoll):
		return false
	return ragdoll.activate_ragdoll(impulse_direction, force, reason)

## Hit entry: fatal hits start the passive ragdoll, non-fatal hits play an active
## reaction. Both emit hit_received. False when suppressed, mounted, or the bone
## or input is invalid. Suppression emits nothing.
func receive_hit(bone_name: StringName, direction: Vector3, force: float, fatal: bool) -> bool:
	if is_hit_suppressed():
		return false
	if is_instance_valid(vehicle_possession):
		return false
	if not is_instance_valid(physical_animation):
		return false
	return physical_animation.receive_hit(bone_name, direction, force, fatal)

func is_ragdoll_active() -> bool:
	return is_instance_valid(ragdoll) and ragdoll.is_active()
