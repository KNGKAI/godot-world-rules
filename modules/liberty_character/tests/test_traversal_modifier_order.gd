extends SceneTree
const IK = preload("res://modules/liberty_character/traversal/liberty_traversal_ik_modifier.gd")
const Capture = preload("res://modules/liberty_character/ragdoll/liberty_pose_capture_modifier.gd")
const Candidate = preload("res://modules/liberty_character/traversal/liberty_traversal_candidate.gd")
const Support = preload("res://modules/liberty_character/tests/liberty_test_support.gd")
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var character = load("res://modules/liberty_character/character/liberty_character.tscn").instantiate()
	root.add_child(character)
	character.set_physics_process(false)
	var skeleton: Skeleton3D = character.find_child("Skeleton3D", true, false)
	var coordinator = character.get_node("Traversal")
	var ik = coordinator.ik
	var capture = coordinator.pose_capture
	Support.expect_true(ik.configuration_error == "", "four real rig limb chains configure")
	var types: Array[String] = []
	for node in skeleton.get_children():
		if node is SkeletonModifier3D: types.append(node.get_class())
	Support.expect_equal(types, ["SkeletonModifier3D", "TwoBoneIK3D", "TwoBoneIK3D", "TwoBoneIK3D", "TwoBoneIK3D", "LookAtModifier3D", "SkeletonModifier3D", "SkeletonModifier3D", "PhysicalBoneSimulator3D", "SkeletonModifier3D"], "exact modifier order: capture, physical animation, simulator, ragdoll rebase")
	var c := Candidate.new()
	var base: Vector3 = character.global_position
	c.left_hand_target = base + Vector3(.28, 1.45, -.35)
	c.right_hand_target = base + Vector3(-.28, 1.45, -.35)
	c.left_foot_target = base + Vector3(.1, .1, -.1)
	c.right_foot_target = base + Vector3(-.1, .1, -.1)
	ik.set_candidate(c)
	for i in range(15):
		await physics_frame
		await process_frame
	Support.expect_true(ik.left_arm_ik.active and ik.left_arm_ik.influence > .99, "IK blends on")
	var hand := skeleton.find_bone("LeftHand")
	var captured: Transform3D = capture.get_captured_pose(hand)
	Support.expect_true((skeleton.global_transform * captured).origin.distance_to(c.left_hand_target) < .03, "captured pose includes actual arm IK")
	var elbow: Transform3D = skeleton.global_transform * capture.get_captured_pose(skeleton.find_bone("LeftLowerArm"))
	Support.expect_true(elbow.origin.z > c.left_hand_target.z, "arm pole preserves backward elbow")
	ik.clear_targets(true)
	for limb in ik.get_limbs():
		Support.expect_false(limb.active, "immediate interruption disables every limb")
		Support.expect_equal(limb.influence, 0.0, "immediate interruption zeroes influence")
	character.queue_free()
	quit(Support.exit_code())
