class_name CinematicLookAtHold
extends CinematicShot
## Holds the director camera on an anchor role, aimed at a target role. Roles are resolved once in enter.

@export var anchor_role: StringName
@export var local_offset := Vector3.ZERO
@export var target_role: StringName

var _anchor: Node3D
var _target: Node3D


func enter(host) -> Error:
	super.enter(host)
	_anchor = host.resolve_role(anchor_role) as Node3D
	_target = host.resolve_role(target_role) as Node3D
	if _anchor == null or not _anchor.is_inside_tree():
		return ERR_DOES_NOT_EXIST
	if _target == null or not _target.is_inside_tree():
		return ERR_DOES_NOT_EXIST
	var aimed := _aim(host)
	if aimed != OK:
		return aimed
	host.set_subtitle(subtitle)
	return OK


func tick(host, delta: float) -> bool:
	if _aim(host) != OK:
		return true
	return super.tick(host, delta)


func _aim(host) -> Error:
	var camera: Camera3D = host.cinematic_camera()
	if camera == null or not is_instance_valid(_anchor) or not is_instance_valid(_target):
		return ERR_DOES_NOT_EXIST
	if not _anchor.is_inside_tree() or not _target.is_inside_tree():
		return ERR_DOES_NOT_EXIST
	camera.global_position = _anchor.to_global(local_offset)
	var dest := _target.global_position
	if camera.global_position.distance_squared_to(dest) <= 0.000001:
		return OK
	camera.look_at(dest, Vector3.UP)
	return OK
