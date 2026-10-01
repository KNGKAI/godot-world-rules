class_name CinematicCameraCut
extends CinematicShot
## One pose of the director camera, copied from a role. Skip expires the clock and does not move the body.

@export var role: StringName


func enter(host) -> Error:
	super.enter(host)
	var marker := host.resolve_role(role) as Node3D
	if marker == null or not marker.is_inside_tree():
		return ERR_DOES_NOT_EXIST
	var camera: Camera3D = host.cinematic_camera()
	if camera == null:
		return ERR_DOES_NOT_EXIST
	camera.global_transform = marker.global_transform
	camera.reset_physics_interpolation()
	host.set_subtitle(subtitle)
	return OK
