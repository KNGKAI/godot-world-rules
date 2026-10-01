class_name CinematicStagedWalk
extends CinematicShot
## Walks toward a role. Skip is the teleport onto that feet-origin marker.

@export var role: StringName
@export var gait_cap := 5.0
@export var arrive_radius := 0.4

var _player: LibertyCharacter
var _marker: Node3D


func requires_on_foot() -> bool:
	return true


func enter(host) -> Error:
	var err := super.enter(host)
	if err != OK:
		return err
	_player = host.resolve_role(&"player") as LibertyCharacter
	_marker = host.resolve_role(role) as Node3D
	if _player == null or not _player.is_inside_tree():
		return ERR_DOES_NOT_EXIST
	if _marker == null or not _marker.is_inside_tree():
		return ERR_DOES_NOT_EXIST
	_player.set_movement_locked(false)
	var armed := _player.set_scripted_locomotion(_planar_direction(), gait_cap)
	if armed != OK:
		_player.set_movement_locked(true)
		return armed
	host.set_subtitle(subtitle)
	return OK


func tick(_host, delta: float) -> bool:
	if not _targets_ready():
		return true
	if _planar_distance() <= arrive_radius:
		return true
	_player.set_scripted_locomotion(_planar_direction(), gait_cap)
	return super.tick(_host, delta)


func exit(_host) -> void:
	if not is_instance_valid(_player):
		return
	_player.clear_scripted_locomotion()
	_player.set_movement_locked(true)


func skip_to_end(_host) -> void:
	if _targets_ready():
		_player.teleport_to(_marker.global_transform, false)
	_finished = true


func _targets_ready() -> bool:
	return (
		is_instance_valid(_player)
		and _player.is_inside_tree()
		and is_instance_valid(_marker)
		and _marker.is_inside_tree()
	)


func _planar_direction() -> Vector3:
	var offset := _marker.global_position - _player.global_position
	offset.y = 0.0
	return offset


func _planar_distance() -> float:
	return _planar_direction().length()
