class_name CinematicHoldAndAct
extends CinematicShot
## Locked full-body performance. An empty clip keeps the lock and the borrowed camera. Skip does not teleport.

@export var clip: StringName = &""

var _driver: LibertyAnimationDriver


func requires_on_foot() -> bool:
	return true


func enter(host) -> Error:
	var err := super.enter(host)
	if err != OK:
		return err
	host.set_subtitle(subtitle)
	if clip.is_empty():
		return OK
	var player := host.resolve_role(&"player") as LibertyCharacter
	if player == null or not player.is_inside_tree():
		return ERR_DOES_NOT_EXIST
	_driver = player.get_node_or_null("AnimationDriver") as LibertyAnimationDriver
	if _driver == null or not _driver.play_performance(clip):
		_driver = null
		return ERR_DOES_NOT_EXIST
	return OK


func exit(_host) -> void:
	# Stop while the sequence lock is still held so the driver latches _was_locked.
	if is_instance_valid(_driver):
		_driver.stop_performance()
