class_name CinematicWorldPassage
extends CinematicShot
## Travels once. A refused travel_to finishes in enter. Skip only completes the fade already running.

@export var world_id: StringName
@export var entry_id: StringName

var _host
var _fade: CinematicFadeTransition
var _world
var _accepted := false
var _settling := false
var _settled := false
var _skip_requested := false
var _rebound := false
var _rebind_error: Error = OK


func requires_on_foot() -> bool:
	return true


## False until travel_to returns OK, so play() still rejects a duration above 8s.
func ignores_duration_cap() -> bool:
	return _accepted


## Stays true through the post-signal frame so the skip branch does not restore early.
func defers_skip_restore() -> bool:
	return _accepted and not _settled


func enter(host) -> Error:
	var err := super.enter(host)
	if err != OK:
		return err
	_host = host
	_accepted = false
	_settling = false
	_settled = false
	_skip_requested = false
	_rebound = false
	_rebind_error = OK
	_fade = CinematicFadeTransition.new(host.fade_rect())
	_world = _lookup_world(host)
	if _world == null:
		host.note_passage_failure(ERR_UNAVAILABLE)
		return OK
	var travel_err: Error = _world.travel_to(world_id, entry_id, {&"transition": _fade})
	if travel_err != OK:
		host.note_passage_failure(travel_err)
		return OK
	_accepted = true
	host.expect_player_exit = true
	var events = _world.events
	events.world_loaded.connect(_on_world_loaded)
	events.transition_completed.connect(_on_transition_completed)
	events.transition_failed.connect(_on_transition_failed)
	events.world_load_failed.connect(_on_world_load_failed)
	return OK


## An accepted passage waits on World, not on this shot's clock. Duration 0 would otherwise end it immediately.
func tick(_host, _delta: float) -> bool:
	return false


func exit(_host) -> void:
	_disconnect_travel()
	if _fade != null:
		_fade.cleanup(0)
	_fade = null
	_world = null
	_host = null


func skip_to_end(_host) -> void:
	_skip_requested = true
	if _fade != null:
		_fade.finish_now()
	_finished = true


func _on_world_loaded(_context: Dictionary, _entry: WorldEntryPointData) -> void:
	if _rebound or _settling or _settled or not _accepted or _host == null:
		return
	_rebound = true
	var player := _host.resolve_role(&"player") as LibertyCharacter
	var err: Error = _host.rebind_passage_player(player)
	if err != OK:
		_rebind_error = err
		# world_loaded runs before the guard is released. Settle after one frame.
		_settle(false, err)


func _on_transition_completed(_context: Dictionary) -> void:
	if _rebind_error != OK:
		_settle(false, _rebind_error)
		return
	_settle(true, OK)


func _on_transition_failed(reason: Error, _context: Dictionary) -> void:
	if _rebind_error != OK:
		_settle(false, _rebind_error)
		return
	_settle(false, reason)


func _on_world_load_failed(reason: Error, _context: Dictionary) -> void:
	if _rebind_error != OK:
		_settle(false, _rebind_error)
		return
	_settle(false, reason)


func _settle(allow_skip: bool, result: Error) -> void:
	if _settling or _settled or not _accepted:
		return
	_settling = true
	var tree: SceneTree = _host.get_tree() if _host != null else null
	if tree != null:
		await tree.process_frame
	if _settled:
		return
	_settled = true
	var skipped := allow_skip and _skip_requested and result == OK
	_disconnect_travel()
	if _host != null and is_instance_valid(_host):
		_host.complete_passage(skipped, result)


func _disconnect_travel() -> void:
	if _world == null:
		return
	var events = _world.events
	if events == null:
		return
	_disconnect(events.world_loaded, _on_world_loaded)
	_disconnect(events.transition_completed, _on_transition_completed)
	_disconnect(events.transition_failed, _on_transition_failed)
	_disconnect(events.world_load_failed, _on_world_load_failed)


func _disconnect(source: Signal, method: Callable) -> void:
	if source.is_connected(method):
		source.disconnect(method)


func _lookup_world(host):
	var tree: SceneTree = host.get_tree()
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null("World")
