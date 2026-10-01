class_name LibertyVehicle
extends VehicleBody3D

signal speed_changed(kph: float)

@export_group("Power")
@export var engine_force_max := 2200.0
@export var reverse_force_max := 1100.0
@export var forward_top_speed_mps := 42.0
@export var reverse_top_speed_mps := 12.0
@export var throttle_response := 2.8
@export var direction_change_speed := 1.0

@export_group("Braking")
@export var brake_force_max := 1800.0
@export var handbrake_force := 2600.0

@export_group("Steering")
@export var steer_low_speed_deg := 28.0
@export var steer_high_speed_deg := 1.6
@export var steer_full_reduction_speed := 22.0
@export var steer_response := 2.2
@export var steer_return_response := 3.6

@export_group("Resistance and Stability")
@export var rolling_resistance := 0.35
@export var aerodynamic_drag := 0.01
@export var maximum_drag_force := 120.0
@export var downforce_coefficient := 1.5
@export var maximum_downforce := 3200.0
@export var yaw_stability_strength := 420.0
@export var yaw_stability_min_speed := 6.0
@export var maximum_yaw_correction := 1400.0

@export_group("Grip")
@export var rear_grip_normal := 1.15
@export_range(0.1, 1.0, 0.05) var handbrake_grip_multiplier := 0.38
@export var grip_recovery_rate := 2.8

@onready var front_left := get_node_or_null("FrontLeft") as VehicleWheel3D
@onready var front_right := get_node_or_null("FrontRight") as VehicleWheel3D
@onready var rear_left := get_node_or_null("RearLeft") as VehicleWheel3D
@onready var rear_right := get_node_or_null("RearRight") as VehicleWheel3D

var spawn_transform: Transform3D
var controls := LibertyVehicleControlSnapshot.new()
var possession: LibertyVehiclePossession
var camera_rig: LibertyVehicleCameraRig
var _smoothed_drive_demand := 0.0

func _ready() -> void:
	spawn_transform = global_transform
	possession = get_node_or_null("Possession") as LibertyVehiclePossession
	if possession != null: possession.control_disabled.connect(_neutralize_controls)
	camera_rig = get_node_or_null("CameraRig") as LibertyVehicleCameraRig
	for wheel in [rear_left, rear_right]:
		if is_instance_valid(wheel):
			wheel.wheel_friction_slip = rear_grip_target(false)

func drive_command(throttle_value: float, brake_value: float, forward_speed: float) -> Vector2:
	var throttle_demand := clampf(throttle_value, 0.0, 1.0)
	var brake_demand := clampf(brake_value, 0.0, 1.0)
	if throttle_demand > 0.0 and brake_demand > 0.0:
		return Vector2(0.0, maxf(throttle_demand, brake_demand))
	if throttle_demand > 0.0:
		if forward_speed < -direction_change_speed:
			return Vector2(0.0, throttle_demand)
		return Vector2(throttle_demand, 0.0)
	if brake_demand > 0.0:
		if forward_speed > direction_change_speed:
			return Vector2(0.0, brake_demand)
		return Vector2(-brake_demand, 0.0)
	return Vector2.ZERO

func engine_force_for_speed(drive_demand: float, forward_speed: float) -> float:
	if is_zero_approx(drive_demand):
		return 0.0
	var reversing := drive_demand < 0.0
	var top_speed := maxf(reverse_top_speed_mps if reversing else forward_top_speed_mps, 0.001)
	var maximum_force := maxf(reverse_force_max if reversing else engine_force_max, 0.0)
	var speed_in_drive_direction := maxf(forward_speed * signf(drive_demand), 0.0)
	var speed_ratio := clampf(speed_in_drive_direction / top_speed, 0.0, 1.0)
	var torque_ratio := 1.0 - smoothstep(0.15, 1.0, speed_ratio)
	return -signf(drive_demand) * maximum_force * absf(drive_demand) * torque_ratio

func steering_limit_for_speed(speed_mps: float) -> float:
	var reduction_speed := maxf(steer_full_reduction_speed, 0.001)
	var ratio := clampf(absf(speed_mps) / reduction_speed, 0.0, 1.0)
	# Keyboard steering is full lock. smoothstep kept a parking angle well into
	# neighborhood speeds, so a held turn sat on the tire limit. The power curve
	# spends most of the reduction early, then keeps tightening as speed rises.
	var shaped := 1.0 - pow(1.0 - ratio, 3.2)
	return deg_to_rad(lerpf(steer_low_speed_deg, steer_high_speed_deg, shaped))

func drag_force_for_velocity(planar_velocity: Vector3) -> Vector3:
	var planar := Vector3(planar_velocity.x, 0.0, planar_velocity.z)
	var speed := planar.length()
	if speed <= 0.001:
		return Vector3.ZERO
	var resistance := maxf(rolling_resistance, 0.0) * speed
	var aero := maxf(aerodynamic_drag, 0.0) * speed * speed
	var magnitude := minf(resistance + aero, maxf(maximum_drag_force, 0.0))
	return -planar.normalized() * magnitude

func rear_grip_target(handbrake_active: bool) -> float:
	var baseline := maxf(rear_grip_normal, 0.05)
	var multiplier := clampf(handbrake_grip_multiplier, 0.1, 1.0) if handbrake_active else 1.0
	return maxf(baseline * multiplier, 0.05)

func yaw_correction_for_state(yaw_rate: float, speed_mps: float, grounded: bool, handbrake_active: bool) -> float:
	if not grounded or speed_mps < yaw_stability_min_speed:
		return 0.0
	var handbrake_scale := 0.2 if handbrake_active else 1.0
	var correction_limit := maxf(maximum_yaw_correction, 0.0)
	return clampf(-yaw_rate * maxf(yaw_stability_strength, 0.0) * handbrake_scale, -correction_limit, correction_limit)

func next_drive_demand(current_demand: float, command: Vector2, handbrake_active: bool, delta: float) -> float:
	if command.y > 0.0 or handbrake_active:
		return 0.0
	return move_toward(current_demand, command.x, maxf(throttle_response, 0.0) * maxf(delta, 0.0))

func wheel_brake_for_state(service_demand: float, handbrake_active: bool, rear_wheel: bool) -> float:
	var service_force := clampf(service_demand, 0.0, 1.0) * maxf(brake_force_max, 0.0)
	if handbrake_active and rear_wheel:
		return maxf(service_force, maxf(handbrake_force, 0.0))
	return service_force

func is_grounded() -> bool:
	for wheel in [front_left, front_right, rear_left, rear_right]:
		if is_instance_valid(wheel) and wheel.is_in_contact():
			return true
	return false

func next_grip(current_grip: float, target_grip: float, delta: float) -> float:
	return move_toward(current_grip, target_grip, maxf(grip_recovery_rate, 0.0) * maxf(delta, 0.0))

func _set_rear_grip(target: float, delta: float) -> void:
	for wheel in [rear_left, rear_right]:
		if is_instance_valid(wheel):
			wheel.wheel_friction_slip = next_grip(wheel.wheel_friction_slip, target, delta)

func _set_wheel_brakes(service_demand: float, handbrake_active: bool) -> void:
	for wheel in [front_left, front_right]:
		if is_instance_valid(wheel):
			wheel.brake = wheel_brake_for_state(service_demand, handbrake_active, false)
	for wheel in [rear_left, rear_right]:
		if is_instance_valid(wheel):
			wheel.brake = wheel_brake_for_state(service_demand, handbrake_active, true)

func _physics_process(delta: float) -> void:
	var drive_enabled := is_instance_valid(possession) and possession.control_enabled
	var intent := controls if drive_enabled else LibertyVehicleControlSnapshot.new()
	var steer_input := clampf(intent.steering, -1.0, 1.0)
	var throttle_input := intent.throttle
	var brake_input := intent.brake
	var handbrake_active := intent.handbrake
	var local_velocity := global_basis.inverse() * linear_velocity
	var forward_speed := -local_velocity.z
	var planar_speed := Vector3(linear_velocity.x, 0.0, linear_velocity.z).length()
	var grounded := is_grounded()
	var command := drive_command(throttle_input, brake_input, forward_speed)

	_smoothed_drive_demand = next_drive_demand(_smoothed_drive_demand, command, handbrake_active, delta)
	engine_force = engine_force_for_speed(_smoothed_drive_demand, forward_speed)
	brake = 0.0
	_set_wheel_brakes(command.y, handbrake_active)
	if handbrake_active:
		engine_force = 0.0

	var limit := steering_limit_for_speed(planar_speed)
	var steering_target := steer_input * limit
	var steering_rate := steer_response if not is_zero_approx(steer_input) else steer_return_response
	steering = move_toward(steering, steering_target, maxf(steering_rate, 0.0) * delta)

	if grounded:
		_set_rear_grip(rear_grip_target(handbrake_active), delta)
		apply_central_force(drag_force_for_velocity(linear_velocity))
		var downforce := minf(maxf(downforce_coefficient, 0.0) * planar_speed * planar_speed, maxf(maximum_downforce, 0.0))
		apply_central_force(-global_basis.y * downforce)
		var local_yaw_rate := angular_velocity.dot(global_basis.y)
		var yaw_correction := yaw_correction_for_state(local_yaw_rate, planar_speed, true, handbrake_active)
		apply_torque(global_basis.y * yaw_correction)

	if drive_enabled and intent.toggle_camera and is_instance_valid(camera_rig):
		camera_rig.toggle_mode()
	if drive_enabled and intent.reset:
		reset_to_spawn()
	speed_changed.emit(linear_velocity.length() * 3.6)

func reset_to_spawn() -> void:
	global_transform = spawn_transform
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_smoothed_drive_demand = 0.0
	engine_force = 0.0
	brake = 0.0
	steering = 0.0
	_set_wheel_brakes(0.0, false)
	_set_rear_grip(rear_grip_target(false), 1.0)
	sleeping = false

## Commands supplied by the possession adapter; no keyboard polling in the sedan.
func submit_controls(value: LibertyVehicleControlSnapshot) -> void:
	controls = value if value != null else LibertyVehicleControlSnapshot.new()

func request_mount(occupant: LibertyCharacter, seat_id: StringName) -> LibertyVehicleContracts.MountResult:
	if not is_instance_valid(possession):
		var result := LibertyVehicleContracts.MountResult.new()
		result.seat_id = seat_id
		result.reason = &"seat not found" if seat_id != &"driver_front_left" else &"vehicle unavailable or destroying"
		return result
	return possession.request_mount(occupant, seat_id)

func request_dismount(seat_id: StringName) -> LibertyVehicleContracts.DismountResult:
	if not is_instance_valid(possession):
		var result := LibertyVehicleContracts.DismountResult.new()
		result.seat_id = seat_id
		result.reason = &"seat not found" if seat_id != &"driver_front_left" else &"vehicle unavailable or destroying"
		return result
	return possession.request_dismount(seat_id)

func set_control_enabled(seat_id: StringName, enabled: bool) -> void:
	if seat_id != &"driver_front_left" or not is_instance_valid(possession): return
	possession.set_control_enabled(seat_id, enabled)
	if not enabled: _neutralize_controls()

func _neutralize_controls() -> void:
	controls = LibertyVehicleControlSnapshot.new()
	_smoothed_drive_demand = 0.0
	engine_force = 0.0
	_set_wheel_brakes(0.0, false)

func get_camera_anchor(seat_id: StringName) -> Node3D:
	if not is_instance_valid(possession): return null
	return possession.get_camera_anchor(seat_id)
