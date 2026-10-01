extends SceneTree
const Probe = preload("res://modules/liberty_character/traversal/liberty_traversal_probe.gd")
const Controller = preload("res://modules/liberty_character/traversal/liberty_traversal_controller.gd")
const Candidate = preload("res://modules/liberty_character/traversal/liberty_traversal_candidate.gd")
const Support = preload("res://modules/liberty_character/tests/liberty_test_support.gd")
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var fixture := Node3D.new()
	root.add_child(fixture)
	var body := StaticBody3D.new()
	body.collision_layer = 9
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3,1.7,1.2)
	shape.shape = box
	body.add_child(shape)
	fixture.add_child(body)
	body.position = Vector3(0,.85,-1.45)
	var probe = Probe.new()
	fixture.add_child(probe)
	var controller = Controller.new()
	fixture.add_child(controller)
	await physics_frame
	await physics_frame
	var source := Transform3D(Basis.IDENTITY, Vector3(0,.15,-.43))
	var values: Array[LibertyTraversalCandidate] = probe.sample(source, false, true)
	var hang: LibertyTraversalCandidate
	var top: LibertyTraversalCandidate
	for value in values:
		if value.kind == Candidate.Kind.HANG: hang = value
		if value.kind == Candidate.Kind.MANTLE: top = value
	Support.expect_true(top != null and hang != null, "hanging root yields hang and clear top-out")
	if top != null and hang != null:
		controller._accept(hang, Controller.State.HANG)
		var eligible: Array[LibertyTraversalCandidate] = controller.filter_candidates(values, false, false, Vector3.FORWARD)
		Support.expect_true(eligible.has(top), "top-out eligible from hang")
		controller.update_intent(top,true,false,false,false,Vector3.FORWARD,Vector3.ZERO,.016)
		Support.expect_equal(controller.state,Controller.State.MANTLE,"forward hang intent enters top-out mantle")
	var tall := StaticBody3D.new()
	tall.collision_layer = 9
	var tall_shape := CollisionShape3D.new()
	var tall_box := BoxShape3D.new()
	tall_box.size = Vector3(3,6,.6)
	tall_shape.shape = tall_box
	tall.add_child(tall_shape)
	fixture.add_child(tall)
	tall.position = Vector3(10,3,-1.15)
	await physics_frame
	await physics_frame
	var jump_source := Transform3D(Basis.IDENTITY,Vector3(10,.3,-.43))
	var jump_values: Array[LibertyTraversalCandidate] = probe.sample(jump_source,false,true)
	var up: LibertyTraversalCandidate
	var current: LibertyTraversalCandidate
	for value in jump_values:
		if value.kind == Candidate.Kind.HANG: current = value
		if value.kind == Candidate.Kind.LEDGE_JUMP and value.destination_transform.origin.y > .9: up = value
	Support.expect_true(up != null,"local vertical jump target detected")
	if current != null and up != null:
		controller._accept(current,Controller.State.HANG)
		var jumping: Array[LibertyTraversalCandidate] = controller.filter_candidates(jump_values,false,true,Vector3.FORWARD)
		Support.expect_true(jumping.has(up),"explicit forward jump selects vertical target")
		for value in jumping: Support.expect_equal(value.kind,Candidate.Kind.LEDGE_JUMP,"explicit jump does not lose to looping climb")
	fixture.queue_free()
	quit(Support.exit_code())
