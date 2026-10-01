extends SceneTree

const VehicleController = preload("res://modules/liberty_vehicle/vehicle/liberty_vehicle.gd")

func _init() -> void:
	var controller := VehicleController.new()

	# Direction changes always brake before applying opposing drive force.
	assert(controller.drive_command(1.0, 0.0, 0.0) == Vector2(1.0, 0.0))
	assert(controller.drive_command(0.0, 1.0, 8.0) == Vector2(0.0, 1.0))
	assert(controller.drive_command(0.0, 1.0, 0.2) == Vector2(-1.0, 0.0))
	assert(controller.drive_command(1.0, 1.0, 8.0) == Vector2(0.0, 1.0))
	assert(controller.drive_command(1.0, 0.0, -4.0) == Vector2(0.0, 1.0))
	assert(controller.drive_command(0.0, 0.0, 0.0) == Vector2.ZERO)

	# Drive force tapers to zero at top speed and stays finite with bad tuning.
	var launch_force := absf(controller.engine_force_for_speed(1.0, 0.0))
	var cruise_force := absf(controller.engine_force_for_speed(1.0, controller.forward_top_speed_mps * 0.5))
	var top_force := absf(controller.engine_force_for_speed(1.0, controller.forward_top_speed_mps))
	assert(launch_force > cruise_force)
	assert(cruise_force > top_force)
	assert(is_zero_approx(top_force))
	# This project presents -Z as visual forward, so forward drive is negative.
	assert(controller.engine_force_for_speed(1.0, 0.0) < 0.0)
	assert(controller.engine_force_for_speed(-1.0, 0.0) > 0.0)
	controller.forward_top_speed_mps = 0.0
	assert(is_finite(controller.engine_force_for_speed(1.0, 5.0)))

	# Steering remains finite and loses authority with speed.
	assert(controller.steering_limit_for_speed(0.0) > controller.steering_limit_for_speed(30.0))
	controller.steer_full_reduction_speed = 0.0
	assert(is_finite(controller.steering_limit_for_speed(10.0)))

	# Resistance acts only in the horizontal plane and always opposes motion.
	var velocity := Vector3(12.0, 5.0, -3.0)
	var drag := controller.drag_force_for_velocity(velocity)
	assert(is_zero_approx(drag.y))
	assert(Vector2(drag.x, drag.z).dot(Vector2(velocity.x, velocity.z)) < 0.0)
	assert(controller.drag_force_for_velocity(Vector3.ZERO).is_zero_approx())
	controller.rolling_resistance = -1.0
	controller.aerodynamic_drag = -1.0
	controller.maximum_drag_force = -1.0
	assert(controller.drag_force_for_velocity(Vector3(10.0, 0.0, 0.0)).is_zero_approx())
	controller.rolling_resistance = 0.35
	controller.aerodynamic_drag = 0.01
	controller.maximum_drag_force = 120.0

	# Handbrake releases rear grip while assists stay grounded and bounded.
	assert(controller.rear_grip_target(true) < controller.rear_grip_target(false))
	controller.rear_grip_normal = -5.0
	assert(controller.rear_grip_target(true) >= 0.05)
	controller.rear_grip_normal = 1.05
	assert(is_zero_approx(controller.yaw_correction_for_state(2.0, 20.0, false, false)))
	assert(is_zero_approx(controller.yaw_correction_for_state(2.0, 2.0, true, false)))
	assert(absf(controller.yaw_correction_for_state(2.0, 20.0, true, true)) < absf(controller.yaw_correction_for_state(2.0, 20.0, true, false)))

	# Rear grip recovers gradually without overshooting its baseline.
	var lowered_grip := controller.rear_grip_target(true)
	var partial_recovery := controller.next_grip(lowered_grip, controller.rear_grip_normal, 0.1)
	assert(partial_recovery > lowered_grip)
	assert(partial_recovery < controller.rear_grip_normal)
	assert(is_equal_approx(controller.next_grip(controller.rear_grip_normal - 0.01, controller.rear_grip_normal, 10.0), controller.rear_grip_normal))
	assert(not controller.is_grounded())

	# Stateful braking cancels drive immediately and distributes wheel braking safely.
	var service_brake := Vector2(0.0, 1.0)
	assert(is_zero_approx(controller.next_drive_demand(1.0, service_brake, false, 1.0 / 60.0)))
	assert(is_equal_approx(controller.wheel_brake_for_state(1.0, false, false), controller.brake_force_max))
	assert(is_equal_approx(controller.wheel_brake_for_state(1.0, false, true), controller.brake_force_max))
	assert(is_equal_approx(controller.wheel_brake_for_state(1.0, true, false), controller.brake_force_max))
	assert(is_equal_approx(controller.wheel_brake_for_state(1.0, true, true), controller.handbrake_force))
	assert(is_zero_approx(controller.wheel_brake_for_state(0.0, false, true)))

	controller.free()
	print("vehicle handling model tests passed")
	quit()
