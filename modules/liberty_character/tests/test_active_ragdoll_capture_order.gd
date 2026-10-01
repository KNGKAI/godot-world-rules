extends SceneTree
## Pose-capture ordering: the PD stage sits between PoseCapture and the simulator, reads
## the same-update capture, and that capture stays the animated pose while bodies deviate.
const Support = preload("res://modules/liberty_character/tests/liberty_test_support.gd")
const Capture = preload("res://modules/liberty_character/ragdoll/liberty_pose_capture_modifier.gd")
const PA = preload("res://modules/liberty_character/ragdoll/liberty_physical_animation.gd")

func _initialize() -> void: call_deferred("run")

func tick(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame

func angle_between(a: Basis, b: Basis) -> float:
	return PA.rotation_error(a, b).length()

func run() -> void:
	var fixture := Node3D.new()
	root.add_child(fixture)
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60, .4, 60)
	shape.shape = box
	floor_body.add_child(shape)
	fixture.add_child(floor_body)
	floor_body.position = Vector3(0, -.2, 0)
	var character = load("res://modules/liberty_character/character/liberty_character.tscn").instantiate()
	fixture.add_child(character)
	await tick(4)
	var ragdoll: LibertyRagdoll = character.get_node("Ragdoll")
	var skeleton := ragdoll.skeleton
	var stage: LibertyPhysicalAnimation = ragdoll.physical_animation
	Support.expect_true(stage != null and stage.configuration_error == "", "physical animation stage configures")
	Support.expect_true(character.physical_animation == stage, "character references the stage")
	var modifiers: Array[Node] = []
	for node in skeleton.get_children():
		if node is SkeletonModifier3D: modifiers.append(node)
	var at := modifiers.find(ragdoll.pose_capture)
	Support.expect_true(at >= 0 and modifiers[at + 1] == stage and modifiers[at + 2] == ragdoll.simulator and modifiers[at + 3] == ragdoll.rebase,
		"PoseCapture -> PhysicalAnimation -> PhysicalBoneSimulator -> RagdollRebase")
	Support.expect_equal(skeleton.modifier_callback_mode_process, Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_PHYSICS, "modifiers run in physics")
	var visible: LibertyPoseCaptureModifier = Capture.new()
	skeleton.add_child(visible) # Test-only: the final, post-simulation pose.

	# Freeze animation so the animated/IK pose is a fixed reference.
	var tree := character.get_node("AnimationTree") as AnimationTree
	tree.active = false
	await tick(2)
	var reference := {}
	for body in ragdoll.get_physical_bones():
		reference[body.bone_name] = ragdoll.pose_capture.get_captured_pose(body.get_bone_id())
	stage.hold_tracking = true
	Support.expect_true(stage.track([&"core"]), "tracking starts")
	await tick(2)
	# Spin the left arm and chest away from the target.
	for bone_name: StringName in [&"LeftUpperArm", &"LeftLowerArm", &"Chest"]:
		var body := ragdoll.get_physical_bone(bone_name)
		PhysicsServer3D.body_set_state(body.get_rid(), PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, Vector3(0, 0, 18.0))
	var frames_match := true
	var capture_drift := 0.0
	var max_visible_deviation := 0.0
	var arm := ragdoll.get_physical_bone(&"LeftUpperArm")
	var initial_error := -1.0
	var final_error := 0.0
	var peak_tracked := 0.0
	var final_tracked := 0.0
	for i in 60:
		await tick(1)
		frames_match = frames_match and stage.last_read_frame == stage.last_capture_frame and stage.last_read_frame == Engine.get_physics_frames()
		for body in ragdoll.get_physical_bones():
			var captured := ragdoll.pose_capture.get_captured_pose(body.get_bone_id())
			var expected: Transform3D = reference[body.bone_name]
			capture_drift = maxf(capture_drift, maxf(captured.origin.distance_to(expected.origin), angle_between(captured.basis, expected.basis)))
		var arm_bone := arm.get_bone_id()
		var deviation := angle_between(visible.get_captured_pose(arm_bone).basis, ragdoll.pose_capture.get_captured_pose(arm_bone).basis)
		max_visible_deviation = maxf(max_visible_deviation, deviation)
		var tracked: float = stage.last_errors_degrees.get(&"LeftUpperArm", 0.0)
		peak_tracked = maxf(peak_tracked, tracked)
		if i == 1: initial_error = deviation
		final_error = deviation
		final_tracked = tracked
	print("capture drift %.6f, visible arm deviation max %.3f rad (tick 1 %.3f, tick 60 %.4f); tracked error peak %.1f, final %.2f deg" % [capture_drift, max_visible_deviation, initial_error, final_error, peak_tracked, final_tracked])
	Support.expect_true(frames_match, "the stage reads the capture from its own physics frame")
	Support.expect_true(capture_drift < .0001, "capture stays the animated pose while bodies deviate")
	Support.expect_true(max_visible_deviation > .1, "visible pose follows the simulated, displaced bodies")
	Support.expect_true(final_tracked < 2.0 and final_tracked < peak_tracked * .25, "tracking returns the spun arm to its clamped target within one second")
	stage.release()
	Support.expect_false(ragdoll.is_reacting(), "release ends the reaction")
	await tick(2)
	var settled := 0.0
	for body in ragdoll.get_physical_bones():
		settled = maxf(settled, angle_between(visible.get_captured_pose(body.get_bone_id()).basis, ragdoll.pose_capture.get_captured_pose(body.get_bone_id()).basis))
	Support.expect_true(settled < .0001, "released skeleton shows the animated pose")
	character.queue_free()
	quit(Support.exit_code())
