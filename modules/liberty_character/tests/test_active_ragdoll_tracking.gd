extends SceneTree
## Tracking quality at full strength while idle, running and sprinting: rotation error
## against the clamped target, joint gap at the kinematic hips, visible-vs-body offset,
## body speeds and PD cost.
const Support = preload("res://modules/liberty_character/tests/liberty_test_support.gd")
const Capture = preload("res://modules/liberty_character/ragdoll/liberty_pose_capture_modifier.gd")

func _initialize() -> void: call_deferred("run")

func tick(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame

func percentile(values: Array, fraction: float) -> float:
	if values.is_empty(): return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[clampi(int(ceil(fraction * sorted.size())) - 1, 0, sorted.size() - 1)]

func run() -> void:
	var fixture := Node3D.new()
	root.add_child(fixture)
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(300, .4, 300)
	shape.shape = box
	floor_body.add_child(shape)
	fixture.add_child(floor_body)
	floor_body.position = Vector3(0, -.2, 0)
	var character = load("res://modules/liberty_character/character/liberty_character.tscn").instantiate()
	fixture.add_child(character)
	character.teleport_to(Transform3D(Basis.IDENTITY, Vector3(0, 0, 100)))
	await tick(4)
	var ragdoll: LibertyRagdoll = character.get_node("Ragdoll")
	var skeleton := ragdoll.skeleton
	var stage: LibertyPhysicalAnimation = ragdoll.physical_animation
	var visible: LibertyPoseCaptureModifier = Capture.new()
	skeleton.add_child(visible) # Test-only: final pose after simulation and rebase.
	stage.hold_tracking = true
	Support.expect_true(stage.track([&"core"]), "core and arms tracked")
	# [name, held actions, ticks, p95 limit, max limit] in degrees. Moving limits were set from
	# measurement (Phase 7 ledger): the sprint clip swings the arms at up to 14 rad/s, which a
	# stable 60 Hz spring follows with a residual lag.
	var phases := [["idle", [], 180, 1.0, 2.0], ["run", [&"liberty_move_forward"], 300, 15.0, 25.0], ["sprint", [&"liberty_move_forward", &"liberty_sprint"], 300, 25.0, 35.0]]
	var all_finite := true
	for phase: Array in phases:
		for action: StringName in phase[1]: Input.action_press(action)
		var errors := []
		var per_bone := {}
		var worst_gap := 0.0
		var worst_speed := 0.0
		var cost := []
		for i in phase[2]:
			await tick(1)
			if not ragdoll.is_reacting():
				break
			if i < 30: continue # Let each gait establish.
			for bone: StringName in stage.last_errors_degrees:
				var e: float = stage.last_errors_degrees[bone]
				errors.append(e)
				per_bone[bone] = maxf(per_bone.get(bone, 0.0), e)
			worst_speed = maxf(worst_speed, stage.max_body_angular_speed)
			cost.append(stage.last_update_usec)
			var spine := skeleton.find_bone("Spine")
			worst_gap = maxf(worst_gap, (visible.get_captured_pose(spine).origin - ragdoll.pose_capture.get_captured_pose(spine).origin).length())
			for bone: StringName in ragdoll.get_reaction_bones():
				var body := ragdoll.get_physical_bone(bone)
				var server: Transform3D = PhysicsServer3D.body_get_state(body.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM)
				all_finite = all_finite and server.origin.is_finite()
		for action: StringName in phase[1]: Input.action_release(action)
		var bone_report := ""
		for bone in per_bone: bone_report += " %s %.1f" % [bone, per_bone[bone]]
		print("%s: speed %.2f m/s | error p50 %.1f p95 %.1f max %.1f deg | spine gap %.4f m | max w %.1f rad/s | PD %.0f us p50, %.0f us max\n   per-bone max:%s" % [
			phase[0], character.planar_speed, percentile(errors, .5), percentile(errors, .95), percentile(errors, 1.0), worst_gap, worst_speed,
			percentile(cost, .5), percentile(cost, 1.0), bone_report])
		Support.expect_true(ragdoll.is_reacting(), "%s: tracking never trips the guard (%s)" % [phase[0], stage.last_guard_trip])
		Support.expect_true(percentile(errors, .95) < phase[3], "%s: 95th-percentile error under %.0f degrees" % [phase[0], phase[3]])
		Support.expect_true(percentile(errors, 1.0) < phase[4], "%s: maximum error under %.0f degrees" % [phase[0], phase[4]])
		Support.expect_true(worst_gap < .02, "%s: hips/spine joint gap under 0.02 m" % phase[0])
		Support.expect_true(worst_speed < 35.0, "%s: body angular speed under 35 rad/s (guard 40)" % phase[0])
	Support.expect_true(all_finite, "bodies stay finite")
	stage.release()
	character.queue_free()
	quit(Support.exit_code())
