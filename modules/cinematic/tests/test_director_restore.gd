extends SceneTree

const Support = preload("res://modules/liberty_character/tests/liberty_test_support.gd")
const CharacterScene = preload("res://modules/liberty_character/character/liberty_character.tscn")
const Sedan = preload("res://modules/liberty_vehicle/vehicle/liberty_vehicle.tscn")

class OnFootProbe extends CinematicShot:
	func requires_on_foot() -> bool:
		return true


## Runs after the traversal coordinator (-30) and before the director (-25).
class TraversalLockSetter extends Node:
	var character: LibertyCharacter
	var armed := true

	func _physics_process(_delta: float) -> void:
		if not armed or character == null:
			return
		armed = false
		character.set_traversal_lock(true)
		set_physics_process(false)


## Writes planar velocity just before the director (-25) so a frozen sedan keeps a scripted speed.
class PlanarSpeedHold extends Node:
	var vehicle: LibertyVehicle
	var velocity := Vector3.ZERO

	func _ready() -> void:
		process_physics_priority = -26

	func _physics_process(_delta: float) -> void:
		if is_instance_valid(vehicle):
			vehicle.linear_velocity = velocity


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_invalid_resolver()
	await _test_null_player()
	await _test_rejected_sequences()
	await _test_guard_and_duration_cap()
	await _test_ancestor_refusal()
	await _test_on_foot_shot_while_mounted()
	await _test_camera_restore()
	await _test_mounted_restore()
	await _test_camera_skip()
	await _test_escape_skips()
	await _test_ragdoll_refusal()
	await _test_traversal_refusal()
	await _test_ragdoll_watchdog()
	await _test_traversal_watchdog()
	await _test_character_exit()
	await _test_hold_and_act_empty()
	await _test_hold_and_act_performance()
	await _test_hold_and_act_missing_clip()
	await _test_hold_and_act_skip()
	await _test_staged_walk_arrival()
	await _test_staged_walk_relock()
	await _test_staged_walk_duration()
	await _test_staged_walk_skip()
	await _test_vehicle_beat_on_foot_refuses()
	await _test_vehicle_beat_without_control_refuses()
	await _test_vehicle_beat_snapshot()
	await _test_vehicle_beat_end_speed()
	await _test_vehicle_beat_missing_anchor()
	await _test_vehicle_beat_skip()
	await _test_mounted_camera_skip_leaves_vehicle()
	await _test_passage()
	var code := Support.exit_code()
	if code == 0:
		print("CINEMATIC_DIRECTOR_PASS")
	quit(code)


func _test_invalid_resolver() -> void:
	var fixture := _spawn_on_foot()
	await _wait(2)
	var director: CinematicDirector = fixture.director
	var character: LibertyCharacter = fixture.character
	var shoulder := _shoulder(character)
	var track := _track(director)
	Support.expect_true(shoulder.current, "shoulder camera starts current")
	var err := director.play(_sequence(&"bare", [_cut(&"cut", 0.2)]))
	Support.expect_equal(err, ERR_DOES_NOT_EXIST, "an invalid resolver refuses play")
	Support.expect_equal(track.started[0], 0, "a refused play emits nothing")
	Support.expect_false(director.is_sequence_active(), "a refused play stays idle")
	Support.expect_true(shoulder.current, "a refused play leaves the shoulder camera")
	Support.expect_false(_adapter(character).is_presentation_borrowed(), "a refused play does not borrow")
	Support.expect_equal(director.last_result, ERR_DOES_NOT_EXIST, "last_result stores the refusal")
	_free_fixture(fixture)


func _test_null_player() -> void:
	var fixture := _spawn_on_foot()
	await _wait(2)
	var director: CinematicDirector = fixture.director
	var character: LibertyCharacter = fixture.character
	var shoulder := _shoulder(character)
	director.role_resolver = func(_role: StringName) -> Node: return null
	var track := _track(director)
	var err := director.play(_sequence(&"missing_player", [_cut(&"cut", 0.2)]))
	Support.expect_equal(err, ERR_DOES_NOT_EXIST, "a null player refuses play")
	Support.expect_equal(track.started[0], 0, "a null player emits nothing")
	Support.expect_true(shoulder.current, "a null player leaves the shoulder camera")
	Support.expect_equal(director.release_presentation_calls, 0, "a null player does not release")
	_free_fixture(fixture)


func _test_rejected_sequences() -> void:
	var director := _add_director()
	var empty := director.play(_sequence(&"empty", []))
	Support.expect_equal(empty, ERR_INVALID_PARAMETER, "an empty sequence is refused")
	Support.expect_false(director.is_sequence_active(), "an empty sequence does not start")
	var longer := CinematicCameraCut.new()
	longer.duration = 8.01
	longer.role = &"cut"
	var too_long := director.play(_sequence(&"too_long", [longer]))
	Support.expect_equal(too_long, ERR_INVALID_PARAMETER, "a shot longer than 8s is refused")
	Support.expect_equal(director.last_result, ERR_INVALID_PARAMETER, "last_result stores the duration refusal")
	Support.expect_equal(director.release_presentation_calls, 0, "a rejected sequence does not borrow")
	var missing := director.play(null)
	Support.expect_equal(missing, ERR_INVALID_PARAMETER, "a null sequence is refused")
	Support.expect_equal(director.skip(), ERR_UNAVAILABLE, "skip while idle is unavailable")
	director.free()


func _test_guard_and_duration_cap() -> void:
	var fixture := _spawn_on_foot()
	var character: LibertyCharacter = fixture.character
	var director: CinematicDirector = fixture.director
	await _settle(character)
	var cut := _marker(Vector3(3.0, 2.0, -4.0), Vector3(-10.0, 25.0, 0.0))
	_bind(director, character, {&"cut": cut})
	director.notify_guard_accepted(&"save_game")
	var refused := director.play(_sequence(&"guarded", [_cut(&"cut", 0.2)]))
	Support.expect_equal(refused, ERR_BUSY, "a save latch refuses play")
	Support.expect_false(_adapter(character).is_presentation_borrowed(), "the save latch does not borrow")
	Support.expect_false(character.is_hit_suppressed(), "the save latch does not suppress hits")
	var fresh := _add_director()
	fresh.notify_guard_accepted(&"not_a_guard")
	_bind(fresh, character, {&"cut": cut})
	var track := _track(fresh)
	var accepted := fresh.play(_sequence(&"eight", [_cut(&"cut", 8.0)]))
	Support.expect_equal(accepted, OK, "an unknown operation does not latch, and 8s is allowed")
	Support.expect_equal(fresh.skip(), OK, "skip latches")
	Support.expect_equal(fresh.skip(), OK, "a second skip while latched returns OK")
	var skipped: bool = await _until(func() -> bool: return track.skipped[0] > 0, 30)
	Support.expect_true(skipped, "the 8s shot skips on the next ticks")
	Support.expect_equal(track.finished[0], 0, "skip does not emit cinematic_finished")
	Support.expect_equal(fresh.last_result, OK, "a skip that finishes is OK")
	await _wait(1)
	_assert_on_foot(character, fresh)
	fresh.free()
	cut.free()
	_free_fixture(fixture)


func _test_ancestor_refusal() -> void:
	var fixture := _spawn_on_foot()
	var character: LibertyCharacter = fixture.character
	await _wait(2)
	var world_root := Node3D.new()
	root.add_child(world_root)
	var director := CinematicDirector.new()
	world_root.add_child(director)
	var cut := _marker(Vector3(1.0, 1.0, 1.0))
	_bind(director, character, {&"cut": cut})
	var scenes = root.get_node("World").scenes
	var previous: Node = scenes._active_root
	scenes._active_root = world_root
	var err := director.play(_sequence(&"under_world", [_cut(&"cut", 0.2)]))
	scenes._active_root = previous
	Support.expect_equal(err, ERR_INVALID_PARAMETER, "a director under the active world is refused")
	Support.expect_equal(root.get_node("World").current_travel_id(), 0, "the refusal does not travel")
	Support.expect_false(director.is_sequence_active(), "the ancestor refusal stays idle")
	Support.expect_false(_adapter(character).is_presentation_borrowed(), "the ancestor refusal does not borrow")
	Support.expect_equal(scenes.get_active_world_root(), null, "the fixture clears the stand-in world root")
	cut.free()
	world_root.free()
	_free_fixture(fixture)


func _test_on_foot_shot_while_mounted() -> void:
	var fixture := await _mount_fixture()
	var director: CinematicDirector = fixture.director
	var character: LibertyCharacter = fixture.character
	var vehicle: LibertyVehicle = fixture.vehicle
	_bind(director, character, {})
	var probe := OnFootProbe.new()
	probe.duration = 0.2
	var err := director.play(_sequence(&"needs_feet", [probe]))
	Support.expect_equal(err, ERR_BUSY, "an on-foot shot refuses a mounted player")
	var held := director.play(_sequence(&"mounted_act", [_act(&"", 0.2)]))
	Support.expect_equal(held, ERR_BUSY, "hold-and-act refuses a mounted player")
	var walked := director.play(_sequence(&"mounted_walk", [_walk(&"mark", 0.2)]))
	Support.expect_equal(walked, ERR_BUSY, "staged walk refuses a mounted player")
	Support.expect_false(_adapter(character).is_presentation_borrowed(), "the mounted refusal does not borrow")
	Support.expect_true(vehicle.camera_rig.chase_camera.current, "the mounted refusal leaves the chase camera")
	_free_fixture(fixture)


func _test_camera_restore() -> void:
	Support.expect_equal(root.get_node("World").scenes.get_active_world_root(), null, "the fixture has no active world")
	var fixture := _spawn_on_foot()
	var character: LibertyCharacter = fixture.character
	var director: CinematicDirector = fixture.director
	await _settle(character)
	var cut := _marker(Vector3(3.0, 2.0, -4.0), Vector3(-12.0, 35.0, 0.0))
	var anchor := _marker(Vector3(-2.0, 0.0, 5.0))
	var target := _marker(Vector3(4.0, 1.2, 5.0))
	_bind(director, character, {&"cut": cut, &"anchor": anchor, &"target": target})
	var track := _track(director)
	var sequence := _sequence(&"restore", [
		_cut(&"cut", 0.2, "Glance"),
		_hold(&"anchor", &"target", Vector3(0.0, 1.6, 0.0), 0.2),
	])
	var err := director.play(sequence)
	Support.expect_equal(err, OK, "play accepts the camera sequence")
	var again := director.play(sequence)
	Support.expect_equal(again, ERR_BUSY, "a second play is busy")
	Support.expect_equal(track.started[0], 1, "a refused play does not start again")
	Support.expect_equal(director.last_result, OK, "a refused second play keeps last_result")
	var camera := director.cinematic_camera()
	Support.expect_true(camera.current, "play makes the cinematic camera current")
	Support.expect_true(camera.global_position.distance_to(cut.global_position) < 0.01, "the cut copies the marker position")
	Support.expect_true(camera.global_basis.is_equal_approx(cut.global_basis), "the cut copies the marker basis")
	var chrome := director.get_node("Chrome") as CanvasLayer
	var subtitle := chrome.get_node("Subtitle") as Label
	var skip_button := chrome.get_node("Skip") as Button
	Support.expect_equal(chrome.layer, 128, "chrome draws on layer 128")
	Support.expect_equal(subtitle.text, "Glance", "the cut assigns its subtitle")
	Support.expect_true(subtitle.visible, "a subtitle is shown")
	Support.expect_true(skip_button.visible, "Skip is visible during the sequence")
	var finished: bool = await _until(func() -> bool: return track.finished[0] > 0, 90)
	Support.expect_true(finished, "the camera sequence finishes")
	Support.expect_equal(track.skipped[0], 0, "a natural end does not emit cinematic_skipped")
	await _wait(1)
	var expected_pos := anchor.to_global(Vector3(0.0, 1.6, 0.0))
	Support.expect_true(camera.global_position.distance_to(expected_pos) < 0.01, "look-at sits on the anchor offset (%.4f)" % camera.global_position.distance_to(expected_pos))
	var forward := -camera.global_basis.z
	var to_target := target.global_position - camera.global_position
	Support.expect_true(forward.normalized().dot(to_target.normalized()) > 0.99, "look-at faces the target")
	Support.expect_false(skip_button.visible, "Skip hides after restore")
	_assert_on_foot(character, director)
	cut.free()
	anchor.free()
	target.free()
	_free_fixture(fixture)


func _test_mounted_restore() -> void:
	var fixture := await _mount_fixture()
	var director: CinematicDirector = fixture.director
	var character: LibertyCharacter = fixture.character
	var vehicle: LibertyVehicle = fixture.vehicle
	var adapter := _adapter(character)
	var shoulder := _shoulder(character)
	var cut := _marker(Vector3(42.0, 3.0, 2.0), Vector3(-8.0, 15.0, 0.0))
	_bind(director, character, {&"cut": cut})
	var mounted_events: Array[bool] = fixture.occupancy
	Support.expect_true(adapter.mounted_vehicle == vehicle, "the fixture is mounted before play")
	Support.expect_true(vehicle.possession.control_enabled, "the driver has control before play")
	var track := _track(director)
	var err := director.play(_sequence(&"mounted_cut", [_cut(&"cut", 0.2)]))
	Support.expect_equal(err, OK, "a mounted camera cut plays")
	var snapshot := LibertyVehicleControlSnapshot.new()
	snapshot.throttle = 1.0
	adapter.set_borrowed_controls(adapter._presentation_token, snapshot)
	await _wait(1)
	Support.expect_true(is_equal_approx(vehicle.controls.throttle, 1.0), "borrowed throttle is submitted during the shot")
	var finished: bool = await _until(func() -> bool: return track.finished[0] > 0, 60)
	Support.expect_true(finished, "the mounted cut finishes")
	await _wait(1)
	var rig := vehicle.camera_rig
	Support.expect_false(rig.hood_mode, "hood mode stays off")
	Support.expect_true(rig.chase_camera.current, "restore returns the chase camera")
	Support.expect_false(shoulder.current, "restore does not return the shoulder camera")
	Support.expect_true(is_instance_valid(adapter.mounted_vehicle), "the player stays mounted")
	Support.expect_true(vehicle.possession.control_enabled, "control stays enabled")
	Support.expect_equal(mounted_events.size(), 1, "play and restore emit no extra occupancy")
	var mobile := character.get_node("MobileControls") as LibertyMobileControls
	var overlay := character.get_node("VehicleMobileControls") as LibertyVehicleMobileControls
	Support.expect_true(mobile.is_suspended(), "on-foot controls stay suspended")
	Support.expect_true(overlay.active, "the vehicle overlay is active again")
	var fresh := LibertyVehicleControlSnapshot.from_input()
	Support.expect_true(vehicle.controls.throttle < 0.01, "borrowed throttle is gone after restore")
	Support.expect_true(is_equal_approx(vehicle.controls.throttle, fresh.throttle), "throttle matches from_input")
	Support.expect_true(is_equal_approx(vehicle.controls.brake, fresh.brake), "brake matches from_input")
	Support.expect_true(is_equal_approx(vehicle.controls.steering, fresh.steering), "steering matches from_input")
	Support.expect_equal(vehicle.controls.reset, fresh.reset, "reset matches from_input")
	Support.expect_equal(vehicle.controls.toggle_camera, fresh.toggle_camera, "toggle_camera matches from_input")
	Support.expect_false(adapter.is_presentation_borrowed(), "mounted restore releases the borrow")
	Support.expect_equal(director.release_presentation_calls, 1, "mounted restore releases once")
	cut.free()
	_free_fixture(fixture)


func _test_camera_skip() -> void:
	var fixture := _spawn_on_foot()
	var character: LibertyCharacter = fixture.character
	var director: CinematicDirector = fixture.director
	await _settle(character)
	var cut := _marker(Vector3(2.0, 1.5, 3.0))
	_bind(director, character, {&"cut": cut, &"hold": cut})
	var track := _track(director)
	var before := character.global_transform
	var err := director.play(_sequence(&"skip_me", [_cut(&"cut", 1.0), _cut(&"hold", 5.0)]))
	Support.expect_equal(err, OK, "the skip sequence plays")
	var started := Time.get_ticks_msec()
	Support.expect_equal(director.skip(), OK, "the first skip latches")
	Support.expect_equal(director.skip(), OK, "the second skip does not run the policy again")
	var skipped: bool = await _until(func() -> bool: return track.skipped[0] > 0, 30)
	Support.expect_true(skipped, "camera skip finishes without waiting out the second shot")
	Support.expect_true(Time.get_ticks_msec() - started < 1000, "camera skip does not wait out 5s")
	Support.expect_equal(track.finished[0], 0, "camera skip does not emit cinematic_finished")
	await _wait(1)
	_same_transform(character.global_transform, before, "camera skip leaves the character transform")
	Support.expect_equal(director.last_result, OK, "camera skip last_result is OK")
	_assert_on_foot(character, director)
	cut.free()
	_free_fixture(fixture)


func _test_escape_skips() -> void:
	var fixture := _spawn_on_foot()
	var character: LibertyCharacter = fixture.character
	var director: CinematicDirector = fixture.director
	await _settle(character)
	var cut := _marker(Vector3(-3.0, 1.5, 2.0))
	_bind(director, character, {&"cut": cut})
	var track := _track(director)
	var before := character.global_transform
	Support.expect_equal(director.play(_sequence(&"escape", [_cut(&"cut", 1.0)])), OK, "escape sequence plays")
	var event := InputEventKey.new()
	event.pressed = true
	event.keycode = KEY_ESCAPE
	director._input(event)
	var skipped: bool = await _until(func() -> bool: return track.skipped[0] > 0, 30)
	Support.expect_true(skipped, "Escape skips the shot")
	Support.expect_equal(track.finished[0], 0, "Escape does not emit cinematic_finished")
	await _wait(1)
	_same_transform(character.global_transform, before, "Escape leaves the character transform")
	_assert_on_foot(character, director)
	cut.free()
	_free_fixture(fixture)


func _test_ragdoll_refusal() -> void:
	var fixture := _spawn_on_foot()
	var character: LibertyCharacter = fixture.character
	var director: CinematicDirector = fixture.director
	await _settle(character)
	var shoulder := _shoulder(character)
	var activated := character.activate_ragdoll(Vector3.UP, 1.0, &"test")
	Support.expect_true(activated, "ragdoll activate accepts a unit impulse")
	_bind(director, character, {})
	var err := director.play(_sequence(&"ragdoll", [_cut(&"cut", 0.2)]))
	Support.expect_equal(err, ERR_BUSY, "an active ragdoll refuses play")
	Support.expect_true(shoulder.current, "ragdoll refusal leaves the shoulder camera")
	Support.expect_false(_adapter(character).is_presentation_borrowed(), "ragdoll refusal does not borrow")
	Support.expect_false(director.is_sequence_active(), "ragdoll refusal stays idle")
	_free_fixture(fixture)


func _test_traversal_refusal() -> void:
	var fixture := _spawn_on_foot()
	var character: LibertyCharacter = fixture.character
	var director: CinematicDirector = fixture.director
	await _settle(character)
	var shoulder := _shoulder(character)
	character.set_traversal_lock(true)
	_bind(director, character, {})
	var err := director.play(_sequence(&"traversal", [_cut(&"cut", 0.2)]))
	Support.expect_equal(err, ERR_BUSY, "a traversal lock refuses play")
	Support.expect_true(shoulder.current, "traversal refusal leaves the shoulder camera")
	Support.expect_false(_adapter(character).is_presentation_borrowed(), "traversal refusal does not borrow")
	character.set_traversal_lock(false)
	_free_fixture(fixture)


func _test_ragdoll_watchdog() -> void:
	var fixture := _spawn_on_foot()
	var character: LibertyCharacter = fixture.character
	var director: CinematicDirector = fixture.director
	await _settle(character)
	var cut := _marker(Vector3(1.0, 2.0, 1.0))
	_bind(director, character, {&"cut": cut})
	var track := _track(director)
	Support.expect_equal(director.play(_sequence(&"ragdoll_abort", [_cut(&"cut", 2.0)])), OK, "ragdoll watchdog sequence plays")
	await _wait(1)
	var before := character.global_transform
	var pivot := _pivot(character)
	Support.expect_true(character.activate_ragdoll(Vector3.FORWARD, 1.0, &"test"), "watchdog ragdoll activates")
	var finished: bool = await _until(func() -> bool: return track.finished[0] > 0, 30)
	Support.expect_true(finished, "ragdoll aborts the sequence")
	Support.expect_equal(track.skipped[0], 0, "ragdoll abort is not a skip")
	await _wait(1)
	Support.expect_equal(director.release_presentation_calls, 1, "ragdoll abort releases presentation")
	Support.expect_true(is_instance_valid(pivot._follow_override), "ragdoll abort keeps the hip follow override")
	Support.expect_false(pivot.is_orbit_held(), "ragdoll abort clears the orbit hold")
	Support.expect_equal(director.last_result, ERR_BUSY, "ragdoll abort last_result is busy")
	Support.expect_false(director.is_sequence_active(), "ragdoll abort returns to idle")
	_same_transform(character.global_transform, before, "ragdoll abort does not teleport")
	cut.free()
	_free_fixture(fixture)


func _test_traversal_watchdog() -> void:
	var fixture := _spawn_on_foot()
	var character: LibertyCharacter = fixture.character
	var director: CinematicDirector = fixture.director
	await _settle(character)
	var cut := _marker(Vector3(0.0, 2.0, -2.0))
	_bind(director, character, {&"cut": cut})
	var track := _track(director)
	Support.expect_equal(director.play(_sequence(&"traversal_abort", [_cut(&"cut", 2.0)])), OK, "traversal watchdog sequence plays")
	await _wait(1)
	# The traversal coordinator runs at -30 and clears a lock that it did not begin.
	# Set the lock at -27 so the director at -25 sees it in the same physics frame.
	var setter := TraversalLockSetter.new()
	setter.character = character
	setter.process_physics_priority = -27
	root.add_child(setter)
	var finished: bool = await _until(func() -> bool: return track.finished[0] > 0, 30)
	Support.expect_true(finished, "traversal aborts the sequence")
	Support.expect_equal(track.skipped[0], 0, "traversal abort is not a skip")
	Support.expect_true(character.is_traversal_locked(), "traversal abort leaves the traversal lock")
	await _wait(1)
	Support.expect_false(_adapter(character).is_presentation_borrowed(), "traversal abort releases presentation")
	Support.expect_equal(director.release_presentation_calls, 1, "traversal abort releases once")
	Support.expect_equal(director.last_result, ERR_BUSY, "traversal abort last_result is busy")
	character.set_traversal_lock(false)
	setter.free()
	cut.free()
	_free_fixture(fixture)


func _test_character_exit() -> void:
	var fixture := _spawn_on_foot()
	var character: LibertyCharacter = fixture.character
	var director: CinematicDirector = fixture.director
	await _settle(character)
	var cut := _marker(Vector3(2.0, 2.0, 2.0))
	_bind(director, character, {&"cut": cut})
	var track := _track(director)
	Support.expect_equal(director.play(_sequence(&"exit", [_cut(&"cut", 2.0)])), OK, "exit sequence plays")
	await _wait(1)
	character.queue_free()
	fixture.character = null
	var finished: bool = await _until_frame(func() -> bool: return track.finished[0] > 0, 30)
	Support.expect_true(finished, "character exit emits cinematic_finished")
	Support.expect_equal(track.skipped[0], 0, "character exit is not a skip")
	Support.expect_false(director.is_sequence_active(), "character exit returns to idle")
	Support.expect_false(director.cinematic_camera().current, "character exit clears the cinematic camera")
	Support.expect_equal(director.release_presentation_calls, 0, "character exit does not call release_presentation")
	Support.expect_equal(director.last_result, ERR_DOES_NOT_EXIST, "character exit last_result is missing")
	cut.free()
	_free_fixture(fixture)


func _test_hold_and_act_empty() -> void:
	var fixture := _spawn_on_foot()
	var character: LibertyCharacter = fixture.character
	var director: CinematicDirector = fixture.director
	await _settle(character)
	_bind(director, character, {})
	var track := _track(director)
	var before := character.global_transform
	var err := director.play(_sequence(&"empty_act", [_act(&"", 0.2)]))
	Support.expect_equal(err, OK, "an empty hold-and-act plays")
	Support.expect_true(director.cinematic_camera().current, "an empty hold keeps the cinematic camera")
	Support.expect_true(character.is_movement_locked(), "an empty hold stays movement locked")
	Support.expect_false(_driver(character).is_performance_playing(), "an empty hold does not play a performance")
	var finished: bool = await _until(func() -> bool: return track.finished[0] > 0, 60)
	Support.expect_true(finished, "an empty hold finishes")
	Support.expect_equal(track.skipped[0], 0, "an empty hold is not a skip")
	await _wait(1)
	_same_transform(character.global_transform, before, "an empty hold leaves the character transform")
	_assert_on_foot(character, director)
	_free_fixture(fixture)


func _test_hold_and_act_performance() -> void:
	var fixture := _spawn_on_foot()
	var character: LibertyCharacter = fixture.character
	var director: CinematicDirector = fixture.director
	await _settle(character)
	_add_performance_clip(character)
	_bind(director, character, {})
	var track := _track(director)
	var before := character.global_transform
	var err := director.play(_sequence(&"act", [_act(&"performance_test", 0.4)]))
	Support.expect_equal(err, OK, "hold-and-act plays a synthetic clip")
	var driver := _driver(character)
	Support.expect_true(driver.is_performance_playing(), "hold-and-act owns the performance")
	await _wait(2)
	Support.expect_true(director.is_sequence_active(), "the performance hold is still playing")
	Support.expect_equal(driver.get_state(), &"Performance", "hold-and-act enters Performance")
	var finished: bool = await _until(func() -> bool: return track.finished[0] > 0, 90)
	Support.expect_true(finished, "the performance hold finishes")
	Support.expect_equal(track.skipped[0], 0, "the performance hold is not a skip")
	await _wait(1)
	var state := driver.get_state()
	Support.expect_true(
		state == &"Locomotion" or state == &"Airborne/Fall",
		"unlock after the hold returns to locomotion or fall (%s)" % state
	)
	_same_transform(character.global_transform, before, "hold-and-act leaves the character transform")
	_assert_on_foot(character, director)
	_free_fixture(fixture)


func _test_hold_and_act_missing_clip() -> void:
	var fixture := _spawn_on_foot()
	var character: LibertyCharacter = fixture.character
	var director: CinematicDirector = fixture.director
	await _settle(character)
	_bind(director, character, {})
	var track := _track(director)
	var err := director.play(_sequence(&"missing_act", [_act(&"missing_performance", 0.2)]))
	Support.expect_equal(err, ERR_DOES_NOT_EXIST, "a missing performance clip refuses the shot")
	Support.expect_equal(track.started[0], 0, "a missing clip emits nothing")
	Support.expect_false(director.is_sequence_active(), "a missing clip stays idle")
	Support.expect_false(_adapter(character).is_presentation_borrowed(), "a missing clip releases the borrow")
	Support.expect_false(character.is_movement_locked(), "a missing clip clears the lock")
	Support.expect_false(_driver(character).is_performance_playing(), "a missing clip does not own a performance")
	Support.expect_equal(director.last_result, ERR_DOES_NOT_EXIST, "a missing clip stores last_result")
	_free_fixture(fixture)


func _test_hold_and_act_skip() -> void:
	var fixture := _spawn_on_foot()
	var character: LibertyCharacter = fixture.character
	var director: CinematicDirector = fixture.director
	await _settle(character)
	_add_performance_clip(character)
	_bind(director, character, {})
	var track := _track(director)
	var before := character.global_transform
	var err := director.play(_sequence(&"skip_act", [_act(&"performance_test", 1.0)]))
	Support.expect_equal(err, OK, "the hold skip sequence plays")
	Support.expect_true(_driver(character).is_performance_playing(), "the hold skip starts the performance")
	Support.expect_equal(director.skip(), OK, "hold-and-act skip latches")
	var skipped: bool = await _until(func() -> bool: return track.skipped[0] > 0, 30)
	Support.expect_true(skipped, "hold-and-act skip finishes")
	Support.expect_equal(track.finished[0], 0, "hold-and-act skip does not emit cinematic_finished")
	await _wait(1)
	_same_transform(character.global_transform, before, "hold-and-act skip does not teleport")
	_assert_on_foot(character, director)
	_free_fixture(fixture)


func _test_staged_walk_arrival() -> void:
	var fixture := _spawn_on_foot()
	var character: LibertyCharacter = fixture.character
	var director: CinematicDirector = fixture.director
	await _settle(character)
	var marker := _marker(_ahead(character, 1.2))
	_bind(director, character, {&"mark": marker})
	var track := _track(director)
	var err := director.play(_sequence(&"arrive", [_walk(&"mark", 2.0)]))
	Support.expect_equal(err, OK, "the staged walk plays")
	await _wait(1)
	Support.expect_true(character.has_scripted_locomotion(), "the staged walk sets scripted locomotion")
	Support.expect_false(character.is_movement_locked(), "the staged walk clears the movement lock")
	var finished: bool = await _until(func() -> bool: return track.finished[0] > 0, 180)
	Support.expect_true(finished, "the staged walk arrives")
	Support.expect_equal(track.skipped[0], 0, "arrival is not a skip")
	var gap := _planar_gap(character.global_position, marker.global_position)
	Support.expect_true(gap <= 0.4, "arrival is inside the radius (%.3f)" % gap)
	Support.expect_true(gap > 0.05, "arrival does not snap onto the marker (%.3f)" % gap)
	await _await_shoulder(character)
	_assert_on_foot(character, director)
	marker.free()
	_free_fixture(fixture)


func _test_staged_walk_relock() -> void:
	var fixture := _spawn_on_foot()
	var character: LibertyCharacter = fixture.character
	var director: CinematicDirector = fixture.director
	await _settle(character)
	var marker := _marker(_ahead(character, 20.0))
	var cut := _marker(Vector3(2.0, 1.5, -3.0))
	_bind(director, character, {&"mark": marker, &"cut": cut})
	var track := _track(director)
	var err := director.play(_sequence(&"relock", [_walk(&"mark", 0.0), _cut(&"cut", 0.3)]))
	Support.expect_equal(err, OK, "the walk-then-cut sequence plays")
	await _wait(1)
	Support.expect_true(director.is_sequence_active(), "the camera cut is still playing")
	Support.expect_true(character.is_movement_locked(), "the staged walk relocks on exit")
	Support.expect_false(character.has_scripted_locomotion(), "the staged walk clears scripted locomotion on exit")
	var finished: bool = await _until(func() -> bool: return track.finished[0] > 0, 60)
	Support.expect_true(finished, "the walk-then-cut sequence finishes")
	var gap := _planar_gap(character.global_position, marker.global_position)
	Support.expect_true(gap > 10.0, "a zero-duration walk does not teleport (%.3f)" % gap)
	await _wait(1)
	_assert_on_foot(character, director)
	marker.free()
	cut.free()
	_free_fixture(fixture)


func _test_staged_walk_duration() -> void:
	var fixture := _spawn_on_foot()
	var character: LibertyCharacter = fixture.character
	var director: CinematicDirector = fixture.director
	await _settle(character)
	var start := character.global_position
	var marker := _marker(_ahead(character, 20.0))
	_bind(director, character, {&"mark": marker})
	var track := _track(director)
	var err := director.play(_sequence(&"expire", [_walk(&"mark", 0.2)]))
	Support.expect_equal(err, OK, "the short staged walk plays")
	var finished: bool = await _until(func() -> bool: return track.finished[0] > 0, 60)
	Support.expect_true(finished, "duration ends the staged walk")
	Support.expect_equal(track.skipped[0], 0, "duration end is not a skip")
	var moved := _planar_gap(character.global_position, start)
	var gap := _planar_gap(character.global_position, marker.global_position)
	Support.expect_true(moved < 1.0, "duration end is not a teleport (moved %.3f)" % moved)
	Support.expect_true(gap > 10.0, "duration end leaves the marker (%.3f)" % gap)
	await _await_shoulder(character)
	_assert_on_foot(character, director)
	marker.free()
	_free_fixture(fixture)


func _test_staged_walk_skip() -> void:
	var fixture := _spawn_on_foot()
	var character: LibertyCharacter = fixture.character
	var director: CinematicDirector = fixture.director
	await _settle(character)
	var marker := _marker(Vector3(6.0, 0.1, -8.0))
	_bind(director, character, {&"mark": marker})
	var track := _track(director)
	var captured := [Transform3D.IDENTITY]
	var did_capture := [false]
	director.cinematic_skipped.connect(func(_id: StringName) -> void:
		captured[0] = character.global_transform
		did_capture[0] = true
	)
	var before := character.global_position
	var err := director.play(_sequence(&"skip_walk", [_walk(&"mark", 2.0)]))
	Support.expect_equal(err, OK, "the staged-walk skip sequence plays")
	Support.expect_true(_planar_gap(before, marker.global_position) > 5.0, "the skip marker is not the spawn")
	Support.expect_equal(director.skip(), OK, "staged-walk skip latches")
	var skipped: bool = await _until(func() -> bool: return track.skipped[0] > 0, 30)
	Support.expect_true(skipped, "staged-walk skip finishes")
	Support.expect_equal(track.finished[0], 0, "staged-walk skip does not emit cinematic_finished")
	Support.expect_true(did_capture[0], "staged-walk skip records the transform before the character tick")
	Support.expect_true(
		captured[0].is_equal_approx(marker.global_transform),
		"staged-walk skip teleports to the feet-origin marker"
	)
	await _wait(1)
	Support.expect_false(character.has_scripted_locomotion(), "staged-walk skip clears scripted locomotion")
	Support.expect_false(character.is_movement_locked(), "staged-walk skip clears the lock")
	var pivot := _pivot(character)
	var near_shoulder := func() -> bool:
		var expected := character.global_position + Vector3.UP * pivot.target_height
		return pivot.global_position.distance_to(expected) < 0.01
	var settled: bool = await _until(near_shoulder, 45)
	Support.expect_true(settled, "the pivot settles on the shoulder anchor after the skip")
	_assert_on_foot(character, director)
	marker.free()
	_free_fixture(fixture)


func _test_vehicle_beat_on_foot_refuses() -> void:
	var fixture := _spawn_on_foot()
	await _wait(2)
	var director: CinematicDirector = fixture.director
	var character: LibertyCharacter = fixture.character
	var shoulder := _shoulder(character)
	_bind(director, character, {})
	var track := _track(director)
	var err := director.play(_sequence(&"needs_driver", [_beat(0.2)]))
	Support.expect_equal(err, ERR_BUSY, "a vehicle beat refuses an on-foot player")
	Support.expect_equal(track.started[0], 0, "an on-foot vehicle beat emits nothing")
	Support.expect_equal(director.last_result, ERR_BUSY, "on-foot vehicle beat last_result is busy")
	Support.expect_false(_adapter(character).is_presentation_borrowed(), "an on-foot vehicle beat does not borrow")
	Support.expect_equal(director.release_presentation_calls, 0, "an on-foot vehicle beat does not release")
	Support.expect_true(shoulder.current, "an on-foot refusal leaves the shoulder camera")
	_free_fixture(fixture)


func _test_vehicle_beat_without_control_refuses() -> void:
	var fixture := await _mount_fixture()
	var director: CinematicDirector = fixture.director
	var character: LibertyCharacter = fixture.character
	var vehicle: LibertyVehicle = fixture.vehicle
	var mounted_events: Array[bool] = fixture.occupancy
	_bind(director, character, {})
	vehicle.set_control_enabled(&"driver_front_left", false)
	var track := _track(director)
	var err := director.play(_sequence(&"no_control", [_beat(0.2)]))
	Support.expect_equal(err, ERR_BUSY, "a vehicle beat refuses a driver without control")
	Support.expect_equal(track.started[0], 0, "a control refusal emits nothing")
	Support.expect_false(_adapter(character).is_presentation_borrowed(), "a control refusal does not borrow")
	Support.expect_equal(director.release_presentation_calls, 0, "a control refusal does not release")
	Support.expect_equal(mounted_events.size(), 1, "a control refusal emits no occupancy")
	Support.expect_true(vehicle.camera_rig.chase_camera.current, "a control refusal leaves the chase camera")
	Support.expect_true(is_instance_valid(_adapter(character).mounted_vehicle), "the player stays mounted")
	_free_fixture(fixture)


func _test_vehicle_beat_snapshot() -> void:
	var fixture := await _mount_fixture()
	var director: CinematicDirector = fixture.director
	var character: LibertyCharacter = fixture.character
	var vehicle: LibertyVehicle = fixture.vehicle
	var mounted_events: Array[bool] = fixture.occupancy
	_bind(director, character, {})
	var beat := _beat(2.0)
	beat.throttle = 0.8
	beat.steering = 0.35
	beat.brake = 0.2
	beat.handbrake = false
	var car_before := vehicle.global_transform
	var body_before := character.global_transform
	var track := _track(director)
	var err := director.play(_sequence(&"drive_beat", [beat]))
	Support.expect_equal(err, OK, "a mounted vehicle beat plays")
	await _wait(1)
	Support.expect_true(director.cinematic_camera().current, "the beat borrows the cinematic camera")
	Support.expect_true(is_equal_approx(vehicle.controls.throttle, 0.8), "borrowed throttle is submitted")
	Support.expect_true(is_equal_approx(vehicle.controls.steering, 0.35), "borrowed steering is submitted")
	Support.expect_true(is_equal_approx(vehicle.controls.brake, 0.2), "borrowed brake is submitted")
	Support.expect_false(vehicle.controls.handbrake, "borrowed handbrake stays clear")
	var reused := vehicle.controls
	await _wait(1)
	Support.expect_true(director.is_sequence_active(), "the beat is still playing across the two samples")
	Support.expect_true(vehicle.controls == reused, "the beat reuses one snapshot")
	Support.expect_true(is_equal_approx(vehicle.controls.throttle, 0.8), "the reused snapshot keeps its throttle")
	var finished: bool = await _until(func() -> bool: return track.finished[0] > 0, 180)
	Support.expect_true(finished, "the vehicle beat finishes on duration")
	Support.expect_equal(track.skipped[0], 0, "a natural vehicle beat does not skip")
	await _wait(1)
	_assert_mounted_followup(character, vehicle, mounted_events)
	_same_transform(vehicle.global_transform, car_before, "duration does not place the sedan")
	_same_transform(character.global_transform, body_before, "a vehicle beat does not move the character")
	Support.expect_false(_adapter(character).is_presentation_borrowed(), "the vehicle beat releases the borrow")
	Support.expect_equal(director.release_presentation_calls, 1, "the vehicle beat releases once")
	_free_fixture(fixture)


func _test_vehicle_beat_end_speed() -> void:
	var fixture := await _mount_fixture()
	var director: CinematicDirector = fixture.director
	var character: LibertyCharacter = fixture.character
	var vehicle: LibertyVehicle = fixture.vehicle
	_bind(director, character, {})
	var hold := PlanarSpeedHold.new()
	hold.vehicle = vehicle
	hold.velocity = Vector3(4.0, 0.0, 0.0)
	hold.process_physics_priority = -26
	root.add_child(hold)
	var beat := _beat(2.0)
	beat.end_speed_mps = 0.5
	var car_before := vehicle.global_transform
	var track := _track(director)
	var err := director.play(_sequence(&"slow_down", [beat]))
	Support.expect_equal(err, OK, "an end-speed beat plays")
	for _i in 4:
		await _wait(1)
		Support.expect_true(director.is_sequence_active(), "speed above end_speed keeps the beat")
	hold.velocity = Vector3.ZERO
	var started := Time.get_ticks_msec()
	var finished: bool = await _until(func() -> bool: return track.finished[0] > 0, 30)
	Support.expect_true(finished, "planar speed under end_speed finishes the beat")
	Support.expect_true(Time.get_ticks_msec() - started < 1000, "end speed does not wait out 2s")
	Support.expect_equal(track.skipped[0], 0, "end speed is a natural finish")
	_same_transform(vehicle.global_transform, car_before, "end speed does not place the sedan")
	hold.free()
	_free_fixture(fixture)


func _test_vehicle_beat_missing_anchor() -> void:
	var fixture := await _mount_fixture()
	var director: CinematicDirector = fixture.director
	var character: LibertyCharacter = fixture.character
	var vehicle: LibertyVehicle = fixture.vehicle
	_bind(director, character, {})
	var beat := _beat(0.2)
	beat.anchor_role = &"missing_bay"
	var car_before := vehicle.global_transform
	var track := _track(director)
	var err := director.play(_sequence(&"missing_bay", [beat]))
	Support.expect_equal(err, ERR_DOES_NOT_EXIST, "a missing skip anchor refuses the beat")
	Support.expect_equal(track.started[0], 0, "a missing anchor emits nothing")
	Support.expect_false(_adapter(character).is_presentation_borrowed(), "a missing anchor releases the borrow")
	Support.expect_equal(director.release_presentation_calls, 1, "a missing anchor releases the borrow it took")
	Support.expect_true(vehicle.camera_rig.chase_camera.current, "a missing anchor restores the chase camera")
	_same_transform(vehicle.global_transform, car_before, "a missing anchor does not place the sedan")
	_free_fixture(fixture)


func _test_vehicle_beat_skip() -> void:
	var fixture := await _mount_fixture()
	var director: CinematicDirector = fixture.director
	var character: LibertyCharacter = fixture.character
	var vehicle: LibertyVehicle = fixture.vehicle
	var mounted_events: Array[bool] = fixture.occupancy
	var marker := _marker(Vector3(52.0, 0.4, -6.0), Vector3(0.0, 25.0, 0.0))
	_bind(director, character, {&"bay": marker, &"cut": marker})
	var beat := _beat(2.0)
	beat.throttle = 1.0
	beat.anchor_role = &"bay"
	var body_before := character.global_transform
	var track := _track(director)
	var err := director.play(_sequence(&"place_sedan", [beat, _cut(&"cut", 5.0)]))
	Support.expect_equal(err, OK, "the vehicle skip sequence plays")
	vehicle.steering = 1.0
	vehicle._smoothed_drive_demand = 1.0
	var started := Time.get_ticks_msec()
	Support.expect_equal(director.skip(), OK, "the first vehicle skip latches")
	Support.expect_equal(director.skip(), OK, "the second vehicle skip does not run the policy again")
	var skipped: bool = await _until(func() -> bool: return track.skipped[0] > 0, 30)
	Support.expect_true(skipped, "vehicle skip finishes without waiting out the camera cut")
	Support.expect_true(Time.get_ticks_msec() - started < 1000, "vehicle skip does not wait out 5s")
	Support.expect_equal(track.finished[0], 0, "vehicle skip does not emit cinematic_finished")
	Support.expect_true(vehicle.global_transform.is_equal_approx(marker.global_transform), "skip places the sedan on the marker")
	Support.expect_true(vehicle.linear_velocity.is_zero_approx(), "skip zeroes linear velocity")
	Support.expect_true(vehicle.angular_velocity.is_zero_approx(), "skip zeroes angular velocity")
	Support.expect_false(vehicle.sleeping, "skip leaves the sedan awake")
	Support.expect_true(is_zero_approx(vehicle._smoothed_drive_demand), "the handbrake tick clears drive demand")
	Support.expect_true(vehicle.steering > 0.5 and vehicle.steering < 1.0, "steering returns through move_toward (%.4f)" % vehicle.steering)
	_same_transform(character.global_transform, body_before, "vehicle skip does not move the character")
	await _wait(1)
	_assert_mounted_followup(character, vehicle, mounted_events)
	Support.expect_equal(director.last_result, OK, "vehicle skip last_result is OK")
	marker.free()
	_free_fixture(fixture)


func _test_mounted_camera_skip_leaves_vehicle() -> void:
	var fixture := await _mount_fixture()
	var director: CinematicDirector = fixture.director
	var character: LibertyCharacter = fixture.character
	var vehicle: LibertyVehicle = fixture.vehicle
	var mounted_events: Array[bool] = fixture.occupancy
	var cut := _marker(Vector3(44.0, 3.0, 2.0))
	_bind(director, character, {&"cut": cut})
	var car_before := vehicle.global_transform
	var body_before := character.global_transform
	var track := _track(director)
	var err := director.play(_sequence(&"mounted_glance", [_cut(&"cut", 1.0)]))
	Support.expect_equal(err, OK, "a mounted camera cut still plays")
	Support.expect_equal(director.skip(), OK, "a mounted camera skip latches")
	var skipped: bool = await _until(func() -> bool: return track.skipped[0] > 0, 30)
	Support.expect_true(skipped, "the mounted camera skip finishes")
	Support.expect_equal(track.finished[0], 0, "a mounted camera skip does not finish naturally")
	_same_transform(vehicle.global_transform, car_before, "a camera skip does not place the sedan")
	_same_transform(character.global_transform, body_before, "a camera skip does not move the mounted character")
	await _wait(1)
	_assert_mounted_followup(character, vehicle, mounted_events)
	cut.free()
	_free_fixture(fixture)


func _test_passage() -> void:
	await _test_passage_duration_and_unregistered()
	_register_passage_worlds()
	await _test_passage_busy()
	root.get_node("World").events.world_loaded.connect(_on_passage_world_loaded)
	await _load_passage(&"passage_from", &"from_entry")
	await _test_passage_missing_entry()
	await _test_passage_success()
	await _test_passage_skip()
	await _test_passage_skip_loses_travel()
	await _test_passage_ancestor()
	await _test_passage_mounted()


func _test_passage_duration_and_unregistered() -> void:
	var director := _add_director()
	var long := _passage(&"passage_to", &"to_entry", 8.01)
	var refused := director.play(_sequence(&"long_passage", [long]))
	Support.expect_equal(refused, ERR_INVALID_PARAMETER, "a passage longer than 8s is refused before travel")
	Support.expect_equal(director.last_result, ERR_INVALID_PARAMETER, "last_result stores the passage duration refusal")
	Support.expect_equal(root.get_node("World").current_travel_id(), 0, "the duration refusal does not travel")
	Support.expect_equal(director.release_presentation_calls, 0, "the duration refusal does not borrow")
	director.free()
	var fixture := _spawn_on_foot()
	var character: LibertyCharacter = fixture.character
	director = fixture.director
	await _settle(character)
	_bind(director, character, {})
	var track := _track(director)
	var err := director.play(_sequence(&"missing_world", [_passage(&"passage_nowhere", &"nowhere_entry")]))
	Support.expect_equal(err, OK, "a refused travel still returns OK from play")
	Support.expect_equal(track.started[0], 1, "a refused travel emits cinematic_started")
	Support.expect_equal(track.finished[0], 1, "a refused travel emits cinematic_finished inside play")
	Support.expect_equal(track.skipped[0], 0, "a refused travel is not a skip")
	Support.expect_equal(director.last_result, ERR_DOES_NOT_EXIST, "an unregistered world is ERR_DOES_NOT_EXIST")
	Support.expect_equal(root.get_node("World").current_travel_id(), 0, "a refused travel does not stay in flight")
	Support.expect_false(director.is_sequence_active(), "a refused travel is idle before play returns")
	Support.expect_false(_adapter(character).is_presentation_borrowed(), "a refused travel releases the borrow")
	Support.expect_equal(director.release_presentation_calls, 1, "a refused travel releases presentation once")
	Support.expect_true(is_zero_approx(director.fade_rect().color.a), "a refused travel leaves the fade clear")
	Support.expect_equal(director.fade_rect().mouse_filter, Control.MOUSE_FILTER_IGNORE, "the fade ignores the pointer")
	Support.expect_equal(director.skip(), ERR_UNAVAILABLE, "skip after a refused travel is unavailable")
	_free_fixture(fixture)


func _test_passage_busy() -> void:
	var fixture := _spawn_on_foot()
	var character: LibertyCharacter = fixture.character
	var director: CinematicDirector = fixture.director
	await _settle(character)
	_bind(director, character, {})
	var world = root.get_node("World")
	var save_done := [false]
	var on_completed := func(_context: Dictionary) -> void:
		save_done[0] = true
	var on_failed := func(_reason: Error, _context: Dictionary) -> void:
		save_done[0] = true
	world.events.save_completed.connect(on_completed)
	world.events.save_failed.connect(on_failed)
	var save_err: Error = world.save_game(&"passage_busy")
	Support.expect_equal(save_err, OK, "the busy fixture accepts a save")
	var track := _track(director)
	var err := director.play(_sequence(&"busy_passage", [_passage(&"passage_to", &"to_entry")]))
	Support.expect_equal(err, OK, "a guard-busy travel still returns OK from play")
	Support.expect_equal(track.started[0], 1, "a guard-busy travel emits cinematic_started")
	Support.expect_equal(track.finished[0], 1, "a guard-busy travel emits cinematic_finished inside play")
	Support.expect_equal(track.skipped[0], 0, "a guard-busy travel is not a skip")
	Support.expect_equal(director.last_result, ERR_BUSY, "a held guard refuses travel_to with ERR_BUSY")
	Support.expect_equal(world.current_travel_id(), 0, "a busy refusal does not start a travel")
	Support.expect_equal(director.release_presentation_calls, 1, "a busy refusal releases presentation")
	Support.expect_true(is_zero_approx(director.fade_rect().color.a), "a busy refusal leaves the fade clear")
	var saved: bool = await _until_msec(func() -> bool: return save_done[0], 8000)
	world.events.save_completed.disconnect(on_completed)
	world.events.save_failed.disconnect(on_failed)
	Support.expect_true(saved, "the busy fixture releases the save guard")
	_free_fixture(fixture)


func _test_passage_missing_entry() -> void:
	var director := _add_director()
	_bind_world_player(director)
	var origin := _passage_player()
	var origin_id := origin.get_instance_id()
	var track := _track(director)
	var err := director.play(_sequence(&"bad_entry", [_passage(&"passage_to", &"no_such_entry")]))
	Support.expect_equal(err, OK, "a missing entry is accepted by travel_to")
	Support.expect_equal(track.finished[0], 0, "a missing entry does not finish inside play")
	var done: bool = await _until_msec(func() -> bool: return track.finished[0] > 0 or track.skipped[0] > 0, 8000)
	Support.expect_true(done, "a missing entry reaches a terminal")
	Support.expect_equal(track.finished[0], 1, "a missing entry emits cinematic_finished")
	Support.expect_equal(track.skipped[0], 0, "a missing entry is not a skip")
	Support.expect_equal(director.last_result, ERR_DOES_NOT_EXIST, "a missing entry fails the passage")
	Support.expect_equal(root.get_node("World").scenes.get_active_world_id(), &"passage_from", "a missing entry keeps the origin")
	Support.expect_equal(root.get_node("World").current_travel_id(), 0, "a missing entry leaves no travel")
	Support.expect_true(is_instance_valid(origin), "a missing entry keeps the origin player")
	Support.expect_equal(origin.get_instance_id(), origin_id, "a missing entry does not replace the player")
	Support.expect_true(is_zero_approx(director.fade_rect().color.a), "a missing entry never shows the fade")
	Support.expect_false(director.is_sequence_active(), "a missing entry returns to idle")
	director.free()


func _test_passage_success() -> void:
	var director := _add_director()
	_bind_world_player(director)
	var origin := _passage_player()
	var world = root.get_node("World")
	var saw_cinematic := [false]
	var on_loaded := func(_context: Dictionary, _entry: WorldEntryPointData) -> void:
		var camera := director.cinematic_camera()
		saw_cinematic[0] = camera != null and camera.current
	var track := _track(director)
	var err := director.play(_sequence(&"cross", [_passage(&"passage_to", &"to_entry")]))
	world.events.world_loaded.connect(on_loaded)
	Support.expect_equal(err, OK, "a world passage plays")
	Support.expect_equal(track.started[0], 1, "a world passage emits cinematic_started")
	Support.expect_equal(track.finished[0], 0, "a world passage does not finish inside play")
	var fade := director.fade_rect()
	Support.expect_false(_passage_root().is_ancestor_of(director), "the director stays outside the world root")
	Support.expect_equal(fade.get_parent().name, "Chrome", "the fade is parented on the chrome")
	var done: bool = await _until_msec(func() -> bool: return track.finished[0] > 0 or track.skipped[0] > 0, 8000)
	if world.events.world_loaded.is_connected(on_loaded):
		world.events.world_loaded.disconnect(on_loaded)
	Support.expect_true(done, "a world passage finishes")
	Support.expect_equal(track.finished[0], 1, "a world passage emits cinematic_finished")
	Support.expect_equal(track.skipped[0], 0, "a world passage is not a skip")
	Support.expect_equal(director.last_result, OK, "a world passage keeps last_result OK")
	Support.expect_equal(world.scenes.get_active_world_id(), &"passage_to", "the passage arrives")
	Support.expect_equal(world.current_travel_id(), 0, "the passage leaves no travel")
	Support.expect_true(saw_cinematic[0], "rebind makes the cinematic camera current during world_loaded")
	Support.expect_false(is_instance_valid(origin), "the origin player is freed at commit")
	var arrived := _passage_player()
	Support.expect_true(arrived != null and arrived.is_inside_tree(), "the destination has a player")
	var shoulder := _shoulder(arrived)
	Support.expect_true(arrived.get_viewport().get_camera_3d() == shoulder, "restore returns the new shoulder camera")
	Support.expect_false(arrived.is_movement_locked(), "the new player is unlocked")
	Support.expect_false(arrived.is_hit_suppressed(), "the new player is not hit suppressed")
	Support.expect_false(_adapter(arrived).is_presentation_borrowed(), "the new presentation is released")
	Support.expect_equal(director.release_presentation_calls, 1, "only the new adapter is released")
	Support.expect_true(director.process_mode != Node.PROCESS_MODE_DISABLED, "the director stays processable")
	Support.expect_true(is_zero_approx(fade.color.a), "cleanup clears the fade")
	var gap := _planar_gap(arrived.global_position, Vector3(3.0, 0.1, -2.0))
	Support.expect_true(gap < 0.75, "world_loaded teleports to the entry (gap %.3f)" % gap)
	director.free()


func _test_passage_skip() -> void:
	var director := _add_director()
	var cut_marker := _marker(Vector3(1.0, 2.0, 3.0))
	_bind_world_player(director, {&"cut": cut_marker})
	var world = root.get_node("World")
	var track := _track(director)
	var err := director.play(_sequence(&"skip_cross", [_passage(&"passage_from", &"from_entry"), _cut(&"cut", 5.0)]))
	Support.expect_equal(err, OK, "the skipped passage plays")
	var rose: bool = await _until_msec(func() -> bool: return director.fade_rect().color.a > 0.05, 8000)
	Support.expect_true(rose, "the fade starts before skip")
	var stamp := Time.get_ticks_msec()
	Support.expect_equal(director.skip(), OK, "skip latches during the fade")
	var done: bool = await _until_msec(func() -> bool: return track.skipped[0] > 0 or track.finished[0] > 0, 5000)
	var elapsed := Time.get_ticks_msec() - stamp
	Support.expect_true(done, "skip reaches a terminal")
	Support.expect_true(elapsed < 5000, "skip finishes in under 5s (%d ms)" % elapsed)
	Support.expect_equal(track.skipped[0], 1, "a completed skip emits cinematic_skipped")
	Support.expect_equal(track.finished[0], 0, "a completed skip does not emit cinematic_finished")
	Support.expect_equal(director.last_result, OK, "a completed skip is OK")
	Support.expect_equal(world.scenes.get_active_world_id(), &"passage_from", "skip still arrives")
	Support.expect_equal(world.current_travel_id(), 0, "skip leaves no travel")
	Support.expect_false(director.is_sequence_active(), "skip does not play the following cut")
	cut_marker.free()
	director.free()


func _test_passage_skip_loses_travel() -> void:
	var director := _add_director()
	_bind_world_player(director)
	var world = root.get_node("World")
	var track := _track(director)
	var err := director.play(_sequence(&"skip_miss", [_passage(&"passage_to", &"no_such_entry")]))
	Support.expect_equal(err, OK, "the losing skip is accepted")
	Support.expect_equal(director.skip(), OK, "skip latches before the travel fails")
	var done: bool = await _until_msec(func() -> bool: return track.finished[0] > 0 or track.skipped[0] > 0, 8000)
	Support.expect_true(done, "a lost travel still terminates")
	Support.expect_equal(track.skipped[0], 0, "a lost travel does not emit cinematic_skipped")
	Support.expect_equal(track.finished[0], 1, "a lost travel emits cinematic_finished")
	Support.expect_true(director.last_result != OK, "a lost travel does not report OK")
	Support.expect_equal(director.last_result, ERR_DOES_NOT_EXIST, "a lost travel keeps the entry error")
	Support.expect_equal(world.scenes.get_active_world_id(), &"passage_from", "a lost travel stays on the origin")
	Support.expect_equal(world.current_travel_id(), 0, "a lost travel leaves no travel")
	director.free()


func _test_passage_ancestor() -> void:
	var world = root.get_node("World")
	var world_root: Node = world.scenes.get_active_world_root()
	var director := CinematicDirector.new()
	world_root.add_child(director)
	_bind_world_player(director)
	var track := _track(director)
	var err := director.play(_sequence(&"under_root", [_passage(&"passage_to", &"to_entry")]))
	Support.expect_equal(err, ERR_INVALID_PARAMETER, "a passage under the world root is refused")
	Support.expect_equal(world.current_travel_id(), 0, "the ancestor refusal does not travel")
	Support.expect_equal(track.started[0], 0, "the ancestor refusal emits nothing")
	Support.expect_equal(director.release_presentation_calls, 0, "the ancestor refusal does not borrow")
	Support.expect_equal(world.scenes.get_active_world_id(), &"passage_from", "the ancestor refusal stays put")
	director.free()


func _test_passage_mounted() -> void:
	var fixture := await _mount_fixture()
	var director: CinematicDirector = fixture.director
	var character: LibertyCharacter = fixture.character
	_bind(director, character, {})
	var track := _track(director)
	var world = root.get_node("World")
	var before: int = world.current_travel_id()
	var err := director.play(_sequence(&"mounted_passage", [_passage(&"passage_to", &"to_entry")]))
	Support.expect_equal(err, ERR_BUSY, "a mounted passage is refused")
	Support.expect_equal(track.started[0], 0, "a mounted passage emits nothing")
	Support.expect_equal(track.finished[0], 0, "a mounted passage does not finish")
	Support.expect_false(_adapter(character).is_presentation_borrowed(), "a mounted passage does not borrow")
	Support.expect_equal(director.release_presentation_calls, 0, "a mounted passage does not release")
	Support.expect_equal(world.current_travel_id(), before, "a mounted passage does not travel")
	_free_fixture(fixture)


func _on_passage_world_loaded(_context: Dictionary, entry: WorldEntryPointData) -> void:
	if not entry is WorldEntryPoint3DData:
		return
	var active := _passage_root()
	if active == null:
		return
	var actor := active.get_node_or_null("Player") as LibertyCharacter
	if actor == null:
		return
	actor.teleport_to((entry as WorldEntryPoint3DData).transform)


func _register_passage_worlds() -> void:
	var from_scene := _pack_passage_world(&"from_entry", Vector3(0.0, 0.1, 2.0))
	var to_scene := _pack_passage_world(&"to_entry", Vector3(3.0, 0.1, -2.0))
	Support.expect_true(from_scene != null, "the origin world packs a player and an entry")
	Support.expect_true(to_scene != null, "the destination world packs a player and an entry")
	var from_def := WorldDefinition.new()
	from_def.id = &"passage_from"
	from_def.scene = from_scene
	var to_def := WorldDefinition.new()
	to_def.id = &"passage_to"
	to_def.scene = to_scene
	var world = root.get_node("World")
	Support.expect_equal(world.scenes.register_world(from_def), OK, "the origin world registers")
	Support.expect_equal(world.scenes.register_world(to_def), OK, "the destination world registers")


func _pack_passage_world(entry_id: StringName, at: Vector3) -> PackedScene:
	var world_root := Node3D.new()
	world_root.name = "PassageWorld"
	var player := CharacterScene.instantiate() as LibertyCharacter
	if player == null:
		world_root.free()
		return null
	player.name = "Player"
	player.position = Vector3(0.0, 0.1, 0.0)
	world_root.add_child(player)
	_claim_owner(world_root, player)
	var entry := WorldEntryPoint3D.new()
	entry.name = "Entry"
	entry.id = entry_id
	entry.position = at
	world_root.add_child(entry)
	entry.owner = world_root
	var floor_body := StaticBody3D.new()
	floor_body.name = "Floor"
	floor_body.collision_layer = 1
	floor_body.position = Vector3(0.0, -0.5, 0.0)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40.0, 1.0, 40.0)
	shape.shape = box
	floor_body.add_child(shape)
	world_root.add_child(floor_body)
	floor_body.owner = world_root
	shape.owner = world_root
	var packed := PackedScene.new()
	var err := packed.pack(world_root)
	if err != OK:
		root.add_child(world_root)
		err = packed.pack(world_root)
		root.remove_child(world_root)
	world_root.free()
	if err != OK:
		push_error("passage pack failed: %s" % error_string(err))
		return null
	var check := packed.instantiate()
	var kept := check.get_node_or_null("Player") != null and check.get_node_or_null("Entry") != null
	check.free()
	if not kept:
		push_error("passage pack dropped the player or the entry")
		return null
	return packed


func _claim_owner(owner: Node, node: Node) -> void:
	node.owner = owner
	for child in node.get_children():
		_claim_owner(owner, child)


func _load_passage(world_id: StringName, entry_id: StringName) -> void:
	var world = root.get_node("World")
	var loaded := [false]
	var failed := [OK]
	var on_loaded := func(_context: Dictionary, _entry: WorldEntryPointData) -> void:
		loaded[0] = true
	var on_failed := func(reason: Error, _context: Dictionary) -> void:
		failed[0] = reason
		loaded[0] = true
	world.events.world_loaded.connect(on_loaded)
	world.events.world_load_failed.connect(on_failed)
	var err: Error = world.scenes.load_world(world_id, entry_id)
	Support.expect_equal(err, OK, "passage world load is accepted")
	var done: bool = await _until_msec(func() -> bool: return loaded[0], 8000)
	if world.events.world_loaded.is_connected(on_loaded):
		world.events.world_loaded.disconnect(on_loaded)
	if world.events.world_load_failed.is_connected(on_failed):
		world.events.world_load_failed.disconnect(on_failed)
	Support.expect_true(done, "passage world load finishes")
	Support.expect_equal(failed[0], OK, "passage world load succeeds")
	Support.expect_equal(world.scenes.get_active_world_id(), world_id, "the loaded world is active")


func _bind_world_player(director: CinematicDirector, extra: Dictionary = {}) -> void:
	director.role_resolver = func(role: StringName) -> Node:
		if extra.has(role):
			return extra[role] as Node
		if role != &"player":
			return null
		var active := _passage_root()
		if active == null:
			return null
		return active.get_node_or_null("Player")


func _passage_root() -> Node:
	var world = root.get_node_or_null("World")
	if world == null:
		return null
	return world.scenes.get_active_world_root()


func _passage_player() -> LibertyCharacter:
	var active := _passage_root()
	if active == null:
		return null
	return active.get_node_or_null("Player") as LibertyCharacter


func _passage(world_id: StringName, entry_id: StringName, duration := 0.0) -> CinematicWorldPassage:
	var shot := CinematicWorldPassage.new()
	shot.world_id = world_id
	shot.entry_id = entry_id
	shot.duration = duration
	return shot


func _assert_mounted_followup(character: LibertyCharacter, vehicle: LibertyVehicle, occupancy: Array) -> void:
	var shoulder := _shoulder(character)
	var rig := vehicle.camera_rig
	Support.expect_false(rig.hood_mode, "hood mode stays off")
	Support.expect_true(rig.chase_camera.current, "restore returns the chase camera")
	Support.expect_false(shoulder.current, "restore does not return the shoulder camera")
	Support.expect_equal(occupancy.size(), 1, "play and restore emit no extra occupancy")
	var mobile := character.get_node("MobileControls") as LibertyMobileControls
	var overlay := character.get_node("VehicleMobileControls") as LibertyVehicleMobileControls
	Support.expect_true(mobile.is_suspended(), "on-foot controls stay suspended")
	Support.expect_true(overlay.active, "the vehicle overlay is active again")
	var fresh := LibertyVehicleControlSnapshot.from_input()
	Support.expect_true(is_equal_approx(vehicle.controls.throttle, fresh.throttle), "throttle matches from_input")
	Support.expect_true(is_equal_approx(vehicle.controls.brake, fresh.brake), "brake matches from_input")
	Support.expect_true(is_equal_approx(vehicle.controls.steering, fresh.steering), "steering matches from_input")
	Support.expect_equal(vehicle.controls.reset, fresh.reset, "reset matches from_input")
	Support.expect_equal(vehicle.controls.toggle_camera, fresh.toggle_camera, "toggle_camera matches from_input")


func _assert_on_foot(character: LibertyCharacter, director: CinematicDirector) -> void:
	var shoulder := _shoulder(character)
	var pivot := _pivot(character)
	var driver := character.get_node("AnimationDriver") as LibertyAnimationDriver
	Support.expect_false(director.is_sequence_active(), "sequence is idle")
	Support.expect_equal(director.current_sequence_id(), &"", "idle sequence id is empty")
	Support.expect_true(character.get_viewport().get_camera_3d() == shoulder, "shoulder camera is current")
	Support.expect_false(character.is_movement_locked(), "movement lock is cleared")
	Support.expect_false(character.has_scripted_locomotion(), "scripted locomotion is cleared")
	Support.expect_false(character.is_hit_suppressed(), "hit suppression is cleared")
	Support.expect_false(driver.is_performance_playing(), "performance is stopped")
	Support.expect_equal(driver.get_state(), &"Locomotion", "grounded state stays Locomotion")
	var expected := character.global_position + Vector3.UP * pivot.target_height
	var drift := pivot.global_position.distance_to(expected)
	Support.expect_true(drift < 0.01, "pivot is within 1cm of the shoulder anchor (%.4f)" % drift)
	Support.expect_false(_adapter(character).is_presentation_borrowed(), "presentation is released")
	Support.expect_equal(director.process_physics_priority, -25, "director runs at priority -25")
	Support.expect_equal(director.release_presentation_calls, 1, "restore releases presentation once")
	Support.expect_equal(director.last_result, OK, "clean restore keeps last_result OK")


func _same_transform(actual: Transform3D, before: Transform3D, message: String) -> void:
	var moved := actual.origin.distance_to(before.origin)
	Support.expect_true(moved < 0.001, "%s (moved %.4f)" % [message, moved])
	Support.expect_true(actual.basis.is_equal_approx(before.basis), message)


func _spawn_on_foot() -> Dictionary:
	var floor_body := _add_floor(Vector3.ZERO)
	var character := CharacterScene.instantiate() as LibertyCharacter
	root.add_child(character)
	return {
		"floor": floor_body,
		"character": character,
		"director": _add_director(),
		"vehicle": null,
	}


func _mount_fixture() -> Dictionary:
	var floor_body := _add_floor(Vector3(40.0, 0.0, 0.0))
	var vehicle := Sedan.instantiate() as LibertyVehicle
	vehicle.position = Vector3(40.0, 0.0, 0.0)
	vehicle.freeze = true
	root.add_child(vehicle)
	var character := CharacterScene.instantiate() as LibertyCharacter
	character.position = Vector3(38.65, 0.02, -0.4)
	root.add_child(character)
	var director := _add_director()
	await _wait(12)
	var mounted_events: Array[bool] = []
	var events := character.get_node("Events") as LibertyEvents
	events.occupancy_changed.connect(func(_vehicle_id: int, _seat: StringName, _occupant: int, mounted: bool, _cause: StringName) -> void:
		mounted_events.append(mounted)
	)
	var adapter := _adapter(character)
	Support.expect_true(adapter.mount(vehicle, &"driver_front_left").succeeded(), "fixture mounts")
	Support.expect_equal(mounted_events.size(), 1, "mount emits one occupancy change")
	Support.expect_true(mounted_events[0], "mount emits mounted")
	return {
		"floor": floor_body,
		"character": character,
		"director": director,
		"vehicle": vehicle,
		"occupancy": mounted_events,
	}


func _add_director() -> CinematicDirector:
	var director := CinematicDirector.new()
	root.add_child(director)
	return director


func _add_floor(at: Vector3) -> StaticBody3D:
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	floor_body.position = at + Vector3(0.0, -0.5, 0.0)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60.0, 1.0, 60.0)
	shape.shape = box
	floor_body.add_child(shape)
	root.add_child(floor_body)
	return floor_body


func _marker(at: Vector3, rotation_degrees := Vector3.ZERO) -> Marker3D:
	var marker := Marker3D.new()
	marker.position = at
	marker.rotation_degrees = rotation_degrees
	root.add_child(marker)
	return marker


func _bind(director: CinematicDirector, character: LibertyCharacter, roles: Dictionary) -> void:
	roles[&"player"] = character
	director.role_resolver = func(role: StringName) -> Node:
		return roles.get(role) as Node


func _cut(role: StringName, duration: float, subtitle := "") -> CinematicCameraCut:
	var shot := CinematicCameraCut.new()
	shot.role = role
	shot.duration = duration
	shot.subtitle = subtitle
	return shot


func _act(clip: StringName, duration: float) -> CinematicHoldAndAct:
	var shot := CinematicHoldAndAct.new()
	shot.clip = clip
	shot.duration = duration
	return shot


func _beat(duration: float) -> CinematicVehicleBeat:
	var shot := CinematicVehicleBeat.new()
	shot.duration = duration
	return shot


func _walk(role: StringName, duration: float) -> CinematicStagedWalk:
	var shot := CinematicStagedWalk.new()
	shot.role = role
	shot.duration = duration
	shot.gait_cap = 5.0
	shot.arrive_radius = 0.4
	return shot


func _hold(anchor_role: StringName, target_role: StringName, offset: Vector3, duration: float) -> CinematicLookAtHold:
	var shot := CinematicLookAtHold.new()
	shot.anchor_role = anchor_role
	shot.target_role = target_role
	shot.local_offset = offset
	shot.duration = duration
	return shot


func _sequence(id: StringName, shots: Array) -> CinematicSequence:
	var sequence := CinematicSequence.new()
	sequence.id = id
	var typed: Array[CinematicShot] = []
	for shot in shots:
		typed.append(shot)
	sequence.shots = typed
	return sequence


func _track(director: CinematicDirector) -> Dictionary:
	var started := [0]
	var finished := [0]
	var skipped := [0]
	director.cinematic_started.connect(func(_id: StringName) -> void: started[0] += 1)
	director.cinematic_finished.connect(func(_id: StringName) -> void: finished[0] += 1)
	director.cinematic_skipped.connect(func(_id: StringName) -> void: skipped[0] += 1)
	return {"started": started, "finished": finished, "skipped": skipped}


func _shoulder(character: LibertyCharacter) -> Camera3D:
	return character.get_node("CameraPivot/SpringArm3D/Camera3D") as Camera3D


func _pivot(character: LibertyCharacter) -> LibertyCameraPivot:
	return character.get_node("CameraPivot") as LibertyCameraPivot


func _adapter(character: LibertyCharacter) -> LibertyEventAdapter:
	return character.get_node("EventAdapter") as LibertyEventAdapter


func _driver(character: LibertyCharacter) -> LibertyAnimationDriver:
	return character.get_node("AnimationDriver") as LibertyAnimationDriver


func _add_performance_clip(character: LibertyCharacter) -> void:
	var tree := character.get_node("AnimationTree") as AnimationTree
	var player := tree.get_node(tree.anim_player) as AnimationPlayer
	var library := player.get_animation_library(&"")
	if library.has_animation(&"performance_test"):
		return
	var clip := Animation.new()
	clip.length = 0.4
	clip.loop_mode = Animation.LOOP_NONE
	library.add_animation(&"performance_test", clip)


func _ahead(character: LibertyCharacter, distance: float) -> Vector3:
	var forward := -character.global_basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.000001:
		forward = Vector3(0.0, 0.0, -1.0)
	else:
		forward = forward.normalized()
	var at := character.global_position + forward * distance
	at.y = character.global_position.y
	return at


func _planar_gap(a: Vector3, b: Vector3) -> float:
	var flat := a - b
	flat.y = 0.0
	return flat.length()


func _await_shoulder(character: LibertyCharacter) -> void:
	var pivot := _pivot(character)
	var near := func() -> bool:
		var expected := character.global_position + Vector3.UP * pivot.target_height
		return pivot.global_position.distance_to(expected) < 0.01
	var settled: bool = await _until(near, 90)
	Support.expect_true(settled, "pivot settles on the shoulder anchor")


func _settle(character: LibertyCharacter) -> void:
	var driver := character.get_node("AnimationDriver") as LibertyAnimationDriver
	for _i in 90:
		if character.is_on_floor() and driver.get_state() == &"Locomotion":
			return
		await _wait(1)


func _free_fixture(fixture: Dictionary) -> void:
	var director: CinematicDirector = fixture.director
	if is_instance_valid(director):
		director.free()
	var character: LibertyCharacter = fixture.character
	if is_instance_valid(character):
		character.free()
	var vehicle: LibertyVehicle = fixture.vehicle
	if is_instance_valid(vehicle):
		vehicle.free()
	var floor_body: StaticBody3D = fixture.floor
	if is_instance_valid(floor_body):
		floor_body.free()


func _until(predicate: Callable, frames: int) -> bool:
	for _i in frames:
		if predicate.call():
			return true
		await physics_frame
	return predicate.call()


func _until_frame(predicate: Callable, frames: int) -> bool:
	for _i in frames:
		if predicate.call():
			return true
		await process_frame
	return predicate.call()


func _until_msec(predicate: Callable, budget_ms: int) -> bool:
	var stamp := Time.get_ticks_msec()
	while Time.get_ticks_msec() - stamp < budget_ms:
		if predicate.call():
			return true
		await process_frame
	return predicate.call()


func _wait(frames: int) -> void:
	for _frame in frames:
		await physics_frame
		await process_frame
