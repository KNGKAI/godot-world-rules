class_name LibertyVehiclePossession
extends Node
## Claims and exit queries have no dependency on the sedan's handling model.
signal teardown_requested(result: LibertyVehicleContracts.DismountResult)
signal control_disabled
const DRIVER_ID: StringName = &"driver_front_left"
const VEHICLE_MASK := 16
const WORLD_MASK := 1
var occupant: LibertyCharacter
var control_enabled := false
var last_safe_transform := Transform3D.IDENTITY
var has_safe_transform := false
var cached_exit := Transform3D.IDENTITY
var has_cached_exit := false
var cached_vehicle_position := Vector3.ZERO
var _destroying := false
var vehicle: Node3D
var seat: LibertyVehicleSeat
var _exit_capsule: CapsuleShape3D

func _ready() -> void:
	vehicle = get_parent() as Node3D
	seat = vehicle.get_node_or_null("DriverSeat") as LibertyVehicleSeat
	_exit_capsule = CapsuleShape3D.new()
	_exit_capsule.radius = 0.4
	_exit_capsule.height = 1.8
	cached_vehicle_position = vehicle.global_position
	vehicle.tree_exiting.connect(_on_vehicle_exiting)

func request_mount(who: LibertyCharacter, seat_id: StringName) -> LibertyVehicleContracts.MountResult:
	var result := LibertyVehicleContracts.MountResult.new()
	result.seat_id = seat_id
	if seat_id != DRIVER_ID or not is_instance_valid(seat): result.reason = &"seat not found"
	elif _destroying or not vehicle.is_inside_tree() or vehicle.is_queued_for_deletion(): result.reason = &"vehicle unavailable or destroying"
	elif is_instance_valid(occupant): result.reason = &"seat already occupied"
	elif not is_instance_valid(who) or not who.is_inside_tree(): result.reason = &"occupant unavailable"
	elif is_instance_valid(who.vehicle_possession): result.reason = &"occupant already mounted elsewhere"
	elif who.is_body_suspended() or who.is_traversal_locked() or (is_instance_valid(who.ragdoll) and (who.ragdoll.is_active() or who.ragdoll.is_reacting())): result.reason = &"occupant busy"
	elif not who.is_on_floor(): result.reason = &"occupant not grounded"
	elif not seat.overlaps_body(who): result.reason = &"occupant not overlapping seat"
	else:
		occupant = who
		who.vehicle_possession = self
		who.tree_exiting.connect(_on_occupant_exiting)
		has_safe_transform = false
		has_cached_exit = false
		result.status = LibertyVehicleContracts.Status.SUCCESS
		result.occupant = who
		result.camera_anchor = get_camera_anchor(seat_id)
	return result

func record_safe_transform(value: Transform3D) -> void:
	last_safe_transform = value
	has_safe_transform = true
	cached_vehicle_position = vehicle.global_position

func request_dismount(seat_id: StringName) -> LibertyVehicleContracts.DismountResult:
	var result := LibertyVehicleContracts.DismountResult.new()
	result.seat_id = seat_id
	if seat_id != DRIVER_ID: result.reason = &"seat not found"
	elif _destroying or not vehicle.is_inside_tree() or vehicle.is_queued_for_deletion(): result.reason = &"vehicle unavailable or destroying"
	elif not is_instance_valid(occupant): result.reason = &"dismount requested from an unoccupied seat"
	else:
		var probe := find_exit()
		if not probe.succeeded(): return probe
		result = probe
		_release_claim()
	return result

func set_control_enabled(seat_id: StringName, enabled: bool) -> void:
	if seat_id == DRIVER_ID:
		control_enabled = enabled and is_instance_valid(occupant) and not _destroying

func get_camera_anchor(seat_id: StringName) -> Node3D:
	if seat_id != DRIVER_ID or not is_instance_valid(seat): return null
	return seat.get_camera_anchor()

func find_exit() -> LibertyVehicleContracts.DismountResult:
	var result := LibertyVehicleContracts.DismountResult.new()
	result.seat_id = DRIVER_ID
	result.occupant = occupant
	result.reason = &"no valid exit location"
	var candidates: Array[Transform3D] = []
	var marker := seat.get_exit_marker()
	if is_instance_valid(marker): candidates.append(marker.global_transform)
	# Left, clockwise when viewed from above. Bounded, local probes only.
	for index in 8:
		var angle := index * TAU / 8.0
		var offset := Vector3(-cos(angle), 0.0, -sin(angle)) * 2.6
		var value := Transform3D(Basis(Vector3.UP, vehicle.global_rotation.y), vehicle.to_global(offset))
		candidates.append(value)
	if has_safe_transform: candidates.append(last_safe_transform)
	for candidate in candidates:
		var probe := probe_exit(candidate)
		if probe.succeeded(): return probe
	return result

func probe_exit(candidate: Transform3D) -> LibertyVehicleContracts.DismountResult:
	# Query and place the same upright capsule, preserving projected forward yaw.
	var yaw := atan2(candidate.basis.z.x, candidate.basis.z.z)
	candidate.basis = Basis(Vector3.UP, yaw)
	var result := LibertyVehicleContracts.DismountResult.new()
	result.occupant = occupant
	result.seat_id = DRIVER_ID
	result.reason = &"no valid exit location"
	var space := vehicle.get_world_3d().direct_space_state
	var ray := PhysicsRayQueryParameters3D.create(candidate.origin + Vector3.UP * 0.25, candidate.origin + Vector3.DOWN * 2.0, WORLD_MASK)
	var floor_hit := space.intersect_ray(ray)
	if floor_hit.is_empty(): return result
	var normal: Vector3 = floor_hit.normal
	var floor_angle := occupant.floor_max_angle if is_instance_valid(occupant) else PI / 4.0
	if normal.angle_to(Vector3.UP) > floor_angle: return result
	candidate.origin = floor_hit.position
	var shape := PhysicsShapeQueryParameters3D.new()
	shape.shape = _exit_capsule
	shape.transform = Transform3D(candidate.basis, candidate.origin + Vector3.UP * 0.9)
	shape.collision_mask = VEHICLE_MASK
	if not space.intersect_shape(shape, 1).is_empty(): return result
	result.status = LibertyVehicleContracts.Status.SUCCESS
	result.reason = &""
	result.exit_transform = candidate
	return result

func _physics_process(_delta: float) -> void:
	if is_instance_valid(occupant) and occupant.is_inside_tree(): cache_exit()
	elif occupant != null:
		_release_claim()

func cache_exit() -> void:
	cached_vehicle_position = vehicle.global_position
	var probe := find_exit()
	if probe.succeeded():
		cached_exit = probe.exit_transform
		has_cached_exit = true

func _release_claim() -> void:
	control_enabled = false
	control_disabled.emit()
	if is_instance_valid(occupant) and occupant.tree_exiting.is_connected(_on_occupant_exiting):
		occupant.tree_exiting.disconnect(_on_occupant_exiting)
	if is_instance_valid(occupant) and occupant.vehicle_possession == self:
		occupant.vehicle_possession = null
	occupant = null

## An adapter exiting with its occupant releases synchronously, using cached data.
func release_occupant(who: LibertyCharacter) -> LibertyVehicleContracts.DismountResult:
	if who != occupant or not is_instance_valid(occupant):
		return LibertyVehicleContracts.DismountResult.new()
	var result := _cached_result()
	_release_claim()
	return result

func _on_occupant_exiting() -> void:
	# Raw claims have no adapter lifecycle; still release their departing occupant.
	_release_claim()

func _cached_result() -> LibertyVehicleContracts.DismountResult:
	var result := LibertyVehicleContracts.DismountResult.new()
	result.status = LibertyVehicleContracts.Status.SUCCESS
	result.occupant = occupant
	result.seat_id = DRIVER_ID
	if has_cached_exit:
		result.exit_transform = cached_exit
		result.cause = &"teardown_grounded"
	elif has_safe_transform:
		result.exit_transform = last_safe_transform
		result.cause = &"teardown_best_effort"
	else:
		result.exit_transform = Transform3D(Basis.IDENTITY, cached_vehicle_position)
		result.cause = &"teardown_best_effort"
	return result

func _on_vehicle_exiting() -> void:
	_destroying = true
	if not is_instance_valid(occupant):
		_release_claim()
		return
	# Children have exited. No scene transform reads or physics queries here.
	teardown_requested.emit(_cached_result())
	_release_claim()
