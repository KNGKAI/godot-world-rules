class_name LibertyVehicleControlSnapshot
extends RefCounted
## One frame of driver intent. Steering follows the reference's left-positive convention.
var steering := 0.0
var throttle := 0.0
var brake := 0.0
var handbrake := false
var reset := false
var toggle_camera := false

static func from_input(allow_reset: bool = false) -> LibertyVehicleControlSnapshot:
	var value := LibertyVehicleControlSnapshot.new()
	value.steering = -Input.get_axis(&"liberty_vehicle_steer_left", &"liberty_vehicle_steer_right")
	value.throttle = Input.get_action_strength(&"liberty_vehicle_throttle")
	value.brake = Input.get_action_strength(&"liberty_vehicle_brake")
	value.handbrake = Input.is_action_pressed(&"liberty_vehicle_handbrake")
	value.reset = allow_reset and Input.is_action_just_pressed(&"liberty_vehicle_reset")
	value.toggle_camera = Input.is_action_just_pressed(&"liberty_vehicle_toggle_camera")
	return value
