extends SceneTree
## Animated targets versus ragdoll joint limits: clamped targets must lie inside every
## limit minus the margin, and targets already inside stay untouched.
const Support = preload("res://modules/liberty_character/tests/liberty_test_support.gd")
const PA = preload("res://modules/liberty_character/ragdoll/liberty_physical_animation.gd")
var worst_raw := {}
var worst_clamped := -INF
var untouched_error := 0.0
var samples := 0

func _initialize() -> void: call_deferred("run")

func tick(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame

func sample(skeleton: Skeleton3D, capture: LibertyPoseCaptureModifier, margin: float) -> void:
	for bone: StringName in PA.PHYSICAL_PARENT:
		var parent: StringName = PA.PHYSICAL_PARENT[bone]
		var parent_basis := capture.get_captured_pose(skeleton.find_bone(parent)).basis
		var child_basis := capture.get_captured_pose(skeleton.find_bone(bone)).basis
		var raw := PA.limit_excess(bone, PA.joint_relative(bone, parent_basis, child_basis))
		worst_raw[bone] = maxf(worst_raw.get(bone, -INF), raw)
		var clamped := PA.clamp_target(bone, parent_basis, child_basis, margin)
		worst_clamped = maxf(worst_clamped, PA.limit_excess(bone, PA.joint_relative(bone, parent_basis, clamped)) + margin)
		if raw <= -margin:
			untouched_error = maxf(untouched_error, PA.rotation_error(child_basis, clamped).length())
		samples += 1

func run() -> void:
	var fixture := Node3D.new()
	root.add_child(fixture)
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, .4, 200)
	shape.shape = box
	floor_body.add_child(shape)
	fixture.add_child(floor_body)
	floor_body.position = Vector3(0, -.2, 0)
	var character = load("res://modules/liberty_character/character/liberty_character.tscn").instantiate()
	fixture.add_child(character)
	await tick(3)
	var ragdoll: LibertyRagdoll = character.get_node("Ragdoll")
	var skeleton := ragdoll.skeleton
	var capture := ragdoll.pose_capture
	var margin := deg_to_rad(2.0)
	# Idle, walk, run, sprint, then jump/fall/land while sprinting and turning.
	var phases := [[], [&"liberty_walk"], [], [&"liberty_sprint"]]
	for held: Array in phases:
		Input.action_press(&"liberty_move_forward")
		for action: StringName in held: Input.action_press(action)
		for i in (60 if held.is_empty() and phases.find(held) == 0 else 90):
			await tick(1)
			sample(skeleton, capture, margin)
		for action: StringName in held: Input.action_release(action)
	Input.action_press(&"liberty_sprint")
	Input.action_press(&"liberty_move_right")
	for jump in 3:
		Input.action_press(&"liberty_jump")
		await tick(1)
		Input.action_release(&"liberty_jump")
		for i in 50:
			await tick(1)
			sample(skeleton, capture, margin)
	Input.action_release(&"liberty_sprint")
	Input.action_release(&"liberty_move_right")
	Input.action_release(&"liberty_move_forward")
	for bone: StringName in worst_raw:
		print("%s worst raw excess %.1f deg" % [bone, rad_to_deg(worst_raw[bone])])
	print("samples %d, worst clamped excess over (limit - margin) %.4f deg, untouched-target change %.5f deg" % [
		samples, rad_to_deg(worst_clamped), rad_to_deg(untouched_error)])
	Support.expect_true(samples > 13 * 400, "sampled locomotion and airborne targets")
	Support.expect_true(worst_clamped <= deg_to_rad(.05), "clamped targets stay inside every limit minus the margin")
	Support.expect_true(untouched_error < deg_to_rad(.01), "targets inside the limits are unchanged")

	# Synthetic: hinge sign convention and off-axis removal; cone swing/twist clamp.
	var elbow := Basis(Vector3.UP, deg_to_rad(-30.0)) # measured: left elbow flexes to positive relative angle
	Support.expect_true(PA.limit_excess(&"LeftLowerArm", PA.joint_relative(&"LeftLowerArm", Basis.IDENTITY, elbow)) > deg_to_rad(29.0), "left elbow hyperextension is a violation")
	var flexed := Basis(Vector3.UP, deg_to_rad(60.0)) * Basis(Vector3.RIGHT, deg_to_rad(15.0))
	var fixed := PA.clamp_target(&"LeftLowerArm", Basis.IDENTITY, flexed, margin)
	var rel := PA.joint_relative(&"LeftLowerArm", Basis.IDENTITY, fixed)
	Support.expect_true(Vector2(rel.x, rel.y).length() < .0001, "hinge clamp removes off-axis rotation")
	Support.expect_true(PA.limit_excess(&"LeftLowerArm", rel) <= -margin + .0001, "hinge clamp result is inside the limits")
	# A knee folds the shin backward (+Z): a negative rotation about the lateral X axis.
	var knee := Basis(Vector3.RIGHT, deg_to_rad(-70.0))
	Support.expect_true(PA.limit_excess(&"LeftLowerLeg", PA.joint_relative(&"LeftLowerLeg", Basis.IDENTITY, knee)) < 0.0, "a flexed knee is inside its limits")
	var hyperextended := Basis(Vector3.RIGHT, deg_to_rad(20.0))
	Support.expect_true(PA.limit_excess(&"LeftLowerLeg", PA.joint_relative(&"LeftLowerLeg", Basis.IDENTITY, hyperextended)) > deg_to_rad(19.0), "a hyperextended knee is a violation")
	var twisted := Basis(Vector3.UP, deg_to_rad(35.0)) * Basis(Vector3.RIGHT, deg_to_rad(40.0))
	var spine := PA.clamp_target(&"Spine", Basis.IDENTITY, twisted, margin)
	Support.expect_true(absf(PA.limit_excess(&"Spine", PA.joint_relative(&"Spine", Basis.IDENTITY, spine)) + margin) < .001, "cone clamp lands on the limit minus margin")
	character.queue_free()
	quit(Support.exit_code())
