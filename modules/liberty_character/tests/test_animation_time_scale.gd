extends SceneTree

const Support = preload("res://modules/liberty_character/tests/liberty_test_support.gd")

var POINTS := PackedFloat32Array([0.0, 2.2, 5.0, 7.5])
var AUTHORED := PackedFloat32Array([0.0, 1.4, 3.5, 6.0])


func _initialize() -> void:
	_expect_scale(0.0, 1.0, "idle must use scale 1.0")
	_expect_scale(0.005, 1.0, "effective authored speed below 0.01 must use scale 1.0")
	_expect_scale(2.2, 2.2 / 1.4, "walk point must scale by actual / authored walk speed")
	_expect_scale(5.0, 5.0 / 3.5, "run point must scale by actual / authored run speed")
	_expect_scale(7.5, 7.5 / 6.0, "sprint point must scale by actual / authored sprint speed")
	_expect_scale(3.6, 3.6 / lerpf(1.4, 3.5, 0.5), "mid walk-run must use weighted authored speed")
	_expect_scale(1.1, 1.1 / lerpf(0.0, 1.4, 0.5), "idle-walk blend must weight the idle authored speed")
	_expect_scale(9.0, 9.0 / 6.0, "speeds above the last point must use the last authored speed")
	_expect_scale(-1.0, 1.0, "negative speed must use scale 1.0")

	var zero_authored := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
	_expect_scale_with(4.0, POINTS, zero_authored, 1.0, "all-zero authored speeds must not divide by zero")
	_expect_scale_with(4.0, POINTS, PackedFloat32Array([0.0, 1.0]), 1.0, "mismatched arrays must use scale 1.0")
	_expect_scale_with(4.0, PackedFloat32Array(), PackedFloat32Array(), 1.0, "empty arrays must use scale 1.0")
	quit(Support.exit_code())


func _expect_scale(speed: float, expected: float, message: String) -> void:
	_expect_scale_with(speed, POINTS, AUTHORED, expected, message)


func _expect_scale_with(
	speed: float,
	points: PackedFloat32Array,
	authored: PackedFloat32Array,
	expected: float,
	message: String
) -> void:
	var actual := LibertyAnimationDriver.compute_time_scale(speed, points, authored)
	Support.expect_true(is_equal_approx(actual, expected), "%s (expected %s, got %s)" % [message, expected, actual])
