extends SceneTree

const Support = preload("res://modules/liberty_character/tests/liberty_test_support.gd")
const CharacterScene = preload("res://modules/liberty_character/character/liberty_character.tscn")


func _initialize() -> void:
	var character := CharacterScene.instantiate() as LibertyCharacter
	Support.expect_true(character != null, "character scene root must be LibertyCharacter")
	if character == null:
		quit(Support.exit_code())
		return

	Support.expect_equal(character.collision_layer, 2, "character must occupy layer 2")
	Support.expect_equal(character.collision_mask, 17, "character must collide with world and vehicles")
	Support.expect_true(is_equal_approx(character.floor_snap_length, 0.3), "floor snap must be 0.3 meters")
	Support.expect_true(is_equal_approx(character.floor_max_angle, deg_to_rad(45.0)), "floor limit must be 45 degrees")

	var collision := character.get_node_or_null("CollisionShape3D") as CollisionShape3D
	Support.expect_true(collision != null, "character must own a CollisionShape3D")
	if collision != null:
		var capsule := collision.shape as CapsuleShape3D
		Support.expect_true(capsule != null, "collision shape must be a capsule")
		if capsule != null:
			Support.expect_true(is_equal_approx(capsule.height, 1.8), "capsule height must be 1.8 meters")
			Support.expect_true(is_equal_approx(capsule.radius, 0.4), "capsule radius must be 0.4 meters")
		Support.expect_true(is_equal_approx(collision.position.y, 0.9), "root origin must remain at the feet")

	var rig := character.get_node_or_null("Rig") as Node3D
	Support.expect_true(rig != null, "playable character must instance the humanoid rig separately from collision")
	if rig != null:
		Support.expect_true(rig.find_child("Skeleton3D", true, false) is Skeleton3D, "playable rig must contain the imported skeleton")
		Support.expect_true(rig.transform.is_equal_approx(Transform3D.IDENTITY), "rig must retain feet-origin and authored orientation")
	var events := character.get_node_or_null("Events") as LibertyEvents
	var adapter := character.get_node_or_null("EventAdapter") as LibertyEventAdapter
	Support.expect_true(events != null, "character must own LibertyEvents")
	Support.expect_true(adapter != null and adapter.events == events, "event adapter must resolve the owned events node")

	Support.expect_true(is_equal_approx(character.walk_speed, 2.2), "walk speed default")
	Support.expect_true(is_equal_approx(character.run_speed, 5.0), "run speed default")
	Support.expect_true(is_equal_approx(character.sprint_speed, 7.5), "sprint speed default")
	Support.expect_true(is_equal_approx(character.ground_acceleration, 9.0), "ground acceleration default")
	Support.expect_true(is_equal_approx(character.ground_deceleration, 6.0), "ground deceleration default")
	Support.expect_true(is_equal_approx(character.grounded_turn_rate_degrees, 420.0), "ground turn rate default")
	Support.expect_true(is_equal_approx(character.high_speed_turn_rate_degrees, 120.0), "high-speed turn rate default")
	Support.expect_true(is_equal_approx(character.air_control, 3.0), "air control default")
	Support.expect_true(is_equal_approx(character.gravity, 24.0), "gravity default")
	Support.expect_true(is_equal_approx(character.jump_velocity, 7.2), "jump velocity default")
	Support.expect_equal(character.movement_state, LibertyCharacter.MovementState.IDLE, "initial movement state")
	Support.expect_equal(character.movement_state_name, &"idle", "initial movement state name")
	Support.expect_true(is_zero_approx(character.planar_speed), "initial planar speed")
	Support.expect_false(character.is_movement_locked(), "movement starts unlocked")
	character.set_movement_locked(true)
	Support.expect_true(character.is_movement_locked(), "movement lock must be queryable")
	Support.expect_equal(character.movement_state, LibertyCharacter.MovementState.MOVEMENT_LOCKED, "lock must update state")

	character.free()
	quit(Support.exit_code())
