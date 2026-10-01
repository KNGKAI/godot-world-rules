class_name WorldEntityRegistry
extends RefCounted
## Weak ID → actor map. Does not log or depend on World.


var _entries: Dictionary = {}


func register_entity(id: StringName, actor: Node) -> Error:
	if WorldId.validate(id) != OK:
		return ERR_INVALID_PARAMETER
	if not _is_usable_actor(actor):
		return ERR_INVALID_PARAMETER
	_prune(id)
	if _entries.has(id):
		var current := _live_actor(id)
		if current == actor:
			return OK
		if current != null:
			return ERR_ALREADY_EXISTS
	_entries[id] = weakref(actor)
	return OK


func unregister_entity(id: StringName, actor: Node) -> Error:
	if not _is_usable_actor(actor):
		return ERR_INVALID_PARAMETER
	if not _entries.has(id):
		return ERR_DOES_NOT_EXIST
	var current := _live_actor(id)
	if current == null:
		_entries.erase(id)
		return ERR_DOES_NOT_EXIST
	if current != actor:
		return ERR_DOES_NOT_EXIST
	_entries.erase(id)
	return OK


func resolve(id: StringName) -> Node:
	_prune(id)
	return _live_actor(id)


func contains(id: StringName) -> bool:
	return resolve(id) != null


func _is_usable_actor(actor: Node) -> bool:
	if actor == null:
		return false
	if not is_instance_valid(actor):
		return false
	if actor.is_queued_for_deletion():
		return false
	return true


func _live_actor(id: StringName) -> Node:
	if not _entries.has(id):
		return null
	var held: WeakRef = _entries[id]
	if held == null:
		return null
	var found: Variant = held.get_ref()
	if found == null or not (found is Node):
		return null
	var actor := found as Node
	if not is_instance_valid(actor):
		return null
	return actor


func _prune(id: StringName) -> void:
	if not _entries.has(id):
		return
	if _live_actor(id) == null:
		_entries.erase(id)
