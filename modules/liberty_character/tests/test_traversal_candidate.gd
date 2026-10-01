extends SceneTree

const Candidate = preload("res://modules/liberty_character/traversal/liberty_traversal_candidate.gd")
const Support = preload("res://modules/liberty_character/tests/liberty_test_support.gd")

func _initialize() -> void:
	var value = Candidate.new()
	Support.expect_false(value.is_valid(), "empty candidate is invalid")
	value.kind = Candidate.Kind.HANG
	value.surface_normal = Vector3.FORWARD
	value.ledge_tangent = Vector3.RIGHT
	value.collider_instance_id = 42
	value.is_clear = true
	Support.expect_true(value.is_valid(), "complete candidate is valid")
	var copy = value.duplicate_candidate()
	copy.left_hand_target = Vector3.ONE
	Support.expect_equal(value.left_hand_target, Vector3.ZERO, "copy must be independent")
	Support.expect_equal(copy.kind, value.kind, "copy retains action")
	value.surface_normal = Vector3.ZERO
	Support.expect_false(value.is_valid(), "zero normal rejected")
	value.surface_normal = Vector3.FORWARD * 2.0
	Support.expect_false(value.is_valid(), "non-unit normal rejected")
	value.surface_normal = Vector3.FORWARD
	value.ledge_tangent = Vector3.FORWARD
	Support.expect_false(value.is_valid(), "parallel surface axes rejected")
	value.ledge_tangent = Vector3.RIGHT
	value.destination_transform.origin.x = NAN
	Support.expect_false(value.is_valid(), "nonfinite destination rejected")
	value.destination_transform = Transform3D.IDENTITY
	value.confidence = INF
	Support.expect_false(value.is_valid(), "nonfinite confidence rejected")
	value.confidence = 0.0
	value.is_clear = false
	Support.expect_false(value.is_valid(), "blocked candidate rejected")
	quit(Support.exit_code())
