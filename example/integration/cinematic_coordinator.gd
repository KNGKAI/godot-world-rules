class_name CinematicCoordinator
extends Node
## Plays example sequences and writes cinematic.* seen-flags. It is not a child of a managed world.

const BOOK: RERuleBook = preload("res://example/rules/cinematics.tres")
const GLANCE: CinematicSequence = preload("res://example/cinematics/package_glance.tres")
const HOLD: CinematicSequence = preload("res://example/cinematics/delivery_hold.tres")
const REVEAL: CinematicSequence = preload("res://example/cinematics/sedan_reveal.tres")
const TOUR: CinematicSequence = preload("res://example/cinematics/tour_finish.tres")
const DOOR: CinematicSequence = preload("res://example/cinematics/home_door.tres")

const SEQUENCES: Dictionary = {
	&"package_glance": GLANCE,
	&"delivery_hold": HOLD,
	&"sedan_reveal": REVEAL,
	&"tour_finish": TOUR,
	&"home_door": DOOR,
}
const SEEN: Dictionary = {
	&"package_glance": &"cinematic.package_glance",
	&"delivery_hold": &"cinematic.delivery_hold",
	&"sedan_reveal": &"cinematic.sedan_reveal",
	&"tour_finish": &"cinematic.tour_finish",
	&"home_door": &"cinematic.home_door",
}
const SUCCESSOR: Dictionary = {
	&"delivery_hold": &"sedan_reveal",
}
const BUSY_WARN_FRAMES := 120

var _director: CinematicDirector
var _engine: RERuleEngine
var _pending: StringName = &""
var _rule_active: StringName = &""
var _writes: Array[StringName] = []
var _busy_streak := 0
var _busy_warned := false


func bind_director(director: CinematicDirector) -> void:
	_director = director
	if not director.cinematic_finished.is_connected(_on_terminal):
		director.cinematic_finished.connect(_on_terminal)
	if not director.cinematic_skipped.is_connected(_on_terminal):
		director.cinematic_skipped.connect(_on_terminal)
	director.role_resolver = resolve_role


func _ready() -> void:
	World.events.world_loaded.connect(_on_world_loaded)


func play_direct(sequence_id: StringName) -> Error:
	return _play(sequence_id, false)


func resolve_role(role: StringName) -> Node:
	var world_root: Node = World.scenes.get_active_world_root()
	if world_root == null:
		return null
	match role:
		&"player":
			return world_root.get_node_or_null("Player")
		&"sedan":
			return world_root.get_node_or_null("Sedan")
		&"package":
			return world_root.get_node_or_null("Package")
		&"contact":
			return world_root.get_node_or_null("Contact")
		&"home_door":
			return world_root.get_node_or_null("HomeDoor")
		&"park_bay":
			return world_root.get_node_or_null("ParkBay")
		&"sedan_view":
			return world_root.get_node_or_null("SedanView")
		_:
			return null


func _physics_process(_delta: float) -> void:
	_flush_write()
	if _director == null or _pending.is_empty() or _director.is_sequence_active():
		return
	var sequence_id := _pending
	_pending = &""
	_play(sequence_id, true)


func _on_world_loaded(_context: Dictionary, _entry: WorldEntryPointData) -> void:
	var world_root: Node = World.scenes.get_active_world_root()
	var errand: ErrandCoordinator = null
	if world_root != null:
		errand = world_root.get_node_or_null("ErrandCoordinator") as ErrandCoordinator
	if errand == null:
		_drop_engine()
		return
	if errand.rule_engine != _engine:
		_drop_engine()
		_engine = errand.rule_engine
		_engine.event_received.connect(_on_rule_event)
	var loaded := _engine.load_book(BOOK)
	if loaded != OK:
		push_warning("Cinematic rule book failed to load: %s" % error_string(loaded))


func _on_rule_event(event: RERuleEvent) -> void:
	if event.name != CinematicRequestAction.EVENT:
		return
	var sequence_id := StringName(event.payload.get(&"sequence_id", &""))
	if sequence_id.is_empty():
		return
	_play(sequence_id, true)


func _on_terminal(sequence_id: StringName) -> void:
	var result := _director.last_result if _director != null else ERR_UNAVAILABLE
	var rule_triggered := _rule_active == sequence_id
	if rule_triggered:
		_rule_active = &""
	if result == OK:
		_queue_write(sequence_id)
		var next := StringName(SUCCESSOR.get(sequence_id, &""))
		if not next.is_empty():
			_play(next, true)
		return
	if rule_triggered and _pending.is_empty():
		_pending = sequence_id


func _play(sequence_id: StringName, from_rule: bool) -> Error:
	if from_rule and _already_seen(sequence_id):
		return OK
	var sequence := _sequence_for(sequence_id)
	if sequence == null or _director == null:
		push_warning("CinematicCoordinator missing sequence %s" % sequence_id)
		return ERR_DOES_NOT_EXIST
	var err := _director.play(sequence)
	if err == OK:
		if from_rule:
			_rule_active = sequence_id
		return OK
	if from_rule and err == ERR_BUSY:
		_pending = sequence_id
		return err
	if from_rule:
		push_warning("CinematicCoordinator[%s] %s" % [sequence_id, error_string(err)])
	return err


func _already_seen(sequence_id: StringName) -> bool:
	var key := StringName(SEEN.get(sequence_id, &""))
	if key.is_empty():
		return false
	if _writes.has(key):
		return true
	return bool(World.state.get_value(key, false))


func _queue_write(sequence_id: StringName) -> void:
	var key := StringName(SEEN.get(sequence_id, &""))
	if key.is_empty():
		return
	if not _writes.has(key):
		_writes.append(key)
	_flush_write()


func _flush_write() -> void:
	if _writes.is_empty():
		return
	var key := _writes[0]
	var err := World.state.set_value(key, true)
	if err == OK:
		_writes.pop_front()
		_busy_streak = 0
		_busy_warned = false
		return
	if err == ERR_BUSY:
		_busy_streak += 1
		if _busy_streak >= BUSY_WARN_FRAMES and not _busy_warned:
			_busy_warned = true
			push_warning("Cinematic seen-flag %s still busy after %d frames" % [key, BUSY_WARN_FRAMES])
		return
	push_warning("Cinematic seen-flag %s write failed: %s" % [key, error_string(err)])
	_writes.pop_front()
	_busy_streak = 0
	_busy_warned = false


func _sequence_for(sequence_id: StringName) -> CinematicSequence:
	return SEQUENCES.get(sequence_id) as CinematicSequence


func _drop_engine() -> void:
	if _engine != null and _engine.event_received.is_connected(_on_rule_event):
		_engine.event_received.disconnect(_on_rule_event)
	_engine = null
