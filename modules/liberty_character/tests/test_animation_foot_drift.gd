extends SceneTree

const Support = preload("res://modules/liberty_character/tests/liberty_test_support.gd")
const CharacterScene = preload("res://modules/liberty_character/character/liberty_character.tscn")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var floor := StaticBody3D.new()
	floor.collision_layer = 1
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(500, 1, 500)
	collision.shape = shape
	collision.position.y = -0.5
	floor.add_child(collision)
	world.add_child(floor)
	var character := CharacterScene.instantiate() as LibertyCharacter
	world.add_child(character)
	for clip in ["walk", "sprint"]:
		Input.action_release(&"liberty_move_forward")
		Input.action_release(&"liberty_walk")
		Input.action_release(&"liberty_sprint")
		character.teleport_to(Transform3D.IDENTITY)
		for _frame in 60:
			await physics_frame
		Input.action_press(&"liberty_move_forward")
		Input.action_press(&"liberty_walk" if clip == "walk" else &"liberty_sprint")
		for _frame in 120:
			await physics_frame
		await _measure(character, clip)
	Input.action_release(&"liberty_move_forward")
	Input.action_release(&"liberty_walk")
	Input.action_release(&"liberty_sprint")
	world.free()
	quit(Support.exit_code())


func _measure(character: LibertyCharacter, clip: String) -> void:
	var tree := character.get_node("AnimationTree") as AnimationTree
	var skeleton := character.get_node("Rig/Skeleton3D") as Skeleton3D
	var duration := 0.8 if clip == "walk" else 0.46
	var stance := 0.5 if clip == "walk" else 0.32
	var speed := 2.2 if clip == "walk" else 7.5
	var bones := [skeleton.find_bone("LeftFoot"), skeleton.find_bone("RightFoot")]
	var anchors := [Vector3.ZERO, Vector3.ZERO]
	var previous := [Vector3.ZERO, Vector3.ZERO]
	var planted := [false, false]
	var armed := [false, false]
	var counts := [0, 0]
	var residual := [0.0, 0.0]
	var excursion := [0.0, 0.0]
	var height_error := 0.0
	var samples := [0, 0]
	var local_start := [Vector3.ZERO, Vector3.ZERO]
	var local_last := [Vector3.ZERO, Vector3.ZERO]
	var phase_start := [0.0, 0.0]
	var phase_last := [0.0, 0.0]
	var measured_speed := [0.0, 0.0]
	# Reads last completed physics tick: body and tree have both evaluated.
	# Omit 2% of a cycle at each stance boundary to exclude touchdown/toe-off.
	for _frame in 700:
		await physics_frame
		Support.expect_true(absf(character.planar_speed - speed) < 0.001, "%s measurement must stay at authored gait speed" % clip)
		var time := float(tree.get("parameters/Locomotion/BlendSpace1D/%s/current_position" % clip))
		for side in 2:
			if counts[side] >= 10:
				continue
			var phase := fposmod(time / duration + side * 0.5, 1.0)
			var contact := phase >= 0.02 and phase <= stance - 0.02
			# Discard a possible partial contact at the start of measurement.
			if not armed[side]:
				armed[side] = not contact
				continue
			var local_point := skeleton.get_bone_global_pose(bones[side]).origin
			var point := skeleton.global_transform * skeleton.get_bone_global_pose(bones[side]).origin
			if contact:
				if not planted[side]:
					anchors[side] = point
					planted[side] = true
					local_start[side] = local_point
					phase_start[side] = phase
				local_last[side] = local_point
				phase_last[side] = phase
				previous[side] = point
				excursion[side] = maxf(excursion[side], point.distance_to(anchors[side]))
				height_error = maxf(height_error, absf(point.y - character.global_position.y - 0.09))
				samples[side] += 1
			elif planted[side]:
				residual[side] += previous[side].distance_to(anchors[side])
				counts[side] += 1
				measured_speed[side] += (local_last[side].z - local_start[side].z) / ((phase_last[side] - phase_start[side]) * duration)
				planted[side] = false
		if counts[0] >= 10 and counts[1] >= 10:
			break
	for side in 2:
		Support.expect_equal(counts[side], 10, "%s foot %d must complete ten stance windows" % [clip, side])
		Support.expect_true(samples[side] > 50, "%s must measure real planted poses, not an empty window" % clip)
		Support.expect_true(excursion[side] < 0.05, "%s foot %d maximum planted drift %.6f must be below 0.05 m" % [clip, side, excursion[side]])
		Support.expect_true(residual[side] < 0.05, "%s foot %d ten-cycle accumulated residual %.6f must be below 0.05 m" % [clip, side, residual[side]])
		Support.expect_true(absf(measured_speed[side] / 10.0 - speed) < 0.12, "%s stance displacement must independently confirm authored m/s" % clip)
	Support.expect_true(height_error < 0.005, "%s contact height must stay within 5 mm of the authored ankle height" % clip)
	print("FOOT_DRIFT %s samples=%s cycles=%s excursion=%s accumulated_residual=%s height_error=%.6f" % [clip, samples, counts, excursion, residual, height_error])
	print("AUTHORED_SPEED %s L/R %.6f %.6f m/s" % [clip, measured_speed[0] / 10.0, measured_speed[1] / 10.0])
