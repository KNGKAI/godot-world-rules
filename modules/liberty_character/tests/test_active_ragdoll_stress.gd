extends SceneTree
## Twenty seeded random hits while sprinting beside a thin wall: no guard trips, bounded
## speeds, no floor penetration, no tunnelling through the wall, and the PD cost per tick.
const Support = preload("res://modules/liberty_character/tests/liberty_test_support.gd")
const WALL_X := 0.55
const WALL_HALF := 0.025

func _initialize() -> void: call_deferred("run")

func tick(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame

func box(parent: Node3D, position: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var resource := BoxShape3D.new()
	resource.size = size
	shape.shape = resource
	body.add_child(shape)
	parent.add_child(body)
	body.position = position

func percentile(values: Array, fraction: float) -> float:
	if values.is_empty(): return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[clampi(int(ceil(fraction * sorted.size())) - 1, 0, sorted.size() - 1)]

func run() -> void:
	var fixture := Node3D.new()
	root.add_child(fixture)
	box(fixture, Vector3(0, -.2, 0), Vector3(60, .4, 300))
	box(fixture, Vector3(WALL_X, 1.2, 0), Vector3(WALL_HALF * 2.0, 2.4, 300)) # Thin wall beside the path.
	var character: LibertyCharacter = load("res://modules/liberty_character/character/liberty_character.tscn").instantiate()
	fixture.add_child(character)
	character.teleport_to(Transform3D(Basis.IDENTITY, Vector3(0, 0, 120)))
	await tick(4)
	var ragdoll: LibertyRagdoll = character.get_node("Ragdoll")
	var stage: LibertyPhysicalAnimation = ragdoll.physical_animation
	var skeleton := ragdoll.skeleton
	var rng := RandomNumberGenerator.new()
	rng.seed = 7007
	Input.action_press(&"liberty_move_forward")
	Input.action_press(&"liberty_sprint")
	await tick(40)
	var accepted := 0
	var max_speed := 0.0
	var max_omega := 0.0
	var lowest := INF
	var farthest := -INF
	var cost := []
	var finite := true
	var separation := 0.0
	for hit in 20:
		var bone := StringName(skeleton.get_bone_name(rng.randi_range(0, skeleton.get_bone_count() - 1)))
		var angle := rng.randf_range(-PI, PI)
		var direction := Vector3(sin(angle), rng.randf_range(-.3, .3), cos(angle)).normalized()
		if hit % 4 == 0:
			direction = Vector3.RIGHT # Drive a hit toward the wall.
		if character.receive_hit(bone, direction, rng.randf_range(20.0, 400.0), false):
			accepted += 1
		for i in 12:
			await tick(1)
			if ragdoll.is_reacting() and stage.last_update_usec > 0:
				cost.append(stage.last_update_usec)
			max_omega = maxf(max_omega, stage.max_body_angular_speed)
			for joint: StringName in stage.last_separations: separation = maxf(separation, stage.last_separations[joint])
			for body in ragdoll.get_physical_bones():
				var state: Transform3D = PhysicsServer3D.body_get_state(body.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM)
				var speed: Vector3 = PhysicsServer3D.body_get_state(body.get_rid(), PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
				finite = finite and state.origin.is_finite()
				if not body.is_simulating_physics(): continue
				var radius: float = LibertyRagdoll.BONE_LAYOUT[StringName(body.bone_name)][3]
				max_speed = maxf(max_speed, (speed - character.velocity).length())
				lowest = minf(lowest, state.origin.y - radius)
				farthest = maxf(farthest, state.origin.x)
	Input.action_release(&"liberty_sprint")
	Input.action_release(&"liberty_move_forward")
	for i in 90:
		await tick(1)
		if not ragdoll.is_reacting(): break
	print("hits accepted %d/20 | max joint separation %.3f m | max relative body speed %.2f m/s | max w %.1f rad/s | lowest body surface %.4f m | farthest body centre x %.3f (wall far face %.3f) | PD %.0f us p50, %.0f us p95, %.0f us max" % [
		accepted, separation, max_speed, max_omega, lowest, farthest, WALL_X + WALL_HALF, percentile(cost, .5), percentile(cost, .95), percentile(cost, 1.0)])
	Support.expect_equal(accepted, 20, "every hit is accepted while running")
	Support.expect_equal(stage.last_guard_trip, "", "no body trips the instability guard")
	Support.expect_true(finite, "bodies stay finite")
	Support.expect_true(max_omega < stage.max_angular_speed, "angular speed stays under the guard")
	Support.expect_true(separation < stage.max_joint_separation, "joints never separate")
	Support.expect_true(max_speed < 15.0, "relative body speed stays under the guard")
	Support.expect_true(lowest > -.02, "no body penetrates the floor by more than 2 cm")
	Support.expect_true(farthest < WALL_X + WALL_HALF, "no body tunnels through the thin wall")
	Support.expect_false(ragdoll.is_reacting(), "the reaction ends after the last hit")
	Support.expect_false(character.is_ragdoll_active(), "non-fatal hits never ragdoll the character")
	character.queue_free()
	quit(Support.exit_code())
