extends SceneTree

const Support = preload("res://modules/liberty_character/tests/liberty_test_support.gd")
const PREVIEW := "res://modules/liberty_character/tests/test_mannequin.tscn"
const ASSET := "res://assets/characters/liberty_mannequin/liberty_mannequin.glb"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	Support.expect_true(ResourceLoader.exists(PREVIEW), "standalone mannequin preview must exist")
	if not ResourceLoader.exists(PREVIEW):
		quit(Support.exit_code())
		return
	var scene := load(PREVIEW) as PackedScene
	var previous_touch_emulation := Input.emulate_mouse_from_touch
	var preview = scene.instantiate()
	root.add_child(preview)
	await process_frame
	Support.expect_true(Input.emulate_mouse_from_touch, "standalone preview enables touch interaction with popup menus")
	var skeleton := preview.find_child("Skeleton3D", true, false) as Skeleton3D
	Support.expect_true(skeleton != null, "GLB must import a usable skeleton")
	if skeleton != null:
		Support.expect_equal(skeleton.get_bone_count(), 23, "all body bones must survive import")
		for bone in ["Root", "Hips", "LeftHand", "RightHand", "LeftFoot", "RightFoot"]:
			Support.expect_true(skeleton.find_bone(bone) >= 0, "missing imported bone %s" % bone)
	var player := preview.find_child("AnimationPlayer", true, false) as AnimationPlayer
	Support.expect_true(player != null, "GLB must import an animation player")
	if player == null or skeleton == null:
		preview.queue_free()
		await process_frame
		quit(Support.exit_code())
		return
	Support.expect_equal(preview.clip_names.size(), 30, "preview exposes every required clip")
	var skin_count := 0
	for mesh in preview.find_children("*", "MeshInstance3D", true, false):
		if mesh.skin != null:
			skin_count += 1
			Support.expect_equal(mesh.skin.get_bind_count(), 23, "mesh skin retains the complete bind set")
	Support.expect_true(skin_count > 0, "preview must show a skinned mesh")
	for clip in preview.clip_names:
		Support.expect_true(preview.select_clip(clip), "preview must select %s" % clip)
		preview.set_playing(false)
		preview.scrub(0.0)
		var start := skeleton.get_bone_pose_rotation(skeleton.find_bone("LeftUpperArm"))
		preview.scrub(preview.clip_duration * 0.5)
		Support.expect_true(is_finite(skeleton.get_bone_global_pose(skeleton.find_bone("Head")).origin.y), "%s pose must stay finite" % clip)
		var animation := player.get_animation(preview.animation_key)
		var expected_loop := bool(preview.manifest["clips"][clip]["loop"])
		Support.expect_equal(animation.loop_mode, Animation.LOOP_LINEAR if expected_loop else Animation.LOOP_NONE, "%s import loop mode" % clip)
		if clip == "walk":
			preview.scrub(preview.clip_duration * 0.25)
			Support.expect_true(start.angle_to(skeleton.get_bone_pose_rotation(skeleton.find_bone("LeftUpperArm"))) > 0.05, "walking must animate the actual imported skeleton")
	# Facing -Z: elbows bend backwards (+Z), whereas knees bend forwards (-Z).
	# Test the actual exported/imported joint geometry, not generator constants.
	for clip in ["idle", "walk", "run", "sprint"]:
		preview.select_clip(clip)
		for phase in [0.0, 0.25, 0.5, 0.75]:
			preview.scrub(preview.clip_duration * phase)
			for side in ["Left", "Right"]:
				var shoulder := skeleton.get_bone_global_pose(skeleton.find_bone(side + "UpperArm")).origin
				var elbow := skeleton.get_bone_global_pose(skeleton.find_bone(side + "LowerArm")).origin
				var hand := skeleton.get_bone_global_pose(skeleton.find_bone(side + "Hand")).origin
				var arm_axis := (hand - shoulder).normalized()
				var elbow_offset := elbow - shoulder - arm_axis * (elbow - shoulder).dot(arm_axis)
				Support.expect_true(elbow_offset.z > 0.02, "%s %s elbow must bend behind the arm axis at phase %.2f (offset %s)" % [clip, side, phase, elbow_offset])
				var hip := skeleton.get_bone_global_pose(skeleton.find_bone(side + "UpperLeg")).origin
				var knee := skeleton.get_bone_global_pose(skeleton.find_bone(side + "LowerLeg")).origin
				var foot := skeleton.get_bone_global_pose(skeleton.find_bone(side + "Foot")).origin
				var leg_axis := (foot - hip).normalized()
				var knee_offset := knee - hip - leg_axis * (knee - hip).dot(leg_axis)
				Support.expect_true(knee_offset.z < -0.005, "%s %s knee must continue bending forward" % [clip, side])
	# A planted foot moves backwards at the authored gait speed; this is what
	# lets the future controller translate the body without obvious foot sliding.
	for clip in ["walk", "run", "sprint"]:
		preview.select_clip(clip)
		var duration: float = preview.clip_duration
		var stance: float = {"walk": 0.5, "run": 0.35, "sprint": 0.32}[clip]
		var speed: float = {"walk": 2.2, "run": 5.0, "sprint": 7.5}[clip]
		preview.scrub(duration * stance * 0.15)
		var early := skeleton.get_bone_global_pose(skeleton.find_bone("LeftFoot")).origin
		preview.scrub(duration * stance * 0.85)
		var late := skeleton.get_bone_global_pose(skeleton.find_bone("LeftFoot")).origin
		var elapsed := duration * stance * 0.7
		Support.expect_true(absf((late.z - early.z) / elapsed - speed) < 0.12, "%s stance must match its authored speed" % clip)
		Support.expect_true(absf(early.y - 0.09) < 0.005 and absf(late.y - 0.09) < 0.005, "%s stance foot must stay on the floor (early %s, late %s)" % [clip, early, late])
	preview.select_clip("mantle_high")
	preview.set_playing(false)
	preview.set_root_motion_visible(true)
	preview.scrub(preview.clip_duration)
	var root_index := skeleton.find_bone("Root")
	var authored := skeleton.get_bone_global_pose(root_index)
	Support.expect_true(authored.origin.y > 1.0, "mantle must contain vertical root motion")
	preview.set_root_motion_visible(false)
	preview.scrub(preview.clip_duration)
	var displayed: Transform3D = preview.rig.transform * skeleton.transform * authored
	Support.expect_true(displayed.origin.length() < 0.001, "in-place preview compensates root motion")
	preview.select_clip("idle")
	Support.expect_true(preview.rig.position.length() < 0.001, "switching clips resets the root origin")
	preview.set_playing(false)
	preview.scrub(preview.clip_duration * 0.4)
	var paused_at: float = player.current_animation_position
	preview.set_playing(true)
	Support.expect_true(absf(player.current_animation_position - paused_at) < 0.001, "resume must not restart a scrubbed clip")
	preview.select_clip("mantle_high")
	preview.set_playing(true)
	preview._process(preview.clip_duration + 0.5)
	Support.expect_true(is_equal_approx(player.current_animation_position, preview.clip_duration), "one-shot completion holds its last frame")
	Support.expect_false(player.is_playing(), "completed one-shot pauses automatically")
	var held_pose := skeleton.get_bone_global_pose(skeleton.find_bone("Head"))
	preview._process(0.5)
	Support.expect_true(held_pose.is_equal_approx(skeleton.get_bone_global_pose(skeleton.find_bone("Head"))), "completed one-shot keeps its final pose")
	preview.set_playing(true)
	Support.expect_true(is_zero_approx(player.current_animation_position), "Play restarts a completed one-shot")
	preview.select_clip("corner_inner_left")
	preview.set_root_motion_visible(false)
	preview.scrub(preview.clip_duration)
	var corner_pose := skeleton.transform * skeleton.get_bone_global_pose(root_index)
	Support.expect_true(absf(corner_pose.basis.get_euler().y) > 1.0, "corner contains authored root yaw")
	Support.expect_true((preview.rig.transform * corner_pose).is_equal_approx(Transform3D.IDENTITY), "in-place preview cancels root yaw as well as translation")
	Support.expect_false(preview.select_clip("missing_clip"), "unknown clip is rejected")
	# Exercise the real popup with touch events, not its hide() method.
	preview._selector.show_popup()
	await create_timer(0.4).timeout
	var popup: PopupMenu = preview._selector.get_popup()
	Support.expect_true(popup.visible, "animation menu opens")
	var touch := InputEventScreenTouch.new()
	touch.index = 0
	touch.position = Vector2(4, 4)
	touch.pressed = true
	Input.parse_input_event(touch)
	await process_frame
	touch = touch.duplicate()
	touch.pressed = false
	Input.parse_input_event(touch)
	await process_frame
	Support.expect_false(popup.visible, "touching outside the animation menu dismisses it")
	preview.set_playing(true)
	touch = touch.duplicate()
	touch.position = preview._play_button.get_global_rect().get_center()
	touch.pressed = true
	Input.parse_input_event(touch)
	await process_frame
	touch = touch.duplicate()
	touch.pressed = false
	Input.parse_input_event(touch)
	await process_frame
	Support.expect_false(player.is_playing(), "touch input reaches Pause after dismissing the menu")
	preview.queue_free()
	await process_frame
	Support.expect_equal(Input.emulate_mouse_from_touch, previous_touch_emulation, "leaving preview restores gameplay touch configuration")
	quit(Support.exit_code())
