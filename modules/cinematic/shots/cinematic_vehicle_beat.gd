class_name CinematicVehicleBeat
extends CinematicShot
## One reused control snapshot, submitted through the director. Skip places the sedan, then holds the borrow for one handbrake frame.

@export var steering := 0.0
@export var throttle := 0.0
@export var brake := 0.0
@export var handbrake := false
## Below 0, only duration ends the shot. 0 is a real planar-speed threshold.
@export var end_speed_mps := -1.0
@export var anchor_role: StringName

var _vehicle: LibertyVehicle
var _marker: Node3D
var _snapshot: LibertyVehicleControlSnapshot


func requires_vehicle() -> bool:
	return true


func skip_holds_borrow() -> bool:
	return true


func enter(host) -> Error:
	var err := super.enter(host)
	if err != OK:
		return err
	var player := host.resolve_role(&"player") as LibertyCharacter
	if player == null or not player.is_inside_tree():
		return ERR_BUSY
	var adapter := player.get_node_or_null("EventAdapter") as LibertyEventAdapter
	if adapter == null:
		return ERR_BUSY
	_vehicle = adapter.mounted_vehicle
	if not _vehicle_in_tree() or _vehicle.possession == null or not _vehicle.possession.control_enabled:
		return ERR_BUSY
	if not anchor_role.is_empty():
		_marker = host.resolve_role(anchor_role) as Node3D
		if _marker == null or not _marker.is_inside_tree():
			return ERR_DOES_NOT_EXIST
	_snapshot = LibertyVehicleControlSnapshot.new()
	_write_drive_fields()
	host.set_vehicle_intent(_snapshot)
	host.set_subtitle(subtitle)
	return OK


func tick(host, delta: float) -> bool:
	if not _vehicle_in_tree():
		return true
	_write_drive_fields()
	host.set_vehicle_intent(_snapshot)
	if end_speed_mps >= 0.0 and _planar_speed() <= end_speed_mps:
		return true
	return super.tick(host, delta)


func skip_to_end(host) -> void:
	var marker_ready := is_instance_valid(_marker) and _marker.is_inside_tree()
	if _vehicle_in_tree() and marker_ready:
		_vehicle.global_transform = _marker.global_transform
	if _vehicle_in_tree():
		_vehicle.linear_velocity = Vector3.ZERO
		_vehicle.angular_velocity = Vector3.ZERO
		_vehicle.sleeping = false
	if _snapshot != null:
		# Steer input 0 starts the wheel return. This does not assign the public steering field.
		_snapshot.handbrake = true
		_snapshot.throttle = 0.0
		_snapshot.brake = 0.0
		_snapshot.steering = 0.0
		_snapshot.reset = false
		_snapshot.toggle_camera = false
		host.set_vehicle_intent(_snapshot)
	_finished = true


func _write_drive_fields() -> void:
	_snapshot.steering = steering
	_snapshot.throttle = throttle
	_snapshot.brake = brake
	_snapshot.handbrake = handbrake
	_snapshot.reset = false
	_snapshot.toggle_camera = false


func _vehicle_in_tree() -> bool:
	return is_instance_valid(_vehicle) and _vehicle.is_inside_tree()


func _planar_speed() -> float:
	var velocity := _vehicle.linear_velocity
	return Vector3(velocity.x, 0.0, velocity.z).length()
