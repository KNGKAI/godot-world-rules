class_name LibertyTestSupport
extends RefCounted

static var _failures := 0


static func expect_true(value: bool, message: String) -> void:
	if not value:
		_failures += 1
		push_error(message)


static func expect_false(value: bool, message: String) -> void:
	expect_true(not value, message)


static func expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	expect_true(actual == expected, "%s (expected %s, got %s)" % [message, expected, actual])


static func exit_code() -> int:
	return 0 if _failures == 0 else 1
