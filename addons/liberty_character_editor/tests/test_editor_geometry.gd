extends SceneTree
## Gizmo geometry matches what the runtime builds: ragdoll bodies, joints and limits, the probe
## template, and the IK chains and pole sides.
const Support = preload("res://modules/liberty_character/tests/liberty_test_support.gd")
const Geometry = preload("res://addons/liberty_character_editor/core/liberty_editor_geometry.gd")
const CHARACTER = preload("res://modules/liberty_character/character/liberty_character.tscn")


func _initialize() -> void: call_deferred("run")


func run() -> void:
	var character := CHARACTER.instantiate() as LibertyCharacter
	root.add_child(character)
	await physics_frame
	var skeleton := character.find_child("Skeleton3D", true, false) as Skeleton3D
	_check_ragdoll(character.ragdoll, skeleton)
	_check_hinge_arcs()
	_check_probe()
	_check_ik(skeleton)
	var segments := Geometry.ragdoll_segments(skeleton, Transform3D.IDENTITY)
	for key in segments:
		Support.expect_true(segments[key].size() > 0 and segments[key].size() % 2 == 0, "ragdoll %s segments are point pairs" % key)
	character.free()
	quit(Support.exit_code())


func _check_ragdoll(ragdoll: LibertyRagdoll, skeleton: Skeleton3D) -> void:
	var bodies := Geometry.ragdoll_bodies(skeleton)
	Support.expect_equal(bodies.size(), ragdoll.get_physical_bones().size(), "one gizmo body per physical bone")
	for body in bodies:
		var runtime := ragdoll.get_physical_bone(body.bone)
		Support.expect_true(runtime != null, "%s exists at runtime" % body.bone)
		if runtime == null: continue
		Support.expect_true(runtime.body_offset.is_equal_approx(body.body_offset), "%s body offset" % body.bone)
		Support.expect_equal(runtime.joint_type, body.joint_type, "%s joint type" % body.bone)
		if body.joint_type != PhysicalBone3D.JOINT_TYPE_NONE:
			Support.expect_true(runtime.joint_offset.is_equal_approx(body.joint_offset), "%s joint offset" % body.bone)
		match body.joint_type:
			PhysicalBone3D.JOINT_TYPE_CONE:
				Support.expect_true(is_equal_approx(runtime.get("joint_constraints/swing_span"), body.limits[0]), "%s swing" % body.bone)
				Support.expect_true(is_equal_approx(runtime.get("joint_constraints/twist_span"), body.limits[1]), "%s twist" % body.bone)
			PhysicalBone3D.JOINT_TYPE_HINGE:
				Support.expect_true(is_equal_approx(runtime.get("joint_constraints/angular_limit_lower"), body.limits[0]), "%s hinge lower" % body.bone)
				Support.expect_true(is_equal_approx(runtime.get("joint_constraints/angular_limit_upper"), body.limits[1]), "%s hinge upper" % body.bone)
		var collider := runtime.get_child(0) as CollisionShape3D
		var shape := collider.shape as CapsuleShape3D
		Support.expect_true(is_equal_approx(shape.radius, body.capsule_radius), "%s capsule radius" % body.bone)
		Support.expect_true(is_equal_approx(shape.height, body.capsule_height), "%s capsule height" % body.bone)
		Support.expect_true(collider.basis.is_equal_approx(body.capsule_basis), "%s capsule axis" % body.bone)


func _check_hinge_arcs() -> void:
	# The character faces -Z: shins fold backward (+Z) and forearms fold forward (-Z).
	for bone in [&"LeftLowerLeg", &"RightLowerLeg"]:
		var arc := Geometry.hinge_arc(bone)
		Support.expect_true(arc[arc.size() / 2].z > 0.5, "%s arc folds backward (%s)" % [bone, arc[arc.size() / 2]])
	for bone in [&"LeftLowerArm", &"RightLowerArm"]:
		var arc := Geometry.hinge_arc(bone)
		Support.expect_true(arc[arc.size() / 2].z < -0.5, "%s arc folds forward (%s)" % [bone, arc[arc.size() / 2]])


func _check_probe() -> void:
	var script: Script = load("res://modules/liberty_character/traversal/liberty_traversal_probe.gd")
	var values := {}
	for name in ["forward_reach", "upward_reach", "downward_reach", "hand_spacing", "foot_spacing", "hand_height", "foot_height"]:
		values[name] = script.get_property_default_value(name)
	var layout := Geometry.probe_layout(values)
	Support.expect_equal(layout.forward_rays.size(), 3, "three forward rays")
	for ray: Array in layout.forward_rays:
		Support.expect_true(is_equal_approx(ray[0].distance_to(ray[1]), values.forward_reach), "forward ray spans forward_reach")
		Support.expect_true(ray[1].z < 0.0, "forward rays point along -Z")
	Support.expect_true(is_equal_approx(layout.forward_rays[2][0].y, values.hand_height), "last ray at hand height")
	Support.expect_true(is_equal_approx(layout.ledge_ray[0].y, values.hand_height + values.upward_reach), "ledge ray top")
	Support.expect_true(is_equal_approx(layout.ledge_ray[1].y, -values.downward_reach), "ledge ray bottom")
	Support.expect_true(is_equal_approx(layout.left_hand.distance_to(layout.right_hand), values.hand_spacing), "hands hand_spacing apart")
	Support.expect_true(is_equal_approx(layout.left_foot.distance_to(layout.right_foot), values.foot_spacing), "feet foot_spacing apart")
	Support.expect_true(is_equal_approx(layout.left_foot.y, values.foot_height), "feet at foot_height")


func _check_ik(skeleton: Skeleton3D) -> void:
	var chains := Geometry.ik_chains(skeleton)
	Support.expect_equal(chains.size(), 4, "four limb chains on the real rig")
	for chain in chains:
		var arm: bool = String(chain.bones[0]).ends_with("Arm")
		var pole_side: float = chain.pole.z - chain.points[0].z
		Support.expect_true(pole_side > 0.0 if arm else pole_side < 0.0, "%s pole side" % chain.bones[0])
		Support.expect_true(is_equal_approx(absf(pole_side), Geometry.POLE_OFFSET), "%s pole offset" % chain.bones[0])
