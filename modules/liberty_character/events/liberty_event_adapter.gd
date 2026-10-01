class_name LibertyEventAdapter
extends Node
## Only integration boundary and only emitter of occupancy_changed.
@export var events_path: NodePath = ^"../Events"
@export var allow_vehicle_reset := false
var events: LibertyEvents:
	get: return get_node_or_null(events_path) as LibertyEvents
var mounted_vehicle: LibertyVehicle
var mounted_seat: StringName = &""
var last_reason: StringName = &""
var _character: LibertyCharacter
var _stored_camera: Camera3D
var _vehicle_id := 0
var _interaction_pending := false
var _mobile: LibertyMobileControls
var _vehicle_mobile: LibertyVehicleMobileControls
var _camera_restore_pending := false
var _pending_restore_transform := Transform3D.IDENTITY
var _presentation_token := 0
var _next_presentation_token := 0
var _borrowed_gameplay_camera: Camera3D
var _borrowed_external_camera: Camera3D
var _borrowed_controls: LibertyVehicleControlSnapshot
var _borrow_on_foot_was_suspended := false
var _borrow_vehicle_overlay_was_active := false
var _borrow_mount_broken := false

func _ready() -> void:
	if events == null:
		push_warning("LibertyEventAdapter could not resolve LibertyEvents at %s" % events_path)
	_character = get_parent() as LibertyCharacter
	process_physics_priority = -20
	if _character != null: call_deferred("_setup_mobile")

func _setup_mobile() -> void:
	if not is_instance_valid(_character) or not _character.is_inside_tree(): return
	_mobile = _character.get_node_or_null("MobileControls") as LibertyMobileControls
	_vehicle_mobile = LibertyVehicleMobileControls.new()
	_vehicle_mobile.name = "VehicleMobileControls"
	if _mobile != null:
		_vehicle_mobile.force_visible = _mobile.force_visible
		_mobile.add_custom_button("ENTER", Color(0.1, 0.55, 0.8, 0.8), request_interaction)
	_character.add_child(_vehicle_mobile)
	_vehicle_mobile.interact_pressed.connect(request_interaction)

func request_interaction() -> void:
	_interaction_pending = true

func _unhandled_input(event: InputEvent) -> void:
	if _character != null and event.is_action_pressed(&"liberty_interact") and not event.is_echo():
		request_interaction()
		get_viewport().set_input_as_handled()

func _physics_process(_delta: float) -> void:
	if _interaction_pending:
		_interaction_pending = false
		interact()
	if is_instance_valid(mounted_vehicle) and mounted_vehicle.possession.control_enabled:
		if _presentation_token != 0:
			var snapshot := _borrowed_controls
			if snapshot == null:
				snapshot = LibertyVehicleControlSnapshot.new()
				_borrowed_controls = snapshot
			snapshot.toggle_camera = false
			snapshot.reset = false
			mounted_vehicle.submit_controls(snapshot)
		else:
			mounted_vehicle.submit_controls(LibertyVehicleControlSnapshot.from_input(allow_vehicle_reset))

func interact() -> void:
	if _presentation_token != 0:
		return
	if is_instance_valid(mounted_vehicle):
		dismount()
		return
	if not is_instance_valid(_character): return
	var nearest: LibertyVehicle
	var nearest_distance := INF
	var nearest_id := 0
	for node in get_tree().get_nodes_in_group(&"liberty_vehicle_seat"):
		var seat := node as LibertyVehicleSeat
		if seat == null or seat.seat_id != LibertyVehicleSeat.DRIVER_ID or not seat.overlaps_body(_character): continue
		var vehicle := seat.get_parent() as LibertyVehicle
		if vehicle == null or vehicle.is_queued_for_deletion() or is_instance_valid(vehicle.possession.occupant): continue
		var distance := seat.global_position.distance_squared_to(_character.global_position)
		var id := vehicle.get_instance_id()
		if distance < nearest_distance or (is_equal_approx(distance, nearest_distance) and id < nearest_id):
			nearest = vehicle
			nearest_distance = distance
			nearest_id = id
	if nearest != null: mount(nearest, LibertyVehicleSeat.DRIVER_ID)

func mount(vehicle: LibertyVehicle, seat_id: StringName) -> LibertyVehicleContracts.MountResult:
	var rejected := LibertyVehicleContracts.MountResult.new()
	if not is_instance_valid(_character) or not is_instance_valid(vehicle):
		rejected.reason = &"vehicle unavailable or destroying"
		return rejected
	if is_instance_valid(mounted_vehicle):
		rejected.reason = &"occupant already mounted elsewhere"
		return rejected
	var result := vehicle.request_mount(_character, seat_id)
	last_reason = result.reason
	if not result.succeeded(): return result
	vehicle.possession.record_safe_transform(_character.global_transform)
	_stored_camera = get_viewport().get_camera_3d()
	mounted_vehicle = vehicle
	mounted_seat = seat_id
	_vehicle_id = vehicle.get_instance_id()
	vehicle.possession.teardown_requested.connect(_on_teardown)
	_character.set_body_suspended(true)
	vehicle.possession.cache_exit()
	var rig := _character.get_node_or_null("Rig") as Node3D
	if rig != null: rig.visible = false
	if _mobile != null: _mobile.set_suspended(true)
	if _vehicle_mobile != null:
		_vehicle_mobile.force_visible = _mobile.force_visible if _mobile != null else false
		_vehicle_mobile.set_active(true)
	vehicle.set_control_enabled(seat_id, true)
	vehicle.camera_rig.activate(result.camera_anchor)
	_emit_occupancy(true, &"mount")
	return result

func dismount() -> LibertyVehicleContracts.DismountResult:
	var rejected := LibertyVehicleContracts.DismountResult.new()
	if not is_instance_valid(mounted_vehicle):
		rejected.reason = &"dismount requested from an unoccupied seat"
		return rejected
	var result := mounted_vehicle.request_dismount(mounted_seat)
	last_reason = result.reason
	if result.succeeded(): _restore_character(result)
	return result

func _on_teardown(result: LibertyVehicleContracts.DismountResult) -> void:
	_restore_character(result)

func _restore_character(result: LibertyVehicleContracts.DismountResult, defer_camera: bool = false) -> void:
	if not is_instance_valid(_character):
		mounted_vehicle = null
		mounted_seat = &""
		return
	var borrowed := _presentation_token != 0
	if _character.is_inside_tree(): _character.global_transform = result.exit_transform
	else: _character.transform = result.exit_transform
	_character.reset_physics_interpolation()
	var rig := _character.get_node_or_null("Rig") as Node3D
	if rig != null: rig.visible = true
	if is_instance_valid(_vehicle_mobile): _vehicle_mobile.set_active(false)
	if is_instance_valid(_mobile) and not borrowed: _mobile.set_suspended(false)
	_character.set_body_suspended(false)
	var pivot := _character.get_node_or_null(_character.camera_pivot_path) as LibertyCameraPivot
	if not defer_camera and not borrowed and pivot != null and pivot.is_inside_tree():
		pivot.clear_follow_override()
		pivot.snap_to_target()
	if not defer_camera and not borrowed and is_instance_valid(_stored_camera) and _stored_camera.is_inside_tree():
		_stored_camera.make_current()
	if is_instance_valid(mounted_vehicle):
		if not borrowed and is_instance_valid(mounted_vehicle.camera_rig):
			mounted_vehicle.camera_rig.deactivate()
		mounted_vehicle.set_control_enabled(mounted_seat, false)
		if mounted_vehicle.possession.teardown_requested.is_connected(_on_teardown):
			mounted_vehicle.possession.teardown_requested.disconnect(_on_teardown)
	_emit_occupancy(false, result.cause)
	mounted_vehicle = null
	mounted_seat = &""
	if borrowed:
		_borrow_mount_broken = true
		if is_instance_valid(_borrowed_external_camera) and _borrowed_external_camera.is_inside_tree():
			_borrowed_external_camera.make_current()
	if defer_camera:
		_camera_restore_pending = true
		_pending_restore_transform = result.exit_transform
	elif not borrowed:
		_stored_camera = null

func _emit_occupancy(mounted: bool, cause: StringName) -> void:
	if events != null:
		events.occupancy_changed.emit(_vehicle_id, mounted_seat, _character.get_instance_id(), mounted, cause)

func _exit_tree() -> void:
	if is_instance_valid(mounted_vehicle) and is_instance_valid(_character):
		var result := mounted_vehicle.possession.release_occupant(_character)
		if result.succeeded(): _restore_character(result, true)

func _enter_tree() -> void:
	if _camera_restore_pending: call_deferred("_resume_after_attach")

func _resume_after_attach() -> void:
	if not is_instance_valid(_character) or not _character.is_inside_tree(): return
	_character.global_transform = _pending_restore_transform
	_character.reset_physics_interpolation()
	var pivot := _character.get_node_or_null(_character.camera_pivot_path) as LibertyCameraPivot
	if pivot != null:
		pivot.clear_follow_override()
		pivot.snap_to_target()
	if _presentation_token == 0 and is_instance_valid(_stored_camera) and _stored_camera.is_inside_tree():
		_stored_camera.make_current()
	if _presentation_token == 0:
		_stored_camera = null
	_camera_restore_pending = false


## Borrow the gameplay camera and, while mounted, the control snapshot. Never writes _stored_camera.
func borrow_presentation(external_camera: Camera3D) -> int:
	if _presentation_token != 0:
		return 0
	if not is_instance_valid(external_camera) or not external_camera.is_inside_tree():
		return 0
	if not is_instance_valid(_character):
		return 0
	_borrow_on_foot_was_suspended = _mobile.is_suspended() if is_instance_valid(_mobile) else false
	_borrow_vehicle_overlay_was_active = _vehicle_mobile.active if is_instance_valid(_vehicle_mobile) else false
	if is_instance_valid(mounted_vehicle) and is_instance_valid(mounted_vehicle.camera_rig):
		var rig := mounted_vehicle.camera_rig
		_borrowed_gameplay_camera = rig.hood_camera if rig.hood_mode else rig.chase_camera
	else:
		_borrowed_gameplay_camera = get_viewport().get_camera_3d()
	if is_instance_valid(_mobile):
		_mobile.set_suspended(true)
	if _borrow_vehicle_overlay_was_active and is_instance_valid(_vehicle_mobile):
		_vehicle_mobile.set_active(false)
	var pivot := _character.get_node_or_null(_character.camera_pivot_path) as LibertyCameraPivot
	if pivot != null:
		pivot.set_orbit_held(true)
	_borrowed_controls = LibertyVehicleControlSnapshot.new()
	_borrow_mount_broken = false
	_borrowed_external_camera = external_camera
	_next_presentation_token += 1
	_presentation_token = _next_presentation_token
	external_camera.make_current()
	return _presentation_token


func set_borrowed_controls(token: int, snapshot: LibertyVehicleControlSnapshot) -> void:
	if token == 0 or token != _presentation_token or snapshot == null:
		return
	_borrowed_controls = snapshot


func release_presentation(token: int, preserve_follow: bool = false) -> bool:
	if token == 0 or token != _presentation_token:
		return false
	var pivot: LibertyCameraPivot = null
	if is_instance_valid(_character):
		pivot = _character.get_node_or_null(_character.camera_pivot_path) as LibertyCameraPivot
	if pivot != null:
		pivot.set_orbit_held(false)
	var mounted_intact := is_instance_valid(mounted_vehicle) and not _borrow_mount_broken
	if mounted_intact:
		var rig := mounted_vehicle.camera_rig
		if is_instance_valid(rig):
			rig.activate(mounted_vehicle.get_camera_anchor(mounted_seat))
		if is_instance_valid(_vehicle_mobile):
			_vehicle_mobile.set_active(_borrow_vehicle_overlay_was_active)
		if is_instance_valid(_mobile):
			_mobile.set_suspended(_borrow_on_foot_was_suspended)
	else:
		if not preserve_follow and pivot != null and pivot.is_inside_tree():
			pivot.clear_follow_override()
			pivot.snap_to_target()
		if is_instance_valid(_borrowed_gameplay_camera) and _borrowed_gameplay_camera.is_inside_tree():
			_borrowed_gameplay_camera.make_current()
		elif is_instance_valid(_stored_camera) and _stored_camera.is_inside_tree():
			_stored_camera.make_current()
		if is_instance_valid(_mobile):
			if _borrow_mount_broken:
				_mobile.set_suspended(false)
			else:
				_mobile.set_suspended(_borrow_on_foot_was_suspended)
		if is_instance_valid(_vehicle_mobile):
			_vehicle_mobile.set_active(false)
	_presentation_token = 0
	_borrowed_gameplay_camera = null
	_borrowed_external_camera = null
	_borrowed_controls = null
	_borrow_mount_broken = false
	return true


func is_presentation_borrowed() -> bool:
	return _presentation_token != 0
