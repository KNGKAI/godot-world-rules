extends SceneTree

const Support = preload("res://modules/liberty_character/tests/liberty_test_support.gd")
const COURSE := "res://modules/liberty_character/tests/test_animation.tscn"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	Support.expect_true(ResourceLoader.exists(COURSE), "playable animation acceptance course must exist")
	if not ResourceLoader.exists(COURSE):
		quit(1)
		return
	var course = load(COURSE).instantiate()
	root.add_child(course)
	for _frame in 10:
		await physics_frame
	Support.expect_true(course.get_node_or_null("LibertyCharacter/AnimationTree") is AnimationTree, "course must use the default animated character")
	Support.expect_true(course.get_node_or_null("WalkOffLedge") is StaticBody3D, "course must offer a walk-off ledge")
	Support.expect_true(course.find_children("SpeedMarker_*", "Label3D", true, false).size() >= 4, "course must offer readable distance markers")
	Support.expect_true(course.get_node("HUD/Panel/Controls/Diagnostics").text.contains("Locomotion"), "course must expose live state diagnostics")
	course.place_on_ledge()
	for _frame in 5:
		await physics_frame
	Support.expect_true(course.character.is_on_floor(), "ledge reset must place character safely on the platform")
	Input.action_press(&"liberty_move_forward")
	var fell := false
	var landed := false
	for _frame in 150:
		await physics_frame
		var state: StringName = course.character.get_node("AnimationDriver").get_state()
		if state == &"Airborne/Fall":
			fell = true
		if fell and state == &"Airborne/Land":
			landed = true
			break
	Input.action_release(&"liberty_move_forward")
	Support.expect_true(fell and landed, "walking off the course ledge must play Fall and Land")
	course.reset_character()
	for _frame in 10:
		await physics_frame
	Support.expect_true(course.character.global_position.y < 0.01, "course reset restores the flat-ground starting point")
	course.free()
	quit(Support.exit_code())
