extends SceneTree

const Support = preload("res://modules/liberty_character/tests/liberty_test_support.gd")
const CharacterScene = preload("res://modules/liberty_character/character/liberty_character.tscn")
const Driver = preload("res://modules/liberty_character/animation/liberty_animation_driver.gd")

const ACTIONS: Array[StringName] = [
	&"liberty_move_forward",
	&"liberty_sprint",
	&"liberty_jump",
]

var _world: Node3D
var _character: LibertyCharacter
var _tree: AnimationTree
var _driver: LibertyAnimationDriver


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_build_world()
	if _driver == null:
		return
	await _wait_physics(10)
	_test_setup()
	await _test_locomotion_parameters()
	await _test_jump_fall_land()
	await _test_short_hop_and_rejump()
	await _test_jump_clip_completion()
	await _test_parent_exit_fade_rejump()
	await _test_teleport_into_air_falls()
	await _test_movement_lock_keeps_state()
	await _test_performance_stop_while_locked()
	_release_actions()
	_world.free()
	quit(Support.exit_code())


func _build_world() -> void:
	_world = Node3D.new()
	root.add_child(_world)
	var floor := StaticBody3D.new()
	floor.collision_layer = 1
	floor.collision_mask = 0
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(200.0, 1.0, 200.0)
	collision.shape = shape
	collision.position.y = -0.5
	floor.add_child(collision)
	_world.add_child(floor)

	_character = CharacterScene.instantiate() as LibertyCharacter
	_tree = _character.get_node_or_null("AnimationTree") as AnimationTree
	_driver = _character.get_node_or_null("AnimationDriver") as LibertyAnimationDriver
	Support.expect_true(_tree != null and _driver != null, "default character must own animation integration")
	if _tree == null or _driver == null:
		_character.free()
		quit(1)
		return
	_driver.walk_authored_speed = 1.6
	_driver.run_authored_speed = 3.8
	_driver.sprint_authored_speed = 6.2
	_world.add_child(_character)


func _test_setup() -> void:
	Support.expect_true(_tree.tree_root is AnimationNodeStateMachine, "driver must build the tree root")
	var skeleton := _character.get_node("Rig/Skeleton3D") as Skeleton3D
	Support.expect_equal(skeleton.modifier_callback_mode_process, Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_PHYSICS, "skeleton must evaluate in physics")
	Support.expect_true(_tree.active, "driver must activate the tree")
	Support.expect_equal(_tree.callback_mode_process, AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS, "tree must process in physics")
	Support.expect_true(_driver.process_physics_priority > _character.process_physics_priority, "driver must read after the character moves")
	Support.expect_true(_tree.process_physics_priority > _driver.process_physics_priority, "tree must evaluate after the driver")
	Support.expect_equal(_current_state(), &"Locomotion", "grounded idle must be in Locomotion")


func _test_locomotion_parameters() -> void:
	await _reset_character()
	Support.expect_true(is_zero_approx(float(_tree.get(Driver.BLEND_POSITION_PARAMETER))), "idle blend position must be zero")
	Support.expect_true(is_equal_approx(float(_tree.get(Driver.TIME_SCALE_PARAMETER)), 1.0), "idle time scale must be 1.0")

	Input.action_press(&"liberty_move_forward")
	var samples := 0
	for _frame in 60:
		await physics_frame
		var speed := _character.planar_speed
		# Independently derive the expected neighboring-speed interpolation.
		var authored := 1.6 * speed / 2.2 if speed <= 2.2 else lerpf(1.6, 3.8, (speed - 2.2) / 2.8)
		var expected_scale := 1.0 if authored < 0.01 else speed / authored
		if absf(float(_tree.get(Driver.BLEND_POSITION_PARAMETER)) - speed) > 0.001:
			Support.expect_true(false, "blend position must follow planar speed (speed %s)" % speed)
			break
		if absf(float(_tree.get(Driver.TIME_SCALE_PARAMETER)) - expected_scale) > 0.001:
			Support.expect_true(false, "time scale must match compute_time_scale (speed %s)" % speed)
			break
		samples += 1
	Support.expect_equal(samples, 60, "every accelerating frame must update locomotion parameters")
	Support.expect_true(_character.planar_speed > 4.5, "run case must reach run speed")
	Support.expect_true(float(_tree.get(Driver.TIME_SCALE_PARAMETER)) > 1.2, "faster-than-authored run must speed the clip up")

	Input.action_press(&"liberty_sprint")
	await _wait_physics(90)
	Support.expect_true(is_equal_approx(float(_tree.get(Driver.BLEND_POSITION_PARAMETER)), _character.sprint_speed), "sprint must reach the last blend point")
	Support.expect_equal(_current_state(), &"Locomotion", "grounded movement must stay in Locomotion")
	_release_actions()


func _test_jump_fall_land() -> void:
	await _reset_character()
	Input.action_press(&"liberty_jump")
	await _wait_physics(2)
	Input.action_release(&"liberty_jump")
	await _wait_physics(3)
	Support.expect_equal(_current_state(), &"Airborne/Jump", "grounded jump must enter Airborne/Jump")
	await _wait_physics(18)
	Support.expect_true(_character.velocity.y <= 0.0, "apex fixture must be descending")
	Support.expect_equal(_current_state(), &"Airborne/Fall", "apex must enter Fall before the 0.55 second jump clip ends")

	var reached_fall := false
	var reached_land := false
	for _frame in 180:
		await physics_frame
		var state := _current_state()
		if state == &"Airborne/Fall":
			reached_fall = true
		if state == &"Airborne/Land":
			reached_land = true
			break
	Support.expect_true(reached_fall, "Jump must flow into Fall before landing")
	Support.expect_true(reached_land, "landing must enter Airborne/Land")
	Support.expect_true(_character.is_on_floor(), "Land must play after touching the floor")

	await _wait_physics(40)
	Support.expect_equal(_current_state(), &"Locomotion", "Land must return to Locomotion after the clip")


func _test_teleport_into_air_falls() -> void:
	await _reset_character()
	_character.teleport_to(Transform3D(Basis.IDENTITY, Vector3(0.0, 3.0, 0.0)))
	await _wait_physics(3)
	Support.expect_equal(_current_state(), &"Airborne/Fall", "leaving the ground without jumping must enter Fall")
	for _frame in 120:
		await physics_frame
		if _character.is_on_floor():
			break
	await _wait_physics(2)
	Support.expect_equal(_current_state(), &"Airborne/Land", "falling onto the floor must enter Land")


func _test_short_hop_and_rejump() -> void:
	await _reset_character()
	_character.jump_velocity = 2.4
	Input.action_press(&"liberty_jump")
	await _wait_physics(2)
	Input.action_release(&"liberty_jump")
	var landed := false
	for _frame in 25:
		await physics_frame
		if _current_state() == &"Airborne/Land":
			landed = true
			break
	Support.expect_true(landed, "short hop must play landing rather than finish the jump clip in midair")
	Input.action_press(&"liberty_jump")
	await _wait_physics(2)
	Input.action_release(&"liberty_jump")
	Support.expect_equal(_current_state(), &"Airborne/Jump", "jump during Land must interrupt landing")
	_character.jump_velocity = 7.2
	await _wait_physics(70)
	Support.expect_equal(_current_state(), &"Locomotion", "repeated hop must recover to grounded locomotion")


func _test_movement_lock_keeps_state() -> void:
	await _reset_character()
	await _wait_physics(20)
	_character.set_movement_locked(true)
	await _wait_physics(10)
	Support.expect_equal(_current_state(), &"Locomotion", "movement lock must not change the animation state")
	_character.teleport_to(Transform3D(Basis.IDENTITY, Vector3(0, 3, 0)))
	await _wait_physics(4)
	Support.expect_equal(_current_state(), &"Locomotion", "locked airborne movement must not select ordinary animations")
	_character.set_movement_locked(false)
	await _wait_physics(3)
	Support.expect_equal(_current_state(), &"Airborne/Fall", "unlock must reevaluate actual airborne state")


func _test_jump_clip_completion() -> void:
	await _reset_character()
	_character.gravity = 6.0
	Input.action_press(&"liberty_jump")
	await _wait_physics(2)
	Input.action_release(&"liberty_jump")
	await _wait_physics(40)
	Support.expect_true(_character.velocity.y > 0.0, "slow-gravity fixture must still be rising after jump clip completes")
	Support.expect_equal(_current_state(), &"Airborne/Fall", "jump clip completion must enter Fall even before the apex")
	_character.gravity = 24.0


func _test_parent_exit_fade_rejump() -> void:
	await _reset_character()
	_character.jump_velocity = 2.4
	Input.action_press(&"liberty_jump")
	await _wait_physics(2)
	Input.action_release(&"liberty_jump")
	var saw_land := false
	for _frame in 100:
		await physics_frame
		if _current_state() == &"Airborne/Land":
			saw_land = true
		if saw_land and _current_state() == &"Locomotion":
			break
	Support.expect_true(saw_land, "parent-fade fixture must have completed a landing")
	Support.expect_equal(_driver.get_playback().get_fading_from_node(), &"Airborne", "fixture must still be fading out of Airborne")
	Input.action_press(&"liberty_jump")
	await _wait_physics(2)
	Input.action_release(&"liberty_jump")
	Support.expect_true(_character.velocity.y > 0.0, "new jump during parent fade must move upward")
	Support.expect_equal(_current_state(), &"Airborne/Jump", "new takeoff must interrupt the parent exit fade immediately")
	_character.jump_velocity = 7.2
	await _wait_physics(70)


func _test_performance_stop_while_locked() -> void:
	await _reset_character()
	var player := _tree.get_node(_tree.anim_player) as AnimationPlayer
	var library := player.get_animation_library(&"")
	var clip := Animation.new()
	clip.length = 0.4
	clip.loop_mode = Animation.LOOP_NONE
	library.add_animation(&"performance_test", clip)

	Support.expect_false(_driver.play_performance(&""), "empty performance clip must be rejected")
	Support.expect_false(_driver.play_performance(&"missing_performance"), "missing performance clip must be rejected")
	Support.expect_false(_driver.is_performance_playing(), "rejected performance must not be owned")
	Support.expect_equal(_current_state(), &"Locomotion", "rejected performance must leave Locomotion")

	_driver.traversal_animation_owned = true
	Support.expect_false(_driver.play_performance(&"performance_test"), "traversal-owned animation must reject performance")
	_driver.traversal_animation_owned = false
	_character.set_traversal_lock(true)
	Support.expect_false(_driver.play_performance(&"performance_test"), "traversal lock must reject performance")
	_character.set_traversal_lock(false)
	await _wait_physics(2)
	Support.expect_equal(_current_state(), &"Locomotion", "rejected traversal cases must stay in Locomotion")
	Support.expect_false(_driver.is_performance_playing(), "rejected traversal cases must not own performance")

	Support.expect_true(_driver.play_performance(&"performance_test"), "present clip must start performance")
	await _wait_physics(2)
	Support.expect_true(_driver.is_performance_playing(), "playing performance must be owned")
	Support.expect_equal(_current_state(), &"Performance", "play must enter Performance")
	_driver.stop_performance()
	Support.expect_false(_driver.is_performance_playing(), "stop must clear ownership immediately")
	await _wait_physics(3)
	Support.expect_equal(_current_state(), &"Locomotion", "unlocked grounded stop must return to Locomotion")
	_driver.stop_performance()
	await _wait_physics(2)
	Support.expect_equal(_current_state(), &"Locomotion", "a second stop must leave Locomotion")

	Support.expect_true(_driver.play_performance(&"performance_test"), "locked stop fixture must enter performance")
	await _wait_physics(2)
	_character.set_movement_locked(true)
	_driver.stop_performance()
	Support.expect_false(_driver.is_performance_playing(), "locked stop must clear ownership before unlock")
	await _wait_physics(3)
	Support.expect_equal(_current_state(), &"Performance", "locked stop must not travel while the body stays locked")
	_character.set_movement_locked(false)
	await _wait_physics(3)
	Support.expect_equal(_driver.get_state(), &"Locomotion", "unlock after a locked stop must reevaluate to Locomotion")

	await _reset_character()
	_character.teleport_to(Transform3D(Basis.IDENTITY, Vector3(0.0, 3.0, 0.0)))
	await _wait_physics(2)
	Support.expect_true(_driver.play_performance(&"performance_test"), "airborne stop fixture must enter performance")
	await _wait_physics(2)
	Support.expect_equal(_current_state(), &"Performance", "airborne body must stay in Performance while owned")
	_driver.stop_performance()
	await _wait_physics(3)
	Support.expect_equal(_driver.get_state(), &"Airborne/Fall", "unlocked airborne stop must enter Fall")
	Support.expect_false(_driver.is_performance_playing(), "airborne stop must clear ownership")


func _current_state() -> StringName:
	var playback := _driver.get_playback()
	if playback == null:
		return &""
	var current := playback.get_current_node()
	if current != Driver.STATE_AIRBORNE:
		return current
	var nested := _tree.get(&"parameters/Airborne/playback") as AnimationNodeStateMachinePlayback
	if nested == null:
		return current
	return StringName("%s/%s" % [current, nested.get_current_node()])


func _reset_character() -> void:
	_release_actions()
	_character.set_movement_locked(false)
	_character.teleport_to(Transform3D.IDENTITY)
	await _wait_physics(30)


func _wait_physics(frames: int) -> void:
	for _frame in frames:
		await physics_frame


func _release_actions() -> void:
	for action in ACTIONS:
		Input.action_release(action)
