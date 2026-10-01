extends SceneTree
const Support = preload("res://modules/liberty_character/tests/liberty_test_support.gd")
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var scene = load("res://modules/liberty_character/tests/test_traversal.tscn")
	Support.expect_true(scene != null,"interactive traversal course exists")
	if scene == null: quit(Support.exit_code());return
	var course = scene.instantiate()
	root.add_child(course)
	await physics_frame
	await process_frame
	Support.expect_true(course.stations.size() >= 10,"course covers traversal situations")
	Support.expect_true(course.character.get_node("Traversal").configuration_error == "","playable course has validated rig")
	course.reset_station(1)
	Support.expect_true(course.character.global_position.distance_to(course.stations[1].source.origin)<.01,"reset station uses safe teleport")
	var debug = course.character.get_node("Traversal").debug_view
	Support.expect_false(debug.visible,"debug disabled by default")
	course.character.get_node("Traversal").debug_traversal = true
	await physics_frame
	await process_frame
	Support.expect_true(debug.visible,"debug toggle enables visualization")
	course.character.get_node("Traversal").debug_traversal = false
	course.reset_station(4)
	course.character.input_basis_source = null
	for tick in range(3):
		await physics_frame
		await process_frame
	Input.action_press(&"liberty_traverse")
	Input.action_press(&"liberty_move_forward")
	for tick in range(100):
		await physics_frame
		await process_frame
	Support.expect_true(course.character.is_traversal_locked(),"held desktop intent enters and climbs through full pipeline")
	var reached: Vector3 = course.character.global_position
	Support.expect_true(reached.y > .35,"held forward continues upward after entry")
	Input.action_release(&"liberty_move_forward")
	Input.action_release(&"liberty_traverse")
	for tick in range(15):
		await physics_frame
		await process_frame
	Support.expect_true(course.character.global_position.distance_to(reached)<.01,"releasing input preserves stationary hang")
	Support.expect_true(course.character.get_node("Traversal").controller.selected_candidate.destination_transform.origin.distance_to(reached)<.08,"stationary IK uses occupied hold")
	# Touch: the mobile overlay consumes screen touches, so course buttons live in it.
	var mobile: LibertyMobileControls = course.character.get_node("MobileControls")
	mobile.force_visible = true
	for title in ["PREV", "RESET", "NEXT", "DEBUG"]:
		Support.expect_true(mobile.get_custom_button(title) != null, "touch %s button exists" % title)
	course.reset_station(2)
	await tap(mobile, "NEXT", 31)
	Support.expect_equal(course._station_index, 3, "touch NEXT advances the station")
	await tap(mobile, "PREV", 32)
	Support.expect_equal(course._station_index, 2, "touch PREV returns to the previous station")
	course.character.global_position += Vector3(1, 0, 0)
	await tap(mobile, "RESET", 33)
	Support.expect_true(course.character.global_position.distance_to(course.stations[2].source.origin) < .01, "touch RESET returns to the station")
	await tap(mobile, "DEBUG", 34)
	Support.expect_true(course.character.get_node("Traversal").debug_traversal, "touch DEBUG toggles visualization")
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
	await physics_frame
	await process_frame
	touch = touch.duplicate()
	touch.pressed = false
	Input.parse_input_event(touch)
	await physics_frame
	await process_frame
