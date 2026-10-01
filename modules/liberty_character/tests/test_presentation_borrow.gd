extends SceneTree

const Support = preload("res://modules/liberty_character/tests/liberty_test_support.gd")
const Sedan = preload("res://modules/liberty_vehicle/vehicle/liberty_vehicle.tscn")
const CharacterScene = preload("res://modules/liberty_character/character/liberty_character.tscn")

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_rejected_borrow_has_no_side_effects()
	await _test_on_foot_borrow_and_release()
	await _test_suspension_and_follow()
	await _test_mounted_borrow_and_release()
	await _test_vehicle_freed_during_borrow()
	await _test_exit_tree_keeps_cinematic_camera()
	quit(Support.exit_code())


func _test_rejected_borrow_has_no_side_effects() -> void:
	var host := Node3D.new()
	root.add_child(host)
	var loose := LibertyEventAdapter.new()
	host.add_child(loose)
	var orphan := Camera3D.new()
	var cinematic := _add_cinematic()
	Support.expect_equal(loose.borrow_presentation(cinematic), 0, "borrow without a character returns 0")
	Support.expect_false(loose.is_presentation_borrowed(), "failed borrow does not hold a token")
	Support.expect_equal(loose.borrow_presentation(orphan), 0, "camera outside the tree returns 0")
	loose.free()
	host.free()
	orphan.free()

	var fixture := _spawn_on_foot()
	var adapter: LibertyEventAdapter = fixture.adapter
	var character: LibertyCharacter = fixture.character
	await _wait(8)
	var shoulder := _shoulder(character)
	var unparented := Camera3D.new()
	Support.expect_true(shoulder.current, "shoulder camera starts current")
	var token := adapter.borrow_presentation(unparented)
	Support.expect_equal(token, 0, "on-foot borrow of an unparented camera returns 0")
	Support.expect_false(adapter.is_presentation_borrowed(), "rejected borrow leaves the adapter idle")
	Support.expect_false(_pivot(character).is_orbit_held(), "rejected borrow does not hold the orbit")
	Support.expect_true(shoulder.current, "rejected borrow leaves the shoulder camera current")
	unparented.free()

	token = adapter.borrow_presentation(cinematic)
	Support.expect_true(token != 0, "a camera in the tree borrows")
	Support.expect_equal(adapter.borrow_presentation(cinematic), 0, "a second borrow returns 0")
	Support.expect_true(cinematic.current, "a rejected second borrow leaves the cinematic camera current")
	Support.expect_false(adapter.release_presentation(token + 1), "a mismatched token does not release")
	Support.expect_true(adapter.is_presentation_borrowed(), "a mismatched release keeps the borrow")
	Support.expect_true(adapter.release_presentation(token), "the matching token releases")
	Support.expect_false(adapter.is_presentation_borrowed(), "release clears the borrow")
	Support.expect_true(shoulder.current, "on-foot release restores the shoulder camera")
	_free_fixture(fixture)
	cinematic.free()


func _test_on_foot_borrow_and_release() -> void:
	var fixture := _spawn_mounted_layout()
	var adapter: LibertyEventAdapter = fixture.adapter
	var character: LibertyCharacter = fixture.character
	var vehicle: LibertyVehicle = fixture.vehicle
	await _wait(12)
	var shoulder := _shoulder(character)
	var cinematic := _add_cinematic()
	var mobile := character.get_node("MobileControls") as LibertyMobileControls
	Support.expect_false(mobile.is_suspended(), "on-foot controls start unsuspended")
	Support.expect_equal(adapter._stored_camera, null, "on-foot borrow starts with no stored camera")
	var occupancy: Array[int] = [0]
	(character.get_node("Events") as LibertyEvents).occupancy_changed.connect(func(_v, _s, _o, _mounted, _cause): occupancy[0] += 1)
	var token := adapter.borrow_presentation(cinematic)
	Support.expect_true(adapter.is_presentation_borrowed(), "on-foot borrow is held")
	Support.expect_true(cinematic.current, "borrow makes the external camera current")
	Support.expect_false(shoulder.current, "borrow leaves the shoulder camera")
	Support.expect_true(_pivot(character).is_orbit_held(), "borrow holds the orbit")
	Support.expect_true(mobile.is_suspended(), "borrow suspends on-foot controls")
	Support.expect_equal(adapter._stored_camera, null, "on-foot borrow does not write _stored_camera")
	adapter.interact()
	Support.expect_equal(adapter.mounted_vehicle, null, "interact does not mount while borrowed")
	Support.expect_equal(occupancy[0], 0, "a blocked interact emits no occupancy")
	Support.expect_true(adapter.release_presentation(token), "on-foot release succeeds")
	Support.expect_false(_pivot(character).is_orbit_held(), "release clears the orbit hold")
	Support.expect_true(shoulder.current, "release restores the gameplay camera")
	Support.expect_false(cinematic.current, "release leaves the cinematic camera")
	Support.expect_false(mobile.is_suspended(), "release restores the unsuspended on-foot controls")
	adapter.interact()
	Support.expect_true(adapter.mounted_vehicle == vehicle, "interact mounts again after release")
	Support.expect_equal(occupancy[0], 1, "the later mount emits occupancy")
	_free_fixture(fixture)
	cinematic.free()


func _test_suspension_and_follow() -> void:
	var fixture := _spawn_on_foot()
	var adapter: LibertyEventAdapter = fixture.adapter
	var character: LibertyCharacter = fixture.character
	await _wait(8)
	var mobile := character.get_node("MobileControls") as LibertyMobileControls
	var overlay := character.get_node("VehicleMobileControls") as LibertyVehicleMobileControls
	mobile.set_suspended(true)
	overlay.set_active(true)
	var cinematic := _add_cinematic()
	var token := adapter.borrow_presentation(cinematic)
	Support.expect_false(overlay.active, "borrow suspends a vehicle overlay that was active")
	Support.expect_true(mobile.is_suspended(), "borrow keeps on-foot controls suspended")
	Support.expect_true(adapter.release_presentation(token), "suspended on-foot release succeeds")
	Support.expect_true(mobile.is_suspended(), "on-foot release restores the pre-borrow suspension")
	Support.expect_false(overlay.active, "on-foot release leaves the vehicle overlay inactive")
	mobile.set_suspended(false)

	var marker := Node3D.new()
	marker.position = Vector3(2.0, 1.0, -3.0)
	root.add_child(marker)
	var pivot := _pivot(character)
	pivot.set_follow_override(marker)
	token = adapter.borrow_presentation(cinematic)
	Support.expect_true(adapter.release_presentation(token, true), "preserve_follow release succeeds")
	Support.expect_equal(pivot._follow_override, marker, "preserve_follow keeps the follow override")
	Support.expect_false(pivot.is_orbit_held(), "preserve_follow still clears the orbit hold")
	token = adapter.borrow_presentation(cinematic)
	Support.expect_true(adapter.release_presentation(token, false), "normal release succeeds")
	Support.expect_equal(pivot._follow_override, null, "release without preserve_follow clears the follow override")
	marker.free()
	_free_fixture(fixture)
	cinematic.free()


func _test_mounted_borrow_and_release() -> void:
	var fixture := _spawn_mounted_layout()
	var adapter: LibertyEventAdapter = fixture.adapter
	var character: LibertyCharacter = fixture.character
	var vehicle: LibertyVehicle = fixture.vehicle
	await _wait(12)
	var occupancy: Array[int] = [0]
	(character.get_node("Events") as LibertyEvents).occupancy_changed.connect(func(_v, _s, _o, _mounted, _cause): occupancy[0] += 1)
	Support.expect_true(adapter.mount(vehicle, &"driver_front_left").succeeded(), "fixture mounts")
	Support.expect_equal(occupancy[0], 1, "mount emits occupancy once")
	var shoulder := _shoulder(character)
	var chase: Camera3D = vehicle.camera_rig.chase_camera
	var mobile := character.get_node("MobileControls") as LibertyMobileControls
	var overlay := character.get_node("VehicleMobileControls") as LibertyVehicleMobileControls
	Support.expect_true(chase.current, "mount makes the chase camera current")
	Support.expect_equal(adapter._stored_camera, shoulder, "mount stores the shoulder camera")
	Support.expect_true(mobile.is_suspended() and overlay.active, "mount suspends on-foot controls and shows the vehicle overlay")
	var cinematic := _add_cinematic()
	var token := adapter.borrow_presentation(cinematic)
	Support.expect_equal(occupancy[0], 1, "borrow does not emit occupancy")
	Support.expect_equal(adapter._stored_camera, shoulder, "borrow does not overwrite _stored_camera")
	Support.expect_true(cinematic.current and not chase.current, "borrow replaces the rig camera with the cinematic camera")
	Support.expect_true(_pivot(character).is_orbit_held(), "mounted borrow holds the orbit")
	Support.expect_true(mobile.is_suspended(), "mounted borrow leaves on-foot controls suspended")
	Support.expect_false(overlay.active, "mounted borrow suspends the active vehicle overlay")
	adapter.interact()
	Support.expect_true(adapter.mounted_vehicle == vehicle, "interact does not dismount while borrowed")
	Support.expect_equal(occupancy[0], 1, "a blocked dismount emits no occupancy")

	var ignored := LibertyVehicleControlSnapshot.new()
	ignored.throttle = 9.0
	adapter.set_borrowed_controls(token + 3, ignored)
	var snapshot := LibertyVehicleControlSnapshot.new()
	snapshot.throttle = 1.0
	snapshot.toggle_camera = true
	snapshot.reset = true
	adapter.allow_vehicle_reset = true
	adapter.set_borrowed_controls(token, snapshot)
	var moved: Vector3 = vehicle.global_position + Vector3(3.0, 0.0, 0.0)
	vehicle.global_position = moved
	await _wait(1)
	Support.expect_true(is_equal_approx(vehicle.controls.throttle, 1.0), "borrowed throttle is submitted")
	Support.expect_false(vehicle.controls.toggle_camera, "borrow strips toggle_camera")
	Support.expect_false(vehicle.controls.reset, "borrow strips reset")
	Support.expect_false(vehicle.camera_rig.hood_mode, "stripped toggle does not switch cameras")
	Support.expect_true(vehicle.global_position.distance_to(moved) < 0.05, "stripped reset does not return the vehicle to spawn")
	Support.expect_true(adapter.release_presentation(token), "mounted release succeeds")
	Support.expect_equal(occupancy[0], 1, "mounted release does not emit occupancy")
	Support.expect_true(chase.current, "mounted release makes the chase camera current")
	Support.expect_false(shoulder.current, "mounted release does not restore the shoulder camera")
	Support.expect_true(is_instance_valid(adapter.mounted_vehicle), "mounted release leaves the seat claimed")
	Support.expect_true(vehicle.possession.control_enabled, "mounted release leaves control enabled")
	Support.expect_true(mobile.is_suspended(), "mounted release restores on-foot suspension")
	Support.expect_true(overlay.active, "mounted release restores the vehicle overlay")
	Support.expect_false(_pivot(character).is_orbit_held(), "mounted release clears the orbit hold")
	Support.expect_equal(adapter._stored_camera, shoulder, "mounted release leaves _stored_camera to the mount")
	await _wait(1)
	var controls: LibertyVehicleControlSnapshot = vehicle.controls
	Support.expect_true(
		is_zero_approx(controls.throttle) and is_zero_approx(controls.brake) and is_zero_approx(controls.steering) and not controls.reset and not controls.toggle_camera,
		"the frame after release submits a fresh from_input snapshot"
	)

	vehicle.camera_rig.toggle_mode()
	Support.expect_true(vehicle.camera_rig.hood_mode, "direct toggle enters hood mode")
	token = adapter.borrow_presentation(cinematic)
	Support.expect_true(adapter.release_presentation(token), "hood release succeeds")
	Support.expect_true(vehicle.camera_rig.hood_camera.current, "mounted release makes the hood camera current")
	adapter.dismount()
	Support.expect_true(shoulder.current, "a later dismount still restores the stored shoulder camera")
	Support.expect_equal(occupancy[0], 2, "dismount emits the matching occupancy")
	_free_fixture(fixture)
	cinematic.free()


func _test_vehicle_freed_during_borrow() -> void:
	var fixture := _spawn_mounted_layout()
	var adapter: LibertyEventAdapter = fixture.adapter
	var character: LibertyCharacter = fixture.character
	var vehicle: LibertyVehicle = fixture.vehicle
	await _wait(12)
	Support.expect_true(adapter.mount(vehicle, &"driver_front_left").succeeded(), "teardown fixture mounts")
	var shoulder := _shoulder(character)
	var cinematic := _add_cinematic()
	var token := adapter.borrow_presentation(cinematic)
	character.set_movement_locked(true)
	var mobile := character.get_node("MobileControls") as LibertyMobileControls
	vehicle.queue_free()
	fixture.vehicle = null
	await _wait(2)
	Support.expect_true(cinematic.current, "freeing the vehicle keeps the cinematic camera current")
	Support.expect_false(shoulder.current, "teardown during a borrow does not restore the shoulder camera")
	Support.expect_true(character.is_movement_locked(), "the movement lock survives vehicle teardown")
	Support.expect_false(character.is_body_suspended(), "teardown still unsuspends the body")
	Support.expect_true(mobile.is_suspended(), "overlays stay suspended until release")
	var position: Vector3 = character.global_position
	Input.action_press(&"liberty_move_forward")
	await _wait(1)
	Input.action_release(&"liberty_move_forward")
	Support.expect_true(character.planar_speed < 0.02, "move input does not walk while the lock is held (%.3f)" % character.planar_speed)
	Support.expect_true(character.global_position.distance_to(position) < 0.02, "move input does not displace the locked body")
	Support.expect_true(adapter.release_presentation(token), "release after teardown succeeds")
	Support.expect_true(character.is_movement_locked(), "release does not clear the movement lock")
	Support.expect_true(shoulder.current, "release after teardown restores the stored shoulder camera")
	Support.expect_false(cinematic.current, "release after teardown leaves the cinematic camera")
	Support.expect_false(_pivot(character).is_orbit_held(), "release after teardown clears the orbit hold")
	Support.expect_false(mobile.is_suspended(), "release after a broken mount unsuspends on-foot controls")
	character.set_movement_locked(false)
	_free_fixture(fixture)
	cinematic.free()


func _test_exit_tree_keeps_cinematic_camera() -> void:
	var fixture := _spawn_mounted_layout()
	var adapter: LibertyEventAdapter = fixture.adapter
	var character: LibertyCharacter = fixture.character
	var vehicle: LibertyVehicle = fixture.vehicle
	await _wait(12)
	Support.expect_true(adapter.mount(vehicle, &"driver_front_left").succeeded(), "exit fixture mounts")
	var shoulder := _shoulder(character)
	var cinematic := _add_cinematic()
	var token := adapter.borrow_presentation(cinematic)
	var rig: LibertyVehicleCameraRig = vehicle.camera_rig
	root.remove_child(character)
	Support.expect_true(cinematic.current, "leaving the tree keeps the cinematic camera current")
	Support.expect_false(shoulder.current, "leaving the tree does not make the stored camera current")
	Support.expect_true(rig.active, "leaving the tree does not deactivate the rig")
	Support.expect_equal(vehicle.possession.occupant, null, "leaving the tree clears the seat claim")
	root.add_child(character)
	await _wait(2)
	Support.expect_true(cinematic.current, "reattach does not make the stored camera current while borrowed")
	Support.expect_false(shoulder.current, "reattach skips the shoulder make_current while borrowed")
	Support.expect_true(adapter.release_presentation(token), "release after detach succeeds")
	Support.expect_true(rig.chase_camera.current, "release uses the gameplay camera while it remains in the tree")
	Support.expect_false(_pivot(character).is_orbit_held(), "release after detach clears the orbit hold")
	_free_fixture(fixture)
	cinematic.free()


func _spawn_on_foot() -> Dictionary:
	var floor_body := _add_floor(Vector3.ZERO)
	var character := CharacterScene.instantiate() as LibertyCharacter
	root.add_child(character)
	return {"floor": floor_body, "character": character, "adapter": character.get_node("EventAdapter") as LibertyEventAdapter, "vehicle": null}


func _spawn_mounted_layout() -> Dictionary:
	var floor_body := _add_floor(Vector3(40.0, 0.0, 0.0))
	var vehicle := Sedan.instantiate() as LibertyVehicle
	vehicle.position = Vector3(40.0, 0.0, 0.0)
	vehicle.freeze = true
	root.add_child(vehicle)
	var character := CharacterScene.instantiate() as LibertyCharacter
	character.position = Vector3(38.65, 0.02, -0.4)
	root.add_child(character)
	return {
		"floor": floor_body,
		"character": character,
		"adapter": character.get_node("EventAdapter") as LibertyEventAdapter,
		"vehicle": vehicle,
	}


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


func _add_cinematic() -> Camera3D:
	var cinematic := Camera3D.new()
	cinematic.name = "CinematicCamera"
	root.add_child(cinematic)
	return cinematic


func _shoulder(character: LibertyCharacter) -> Camera3D:
	return character.get_node("CameraPivot/SpringArm3D/Camera3D") as Camera3D


func _pivot(character: LibertyCharacter) -> LibertyCameraPivot:
	return character.get_node("CameraPivot") as LibertyCameraPivot


func _free_fixture(fixture: Dictionary) -> void:
	var character: LibertyCharacter = fixture.character
	if is_instance_valid(character):
		character.free()
	var vehicle: LibertyVehicle = fixture.vehicle
	if is_instance_valid(vehicle):
		vehicle.free()
	var floor_body: StaticBody3D = fixture.floor
	if is_instance_valid(floor_body):
		floor_body.free()


func _wait(frames: int) -> void:
	for _frame in frames:
		await physics_frame
		await process_frame
