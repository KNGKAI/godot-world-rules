extends SceneTree
const Driver = preload("res://modules/liberty_character/traversal/liberty_traversal_animation_driver.gd")
const Candidate = preload("res://modules/liberty_character/traversal/liberty_traversal_candidate.gd")
const Support = preload("res://modules/liberty_character/tests/liberty_test_support.gd")
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var character = load("res://modules/liberty_character/character/liberty_character.tscn").instantiate()
	root.add_child(character)
	character.set_physics_process(false)
	var driver = Driver.new()
	root.add_child(driver)
	driver.configure(character.get_node("AnimationTree"))
	Support.expect_true(driver.missing_required_clips().is_empty(), "all imported traversal clips validate")
	var terminal: Transform3D = driver.get_authored_terminal(&"mantle_low")
	Support.expect_true(terminal.origin.is_equal_approx(Vector3(0,.75,-.95)), "real imported terminal root calibrated")
	var c := Candidate.new()
	c.kind = Candidate.Kind.LEDGE_JUMP
	c.destination_transform.origin = Vector3.RIGHT * .9
	Support.expect_equal(driver.select_clip(c, false), &"ledge_jump_left", "local +X follows authored anatomical Left")
	c.destination_transform.origin = Vector3.LEFT * .9
	Support.expect_equal(driver.select_clip(c, false), &"ledge_jump_right", "local -X follows anatomical Right")
	c.kind = Candidate.Kind.INNER_CORNER
	c.destination_transform = Transform3D(Basis(Vector3.UP, -PI/2),Vector3(.08,0,0))
	Support.expect_equal(driver.select_clip(c, false), &"corner_inner_left", "signed authored corner yaw selects clip")
	Support.expect_true(driver.play_clip(&"mantle_low"), "start real traversal clip")
	var total := Vector3.ZERO
	var previous := 0.0
	for tick in range(85):
		await physics_frame
		await process_frame
		var progress: float = driver.get_action_progress()
		Support.expect_true(progress >= previous, "action progress monotonic")
		previous = progress
		total += driver.get_root_motion_delta().origin
	Support.expect_true(total.distance_to(terminal.origin) < .005, "AnimationTree extracts root once without retaining it in skeleton")
	var player: AnimationPlayer = character.get_node("Rig/AnimationPlayer")
	var library := player.get_animation_library(&"")
	library.remove_animation(&"ledge_jump_up")
	Support.expect_equal(driver.missing_required_clips(), PackedStringArray(["ledge_jump_up"]), "exact missing traversal name")
	Support.expect_false(driver.play_clip(&"hang_idle"), "missing clip blocks traversal activation")
	character.queue_free()
	driver.queue_free()
	quit(Support.exit_code())
