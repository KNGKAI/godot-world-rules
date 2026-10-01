extends SceneTree
const Candidate = preload("res://modules/liberty_character/traversal/liberty_traversal_candidate.gd")
const Controller = preload("res://modules/liberty_character/traversal/liberty_traversal_controller.gd")
const Support = preload("res://modules/liberty_character/tests/liberty_test_support.gd")
var event_count := 0

func make_candidate(body: StaticBody3D, kind: Candidate.Kind) -> LibertyTraversalCandidate:
	var value := Candidate.new()
	value.kind = kind
	value.collider_instance_id = body.get_instance_id()
	value.surface_normal = Vector3.BACK
	value.ledge_tangent = Vector3.RIGHT
	value.is_clear = true
	value.destination_transform.origin = Vector3.RIGHT * 0.35
	return value

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 9
	root.add_child(body)
	var events := LibertyEvents.new()
	root.add_child(events)
	events.traversal_state_changed.connect(func(_old: StringName, _new: StringName): event_count += 1)
	var controller = Controller.new()
	controller.events = events
	root.add_child(controller)
	var mantle := make_candidate(body, Candidate.Kind.MANTLE)
	controller.update_intent(mantle, true, false, false, true, Vector3.ZERO, Vector3.ZERO, 0.016)
	Support.expect_equal(controller.state, Controller.State.GROUNDED, "entry requires movement intent")
	controller.update_intent(mantle, true, false, false, true, Vector3.FORWARD, Vector3.ZERO, 0.016)
	Support.expect_equal(controller.state, Controller.State.MANTLE, "held traverse enters mantle")
	Support.expect_true(controller.movement_locked, "action requests lock")
	Support.expect_equal(event_count, 1, "typed event once for transition")
	controller.interrupt(&"test")
	Support.expect_false(controller.movement_locked, "interrupt releases lock")
	Support.expect_equal(controller.selected_candidate, null, "interrupt clears candidate")
	controller.update_intent(null, false, false, false, true, Vector3.ZERO, Vector3.ZERO, 0.016)
	Support.expect_equal(controller.state, Controller.State.GROUNDED, "falling returns to grounded without candidate")
	var vault := make_candidate(body, Candidate.Kind.VAULT)
	controller.update_intent(vault, true, false, false, true, Vector3.FORWARD, Vector3.ZERO, 0.016)
	Support.expect_equal(controller.state, Controller.State.VAULT, "vault entry")
	controller.complete_action()
	Support.expect_equal(controller.state, Controller.State.GROUNDED, "vault completion unlocks")
	Support.expect_false(controller.movement_locked, "vault completion releases lock")
	controller.update_intent(mantle, true, false, false, true, Vector3.FORWARD, Vector3.ZERO, 0.016)
	controller.complete_action()
	Support.expect_equal(controller.state, Controller.State.GROUNDED, "mantle completion unlocks")
	var hang := make_candidate(body, Candidate.Kind.HANG)
	controller.update_intent(hang, true, false, false, true, Vector3.FORWARD, Vector3.ZERO, 0.016)
	Support.expect_equal(controller.state, Controller.State.HANG, "tagged hang entry")
	controller.update_intent(null, true, false, false, false, Vector3.RIGHT, Vector3.ZERO, 0.2)
	Support.expect_equal(controller.state, Controller.State.HANG, "live ledge end stops safely")
	var wrong_direction := make_candidate(body, Candidate.Kind.SHIMMY)
	wrong_direction.destination_transform.origin = Vector3.LEFT * 0.35
	controller.update_intent(wrong_direction, true, false, false, false, Vector3.RIGHT, Vector3.ZERO, 0.016)
	Support.expect_equal(controller.state, Controller.State.HANG, "opposite continuation rejected at reversal")
	controller.update_intent(wrong_direction, true, false, false, false, Vector3.LEFT, Vector3.ZERO, 0.016)
	Support.expect_equal(controller.state, Controller.State.SHIMMY, "left intent enters left shimmy")
	controller.update_intent(wrong_direction, true, false, false, false, Vector3.RIGHT, Vector3.ZERO, 0.016)
	Support.expect_equal(controller.state, Controller.State.HANG, "reversal immediately stops previous shimmy")
	var leap := make_candidate(body, Candidate.Kind.LEDGE_JUMP)
	controller.update_intent(leap, true, false, false, false, Vector3.RIGHT, Vector3.ZERO, 0.016)
	Support.expect_equal(controller.state, Controller.State.HANG, "gap never crossed automatically")
	controller.update_intent(leap, true, true, false, false, Vector3.RIGHT, Vector3.ZERO, 0.016)
	Support.expect_equal(controller.state, Controller.State.LEDGE_JUMP, "explicit jump crosses reachable gap")
	controller.update_intent(null, false, false, true, false, Vector3.ZERO, Vector3.ZERO, 0.016)
	Support.expect_equal(controller.state, Controller.State.FALLING, "drop immediately releases")
	var catch := make_candidate(body, Candidate.Kind.AIR_CATCH)
	controller.update_intent(catch, true, false, false, false, Vector3.FORWARD, Vector3.DOWN * 100.0, 0.016)
	Support.expect_equal(controller.state, Controller.State.FALLING, "excessive catch speed rejected")
	controller.update_intent(catch, true, false, false, false, Vector3.FORWARD, Vector3.DOWN * 3.0, 0.016)
	Support.expect_equal(controller.state, Controller.State.AIR_CATCH, "reachable airborne catch accepted")
	controller.complete_action()
	Support.expect_equal(controller.state, Controller.State.HANG, "catch completion settles into hang")
	for kind in [Candidate.Kind.SHIMMY, Candidate.Kind.CLIMB, Candidate.Kind.INNER_CORNER, Candidate.Kind.OUTER_CORNER]:
		var continuation := make_candidate(body, kind)
		var intent := Vector3.RIGHT
		if kind == Candidate.Kind.CLIMB:
			continuation.destination_transform.origin = Vector3.UP * 0.45
			intent = Vector3.FORWARD
		controller.update_intent(continuation, true, false, false, false, intent, Vector3.ZERO, 0.016)
		Support.expect_true(controller.state != Controller.State.HANG, "valid continuation enters action")
		controller.complete_action()
		Support.expect_equal(controller.state, Controller.State.HANG, "continuation settles into hang")
	controller.update_intent(null, true, false, false, false, Vector3.RIGHT, Vector3.ZERO, 0.05, false)
	Support.expect_equal(controller.state, Controller.State.HANG, "missing live-surface contact gets grace")
	controller.update_intent(null, true, false, false, false, Vector3.RIGHT, Vector3.ZERO, 0.08, false)
	Support.expect_equal(controller.state, Controller.State.FALLING, "live collider with lost contact must fall")
	controller.update_intent(hang, true, false, false, true, Vector3.FORWARD, Vector3.ZERO, 0.016)
	controller.update_intent(hang, false, false, false, false, Vector3.ZERO, Vector3.ZERO, 0.016)
	Support.expect_equal(controller.state, Controller.State.HANG, "releasing traverse holds safely")
	body.free()
	controller.update_intent(null, true, false, false, false, Vector3.ZERO, Vector3.ZERO, 0.05)
	Support.expect_equal(controller.state, Controller.State.HANG, "deleted support gets grace")
	controller.update_intent(null, true, true, false, false, Vector3.RIGHT, Vector3.ZERO, 0.069)
	Support.expect_equal(controller.state, Controller.State.HANG, "no stale action during grace")
	controller.update_intent(null, true, false, false, false, Vector3.ZERO, Vector3.ZERO, 0.002)
	Support.expect_equal(controller.state, Controller.State.FALLING, "grace expires at 0.12 seconds")
	Support.expect_false(controller.movement_locked, "loss releases lock")
	quit(Support.exit_code())
