extends SceneTree
const S = preload("res://modules/liberty_character/tests/liberty_test_support.gd")
func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	call_deferred("run")
func run() -> void:
	var scene = load("res://modules/liberty_vehicle/tests/test_vehicle.tscn")
	S.expect_true(scene != null, "playable vehicle course exists")
	if scene != null:
		var course = scene.instantiate()
		root.add_child(course)
		await physics_frame
		S.expect_true(course.character is LibertyCharacter, "course includes playable character")
		S.expect_equal(course.vehicles.size(), 2, "course includes drive and blocked-exit sedan")
		await process_frame
		S.expect_true(course.get_node_or_null("CourseControls/REMOVE") != null, "course has a mounted touch escape from blocked sedan")
		# Verify a touch-only user can leave the deliberately blocked demonstration.
		course.character.teleport_to(Transform3D(Basis.IDENTITY, Vector3(12.65, 0.1, -0.4)))
		course.character.get_node("MobileControls").force_visible = true
		for i in 15:
			await physics_frame
			await process_frame
		var adapter := course.character.get_node("EventAdapter") as LibertyEventAdapter
		S.expect_true(adapter.mount(course.vehicles[1], &"driver_front_left").succeeded(), "touch escape fixture mounts blocked sedan")
		await physics_frame
		await process_frame
		await physics_frame
		await process_frame
		S.expect_false(adapter.dismount().succeeded(), "orange car deliberately blocks exits")
		var remove_touch := InputEventScreenTouch.new()
		remove_touch.index = 8
		remove_touch.pressed = true
		remove_touch.position = course.get_node("CourseControls/REMOVE").get_global_rect().get_center()
		Input.parse_input_event(remove_touch)
		await physics_frame
		await process_frame
		S.expect_false(course.character.is_body_suspended(), "course-only REMOVE touch frees trapped occupant")
		course.free()
	quit(S.exit_code())
