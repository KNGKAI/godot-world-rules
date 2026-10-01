class_name LibertyVehicleContracts
extends RefCounted

enum Status { SUCCESS, REJECTED }

class MountResult extends RefCounted:
	var status: Status = Status.REJECTED
	var reason: StringName = &""
	var occupant: LibertyCharacter
	var seat_id: StringName = &""
	var camera_anchor: Node3D
	func succeeded() -> bool: return status == Status.SUCCESS

class DismountResult extends RefCounted:
	var status: Status = Status.REJECTED
	var reason: StringName = &""
	var occupant: LibertyCharacter
	var seat_id: StringName = &""
	var exit_transform := Transform3D.IDENTITY
	var cause: StringName = &"dismount"
	func succeeded() -> bool: return status == Status.SUCCESS
