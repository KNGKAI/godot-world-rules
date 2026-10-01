extends SceneTree
## Smoke test for the interactive Phase 7 course: stations, hits, fatal hits, touch buttons.
const Support = preload("res://modules/liberty_character/tests/liberty_test_support.gd")
func _initialize() -> void: call_deferred("run")
func tick(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame
func run() -> void:
	var scene = load("res://modules/liberty_character/tests/test_active_ragdoll.tscn")
	Support.expect_true(scene != null, "interactive active ragdoll course exists")
	if scene == null: quit(Support.exit_code()); return
	var course = scene.instantiate()
	root.add_child(course)
	await tick(3)
	Support.expect_true(course.stations.size() >= 4, "course covers standing, run lane, wall and traversal")
	Support.expect_equal(course.stage.configuration_error, "", "course physical animation is configured")
	course.target_index = course.TARGETS.find(&"LeftHand")
	Support.expect_true(course.hit(), "course hit starts a reaction")
	await tick(1)
	Support.expect_true(course.ragdoll.is_reacting(), "character reacts")
	Support.expect_true(course.last_hit.begins_with("hit LeftHand"), "HUD records the hit")
	course.reset_station(1)
	await tick(2)
	Support.expect_false(course.ragdoll.is_reacting(), "reset cancels the reaction")
	Support.expect_true(course.character.global_position.distance_to(course.stations[1].source.origin) < .01, "reset uses safe teleport")
	course.cycle_target()
	Support.expect_equal(course.TARGETS[course.target_index], &"RightHand", "target cycles")
	var press := InputEventAction.new() # Reaches _unhandled_input, unlike Input.action_press.
	press.action = &"liberty_debug_hit"
	press.pressed = true
	Input.parse_input_event(press)
	await tick(2)
	var release := press.duplicate()
	release.pressed = false
	Input.parse_input_event(release)
	Support.expect_true(course.ragdoll.is_reacting(), "F hits")
	Support.expect_true(course.fatal_hit(), "fatal hit accepted")
	await tick(1)
	Support.expect_true(course.character.is_ragdoll_active(), "fatal hit ragdolls")
	course.reset_station(0)
	await tick(2)
	Support.expect_false(course.character.is_ragdoll_active(), "reset cancels the ragdoll")
	var mobile: LibertyMobileControls = course.character.get_node("MobileControls")
	mobile.force_visible = true
	for title in ["HIT", "FATAL", "TARGET", "PREV", "RESET", "NEXT"]:
		Support.expect_true(mobile.get_custom_button(title) != null, "touch %s button exists" % title)
	await tap(mobile, "NEXT", 21)
	Support.expect_equal(course._station_index, 1, "touch NEXT advances the station")
	await tap(mobile, "HIT", 22)
	Support.expect_true(course.ragdoll.is_reacting(), "touch HIT hits")
	await tap(mobile, "RESET", 23)
	Support.expect_false(course.ragdoll.is_reacting(), "touch RESET cancels the reaction")
	Support.expect_equal(Input.get_action_strength(&"liberty_touch_move_forward"), 0.0, "button taps never start the joystick")
	course.queue_free()
	quit(Support.exit_code())
func tap(mobile: LibertyMobileControls, title: String, index: int) -> void:
	var button := mobile.get_custom_button(title)
	if button == null: return
	var touch := InputEventScreenTouch.new()
	touch.index = index
	touch.position = button.position + button.size * 0.5
	touch.pressed = true
	Input.parse_input_event(touch)
	await tick(1)
	touch = touch.duplicate()
	touch.pressed = false
	Input.parse_input_event(touch)
	await tick(2)
