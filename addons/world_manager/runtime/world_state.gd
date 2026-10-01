class_name WorldState
extends RefCounted
## Isolated world state. Usable without a SceneTree.


const MAX_KEY_LENGTH := 256

signal state_changed(key: StringName, previous: Variant, current: Variant, exists: bool)
signal state_restored()

var _store: Dictionary = {}
var _guard: WorldOperationGuard
var _events: WorldEvents
var _notification_depth: int = 0


func configure(guard: WorldOperationGuard, events: WorldEvents) -> void:
	_guard = guard
	_events = events


func get_value(key: StringName, default_value: Variant = null) -> Variant:
	if _validate_key(key) != OK:
		return default_value
	if not _store.has(key):
		return default_value
	return WorldValue.clone_validated(_store[key])


func has_value(key: StringName) -> bool:
	if _validate_key(key) != OK:
		return false
	return _store.has(key)


func set_value(key: StringName, value: Variant) -> Error:
	if _validate_key(key) != OK:
		return _reject(&"set_value", ERR_INVALID_PARAMETER, _key_context(key))
	if WorldValue.validate(value) != OK:
		return _reject(&"set_value", ERR_INVALID_PARAMETER, _key_context(key))
	if _is_busy():
		return _reject(&"set_value", ERR_BUSY, _key_context(key))
	var cloned: Variant = WorldValue.clone_validated(value)
	if _store.has(key) and _store[key] == cloned:
		return OK
	var begin_err := _begin_public(&"set_value", _key_context(key))
	if begin_err != OK:
		return begin_err
	var previous: Variant = null
	if _store.has(key):
		previous = WorldValue.clone_validated(_store[key])
	_store[key] = cloned
	_emit_changed(key, previous, WorldValue.clone_validated(cloned), true)
	_finish_public()
	return OK


func remove_value(key: StringName) -> Error:
	if _validate_key(key) != OK:
		return _reject(&"remove_value", ERR_INVALID_PARAMETER, _key_context(key))
	if _is_busy():
		return _reject(&"remove_value", ERR_BUSY, _key_context(key))
	if not _store.has(key):
		return OK
	var begin_err := _begin_public(&"remove_value", _key_context(key))
	if begin_err != OK:
		return begin_err
	var previous: Variant = WorldValue.clone_validated(_store[key])
	_store.erase(key)
	_emit_changed(key, previous, null, false)
	_finish_public()
	return OK


func clear() -> Error:
	if _is_busy():
		return _reject(&"clear", ERR_BUSY, {})
	if _store.is_empty():
		return OK
	var begin_err := _begin_public(&"clear", {})
	if begin_err != OK:
		return begin_err
	_replace_store({})
	_emit_restored()
	_finish_public()
	return OK


func snapshot() -> Dictionary:
	var out: Dictionary = {}
	for key: Variant in _store.keys():
		out[key] = WorldValue.clone_validated(_store[key])
	return out


func restore_snapshot(values: Dictionary) -> Error:
	return _restore(values, false, true)


## notify=false leaves the coalesced restore notification unpublished, so a
## load can swap the store inside its commit window and announce it only after
## the whole transaction succeeds.
func restore_owned(values: Dictionary, notify: bool = true) -> Error:
	return _restore(values, true, notify)


func notify_restored_owned() -> void:
	_emit_restored()


func _restore(values: Dictionary, owned: bool, notify: bool) -> Error:
	if not owned and _is_busy():
		return _reject(&"restore_snapshot", ERR_BUSY, {})
	var began := false
	if not owned:
		var begin_err := _begin_public(&"restore_snapshot", {})
		if begin_err != OK:
			return begin_err
		began = _guard != null
	var next: Dictionary = {}
	for key: Variant in values.keys():
		var key_type := typeof(key)
		var key_name: StringName
		if key_type == TYPE_STRING_NAME:
			key_name = key
		elif key_type == TYPE_STRING:
			key_name = StringName(key)
		else:
			if began:
				_finish_public()
			return _reject(&"restore_snapshot", ERR_INVALID_PARAMETER, {})
		if _validate_key(key_name) != OK:
			if began:
				_finish_public()
			return _reject(&"restore_snapshot", ERR_INVALID_PARAMETER, _key_context(key_name))
		var value: Variant = values[key]
		if WorldValue.validate(value) != OK:
			if began:
				_finish_public()
			return _reject(&"restore_snapshot", ERR_INVALID_PARAMETER, _key_context(key_name))
		next[key_name] = WorldValue.clone_validated(value)
	_replace_store(next)
	if notify:
		_emit_restored()
	if began:
		_finish_public()
	return OK


func _validate_key(key: StringName) -> Error:
	var text := String(key)
	if text.is_empty():
		return ERR_INVALID_PARAMETER
	if text.length() > MAX_KEY_LENGTH:
		return ERR_INVALID_PARAMETER
	return OK


func _is_busy() -> bool:
	if _notification_depth > 0:
		return true
	if _guard != null and _guard.is_busy():
		return true
	return false


func _begin_public(operation: StringName, context: Dictionary) -> Error:
	if _guard == null:
		return OK
	var begin_err := _guard.try_begin(operation)
	if begin_err != OK:
		return _reject(operation, begin_err, context)
	return OK


func _finish_public() -> void:
	if _guard == null or not _guard.is_busy():
		return
	_guard.finish(_guard.get_operation_id())


func _replace_store(next: Dictionary) -> void:
	set_block_signals(true)
	_store = next
	set_block_signals(false)


func _emit_changed(
	key: StringName, previous: Variant, current: Variant, exists: bool
) -> void:
	_notification_depth += 1
	state_changed.emit(key, previous, current, exists)
	if _events != null:
		_events.state_changed.emit(key, previous, current, exists)
	_notification_depth -= 1


func _emit_restored() -> void:
	_notification_depth += 1
	state_restored.emit()
	if _events != null:
		_events.state_restored.emit()
	_notification_depth -= 1


func _reject(operation: StringName, reason: Error, context: Dictionary) -> Error:
	return WorldDiagnostics.reject(operation, reason, context)


func _key_context(key: StringName) -> Dictionary:
	var context: Dictionary = {}
	if String(key) != "":
		context["key"] = key
	return context
