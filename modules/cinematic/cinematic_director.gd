class_name CinematicDirector
extends Node
## Plays one sequence by borrowing the character, the gameplay camera, and input. Shots do not borrow on their own.

signal cinematic_started(sequence_id: StringName)
signal cinematic_finished(sequence_id: StringName)
signal cinematic_skipped(sequence_id: StringName)

enum _Phase { IDLE, PLAYING, RESTORING }

const _PRIORITY := -25
const _MAX_SHOT_SECONDS := 8.0

## (StringName) -> Node. An invalid callable refuses play().
var role_resolver: Callable
var last_result: Error = OK
## Counts release_presentation calls. A character leaving the tree drops the token instead.
var release_presentation_calls := 0
## Passage sets this only after travel_to returns OK. Any other exit aborts.
var expect_player_exit := false

var _passage_error: Error = OK

var _phase := _Phase.IDLE
var _sequence: CinematicSequence
var _shot_index := -1
var _shot_entered := false
var _skip_latched := false
var _character: LibertyCharacter
var _adapter: LibertyEventAdapter
var _hit_token := 0
var _presentation_token := 0
var _camera: Camera3D
var _chrome: CinematicChrome
var _guard_latched := false
var _guard_bound := false
var _skip_policy_done := false


func _ready() -> void:
	process_physics_priority = _PRIORITY
	_camera = Camera3D.new()
	_camera.name = "CinematicCamera"
	_camera.top_level = true
	_camera.current = false
	add_child(_camera)
	_chrome = CinematicChrome.new()
	_chrome.name = "Chrome"
	add_child(_chrome)
	_chrome.skip_pressed.connect(skip)
	_bind_guard()


func _exit_tree() -> void:
	_unbind_guard()


func _physics_process(delta: float) -> void:
	if _phase != _Phase.PLAYING:
		return
	if _ragdoll_blocked():
		_abort(&"ragdoll", true, true)
		return
	if _traversal_blocked():
		_abort(&"traversal", false, false)
		return
	if _skip_latched:
		var shot := _current_shot()
		if shot != null and _shot_entered and not _skip_policy_done:
			shot.skip_to_end(self)
			_skip_policy_done = true
			# Adapter -20 and the sedan still run this frame. Finish on the next tick.
			if shot.skip_holds_borrow():
				return
		# Passage stays borrowed until the travel terminal has waited one frame.
		if shot != null and _shot_entered and shot.defers_skip_restore():
			return
		_finish(true)
		return
	var current := _current_shot()
	if current == null or not _shot_entered:
		_finish(false)
		return
	if current.tick(self, delta):
		_advance()


func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or key.keycode != KEY_ESCAPE:
		return
	if skip() != OK:
		return
	var viewport := get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()


func play(sequence: CinematicSequence) -> Error:
	var sequence_id := _sequence_name(sequence)
	if _phase != _Phase.IDLE:
		push_warning("CinematicDirector[%s] play code=%d" % [current_sequence_id(), ERR_BUSY])
		return ERR_BUSY
	if not is_inside_tree():
		return _refuse(sequence_id, ERR_UNAVAILABLE)
	var invalid := _invalid_sequence(sequence)
	if invalid != OK:
		return _refuse(sequence_id, invalid)
	var root := _active_world_root()
	if root != null and root.is_ancestor_of(self):
		return _refuse(sequence_id, ERR_INVALID_PARAMETER)
	var player := resolve_role(&"player") as LibertyCharacter
	if player == null or not player.is_inside_tree():
		return _refuse(sequence_id, ERR_DOES_NOT_EXIST)
	if player.is_ragdoll_active() or _player_reacting(player):
		return _refuse(sequence_id, ERR_BUSY)
	if player.is_traversal_locked():
		return _refuse(sequence_id, ERR_BUSY)
	var world = _world()
	if world == null:
		return _refuse(sequence_id, ERR_UNAVAILABLE)
	if world.current_travel_id() != 0:
		return _refuse(sequence_id, ERR_BUSY)
	var scenes = world.scenes
	if scenes != null and scenes.is_loading():
		return _refuse(sequence_id, ERR_BUSY)
	if _guard_latched:
		return _refuse(sequence_id, ERR_BUSY)
	if world.is_recovery_required():
		return _refuse(sequence_id, ERR_UNAVAILABLE)
	if player.is_body_suspended() and _needs_on_foot(sequence):
		return _refuse(sequence_id, ERR_BUSY)
	var adapter := player.get_node_or_null("EventAdapter") as LibertyEventAdapter
	if adapter == null or _camera == null or not _camera.is_inside_tree():
		return _refuse(sequence_id, ERR_CANT_ACQUIRE_RESOURCE)
	if _needs_vehicle(sequence) and not _vehicle_ready(adapter):
		return _refuse(sequence_id, ERR_BUSY)
	_character = player
	_adapter = adapter
	_hit_token = player.acquire_hit_suppression()
	_presentation_token = adapter.borrow_presentation(_camera)
	if _presentation_token == 0:
		player.release_hit_suppression(_hit_token)
		_hit_token = 0
		_character = null
		_adapter = null
		return _refuse(sequence_id, ERR_CANT_ACQUIRE_RESOURCE)
	player.set_movement_locked(true)
	if not player.tree_exiting.is_connected(_on_character_tree_exiting):
		player.tree_exiting.connect(_on_character_tree_exiting)
	if _chrome != null:
		_chrome.open()
	_sequence = sequence
	_shot_index = 0
	_skip_latched = false
	_shot_entered = false
	_phase = _Phase.PLAYING
	var entered := _enter_current()
	if entered != OK:
		_release_owners(false)
		_clear_playback()
		return _refuse(sequence.id, entered)
	last_result = OK
	cinematic_started.emit(sequence.id)
	if _passage_error != OK:
		last_result = _passage_error
		_passage_error = OK
		_finish(false)
	return OK


func skip() -> Error:
	if _phase != _Phase.PLAYING:
		return ERR_UNAVAILABLE
	if _skip_latched:
		return OK
	_skip_latched = true
	return OK


func is_sequence_active() -> bool:
	return _phase != _Phase.IDLE


func current_sequence_id() -> StringName:
	if _phase == _Phase.IDLE or _sequence == null:
		return &""
	return _sequence.id


func notify_guard_accepted(operation: StringName) -> void:
	if operation == &"save_game" or operation == &"load_game":
		_guard_latched = true


func resolve_role(role: StringName) -> Node:
	if not role_resolver.is_valid():
		return null
	var resolved: Variant = role_resolver.call(role)
	return resolved as Node


func cinematic_camera() -> Camera3D:
	return _camera


func set_subtitle(text: String) -> void:
	if _chrome != null:
		_chrome.set_subtitle(text)


func fade_rect() -> ColorRect:
	if _chrome == null:
		return null
	return _chrome.fade_rect()


## A passage whose travel_to was refused. play() emits the terminal after cinematic_started.
func note_passage_failure(err: Error) -> void:
	_passage_error = err


## Drops the freed player's token ids, then borrows the player that just entered.
func rebind_passage_player(player: LibertyCharacter) -> Error:
	if player == null or not is_instance_valid(player) or not player.is_inside_tree():
		return ERR_DOES_NOT_EXIST
	_disconnect_character()
	_hit_token = 0
	_presentation_token = 0
	_character = null
	_adapter = null
	var adapter := player.get_node_or_null("EventAdapter") as LibertyEventAdapter
	if adapter == null or _camera == null or not _camera.is_inside_tree():
		return ERR_CANT_ACQUIRE_RESOURCE
	_character = player
	_adapter = adapter
	_hit_token = player.acquire_hit_suppression()
	player.set_movement_locked(true)
	_presentation_token = adapter.borrow_presentation(_camera)
	if _presentation_token == 0:
		if _hit_token != 0:
			player.release_hit_suppression(_hit_token)
		_hit_token = 0
		player.set_movement_locked(false)
		_disconnect_character()
		_character = null
		_adapter = null
		return ERR_CANT_ACQUIRE_RESOURCE
	if not player.tree_exiting.is_connected(_on_character_tree_exiting):
		player.tree_exiting.connect(_on_character_tree_exiting)
	expect_player_exit = false
	return OK


## The passage shot calls this after the travel signal and one process frame.
func complete_passage(skipped: bool, result: Error) -> void:
	if _phase != _Phase.PLAYING:
		return
	if result != OK:
		last_result = result
		skipped = false
	_finish(skipped)


## The shot reuses one snapshot. Submit it only through the adapter.
func set_vehicle_intent(snapshot: LibertyVehicleControlSnapshot) -> void:
	if snapshot == null or _presentation_token == 0 or not is_instance_valid(_adapter):
		return
	_adapter.set_borrowed_controls(_presentation_token, snapshot)


func _advance() -> void:
	_exit_current()
	_shot_index += 1
	if _sequence == null or _shot_index >= _sequence.shots.size():
		_finish(false)
		return
	var entered := _enter_current()
	if entered != OK:
		last_result = entered
		_finish(false)


func _finish(skipped: bool) -> void:
	if _phase != _Phase.PLAYING:
		return
	var sequence_id := current_sequence_id()
	_phase = _Phase.RESTORING
	_release_owners(false)
	if skipped:
		last_result = OK
	_emit_terminal(sequence_id, skipped)


func _abort(reason: String, preserve_follow: bool, pivot_camera: bool) -> void:
	if _phase != _Phase.PLAYING:
		return
	var sequence_id := current_sequence_id()
	_phase = _Phase.RESTORING
	_release_owners(preserve_follow)
	if pivot_camera:
		_make_pivot_camera_current()
	last_result = ERR_BUSY
	push_warning("CinematicDirector[%s] %s" % [sequence_id, reason])
	_emit_terminal(sequence_id, false)


func _release_owners(preserve_follow: bool) -> void:
	_exit_current()
	# Stop while the movement lock is still set so a performance latches _was_locked.
	_stop_performance()
	if _presentation_token != 0 and is_instance_valid(_adapter):
		_adapter.release_presentation(_presentation_token, preserve_follow)
		release_presentation_calls += 1
	_presentation_token = 0
	if is_instance_valid(_character):
		_character.clear_scripted_locomotion()
		_character.set_movement_locked(false)
		if _hit_token != 0:
			_character.release_hit_suppression(_hit_token)
	_hit_token = 0
	_disconnect_character()
	set_subtitle("")
	if _chrome != null:
		_chrome.close()


func _emit_terminal(sequence_id: StringName, skipped: bool) -> void:
	_clear_playback()
	if skipped:
		cinematic_skipped.emit(sequence_id)
	else:
		cinematic_finished.emit(sequence_id)


func _clear_playback() -> void:
	_phase = _Phase.IDLE
	_sequence = null
	_shot_index = -1
	_shot_entered = false
	_skip_latched = false
	_skip_policy_done = false
	_passage_error = OK
	expect_player_exit = false
	_character = null
	_adapter = null


func _enter_current() -> Error:
	var shot := _current_shot()
	if shot == null:
		return ERR_INVALID_PARAMETER
	var err := shot.enter(self)
	_shot_entered = err == OK
	if err == OK:
		return OK
	return err


func _exit_current() -> void:
	if not _shot_entered:
		return
	var shot := _current_shot()
	_shot_entered = false
	if shot != null:
		shot.exit(self)


func _current_shot() -> CinematicShot:
	if _sequence == null or _shot_index < 0 or _shot_index >= _sequence.shots.size():
		return null
	return _sequence.shots[_shot_index]


func _on_character_tree_exiting() -> void:
	if _phase != _Phase.PLAYING and _phase != _Phase.RESTORING:
		return
	var sequence_id := current_sequence_id()
	# Children have already run _exit_tree. Dropping the ids leaves the adapter's borrow path alone.
	_disconnect_character()
	_hit_token = 0
	_presentation_token = 0
	_character = null
	_adapter = null
	if expect_player_exit:
		return
	_shot_entered = false
	set_subtitle("")
	if _chrome != null:
		_chrome.close()
	if _camera != null:
		_camera.clear_current(false)
	last_result = ERR_DOES_NOT_EXIST
	push_warning("CinematicDirector[%s] character left tree" % sequence_id)
	_clear_playback()
	cinematic_finished.emit(sequence_id)


func _stop_performance() -> void:
	if not is_instance_valid(_character):
		return
	var driver := _character.get_node_or_null("AnimationDriver") as LibertyAnimationDriver
	if driver != null:
		driver.stop_performance()


func _make_pivot_camera_current() -> void:
	if not is_instance_valid(_character):
		return
	var pivot := _character.get_node_or_null(_character.camera_pivot_path)
	if pivot == null:
		return
	var camera := pivot.get_node_or_null("SpringArm3D/Camera3D") as Camera3D
	if camera != null and camera.is_inside_tree():
		camera.make_current()


func _ragdoll_blocked() -> bool:
	if not is_instance_valid(_character):
		return false
	if _character.is_ragdoll_active():
		return true
	return _player_reacting(_character)


func _player_reacting(player: LibertyCharacter) -> bool:
	var ragdoll := player.ragdoll as LibertyRagdoll
	return ragdoll != null and ragdoll.is_reacting()


func _traversal_blocked() -> bool:
	return is_instance_valid(_character) and _character.is_traversal_locked()


func _disconnect_character() -> void:
	if is_instance_valid(_character) and _character.tree_exiting.is_connected(_on_character_tree_exiting):
		_character.tree_exiting.disconnect(_on_character_tree_exiting)


func _invalid_sequence(sequence: CinematicSequence) -> Error:
	if sequence == null or sequence.shots.is_empty():
		return ERR_INVALID_PARAMETER
	for shot in sequence.shots:
		if shot == null or not is_finite(shot.duration):
			return ERR_INVALID_PARAMETER
		if shot.duration > _MAX_SHOT_SECONDS and not shot.ignores_duration_cap():
			return ERR_INVALID_PARAMETER
	return OK


func _needs_on_foot(sequence: CinematicSequence) -> bool:
	for shot in sequence.shots:
		if shot != null and shot.requires_on_foot():
			return true
	return false


func _needs_vehicle(sequence: CinematicSequence) -> bool:
	for shot in sequence.shots:
		if shot != null and shot.requires_vehicle():
			return true
	return false


func _vehicle_ready(adapter: LibertyEventAdapter) -> bool:
	var vehicle := adapter.mounted_vehicle
	return (
		is_instance_valid(vehicle)
		and vehicle.possession != null
		and vehicle.possession.control_enabled
	)


func _active_world_root() -> Node:
	var world = _world()
	if world == null:
		return null
	var scenes = world.scenes
	if scenes == null:
		return null
	return scenes.get_active_world_root()


## The headless --script entry compiles this file before the autoload name exists.
func _world():
	var tree := get_tree()
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null("World")


func _sequence_name(sequence: CinematicSequence) -> StringName:
	if sequence == null:
		return &""
	return sequence.id


func _refuse(sequence_id: StringName, err: Error) -> Error:
	last_result = err
	push_warning("CinematicDirector[%s] play code=%d" % [sequence_id, err])
	return err


func _bind_guard() -> void:
	var world = _world()
	if world == null:
		return
	var events = world.events
	if events == null:
		return
	events.save_started.connect(_on_guard_started)
	events.load_started.connect(_on_guard_started)
	events.new_game_started.connect(_on_guard_started)
	events.entity_spawn_started.connect(_on_guard_started)
	events.entity_remove_started.connect(_on_guard_started)
	events.save_completed.connect(_on_guard_ended)
	events.load_completed.connect(_on_guard_ended)
	events.new_game_completed.connect(_on_guard_ended)
	events.save_failed.connect(_on_guard_failed)
	events.load_failed.connect(_on_guard_failed)
	events.new_game_failed.connect(_on_guard_failed)
	events.entity_spawn_failed.connect(_on_guard_failed)
	events.entity_remove_failed.connect(_on_guard_failed)
	events.entity_spawned.connect(_on_entity_spawned)
	events.entities_removed.connect(_on_entities_removed)
	_guard_bound = true


func _unbind_guard() -> void:
	if not _guard_bound:
		return
	_guard_bound = false
	var world = _world()
	if world == null:
		return
	var events = world.events
	if events == null:
		return
	_disconnect_guard(events.save_started, _on_guard_started)
	_disconnect_guard(events.load_started, _on_guard_started)
	_disconnect_guard(events.new_game_started, _on_guard_started)
	_disconnect_guard(events.entity_spawn_started, _on_guard_started)
	_disconnect_guard(events.entity_remove_started, _on_guard_started)
	_disconnect_guard(events.save_completed, _on_guard_ended)
	_disconnect_guard(events.load_completed, _on_guard_ended)
	_disconnect_guard(events.new_game_completed, _on_guard_ended)
	_disconnect_guard(events.save_failed, _on_guard_failed)
	_disconnect_guard(events.load_failed, _on_guard_failed)
	_disconnect_guard(events.new_game_failed, _on_guard_failed)
	_disconnect_guard(events.entity_spawn_failed, _on_guard_failed)
	_disconnect_guard(events.entity_remove_failed, _on_guard_failed)
	_disconnect_guard(events.entity_spawned, _on_entity_spawned)
	_disconnect_guard(events.entities_removed, _on_entities_removed)


func _disconnect_guard(source: Signal, method: Callable) -> void:
	if source.is_connected(method):
		source.disconnect(method)


func _on_guard_started(_context: Dictionary) -> void:
	_guard_latched = true


func _on_guard_ended(_context: Dictionary) -> void:
	_guard_latched = false


func _on_guard_failed(_reason: Error, _context: Dictionary) -> void:
	_guard_latched = false


func _on_entity_spawned(_id: StringName, _world_id: StringName, _context: Dictionary) -> void:
	_guard_latched = false


func _on_entities_removed(_ids: Array, _context: Dictionary) -> void:
	_guard_latched = false
