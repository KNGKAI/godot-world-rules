extends SceneTree
const Support = preload("res://modules/liberty_character/tests/liberty_test_support.gd")
const Capture = preload("res://modules/liberty_character/ragdoll/liberty_pose_capture_modifier.gd")
var recovered: Array = []
func _initialize() -> void: call_deferred("run")
func tick(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame
func box(parent: Node3D, xf: Transform3D, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var resource := BoxShape3D.new()
	resource.size = size
	shape.shape = resource
	body.add_child(shape)
	parent.add_child(body)
	body.transform = xf
	return body
func spine_yaw(basis: Basis) -> float:
	var axis := basis * Vector3.UP
	return atan2(-axis.x, -axis.z)
func run() -> void:
	var fixture := Node3D.new()
	root.add_child(fixture)
	box(fixture, Transform3D(Basis.IDENTITY, Vector3(0, -.2, 0)), Vector3(40, .4, 40))
	var character = load("res://modules/liberty_character/character/liberty_character.tscn").instantiate()
	fixture.add_child(character)
	await tick(3)
	var ragdoll: LibertyRagdoll = character.get_node("Ragdoll")
	var driver: LibertyAnimationDriver = character.get_node("AnimationDriver")
	var events: LibertyEvents = character.get_node("Events")
	events.ragdoll_recovered.connect(func(face_up: bool): recovered.append(face_up))
	Support.expect_true(ragdoll.is_face_up(driver.sample_bone_pose(&"get_up_back", &"Hips", 0.0).basis), "get_up_back starts face-up")
	Support.expect_false(ragdoll.is_face_up(driver.sample_bone_pose(&"get_up_front", &"Hips", 0.0).basis), "get_up_front starts face-down")
	var skeleton: Skeleton3D = ragdoll.skeleton
	var final_pose: LibertyPoseCaptureModifier = Capture.new()
	skeleton.add_child(final_pose) # Test-only: records the visible post-simulation pose.
	var head := skeleton.find_bone("Head")
	var hips_bone := skeleton.find_bone("Hips")
	var seen := {}
	var pushes := [Vector3.FORWARD, Vector3.BACK, Vector3(1, 0, -1).normalized(), Vector3(-1, 0, 1).normalized()]
	for trial in pushes.size():
		character.teleport_to(Transform3D(Basis(Vector3.UP, .7 * trial), Vector3(trial * 6.0 - 9.0, 0, 0)))
		await tick(4)
		recovered.clear()
		character.activate_ragdoll(character.global_basis * pushes[trial], 170.0, &"recovery_test")
		var previous_head := Vector3.ZERO
		var began := false
		for i in 900:
			await tick(1)
			if ragdoll.state == LibertyRagdoll.State.BLENDING_OUT:
				began = true
				break
			previous_head = skeleton.global_transform * final_pose.get_captured_pose(head).origin
		Support.expect_true(began, "trial %d recovery begins" % trial)
		if not began: break
		var face_up := ragdoll.face_up
		seen[face_up] = true
		var head_error := previous_head.distance_to(skeleton.global_transform * final_pose.get_captured_pose(head).origin)
		var ragdoll_hips := ragdoll.get_hips_world_transform()
		var animated_hips: Transform3D = skeleton.global_transform * ragdoll.pose_capture.get_captured_pose(hips_bone)
		var planar := Vector2(ragdoll_hips.origin.x - animated_hips.origin.x, ragdoll_hips.origin.z - animated_hips.origin.z).length()
		var yaw_error := rad_to_deg(absf(wrapf(spine_yaw(ragdoll_hips.basis) - spine_yaw(animated_hips.basis), -PI, PI)))
		Support.expect_true(absf(character.global_position.y) < .02, "trial %d root placed on the floor" % trial)
		Support.expect_true(head_error < .01, "trial %d alignment preserves visible head" % trial)
		Support.expect_true(planar < .05, "trial %d hips match first get-up frame horizontally" % trial)
		Support.expect_true(yaw_error < 10.0, "trial %d hips match first get-up frame yaw" % trial)
		Support.expect_equal(driver.get_state(), &"Recovery", "trial %d plays Recovery" % trial)
		var blend_ticks := 0
		var lowest := INF
		var lowest_at := ""
		var lowest_blend := INF
		var sim_stopped := false
		for i in 400:
			await tick(1)
			if ragdoll.state == LibertyRagdoll.State.BLENDING_OUT:
				blend_ticks += 1
			elif not sim_stopped and ragdoll.state == LibertyRagdoll.State.GETTING_UP:
				sim_stopped = true
				Support.expect_false(ragdoll.simulator.is_simulating_physics(), "trial %d simulation stops after blend" % trial)
				Support.expect_equal(ragdoll.simulator.influence, 0.0, "trial %d influence reaches zero" % trial)
			for bone in skeleton.get_bone_count():
				var height := (skeleton.global_transform * final_pose.get_captured_pose(bone)).origin.y
				if ragdoll.state == LibertyRagdoll.State.BLENDING_OUT or blend_ticks > 0 and not sim_stopped:
					lowest_blend = minf(lowest_blend, height)
					continue
				if height < lowest:
					lowest = height
					lowest_at = "%s %s p=%.2f" % [skeleton.get_bone_name(bone), ragdoll.state_name, driver.get_recovery_progress()]
			if ragdoll.state == LibertyRagdoll.State.INACTIVE:
				break
		print("trial %d face_up=%s head %.4f m hips %.4f m yaw %.2f deg blend %d ticks lowest bone %.4f m (%s) lowest during blend %.4f m" % [trial, face_up, head_error, planar, yaw_error, blend_ticks + 1, lowest, lowest_at, lowest_blend])
		Support.expect_true(absi(blend_ticks + 1 - 24) <= 1, "trial %d physical influence blends over 0.4 s" % trial)
		Support.expect_true(lowest > -.03, "trial %d no bone penetrates the floor during get-up" % trial)
		# Documented tolerance: the global influence blend interpolates unsimulated
		# hand tips between ragdoll and authored arm poses (see Phase 6 report). Widened
		# from 0.08 m in Phase 7 once the corrected knees changed the face-down rest pose.
		Support.expect_true(lowest_blend > -.14, "trial %d blend dip stays within tolerance" % trial)
		Support.expect_equal(ragdoll.state, LibertyRagdoll.State.INACTIVE, "trial %d recovery completes" % trial)
		Support.expect_equal(recovered, [face_up], "trial %d ragdoll_recovered emits orientation once" % trial)
		Support.expect_false(character.is_movement_locked(), "trial %d movement restored" % trial)
		Support.expect_false((character.get_node("CollisionShape3D") as CollisionShape3D).disabled, "trial %d capsule restored" % trial)
		await tick(12)
		Support.expect_true(character.is_on_floor(), "trial %d standing on the floor" % trial)
		Support.expect_equal(driver.get_state(), &"Locomotion", "trial %d returns to Locomotion" % trial)
		Support.expect_false(character.is_traversal_locked(), "trial %d never recovers into traversal" % trial)
	Support.expect_true(seen.has(true) and seen.has(false), "both get-up orientations exercised")

	# Floor validation: steep slopes and missing floors are rejected conservatively.
	ragdoll.set_physics_process(false)
	var slope_normal := Basis(Vector3.BACK, deg_to_rad(55.0)) * Vector3.UP
	box(fixture, Transform3D(Basis(Vector3.BACK, deg_to_rad(55.0)), Vector3(40, 0, 0) - slope_normal * .2), Vector3(4, .4, 4))
	character.teleport_to(Transform3D(Basis.IDENTITY, Vector3(40, 0, 0)))
	character.activate_ragdoll(Vector3.FORWARD, 0.0, &"slope_test")
	await tick(1)
	Support.expect_false(ragdoll.try_begin_recovery(), "55 degree slope refuses recovery")
	Support.expect_equal(ragdoll.last_rejection, &"steep_floor", "rejection names the steep floor")
	Support.expect_equal(ragdoll.state, LibertyRagdoll.State.SIMULATING, "refused recovery stays ragdolled")
	Support.expect_true(character.is_movement_locked(), "refused recovery keeps movement disabled")
	for body in ragdoll.get_physical_bones():
		PhysicsServer3D.body_set_state(body.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(body.global_basis, body.global_position + Vector3(0, 30, 60)))
	await tick(1)
	Support.expect_false(ragdoll.try_begin_recovery(), "no floor refuses recovery")
	Support.expect_equal(ragdoll.last_rejection, &"no_floor", "rejection names the missing floor")
	character.queue_free()
	quit(Support.exit_code())
