extends SceneTree

func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var scene: PackedScene = load("res://example/scenes/main.tscn")
	var app: Node = scene.instantiate()
	root.add_child(app)
	for _i in 3:
		await process_frame
	var world: Node = root.get_node("World")
	var director := app.get_node("CinematicDirector") as CinematicDirector
	var neighborhood: Node = world.scenes.get_active_world_root()
	if director.get_parent() != app or neighborhood.is_ancestor_of(director):
		_fail(1, "Director is not a child of NeighborhoodErrand")
		return
	if director.process_mode == Node.PROCESS_MODE_DISABLED:
		_fail(1, "Director process mode is disabled")
		return
	var player := neighborhood.get_node("Player") as LibertyCharacter
	var errand: Node = neighborhood.get_node("ErrandCoordinator")
	var started: Array[StringName] = []
	var marks := {"hold_before_reveal": false, "replayed": false, "save_started": false, "load_started": false}
	director.cinematic_started.connect(func(sequence_id: StringName) -> void:
		started.append(sequence_id)
		if sequence_id == &"sedan_reveal":
			marks["hold_before_reveal"] = bool(world.state.get_value(&"cinematic.delivery_hold", false))
	)
	if not errand.pick_up_package():
		_fail(2, "Package pickup failed")
		return
	if director.current_sequence_id() != &"package_glance":
		_fail(2, "Pickup did not start package_glance")
		return
	var on_save := func(_context: Dictionary) -> void:
		marks["save_started"] = true
	var on_load := func(_context: Dictionary) -> void:
		marks["load_started"] = true
	world.events.save_started.connect(on_save)
	world.events.load_started.connect(on_load)
	neighborhood._save()
	if neighborhood.status.text != "Save rejected during cinematic":
		_fail(3, "Save status was '%s'" % neighborhood.status.text)
		return
	neighborhood._load()
	if neighborhood.status.text != "Load rejected during cinematic":
		_fail(3, "Load status was '%s'" % neighborhood.status.text)
		return
	await process_frame
	await physics_frame
	if marks["save_started"] or marks["load_started"]:
		_fail(3, "Save or load started during the glance")
		return
	world.events.save_started.disconnect(on_save)
	world.events.load_started.disconnect(on_load)
	var before := player.global_transform
	if director.skip() != OK:
		_fail(4, "Glance skip was refused")
		return
	if not await _until(func() -> bool: return not director.is_sequence_active(), 3000):
		_fail(4, "Glance did not finish after skip")
		return
	if player.global_transform.origin.distance_to(before.origin) > 0.05:
		_fail(4, "Glance skip moved the player")
		return
	if not player.global_transform.basis.is_equal_approx(before.basis):
		_fail(4, "Glance skip rotated the player")
		return
	if player.is_movement_locked():
		_fail(4, "Movement stayed locked after the glance")
		return
	var pivot := player.get_node("CameraPivot") as LibertyCameraPivot
	if pivot.is_orbit_held():
		_fail(4, "Orbit hold stayed on after the glance")
		return
	var shoulder := _shoulder(player)
	if player.get_viewport().get_camera_3d() != shoulder:
		_fail(4, "Shoulder camera was not restored after the glance")
		return
	if not bool(world.state.get_value(&"cinematic.package_glance", false)):
		_fail(4, "cinematic.package_glance was not written")
		return
	var on_replay := func(sequence_id: StringName) -> void:
		if sequence_id == &"package_glance":
			marks["replayed"] = true
	director.cinematic_started.connect(on_replay)
	errand.rule_engine.emit_event(&"package_picked_up", {})
	await physics_frame
	await physics_frame
	director.cinematic_started.disconnect(on_replay)
	if marks["replayed"] or director.is_sequence_active():
		_fail(5, "A second package_picked_up replayed the glance")
		return
	if not errand.deliver_package():
		_fail(6, "Delivery failed")
		return
	if not await _until(func() -> bool: return director.current_sequence_id() == &"delivery_hold" or director.current_sequence_id() == &"sedan_reveal", 2000):
		_fail(6, "Delivery did not start a cinematic")
		return
	var settle: Script = load("res://example/tests/settle_cinematic.gd")
	await settle.settle(self)
	if director.is_sequence_active():
		_fail(6, "Delivery beats did not settle")
		return
	if not started.has(&"delivery_hold") or not started.has(&"sedan_reveal"):
		_fail(6, "Delivery did not run hold then reveal: %s" % [started])
		return
	if not marks["hold_before_reveal"]:
		_fail(6, "cinematic.delivery_hold was not set before sedan_reveal")
		return
	if not bool(world.state.get_value(&"cinematic.delivery_hold", false)) or not bool(world.state.get_value(&"cinematic.sedan_reveal", false)):
		_fail(6, "Delivery seen-flags were not both written")
		return
	if player.get_viewport().get_camera_3d() != shoulder or player.is_movement_locked():
		_fail(6, "Reveal did not return the shoulder camera and clear the lock")
		return
	player.teleport_to(Transform3D(Basis.IDENTITY, Vector3(-8, 0.1, 7)))
	await physics_frame
	neighborhood._save()
	neighborhood._interact()
	if world.scenes.get_active_world_id() != &"neighborhood" or world.current_travel_id() != 0:
		_fail(7, "Busy save still traveled")
		return
	if director.is_sequence_active() or bool(world.state.get_value(&"cinematic.home_door", false)):
		_fail(7, "Busy save wrote cinematic.home_door or left a sequence running")
		return
	marks["save_done"] = false
	world.events.save_completed.connect(func(_context: Dictionary) -> void: marks["save_done"] = true, CONNECT_ONE_SHOT)
	if not await _until(func() -> bool: return bool(marks["save_done"]), 8000):
		_fail(7, "Save did not finish")
		return
	await process_frame
	player.teleport_to(Transform3D(Basis.IDENTITY, Vector3(-8, 0.1, 7)))
	await physics_frame
	neighborhood._interact()
	var travel_id: int = world.current_travel_id()
	if travel_id == 0:
		_fail(8, "Home door did not start travel: %s" % error_string(director.last_result))
		return
	neighborhood.travel_pending = false
	neighborhood._interact()
	if world.current_travel_id() != travel_id or world.scenes.get_active_world_id() != &"neighborhood":
		_fail(8, "Second interact changed the home-door travel")
		return
	if not await _until(func() -> bool: return world.scenes.get_active_world_id() == &"home", 8000):
		_fail(8, "Home door did not arrive")
		return
	if not await _until(func() -> bool: return not director.is_sequence_active(), 3000):
		_fail(8, "Home door sequence stayed active")
		return
	await process_frame
	if not bool(world.state.get_value(&"cinematic.home_door", false)):
		_fail(8, "cinematic.home_door was not written after arrival")
		return
	if director.get_parent() != app or director.process_mode == Node.PROCESS_MODE_DISABLED:
		_fail(8, "Director was reparented or disabled by the passage")
		return
	var home: Node = world.scenes.get_active_world_root()
	if home.get_node_or_null("ErrandCoordinator") != null:
		_fail(8, "Home created an ErrandCoordinator")
		return
	var home_player := home.get_node("Player") as LibertyCharacter
	var home_shoulder := _shoulder(home_player)
	if not await _until(func() -> bool: return home_player.get_viewport().get_camera_3d() == home_shoulder, 2000):
		_fail(8, "Home shoulder camera was not current")
		return
	home._interact()
	if not await _until(func() -> bool: return world.scenes.get_active_world_id() == &"neighborhood", 8000):
		_fail(9, "Street return did not arrive")
		return
	await process_frame
	neighborhood = world.scenes.get_active_world_root()
	player = neighborhood.get_node("Player") as LibertyCharacter
	var sedan := neighborhood.get_node("Sedan") as LibertyVehicle
	var adapter := player.get_node("EventAdapter") as LibertyEventAdapter
	player.teleport_to(Transform3D(Basis.IDENTITY, Vector3(6, 0.1, -6)))
	for _i in 12:
		await physics_frame
	if not adapter.mount(sedan, &"driver_front_left").succeeded():
		_fail(10, "Mount failed: %s" % adapter.last_reason)
		return
	var seat := adapter.mounted_seat
	sedan.global_position = neighborhood.park_bay + Vector3(0, 0.4, 0)
	sedan.linear_velocity = Vector3.ZERO
	if not await _until(func() -> bool: return director.current_sequence_id() == &"tour_finish", 3000):
		_fail(10, "Parking did not start tour_finish")
		return
	sedan.freeze = true
	await physics_frame
	sedan.linear_velocity = Vector3.ZERO
	sedan.angular_velocity = Vector3.ZERO
	var parked := sedan.global_transform
	if director.skip() != OK:
		_fail(11, "Tour skip was refused")
		return
	if not await _until(func() -> bool: return not director.is_sequence_active(), 3000):
		_fail(11, "Tour finish did not end")
		return
	await physics_frame
	var gap := sedan.global_transform.origin.distance_to(parked.origin)
	var angle := sedan.global_transform.basis.get_rotation_quaternion().angle_to(parked.basis.get_rotation_quaternion())
	if gap > 0.02 or angle > 0.02:
		_fail(11, "Tour skip moved the sedan by %s m and %s rad" % [gap, angle])
		return
	var rig := sedan.get_node("CameraRig") as LibertyVehicleCameraRig
	var current := player.get_viewport().get_camera_3d()
	if current != rig.chase_camera and current != rig.hood_camera:
		_fail(11, "Tour restore did not leave the rig camera current")
		return
	if not player.is_body_suspended():
		_fail(11, "Tour restore cleared the mounted body suspension")
		return
	if adapter.mounted_vehicle != sedan or adapter.mounted_seat != seat or sedan.possession.occupant != player:
		_fail(11, "Tour skip changed occupancy")
		return
	if not bool(world.state.get_value(&"cinematic.tour_finish", false)):
		_fail(11, "cinematic.tour_finish was not written")
		return
	print("EXAMPLE_CINEMATICS_PASS")
	quit()


func _shoulder(character: LibertyCharacter) -> Camera3D:
	return character.get_node("CameraPivot/SpringArm3D/Camera3D") as Camera3D


func _until(predicate: Callable, msec: int) -> bool:
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < msec:
		if predicate.call():
			return true
		await process_frame
	return bool(predicate.call())


func _fail(code: int, message: String) -> void:
	push_error(message)
	quit(code)
