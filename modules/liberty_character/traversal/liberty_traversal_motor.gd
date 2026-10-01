class_name LibertyTraversalMotor
extends Node
## Converts authored root motion and bounded residual correction to a body request.
class MotionRequest:
	var displacement := Vector3.ZERO
	var yaw_delta := 0.0
	var accepted := false
	var blocked := false

@export var max_position_correction := 0.45
@export var max_angular_correction := deg_to_rad(25.0)
@export var shimmy_speed := 0.35
@export var climb_speed := 0.375
var candidate: LibertyTraversalCandidate
var _residual := Vector3.ZERO
var _yaw_residual := 0.0
var _root_orientation := Basis.IDENTITY

func prepare_action(value: LibertyTraversalCandidate, authored_terminal: Transform3D) -> bool:
	clear()
	if value == null or not value.is_valid() or not authored_terminal.is_finite():
		return false
	var predicted := value.source_transform * authored_terminal
	_residual = value.destination_transform.origin - predicted.origin
	_yaw_residual = wrapf(value.destination_transform.basis.get_euler().y - predicted.basis.get_euler().y, -PI, PI)
	if _residual.length() > max_position_correction + 0.000001 or absf(_yaw_residual) > max_angular_correction + 0.000001:
		clear()
		return false
	candidate = value.duplicate_candidate()
	candidate.positional_correction = _residual.length()
	candidate.angular_correction = absf(_yaw_residual)
	_root_orientation = value.source_transform.basis.orthonormalized()
	return true

func compute_request(root_motion: Transform3D, previous_progress: float, progress: float) -> MotionRequest:
	var request := MotionRequest.new()
	if candidate == null or not root_motion.is_finite() or not is_finite(progress) or not is_finite(previous_progress) or progress < previous_progress:
		return request
	var correction_weight := smoothstep(0.15, 0.75, clampf(progress, 0, 1)) - smoothstep(0.15, 0.75, clampf(previous_progress, 0, 1))
	request.displacement = _root_orientation * root_motion.origin + _residual * correction_weight
	request.yaw_delta = root_motion.basis.get_euler().y + _yaw_residual * correction_weight
	request.accepted = true
	return request

func sustained_request(value: LibertyTraversalCandidate, from: Transform3D, delta: float) -> MotionRequest:
	var request := MotionRequest.new()
	if value == null or not value.is_valid() or not value.has_live_static_collider() or not is_finite(delta) or delta <= 0:
		return request
	var displacement := value.destination_transform.origin - from.origin
	var speed := climb_speed if value.kind == LibertyTraversalCandidate.Kind.CLIMB else shimmy_speed
	request.displacement = displacement.limit_length(speed * delta)
	request.accepted = true
	return request

func clear() -> void:
	candidate = null
	_residual = Vector3.ZERO
	_yaw_residual = 0.0
	_root_orientation = Basis.IDENTITY
