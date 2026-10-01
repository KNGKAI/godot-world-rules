extends SceneTree
const Support = preload("res://modules/liberty_character/tests/liberty_test_support.gd")
const Candidate = preload("res://modules/liberty_character/traversal/liberty_traversal_candidate.gd")
var finished := 0
func _initialize() -> void:
	call_deferred("run")
func box(parent: Node3D, position: Vector3, size: Vector3, layer: int) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = layer
	var shape := CollisionShape3D.new()
	var resource := BoxShape3D.new()
	resource.size = size
	shape.shape = resource
	body.add_child(shape)
	parent.add_child(body)
	body.position = position
	return body
func run() -> void:
	var fixture := Node3D.new()
	root.add_child(fixture)
	box(fixture, Vector3(0,-.2,0), Vector3(30,.4,30),1)
	var wall := box(fixture, Vector3(0,3,-1.15), Vector3(20,6,.6),9)
	var character = load("res://modules/liberty_character/character/liberty_character.tscn").instantiate()
	fixture.add_child(character)
	await physics_frame
	await process_frame
	var coordinator = character.get_node_or_null("Traversal")
	Support.expect_true(coordinator != null, "playable character owns full traversal pipeline")
	if coordinator == null:
		quit(Support.exit_code()); return
	coordinator.set_physics_process(false)
	var values: Array[LibertyTraversalCandidate] = coordinator.probe.sample(character.global_transform, true)
	var hold: LibertyTraversalCandidate
	for c in values:
		if c.kind == Candidate.Kind.HANG: hold = c; break
	Support.expect_true(hold != null, "actual wall supplies enter candidate")
	if hold == null:
		quit(Support.exit_code()); return
	var events: LibertyEvents = character.get_node("Events")
	events.interaction_finished.connect(func(_reason: StringName): finished += 1)
	Support.expect_true(coordinator.begin_action(hold, false), "grounded enter fits authored motion")
	for i in range(65):
		await physics_frame
		await process_frame
	Support.expect_true(character.is_traversal_locked(), "entry settles into supported hold")
	Support.expect_true(character.global_position.distance_to(hold.destination_transform.origin) < .08, "real root motor achieves hang alignment")
	var cycle_start: Vector3 = character.global_position
	var repeat_catch := hold.duplicate_candidate()
	repeat_catch.kind = Candidate.Kind.AIR_CATCH
	for cycle in range(20):
		Support.expect_true(coordinator.begin_action(repeat_catch, true), "repeat catch starts")
		for tick in range(42):
			await physics_frame
			await process_frame
		Support.expect_true(character.is_traversal_locked(), "repeat catch retains hold")
	var drift: float = character.global_position.distance_to(cycle_start)
	print("20 catch cycles drift=", drift)
	Support.expect_true(drift < .05, "twenty repeated action cycles remain below drift limit")
	var continuation := hold.duplicate_candidate()
	continuation.kind = Candidate.Kind.SHIMMY
	continuation.source_transform = character.global_transform
	continuation.destination_transform.origin = character.global_position + Vector3.RIGHT*.35
	continuation.contact_point += Vector3.RIGHT*.35
	continuation.left_hand_target += Vector3.RIGHT*.35
	continuation.right_hand_target += Vector3.RIGHT*.35
	continuation.left_foot_target += Vector3.RIGHT*.35
	continuation.right_foot_target += Vector3.RIGHT*.35
	coordinator.controller._accept(continuation,coordinator.Controller.State.SHIMMY)
	coordinator._physics_process(1.0/60)
	Support.expect_true(coordinator.controller.selected_candidate.destination_transform.origin.distance_to(character.global_position)<.08,"stopped shimmy uses occupied hold rather than future target")
	character.interrupt_traversal(&"ragdoll")
	await physics_frame
	await process_frame
	Support.expect_false(character.is_traversal_locked(), "interrupt releases body lock within one tick")
	Support.expect_equal(coordinator.controller.selected_candidate, null, "interrupt clears controller support")
	Support.expect_equal(coordinator.motor.candidate, null, "interrupt clears motor")
	Support.expect_equal(coordinator.animation.current_clip, &"", "interrupt clears animation progress")
	for limb in coordinator.ik.get_limbs(): Support.expect_false(limb.active, "interrupt disables IK")
	Support.expect_equal(finished, 22, "entry completion and interruption each finish exactly once")
	var catching := hold.duplicate_candidate()
	catching.kind = Candidate.Kind.AIR_CATCH
	Support.expect_true(coordinator.begin_action(catching,false),"zero-root catch can regain nearby hold")
	for i in range(42):
		await physics_frame
		await process_frame
	coordinator.set_physics_process(true)
	character.interrupt_traversal(&"drop")
	Support.expect_equal(coordinator.animation.current_clip,&"ledge_drop","drop releases while playing explicit visual clip")
	var drop_start: Vector3 = character.global_position
	for i in range(5):
		await physics_frame
		await process_frame
	Support.expect_true(character.global_position.y < drop_start.y,"released drop resumes gravity")
	Support.expect_true(absf(character.global_position.z-drop_start.z)<.005,"drop root motion is not added to physical falling")
	coordinator.enabled = false
	coordinator._physics_process(1.0/60)
	Support.expect_false(character.get_node("AnimationDriver").traversal_animation_owned,"disable releases drop animation ownership")
	Support.expect_equal(coordinator.animation.current_clip,&"","disable leaves visual traversal")
	fixture.queue_free()
	quit(Support.exit_code())
