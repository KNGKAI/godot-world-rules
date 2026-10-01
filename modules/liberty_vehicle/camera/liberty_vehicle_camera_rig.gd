class_name LibertyVehicleCameraRig
extends Node3D
## The rig owns both cameras; seat anchors remain ordinary tracking targets.
@export var chase_offset := Vector3(0.0, 3.0, 7.6)
@export var look_height := 0.9
@export var position_smoothing := 5.5
@export var rotation_smoothing := 7.0
@export var base_fov := 68.0
@export var high_speed_fov := 74.0
@export var full_fov_speed := 38.0
@export var fov_smoothing := 3.5
var target: VehicleBody3D
var anchor: Node3D
var hood_marker: Node3D
var chase_camera: Camera3D
var hood_camera: Camera3D
var hood_mode := false
var active := false
var collision_mask := 17
var _sphere: SphereShape3D

func _ready() -> void:
	target = get_parent() as VehicleBody3D
	chase_camera = get_node("ChaseCamera") as Camera3D
	hood_camera = get_node("HoodCamera") as Camera3D
	hood_marker = target.get_node("HoodCameraMarker") as Node3D
	set_as_top_level(true)
	_sphere = SphereShape3D.new()
	_sphere.radius = 0.3
	chase_camera.fov = base_fov
	hood_camera.fov = base_fov
	# Children exit in reverse order. Clear current without choosing a replacement
	# before the camera children unregister; the adapter restores after its snap.
	var exit_guard := Node.new()
	exit_guard.name = "CameraExitGuard"
	add_child(exit_guard)
	exit_guard.tree_exiting.connect(_clear_camera_for_teardown)

func activate(seat_anchor: Node3D) -> void:
	anchor = seat_anchor
	active = true
	_update_camera(0.0, true)
	_current_camera().make_current()

func deactivate() -> void:
	_clear_camera_for_teardown()
	active = false

func toggle_mode() -> void:
	hood_mode = not hood_mode
	if active:
		_update_camera(0.0, true)
		_current_camera().make_current()

func _current_camera() -> Camera3D:
	return hood_camera if hood_mode else chase_camera

func target_fov_for_speed(speed_mps: float) -> float:
	var ratio := clampf(absf(speed_mps) / maxf(full_fov_speed, 0.001), 0.0, 1.0)
	return lerpf(base_fov, high_speed_fov, smoothstep(0.0, 1.0, ratio))

func make_collision_query(from: Vector3, motion: Vector3) -> PhysicsShapeQueryParameters3D:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _sphere
	query.transform = Transform3D(Basis.IDENTITY, from)
	query.motion = motion
	query.collision_mask = collision_mask
	query.exclude = [target.get_rid()]
	return query

func _physics_process(delta: float) -> void:
	if active and is_instance_valid(target): _update_camera(delta)

func _update_camera(delta: float, snap: bool = false) -> void:
	var origin := target.global_position
	var look_target := anchor.global_position if is_instance_valid(anchor) else origin + Vector3.UP * look_height
	var desired := origin + target.global_basis * chase_offset
	var desired_position := desired if snap else chase_camera.global_position.lerp(desired, 1.0 - exp(-position_smoothing * delta))
	var motion := desired_position - look_target
	var query := make_collision_query(look_target, motion)
	var fractions := target.get_world_3d().direct_space_state.cast_motion(query)
	chase_camera.global_position = look_target + motion * fractions[0]
	if chase_camera.global_position.distance_squared_to(look_target) > 0.001:
		var wanted_basis := chase_camera.global_transform.looking_at(look_target, Vector3.UP).basis
		chase_camera.global_basis = wanted_basis if snap else chase_camera.global_basis.slerp(wanted_basis, 1.0 - exp(-rotation_smoothing * delta))
	var weight := 1.0 if snap else 1.0 - exp(-fov_smoothing * delta)
	chase_camera.fov = lerpf(chase_camera.fov, target_fov_for_speed(target.linear_velocity.length()), weight)
	hood_camera.global_transform = hood_marker.global_transform
	hood_camera.fov = lerpf(hood_camera.fov, base_fov, weight)

func _clear_camera_for_teardown() -> void:
	if active:
		var camera := _current_camera()
		if is_instance_valid(camera) and camera.is_inside_tree(): camera.clear_current(false)
