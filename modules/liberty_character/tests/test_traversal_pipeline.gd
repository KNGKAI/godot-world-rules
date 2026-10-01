extends SceneTree
const Probe = preload("res://modules/liberty_character/traversal/liberty_traversal_probe.gd")
const Solver = preload("res://modules/liberty_character/traversal/liberty_traversal_solver.gd")
const Controller = preload("res://modules/liberty_character/traversal/liberty_traversal_controller.gd")
const Candidate = preload("res://modules/liberty_character/traversal/liberty_traversal_candidate.gd")
const Support = preload("res://modules/liberty_character/tests/liberty_test_support.gd")

func box(parent: Node3D, at: Vector3, size: Vector3, layer: int) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = layer
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	parent.add_child(body)
	body.position = at

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var fixture := Node3D.new()
	root.add_child(fixture)
	var probe = Probe.new()
	var solver = Solver.new()
	var controller = Controller.new()
	fixture.add_child(probe)
	fixture.add_child(solver)
	fixture.add_child(controller)
	box(fixture, Vector3(0, -0.2, 0), Vector3(40, 0.4, 20), 1)
	box(fixture, Vector3(-15, 0.5, -0.95), Vector3(3, 1, 0.7), 9)
	box(fixture, Vector3(5, 3, -0.95), Vector3(20, 6, 0.7), 9)
	await physics_frame
	await physics_frame
	var observations: Array[LibertyTraversalCandidate] = probe.sample(Transform3D(Basis.IDENTITY, Vector3(-15, 0, 0)))
	var eligible: Array[LibertyTraversalCandidate] = controller.filter_candidates(observations, true, false)
	var selected: LibertyTraversalCandidate = solver.choose(eligible, Vector3.FORWARD, 0.016)
	controller.update_intent(selected, true, false, false, true, Vector3.FORWARD, Vector3.ZERO, 0.016)
	Support.expect_true(controller.state in [Controller.State.MANTLE, Controller.State.VAULT], "grounded pipeline selects grounded action")
	controller.interrupt(&"reset")
	solver.clear()
	var source := Transform3D(Basis.IDENTITY, Vector3(5, 0.6, 0))
	observations = probe.sample(source)
	eligible = controller.filter_candidates(observations, false, false)
	selected = solver.choose(eligible, Vector3.FORWARD, 0.016)
	controller.update_intent(selected, true, false, false, false, Vector3.FORWARD, Vector3.DOWN * 3.0, 0.016)
	Support.expect_equal(controller.state, Controller.State.AIR_CATCH, "real probe solver controller catches airborne")
	controller.complete_action()
	solver.clear()
	source = selected.destination_transform
	observations = probe.sample(source)
	eligible = controller.filter_candidates(observations, false, false, Vector3.FORWARD)
	selected = solver.choose(eligible, Vector3.FORWARD, 0.016)
	controller.update_intent(selected, true, false, false, false, Vector3.FORWARD, Vector3.ZERO, 0.016)
	Support.expect_equal(controller.state, Controller.State.VERTICAL_CLIMB, "forward intent wins upward climb over idle hang")
	controller.complete_action()
	for intent in [Vector3.RIGHT, Vector3.LEFT]:
		source = controller.selected_candidate.destination_transform
		observations = probe.sample(source)
		solver.clear()
		eligible = controller.filter_candidates(observations, false, false, intent)
		selected = solver.choose(eligible, intent, 0.016)
		controller.update_intent(selected, true, false, false, false, intent, Vector3.ZERO, 0.016)
		Support.expect_equal(controller.state, Controller.State.SHIMMY, "directional shimmy beats stationary hang")
		controller.complete_action()
	# Repeated horizontal virtual traversal must preserve body elevation.
	source.origin = Vector3(5, 0.6, -0.18)
	for cycle in range(20):
		observations = probe.sample(source)
		var continuation: LibertyTraversalCandidate
		for value in observations:
			if value.kind == Candidate.Kind.SHIMMY and value.destination_transform.origin.x > source.origin.x:
				continuation = value
				break
		Support.expect_true(continuation != null, "horizontal continuation available")
		if continuation == null:
			break
		source = continuation.destination_transform
	Support.expect_true(absf(source.origin.y - 0.6) < 0.0001, "twenty virtual shimmies have no vertical drift")
	quit(Support.exit_code())
