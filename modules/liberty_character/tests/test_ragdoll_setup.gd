extends SceneTree
const Support = preload("res://modules/liberty_character/tests/liberty_test_support.gd")
const EXPECTED := {
	&"Hips": [12.0, PhysicalBone3D.JOINT_TYPE_NONE],
	&"Spine": [8.0, PhysicalBone3D.JOINT_TYPE_CONE],
	&"Chest": [12.0, PhysicalBone3D.JOINT_TYPE_CONE],
	&"Head": [5.0, PhysicalBone3D.JOINT_TYPE_CONE],
	&"LeftUpperArm": [2.5, PhysicalBone3D.JOINT_TYPE_CONE],
	&"RightUpperArm": [2.5, PhysicalBone3D.JOINT_TYPE_CONE],
	&"LeftLowerArm": [1.5, PhysicalBone3D.JOINT_TYPE_HINGE],
	&"RightLowerArm": [1.5, PhysicalBone3D.JOINT_TYPE_HINGE],
	&"LeftUpperLeg": [8.0, PhysicalBone3D.JOINT_TYPE_CONE],
	&"RightUpperLeg": [8.0, PhysicalBone3D.JOINT_TYPE_CONE],
	&"LeftLowerLeg": [4.0, PhysicalBone3D.JOINT_TYPE_HINGE],
	&"RightLowerLeg": [4.0, PhysicalBone3D.JOINT_TYPE_HINGE],
	&"LeftFoot": [1.0, PhysicalBone3D.JOINT_TYPE_CONE],
	&"RightFoot": [1.0, PhysicalBone3D.JOINT_TYPE_CONE],
}
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var character = load("res://modules/liberty_character/character/liberty_character.tscn").instantiate()
	root.add_child(character)
	await physics_frame
	var ragdoll = character.get_node_or_null("Ragdoll")
	Support.expect_true(ragdoll is LibertyRagdoll, "character owns a LibertyRagdoll")
	if ragdoll == null:
		quit(Support.exit_code())
		return
	Support.expect_equal(ragdoll.configuration_error, "", "ragdoll configures on the real rig")
	var skeleton: Skeleton3D = character.find_child("Skeleton3D", true, false)
	var modifiers: Array[Node] = []
	for node in skeleton.get_children():
		if node is SkeletonModifier3D: modifiers.append(node)
	Support.expect_true(modifiers[-1] == ragdoll.rebase, "one-shot rebase runs after the simulator")
	Support.expect_true(modifiers[-2] == ragdoll.simulator and modifiers[-3] == ragdoll.physical_animation, "physical animation precedes the simulator")
	Support.expect_true(modifiers[-4] == ragdoll.pose_capture, "capture precedes physical animation")
	var bones: Array = ragdoll.get_physical_bones()
	Support.expect_equal(bones.size(), EXPECTED.size(), "fourteen physical bones")
	for bone: PhysicalBone3D in bones:
		var expected: Array = EXPECTED.get(StringName(bone.bone_name), [])
		Support.expect_false(expected.is_empty(), "unexpected bone %s" % bone.bone_name)
		if expected.is_empty(): continue
		Support.expect_equal(bone.mass, expected[0], "%s mass" % bone.bone_name)
		Support.expect_equal(bone.joint_type, expected[1], "%s joint" % bone.bone_name)
		Support.expect_equal(bone.collision_layer, 4, "%s occupies ragdoll layer 3 only" % bone.bone_name)
		Support.expect_equal(bone.collision_mask, 1, "%s node preserves WORLD_MASK" % bone.bone_name)
		Support.expect_equal(PhysicsServer3D.body_get_collision_layer(bone.get_rid()), 0, "%s standby RID layer is zero" % bone.bone_name)
		Support.expect_equal(PhysicsServer3D.body_get_collision_mask(bone.get_rid()), 0, "%s standby RID mask is zero" % bone.bone_name)
		Support.expect_true(bone.get_bone_id() >= 0, "%s resolves its skeleton bone" % bone.bone_name)
		var shape := bone.get_child(0) as CollisionShape3D
		Support.expect_true(shape != null and shape.shape is CapsuleShape3D, "%s has a capsule" % bone.bone_name)
	var capsule := character.get_node("CollisionShape3D") as CollisionShape3D
	Support.expect_false(capsule.disabled, "capsule starts enabled")
	Support.expect_equal(character.collision_mask & 4, 0, "capsule never collides with ragdoll layer")
	Support.expect_false(ragdoll.simulator.is_simulating_physics(), "ragdoll starts inactive")
	Support.expect_false(character.is_ragdoll_active(), "character starts upright")
	character.queue_free()
	quit(Support.exit_code())
