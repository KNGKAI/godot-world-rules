class_name LibertyTraversalIKModifier
extends SkeletonModifier3D
## Owns target nodes and four subsequent modifiers; never probes or chooses actions.
@export var blend_seconds := 0.1
var left_hand_target: Node3D
var right_hand_target: Node3D
var left_foot_target: Node3D
var right_foot_target: Node3D
var left_arm_ik: TwoBoneIK3D
var right_arm_ik: TwoBoneIK3D
var left_leg_ik: TwoBoneIK3D
var right_leg_ik: TwoBoneIK3D
var configuration_error := ""
var _candidate: LibertyTraversalCandidate
var _target_influence := 0.0
var _poles: Array[Node3D] = []
var _skeleton: Skeleton3D

func configure(skeleton: Skeleton3D) -> bool:
	_skeleton = skeleton
	for side in ["Left", "Right"]:
		for part in ["UpperArm", "LowerArm", "Hand", "UpperLeg", "LowerLeg", "Foot"]:
			if skeleton.find_bone(side + part) < 0:
				configuration_error = "Missing IK bone: " + side + part
				return false
	left_hand_target = _target("LeftHandTarget")
	right_hand_target = _target("RightHandTarget")
	left_foot_target = _target("LeftFootTarget")
	right_foot_target = _target("RightFootTarget")
	left_arm_ik = _limb("Left", true, left_hand_target)
	right_arm_ik = _limb("Right", true, right_hand_target)
	left_leg_ik = _limb("Left", false, left_foot_target)
	right_leg_ik = _limb("Right", false, right_foot_target)
	return true

func _target(node_name: String) -> Node3D:
	var target := Node3D.new()
	target.name = node_name
	add_child(target)
	return target

func _limb(side: String, arm: bool, target: Node3D) -> TwoBoneIK3D:
	var pole := _target(side + ("ElbowPole" if arm else "KneePole"))
	_poles.append(pole)
	var ik := TwoBoneIK3D.new()
	ik.name = side + ("ArmIK" if arm else "LegIK")
	ik.setting_count = 1
	_skeleton.add_child(ik)
	ik.set_root_bone_name(0, side + ("UpperArm" if arm else "UpperLeg"))
	ik.set_middle_bone_name(0, side + ("LowerArm" if arm else "LowerLeg"))
	ik.set_end_bone_name(0, side + ("Hand" if arm else "Foot"))
	ik.set_target_node(0, ik.get_path_to(target))
	ik.set_pole_node(0, ik.get_path_to(pole))
	ik.influence = 0.0
	ik.active = false
	return ik

func get_limbs() -> Array[TwoBoneIK3D]:
	return [left_arm_ik, right_arm_ik, left_leg_ik, right_leg_ik]

func set_candidate(candidate: LibertyTraversalCandidate) -> void:
	if candidate == null:
		clear_targets()
		return
	_candidate = candidate.duplicate_candidate()
	_target_influence = 1.0

func clear_targets(immediate: bool = false) -> void:
	_candidate = null
	_target_influence = 0.0
	if immediate:
		for ik in get_limbs():
			if ik != null:
				ik.influence = 0.0
				ik.active = false

func _process_modification_with_delta(delta: float) -> void:
	if _skeleton == null or left_arm_ik == null:
		return
	if _candidate != null:
		left_hand_target.global_position = _candidate.left_hand_target
		right_hand_target.global_position = _candidate.right_hand_target
		left_foot_target.global_position = _candidate.left_foot_target
		right_foot_target.global_position = _candidate.right_foot_target
	var limbs := get_limbs()
	for index in limbs.size():
		var ik := limbs[index]
		var bone := ik.get_root_bone(0)
		if bone >= 0:
			var origin := (_skeleton.global_transform * _skeleton.get_bone_global_pose(bone)).origin
			_poles[index].global_position = origin + _skeleton.global_basis.z * (0.6 if index < 2 else -0.6)
		ik.influence = move_toward(ik.influence, _target_influence, delta / maxf(blend_seconds, 0.001))
		ik.active = ik.influence > 0.0
