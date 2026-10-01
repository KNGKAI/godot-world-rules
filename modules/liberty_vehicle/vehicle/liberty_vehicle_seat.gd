class_name LibertyVehicleSeat
extends Area3D
const DRIVER_ID: StringName = &"driver_front_left"
@export var seat_id: StringName = DRIVER_ID
@export var camera_anchor_path: NodePath = ^"CameraAnchor"
@export var exit_marker_path: NodePath = ^"ExitMarker"

func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	monitoring = true
	monitorable = false
	add_to_group(&"liberty_vehicle_seat")

func get_camera_anchor() -> Node3D:
	return get_node_or_null(camera_anchor_path) as Node3D

func get_exit_marker() -> Node3D:
	return get_node_or_null(exit_marker_path) as Node3D
