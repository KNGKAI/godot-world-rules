extends SceneTree
## Phase 7 pre-flight: engine behaviour the active ragdoll design depends on.
const Support = preload("res://modules/liberty_character/tests/liberty_test_support.gd")
const ARM: Array[StringName] = [&"LeftUpperArm", &"LeftLowerArm"]
const OTHER_ARM: Array[StringName] = [&"RightUpperArm", &"RightLowerArm"]

## Test-only stage placed after PoseCapture: records which capture it sees.
class StageProbe extends SkeletonModifier3D:
	var capture: LibertyPoseCaptureModifier
	var seen_capture_frame := -1
	var seen_physics_frame := -1
	var calls := 0
	func _process_modification_with_delta(_delta: float) -> void:
		calls += 1
		seen_capture_frame = capture.capture_frame
		seen_physics_frame = Engine.get_physics_frames()

## Test-only node reading the capture from _physics_process at a late priority.
class PriorityProbe extends Node:
	var capture: LibertyPoseCaptureModifier
	var lag := -1
	func _physics_process(_delta: float) -> void:
		lag = Engine.get_physics_frames() - capture.capture_frame

func _initialize() -> void: call_deferred("run")

func tick(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame

func server_transform(body: PhysicalBone3D) -> Transform3D:
	return PhysicsServer3D.body_get_state(body.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM)

func server_velocity(body: PhysicalBone3D) -> Vector3:
	return PhysicsServer3D.body_get_state(body.get_rid(), PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)

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
	await tick(3)
	var ragdoll: LibertyRagdoll = character.get_node("Ragdoll")
	var skeleton := ragdoll.skeleton
	var capture := ragdoll.pose_capture
	var stage := StageProbe.new()
	stage.capture = capture
	skeleton.add_child(stage)
	skeleton.move_child(stage, capture.get_index() + 1)
	var late := PriorityProbe.new()
	late.capture = capture
	late.process_physics_priority = 20
	fixture.add_child(late)
	await tick(3)
	print("stage calls %d, stage capture frame %d vs physics frame %d; priority-20 node capture lag %d" % [
		stage.calls, stage.seen_capture_frame, stage.seen_physics_frame, late.lag])
	Support.expect_true(stage.calls > 0, "a modifier stage after PoseCapture runs every tick")
	Support.expect_equal(stage.seen_capture_frame, stage.seen_physics_frame, "stage sees the same-update capture")

	# Partial simulation of one arm.
	var simulator := ragdoll.simulator
	simulator.active = true
	simulator.influence = 1.0
	simulator.physical_bones_start_simulation(ARM)
	await tick(1)
	var hips := ragdoll.get_physical_bone(&"Hips")
	var upper := ragdoll.get_physical_bone(&"LeftUpperArm")
	print("modes: hips %d, left upper arm %d, right upper arm %d (static 0, kinematic 1, rigid 2)" % [
		PhysicsServer3D.body_get_mode(hips.get_rid()), PhysicsServer3D.body_get_mode(upper.get_rid()),
		PhysicsServer3D.body_get_mode(ragdoll.get_physical_bone(&"RightUpperArm").get_rid())])
	Support.expect_true(simulator.is_simulating_physics(), "partial start reports simulating")
	Support.expect_true(upper.is_simulating_physics(), "listed bone simulates")
	Support.expect_false(hips.is_simulating_physics(), "unlisted hips do not simulate")
	Support.expect_equal(PhysicsServer3D.body_get_mode(upper.get_rid()), PhysicsServer3D.BODY_MODE_RIGID, "listed bone is rigid")
	Support.expect_true(PhysicsServer3D.body_get_mode(hips.get_rid()) != PhysicsServer3D.BODY_MODE_RIGID, "unlisted hips are not dynamic")

	# Unlisted hips follow the animated pose while the capsule moves.
	var hips_error := 0.0
	var hips_speed := 0.0
	character.teleport_to(Transform3D.IDENTITY)
	simulator.active = true
	simulator.influence = 1.0
	simulator.physical_bones_start_simulation(ARM)
	Input.action_press(&"liberty_move_forward")
	for i in 60:
		await tick(1)
		if i < 5: continue
		var target := skeleton.global_transform * capture.get_captured_pose(hips.get_bone_id()) * hips.body_offset
		hips_error = maxf(hips_error, server_transform(hips).origin.distance_to(target.origin))
		hips_speed = maxf(hips_speed, server_velocity(hips).length())
	Input.action_release(&"liberty_move_forward")
	print("moving: hips body vs animated error max %.4f m, hips server speed max %.3f m/s, character speed %.2f" % [
		hips_error, hips_speed, character.planar_speed])
	Support.expect_true(character.planar_speed > 2.0, "capsule moves while an arm simulates")
	Support.expect_true(hips_error < .15, "kinematic hips stay with the animated pose")

	# A second subset start leaves already-running bodies alone.
	PhysicsServer3D.body_apply_central_impulse(upper.get_rid(), Vector3(0, 0, -6))
	await tick(4)
	var before := server_transform(upper)
	var before_velocity := server_velocity(upper)
	simulator.physical_bones_start_simulation(OTHER_ARM)
	var after := server_transform(upper)
	print("second subset start: left arm moved %.5f m, velocity %.3f -> %.3f; right arm simulating %s; left still %s" % [
		before.origin.distance_to(after.origin), before_velocity.length(), server_velocity(upper).length(),
		ragdoll.get_physical_bone(&"RightUpperArm").is_simulating_physics(), upper.is_simulating_physics()])
	Support.expect_true(before.origin.distance_to(after.origin) < .001, "second subset start does not reset a running body")
	Support.expect_true(upper.is_simulating_physics(), "first subset keeps simulating after the second start")

	# Direct state exposes world inertia; gravity scale changes the fall.
	var state := PhysicsServer3D.body_get_direct_state(upper.get_rid())
	var inverse_inertia: Basis = state.inverse_inertia_tensor
	print("left upper arm inverse inertia diag %s, inverse mass %.3f" % [
		Vector3(inverse_inertia.x.x, inverse_inertia.y.y, inverse_inertia.z.z), state.inverse_mass])
	Support.expect_true(inverse_inertia.determinant() > 0.0, "world inverse inertia is non-singular")
	simulator.physical_bones_stop_simulation()
	await tick(2)
	var probe := ragdoll.get_physical_bone(&"Head")
	var fall := {}
	for scale: float in [1.0, 0.0]:
		character.teleport_to(Transform3D(Basis.IDENTITY, Vector3(0, 3, 0)))
		character.set_body_suspended(true)
		await tick(2)
		simulator.active = true
		simulator.physical_bones_start_simulation()
		for body in ragdoll.get_physical_bones():
			PhysicsServer3D.body_set_param(body.get_rid(), PhysicsServer3D.BODY_PARAM_GRAVITY_SCALE, scale)
			PhysicsServer3D.body_set_state(body.get_rid(), PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, Vector3.ZERO)
		await tick(1)
		var start_y := server_transform(probe).origin.y
		await tick(10)
		fall[scale] = start_y - server_transform(probe).origin.y
		simulator.physical_bones_stop_simulation()
		for body in ragdoll.get_physical_bones():
			PhysicsServer3D.body_set_param(body.get_rid(), PhysicsServer3D.BODY_PARAM_GRAVITY_SCALE, 1.0)
		character.set_body_suspended(false)
	print("head fall over 10 ticks: gravity 1 -> %.4f m, gravity 0 -> %.4f m" % [fall[1.0], fall[0.0]])
	Support.expect_true(fall[1.0] > .05 and absf(fall[0.0]) < .01, "gravity scale takes effect through the server")
	character.queue_free()
	quit(Support.exit_code())
