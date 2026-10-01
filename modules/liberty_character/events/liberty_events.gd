class_name LibertyEvents
extends Node

signal movement_state_changed(old_state: StringName, new_state: StringName)
signal landed(impact_speed: float)
signal ragdoll_started(reason: StringName)
signal ragdoll_recovered(face_up: bool)
signal hit_received(bone_name: StringName, direction: Vector3, force: float, fatal: bool)
signal interaction_started(kind: StringName)
signal interaction_finished(kind: StringName)
signal traversal_state_changed(old_state: StringName, new_state: StringName)

signal occupancy_changed(vehicle_id: int, seat_id: StringName, occupant_id: int, mounted: bool, cause: StringName)
