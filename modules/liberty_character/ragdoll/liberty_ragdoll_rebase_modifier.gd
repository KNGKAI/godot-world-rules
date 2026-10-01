class_name LibertyRagdollRebaseModifier
extends SkeletonModifier3D
## Runs after PhysicalBoneSimulator3D. Simulated bones cache their pose relative to the
## skeleton transform seen during the last physics step, so moving the character root
## leaves one tick of stale poses. rebase() re-expresses them in the new skeleton space once.
##
## During a hit reaction the kinematic Hips anchor shows this tick's animation while the
## simulated bodies show the last physics step, so a fast hip bob opens a visible gap at
## the waist. Each reacting tick re-anchors every simulated bone by the Hips' motion since
## that step, blended by the simulator influence.
var ragdoll: LibertyRagdoll
var _pending := false
var _correction := Transform3D.IDENTITY
var _bones := PackedInt32Array()


## correction = new_skeleton_global.affine_inverse() * old_skeleton_global
func rebase(correction: Transform3D, bones: PackedInt32Array) -> void:
	_correction = correction
	_bones = bones.duplicate()
	_bones.sort()
	_pending = true


func _process_modification_with_delta(_delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	if ragdoll != null and ragdoll.is_reacting():
		_anchor_reaction(skeleton)
	if not _pending:
		return
	_pending = false
	var poses: Array[Transform3D] = []
	for bone in _bones:
		poses.append(_correction * skeleton.get_bone_global_pose(bone))
	# Parents first: children keep local poses, so each write is independent.
	for index in _bones.size():
		skeleton.set_bone_global_pose(_bones[index], poses[index])


func _anchor_reaction(skeleton: Skeleton3D) -> void:
	var hips := ragdoll.get_physical_bone(&"Hips")
	var to_skeleton := skeleton.global_transform.affine_inverse()
	var hips_bone := hips.get_bone_id()
	var hips_step := to_skeleton * _server_bone(hips)
	var anchor := skeleton.get_bone_global_pose(hips_bone) * hips_step.affine_inverse()
	var influence := ragdoll.simulator.influence
	var bones := PackedInt32Array()
	var poses: Array[Transform3D] = []
	for bone_name in ragdoll.get_reaction_bones():
		var body := ragdoll.get_physical_bone(bone_name)
		var bone := body.get_bone_id()
		var simulated := anchor * to_skeleton * _server_bone(body)
		var animated := ragdoll.pose_capture.get_captured_pose(bone)
		bones.append(bone)
		poses.append(animated.interpolate_with(simulated, influence))
	for index in bones.size():
		skeleton.set_bone_global_pose(bones[index], poses[index])


## World bone transform of a physical body as of the last physics step.
static func _server_bone(body: PhysicalBone3D) -> Transform3D:
	var state: Transform3D = PhysicsServer3D.body_get_state(body.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM)
	return state * body.body_offset.affine_inverse()
