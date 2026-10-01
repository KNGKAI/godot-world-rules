extends SceneTree
const Support = preload("res://modules/liberty_character/tests/liberty_test_support.gd")
func _initialize() -> void: call_deferred("run")
func tick(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame
func run() -> void:
	var scene = load("res://modules/liberty_character/tests/test_ragdoll.tscn")
	Support.expect_true(scene != null, "interactive ragdoll course exists")
	if scene == null: quit(Support.exit_code()); return
	var course = scene.instantiate()
	root.add_child(course)
	await tick(3)
	Support.expect_true(course.stations.size() >= 5, "course covers floor, ramp, slope, wall and traversal")
	Support.expect_equal(course.ragdoll.configuration_error, "", "course ragdoll is configured")
	course.reset_station(3)
	await tick(2)
	Support.expect_true(course.knock(), "course knockdown activates the ragdoll")
	await tick(2)
	Support.expect_true(course.character.is_ragdoll_active(), "character is ragdolled")
	course.reset_station(0)
	await tick(2)
	Support.expect_false(course.character.is_ragdoll_active(), "reset cancels the ragdoll")
	Support.expect_false(course.character.is_movement_locked(), "reset restores movement")
	Support.expect_true(course.character.global_position.distance_to(course.stations[0].source.origin) < .01, "reset uses safe teleport")
	Input.action_press(&"liberty_debug_ragdoll")
	await tick(2)
	Input.action_release(&"liberty_debug_ragdoll")
	course.knock()
	await tick(1)
	Support.expect_true(course.character.is_ragdoll_active(), "knock repeats from standing")
	# Touch: the mobile overlay owns screen touches, so course buttons live in it.
	course.reset_station(0)
	await tick(2)
	var mobile: LibertyMobileControls = course.character.get_node("MobileControls")
	mobile.force_visible = true
	for title in ["KNOCK", "PREV", "RESET", "NEXT"]:
		Support.expect_true(mobile.get_custom_button(title) != null, "touch %s button exists" % title)
	await tap(mobile, "NEXT", 21)
	Support.expect_equal(course._station_index, 1, "touch NEXT advances the station")
	await tap(mobile, "PREV", 22)
	Support.expect_equal(course._station_index, 0, "touch PREV returns to the previous station")
	await tap(mobile, "KNOCK", 23)
	Support.expect_true(course.character.is_ragdoll_active(), "touch KNOCK knocks down")
	await tap(mobile, "RESET", 24)
	Support.expect_false(course.character.is_ragdoll_active(), "touch RESET cancels the ragdoll")
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
