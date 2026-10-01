extends SceneTree
const S = preload("res://modules/liberty_character/tests/liberty_test_support.gd")
func _initialize() -> void:
	var vehicle := LibertyVehicle.new()
	var mount = vehicle.request_mount(null, &"driver_front_left")
	S.expect_true(mount != null, "unavailable vehicle returns typed mount result")
	if mount != null: S.expect_equal(mount.reason, &"vehicle unavailable or destroying", "unready mount fails explicitly")
	var dismount = vehicle.request_dismount(&"driver_front_left")
	S.expect_true(dismount != null, "unavailable vehicle returns typed dismount result")
	if dismount != null: S.expect_equal(dismount.reason, &"vehicle unavailable or destroying", "unready exit fails explicitly")
	var unknown = vehicle.request_mount(null, &"passenger_front_right")
	if unknown != null: S.expect_equal(unknown.reason, &"seat not found", "unknown seat rejects even before ready")
	var malformed := LibertyRagdoll.new()
	malformed.configuration_error = "invalid parent fixture"
	S.expect_false(malformed.activate_ragdoll(Vector3.ZERO, 0.0, &"test"), "invalid ragdoll config rejects activation without dereferencing character")
	malformed.free()
	vehicle.free()
	quit(S.exit_code())
