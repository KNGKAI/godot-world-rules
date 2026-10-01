extends SceneTree
const Candidate = preload("res://modules/liberty_character/traversal/liberty_traversal_candidate.gd")
const Solver = preload("res://modules/liberty_character/traversal/liberty_traversal_solver.gd")
const Support = preload("res://modules/liberty_character/tests/liberty_test_support.gd")

func make_candidate(body: StaticBody3D, direction: Vector3, confidence: float) -> LibertyTraversalCandidate:
	var value := Candidate.new()
	value.kind = Candidate.Kind.SHIMMY
	value.collider_instance_id = body.get_instance_id()
	value.surface_normal = Vector3.FORWARD
	value.ledge_tangent = direction
	value.is_clear = true
	value.confidence = confidence
	return value

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var first := StaticBody3D.new()
	var second := StaticBody3D.new()
	first.collision_layer = 9
	second.collision_layer = 9
	root.add_child(first)
	root.add_child(second)
	var solver = Solver.new()
	root.add_child(solver)
	var left := make_candidate(first, Vector3.LEFT, 0.8)
	var right := make_candidate(second, Vector3.RIGHT, 0.85)
	Support.expect_equal(solver.choose([left, right], Vector3.RIGHT, 0.016), right, "direction chooses right")
	solver.clear()
	left.surface_normal = Vector3.ZERO
	Support.expect_equal(solver.choose([left], Vector3.LEFT, 0.016), null, "invalid normal ignored")
	left.surface_normal = Vector3.FORWARD
	solver.choose([left], Vector3.LEFT, 0.016)
	Support.expect_equal(solver.choose([right], Vector3.RIGHT, 0.05), left, "retain seam selection during delay")
	Support.expect_equal(solver.choose([right], Vector3.RIGHT, 0.069), left, "retain before 0.12 seconds")
	Support.expect_equal(solver.choose([right], Vector3.RIGHT, 0.002), right, "switch after 0.12 seconds")
	solver.clear()
	solver.choose([left], Vector3.LEFT, 0.016)
	solver.choose([right], Vector3.RIGHT, 0.08)
	Support.expect_equal(solver.choose([], Vector3.RIGHT, 0.001), null, "no samples cannot authorize stale action")
	solver.choose([left], Vector3.LEFT, 0.05)
	Support.expect_equal(solver.choose([right], Vector3.RIGHT, 0.05), left, "missing challenger resets timer")
	var same_body := make_candidate(first, Vector3.RIGHT, 0.85)
	same_body.contact_point = Vector3.RIGHT
	solver.clear()
	solver.choose([left], Vector3.LEFT, 0.016)
	Support.expect_equal(solver.choose([same_body], Vector3.RIGHT, 0.05), left, "same collider different contact still waits")
	Support.expect_equal(solver.choose([same_body], Vector3.RIGHT, 0.08), same_body, "same collider new contact can win")
	solver.clear()
	solver.choose([right], Vector3.RIGHT, 0.016)
	solver.choose([], Vector3.LEFT, 0.13)
	Support.expect_equal(solver.choose([left], Vector3.RIGHT, 0.016), left, "expired cache cannot suppress fresh lower score")
	first.free()
	Support.expect_equal(solver.choose([same_body], Vector3.RIGHT, 0.02), null, "freed cached collider cannot be selected")
	solver.clear()
	var virtual := make_candidate(second, Vector3.RIGHT, 0.9)
	var ledge := make_candidate(second, Vector3.RIGHT, 0.8)
	ledge.is_geometric_ledge = true
	Support.expect_equal(solver.choose([virtual, ledge], Vector3.RIGHT, 0.016), ledge, "real ledge takes precedence")
	solver.clear()
	var upward := make_candidate(second, Vector3.RIGHT, 0.8)
	upward.kind = Candidate.Kind.CLIMB
	upward.surface_normal = Vector3.BACK
	upward.destination_transform.origin = Vector3.UP * 0.45
	upward.contact_point.y = 0.45
	var downward := upward.duplicate_candidate()
	downward.destination_transform.origin = Vector3.DOWN * 0.45
	downward.contact_point.y = -0.45
	Support.expect_equal(solver.choose([downward, upward], Vector3.FORWARD, 0.016), upward, "forward into wall scores upward climb")
	quit(Support.exit_code())
