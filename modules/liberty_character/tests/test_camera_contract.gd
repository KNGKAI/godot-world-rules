extends SceneTree

const Support = preload("res://modules/liberty_character/tests/liberty_test_support.gd")
const CharacterScene = preload("res://modules/liberty_character/character/liberty_character.tscn")


func _initialize() -> void:
	var character := CharacterScene.instantiate() as LibertyCharacter
	Support.expect_true(character != null, "camera contract requires LibertyCharacter")
	if character == null:
		quit(Support.exit_code())
		return

	root.add_child(character)

	var pivot := character.get_node_or_null("CameraPivot") as Node3D
	Support.expect_true(pivot != null, "character must own CameraPivot")
	if pivot != null:
		Support.expect_true(pivot.is_set_as_top_level(), "camera pivot must be top-level")
		Support.expect_true(is_equal_approx(pivot.get("target_height") as float, 1.45), "camera target height must default to 1.45 meters")
		Support.expect_true(is_equal_approx(pivot.get("mouse_sensitivity_degrees") as float, 0.12), "mouse sensitivity must default to 0.12 degrees per pixel")
		Support.expect_true(is_equal_approx(pivot.get("follow_half_life") as float, 0.12), "follow half-life must default to 0.12 seconds")

	var spring_arm := character.get_node_or_null("CameraPivot/SpringArm3D") as SpringArm3D
	Support.expect_true(spring_arm != null, "camera pivot must own SpringArm3D")
	if spring_arm != null:
		Support.expect_true(is_equal_approx(spring_arm.spring_length, 4.5), "spring arm must default to 4.5 meters")
		Support.expect_equal(spring_arm.collision_mask, 17, "spring arm must query world and vehicle")
		var sphere := spring_arm.shape as SphereShape3D
		Support.expect_true(sphere != null, "spring arm must use a sphere shape")
		if sphere != null:
			Support.expect_true(is_equal_approx(sphere.radius, 0.3), "camera collision sphere must have a 0.3 meter radius")

	var camera := character.get_node_or_null("CameraPivot/SpringArm3D/Camera3D") as Camera3D
	Support.expect_true(camera != null, "spring arm must own Camera3D")
	if camera != null:
		Support.expect_true(camera.current, "character camera must be current")
		Support.expect_true(is_equal_approx(camera.fov, 75.0), "camera FOV must default to 75 degrees")

	Support.expect_true(character.input_basis_source == pivot, "movement basis must use CameraPivot")
	character.free()
	quit(Support.exit_code())
