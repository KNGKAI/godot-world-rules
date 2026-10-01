class_name LibertyCameraPivot
extends Node3D

@export_group("Framing")
@export_range(0.0, 3.0, 0.05, "or_greater") var target_height := 1.45

@export_group("Look")
@export_range(0.01, 2.0, 0.01, "or_greater") var mouse_sensitivity_degrees := 0.12
@export_range(0.0, 89.0, 1.0) var pitch_up_limit_degrees := 70.0
@export_range(0.0, 89.0, 1.0) var pitch_down_limit_degrees := 50.0

@export_group("Follow")
@export_range(0.001, 2.0, 0.001, "or_greater") var follow_half_life := 0.12
@export_range(0.0, 10.0, 0.05, "or_greater") var teleport_snap_distance := 3.0

@export_group("Recenter")
@export_range(0.0, 10.0, 0.05, "or_greater") var recenter_delay := 1.25
@export_range(0.001, 5.0, 0.001, "or_greater") var recenter_half_life := 0.45

var _pitch := 0.0
var _yaw := 0.0
var _time_since_mouse_input := 0.0
var _orbit_held := false
var _follow_override: Node3D
var _follow_override_height := 0.0


func _ready() -> void:
	set_as_top_level(true)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_pitch = global_rotation.x
	_yaw = global_rotation.y
	snap_to_target()


func _unhandled_input(event: InputEvent) -> void:
	if _orbit_held:
		return
	var character := get_parent() as LibertyCharacter
	if character != null and is_instance_valid(character.vehicle_possession): return
	var mouse_motion := event as InputEventMouseMotion
	if mouse_motion == null:
		return
	apply_look_delta(mouse_motion.relative)


func apply_look_delta(relative: Vector2) -> void:
	if _orbit_held:
		return
	_yaw = wrapf(
		_yaw - deg_to_rad(relative.x * mouse_sensitivity_degrees),
		-PI,
		PI
	)
	_pitch = clampf(
		_pitch - deg_to_rad(relative.y * mouse_sensitivity_degrees),
		-deg_to_rad(pitch_down_limit_degrees),
		deg_to_rad(pitch_up_limit_degrees)
	)
	_time_since_mouse_input = 0.0
	_apply_look_rotation()
	_resolve_spring_arm_endpoint()


func _physics_process(delta: float) -> void:
	var target := get_parent() as Node3D
	if target == null:
		return
	var anchor := _anchor(target)
	if global_position.distance_to(anchor) > teleport_snap_distance:
		snap_to_target()
	else:
		var follow_target := global_position.lerp(
			anchor,
			_half_life_weight(follow_half_life, delta)
		)
		_move_follow_point_collision_safe(follow_target)

	_time_since_mouse_input += delta
	if not _orbit_held and _time_since_mouse_input > recenter_delay and _can_recenter(target):
		_yaw = lerp_angle(
			_yaw,
			target.global_rotation.y,
			_half_life_weight(recenter_half_life, delta)
		)
		_apply_look_rotation()
	_resolve_spring_arm_endpoint()


func snap_to_target() -> void:
	var target := get_parent() as Node3D
	if target == null:
		return
	global_position = _anchor(target)
	_resolve_spring_arm_endpoint()
	reset_physics_interpolation()
	for child in get_children():
		(child as Node).propagate_call(&"reset_physics_interpolation")


## Follows another node, such as the ragdoll hips, until cleared.
func set_follow_override(target: Node3D, height: float = 0.6) -> void:
	_follow_override = target
	_follow_override_height = height


func clear_follow_override() -> void:
	_follow_override = null


func set_orbit_held(held: bool) -> void:
	_orbit_held = held


func is_orbit_held() -> bool:
	return _orbit_held


func _anchor(target: Node3D) -> Vector3:
	if is_instance_valid(_follow_override):
		return _follow_override.global_position + Vector3.UP * _follow_override_height
	return target.global_position + Vector3.UP * target_height


func _move_follow_point_collision_safe(destination: Vector3) -> void:
	var motion := destination - global_position
	if motion.is_zero_approx():
		return
	var query := _make_camera_shape_query(motion)
	if query == null:
		global_position = destination
		return
	var space_state := get_world_3d().direct_space_state
	var fractions := space_state.cast_motion(query)
	var safe_fraction := clampf(fractions[0], 0.0, 1.0)
	if safe_fraction >= 1.0:
		global_position = destination
		return

	var rest_info := space_state.get_rest_info(query)
	global_position += motion * safe_fraction
	if rest_info.is_empty():
		return
	var collision_normal: Vector3 = rest_info.get("normal", Vector3.ZERO)
	if collision_normal.is_zero_approx():
		return
	var slide_motion := (motion * (1.0 - safe_fraction)).slide(collision_normal)
	if slide_motion.is_zero_approx():
		return
	var slide_query := _make_camera_shape_query(slide_motion)
	if slide_query == null:
		return
	var slide_fractions := space_state.cast_motion(slide_query)
	global_position += slide_motion * clampf(slide_fractions[0], 0.0, 1.0)


func _resolve_spring_arm_endpoint() -> void:
	var spring_arm := get_node_or_null(^"SpringArm3D") as SpringArm3D
	if spring_arm == null or spring_arm.shape == null or not is_inside_tree():
		return
	var query := _make_camera_shape_query(spring_arm.global_basis.z * spring_arm.spring_length)
	if query == null:
		return
	var fractions := get_world_3d().direct_space_state.cast_motion(query)
	var safe_length := spring_arm.spring_length * clampf(fractions[0], 0.0, 1.0)
	for child in spring_arm.get_children():
		var child_3d := child as Node3D
		if child_3d == null:
			continue
		var child_position := child_3d.position
		child_position.z = safe_length
		child_3d.position = child_position


func _make_camera_shape_query(motion: Vector3) -> PhysicsShapeQueryParameters3D:
	var spring_arm := get_node_or_null(^"SpringArm3D") as SpringArm3D
	if spring_arm == null or spring_arm.shape == null or not is_inside_tree():
		return null
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = spring_arm.shape
	query.transform = spring_arm.global_transform
	query.motion = motion
	query.margin = spring_arm.margin
	query.collision_mask = spring_arm.collision_mask
	query.collide_with_bodies = true
	query.collide_with_areas = false
	return query


func _can_recenter(target: Node3D) -> bool:
	var character := target as CharacterBody3D
	if character == null or not character.is_on_floor():
		return false
	return Vector2(character.velocity.x, character.velocity.z).length() > 0.1


func _apply_look_rotation() -> void:
	global_rotation = Vector3(_pitch, _yaw, 0.0)


func _half_life_weight(half_life: float, delta: float) -> float:
	if half_life <= 0.0:
		return 1.0
	return 1.0 - pow(0.5, delta / half_life)
