class_name LibertyPoseCaptureModifier
extends SkeletonModifier3D
## Snapshot after animation/IK and before physical simulation. Keeps the previous tick's
## snapshot too, so bodies can start with the animated velocity.
var _captured: Array[Transform3D] = []
var _previous: Array[Transform3D] = []
var capture_frame := -1
var previous_frame := -1
var skeleton_transform := Transform3D.IDENTITY
var previous_skeleton_transform := Transform3D.IDENTITY
func _process_modification_with_delta(_delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	var frame := Engine.get_physics_frames()
	if frame != capture_frame:
		var swap := _previous
		_previous = _captured
		_captured = swap
		previous_frame = capture_frame
		previous_skeleton_transform = skeleton_transform
	_captured.resize(skeleton.get_bone_count())
	for index in skeleton.get_bone_count():
		_captured[index] = skeleton.get_bone_global_pose(index)
	capture_frame = frame
	skeleton_transform = skeleton.global_transform
func get_captured_pose(index: int) -> Transform3D:
	assert(index >= 0 and index < _captured.size(), "Pose capture requires a completed skeleton tick")
	return _captured[index]
## World linear and angular velocity of a point fixed in the bone (bone-local `offset`),
## from the last two captures; zero before two consecutive frames exist.
func get_animated_velocity(index: int, offset: Transform3D, delta: float) -> Array[Vector3]:
	if previous_frame != capture_frame - 1 or index >= _previous.size() or delta <= 0.0:
		return [Vector3.ZERO, Vector3.ZERO]
	var now := skeleton_transform * _captured[index] * offset
	var before := previous_skeleton_transform * _previous[index] * offset
	var turn := Quaternion((now.basis.orthonormalized() * before.basis.orthonormalized().inverse()).orthonormalized())
	if turn.w < 0.0:
		turn = -turn
	return [(now.origin - before.origin) / delta, turn.get_axis() * turn.get_angle() / delta if turn.get_angle() > 0.000001 else Vector3.ZERO]
