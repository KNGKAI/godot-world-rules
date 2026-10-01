class_name WorldSceneDirector
extends Node
## Owns a private container and swaps validated 2D/3D world roots.


var _guard: WorldOperationGuard
var _events: WorldEvents
var _entities: WorldEntityManager
var _persistence: WorldPersistenceManager
var _container: Node
var _catalog: Dictionary = {}
var _active_id: StringName = &""
var _active_root: Node = null
var _pending_world_id: StringName = &""
var _pending_entry_id: StringName = &""
var _pending_operation_id: int = 0


func configure(
	guard: WorldOperationGuard,
	events: WorldEvents,
	entities: WorldEntityManager = null,
	persistence: WorldPersistenceManager = null
) -> void:
	_guard = guard
	_events = events
	_entities = entities
	_persistence = persistence


func _enter_tree() -> void:
	if _container != null:
		return
	_container = Node.new()
	add_child(_container)


func register_world(definition: WorldDefinition) -> Error:
	if not is_inside_tree() or _guard == null:
		return WorldDiagnostics.reject(&"register_world", ERR_UNCONFIGURED, {})
	if definition == null:
		return WorldDiagnostics.reject(&"register_world", ERR_INVALID_PARAMETER, {})
	var world_id := definition.id
	var id_err := WorldId.validate(world_id)
	if id_err != OK:
		return WorldDiagnostics.reject(&"register_world", id_err, _reject_context(world_id, &""))
	if definition.scene == null:
		return WorldDiagnostics.reject(&"register_world", ERR_INVALID_PARAMETER, _reject_context(world_id, &""))
	var copied_metadata: Dictionary = {}
	var meta_err := _copy_metadata(definition.metadata, copied_metadata)
	if meta_err != OK:
		return WorldDiagnostics.reject(&"register_world", meta_err, _reject_context(world_id, &""))
	if _catalog.has(world_id):
		return WorldDiagnostics.reject(&"register_world", ERR_ALREADY_EXISTS, _reject_context(world_id, &""))
	var begin_err := _guard.try_begin(&"register_world")
	if begin_err != OK:
		return WorldDiagnostics.reject(&"register_world", begin_err, _reject_context(world_id, &""))
	var stored := WorldDefinition.new()
	stored.id = world_id
	stored.scene = definition.scene
	stored.display_name = definition.display_name
	stored.metadata = copied_metadata
	_catalog[world_id] = stored
	_guard.finish(_guard.get_operation_id())
	return OK


func has_world(world_id: StringName) -> bool:
	return _catalog.has(world_id)


func get_active_world_id() -> StringName:
	if _active_root == null or not is_instance_valid(_active_root):
		return &""
	return _active_id


func get_active_world_root() -> Node:
	if _active_root == null or not is_instance_valid(_active_root):
		_active_root = null
		_active_id = &""
		return null
	return _active_root


func resolve_entry_point(entry_id: StringName) -> WorldEntryPointData:
	var root := get_active_world_root()
	if root == null or not root.is_inside_tree():
		return null
	if WorldId.validate(entry_id) != OK:
		return null
	return _snapshot_entry(root, _active_id, entry_id)


func is_loading() -> bool:
	if _guard == null:
		return false
	return _guard.is_busy() and _guard.get_operation() == &"load_world"


func load_world(world_id: StringName, entry_id: StringName = &"") -> Error:
	if not is_inside_tree() or _guard == null or _events == null or _container == null:
		return WorldDiagnostics.reject(&"load_world", ERR_UNCONFIGURED, _reject_context(world_id, entry_id))
	var id_err := WorldId.validate(world_id)
	if id_err != OK:
		return WorldDiagnostics.reject(&"load_world", id_err, _reject_context(world_id, entry_id))
	if not _catalog.has(world_id):
		return WorldDiagnostics.reject(&"load_world", ERR_DOES_NOT_EXIST, _reject_context(world_id, entry_id))
	if entry_id != &"":
		var entry_err := WorldId.validate(entry_id)
		if entry_err != OK:
			return WorldDiagnostics.reject(&"load_world", entry_err, _reject_context(world_id, entry_id))
	var begin_err := _guard.try_begin(&"load_world")
	if begin_err != OK:
		return WorldDiagnostics.reject(&"load_world", begin_err, _reject_context(world_id, entry_id))
	_pending_world_id = world_id
	_pending_entry_id = entry_id
	_pending_operation_id = _guard.get_operation_id()
	call_deferred("_run_load")
	return OK


func unload_world() -> Error:
	if not is_inside_tree() or _guard == null or _events == null or _container == null:
		return WorldDiagnostics.reject(&"unload_world", ERR_UNCONFIGURED, {})
	if get_active_world_root() == null:
		return WorldDiagnostics.reject(&"unload_world", ERR_DOES_NOT_EXIST, {})
	var begin_err := _guard.try_begin(&"unload_world")
	if begin_err != OK:
		return WorldDiagnostics.reject(&"unload_world", begin_err, _reject_context(_active_id, &""))
	_pending_world_id = _active_id
	_pending_entry_id = &""
	_pending_operation_id = _guard.get_operation_id()
	call_deferred("_run_unload")
	return OK


func _run_load() -> void:
	var operation_id := _pending_operation_id
	var world_id := _pending_world_id
	var entry_id := _pending_entry_id
	_events.world_loading.emit(_event_context(operation_id, &"load_world", world_id, &"started"))
	var definition: WorldDefinition = _catalog.get(world_id)
	if definition == null or definition.scene == null:
		_fail_load(operation_id, world_id, entry_id, ERR_DOES_NOT_EXIST, &"instantiate")
		return
	var candidate := definition.scene.instantiate()
	if candidate == null:
		_fail_load(operation_id, world_id, entry_id, ERR_CANT_CREATE, &"instantiate")
		return
	var valid_err := WorldSceneValidator.validate_candidate(candidate, entry_id)
	if valid_err != OK:
		candidate.free()
		_fail_load(operation_id, world_id, entry_id, valid_err, &"validate")
		return
	var expected_dim := WorldSceneValidator.dimension_of_root(candidate)
	var outgoing: Node = _active_root
	var outgoing_id := _active_id
	if outgoing != null and not is_instance_valid(outgoing):
		outgoing = null
		outgoing_id = &""
	if _entities != null:
		var pre := _entities.preflight_candidate(candidate, outgoing, world_id)
		if pre == OK and _persistence != null:
			pre = _persistence.preflight_logical_ids(candidate, world_id)
		if pre != OK:
			candidate.free()
			_fail_load(operation_id, world_id, entry_id, pre, &"validate")
			return
		_entities.begin_batch()
		_entities.bind_world_root(world_id, candidate)
	if outgoing != null and is_instance_valid(outgoing):
		if outgoing.get_parent() == _container:
			_container.remove_child(outgoing)
	_active_id = world_id
	_active_root = candidate
	_container.add_child(candidate)
	var inv := _verify_owned_invariants(candidate, expected_dim)
	if inv != OK:
		_fail_activation(outgoing, outgoing_id, candidate, operation_id, world_id, entry_id, inv)
		return
	var entry: WorldEntryPointData = null
	if entry_id != &"":
		entry = _snapshot_entry(candidate, world_id, entry_id)
		if entry == null:
			_fail_activation(
				outgoing, outgoing_id, candidate, operation_id, world_id, entry_id, ERR_DOES_NOT_EXIST
			)
			return
	if outgoing != null and is_instance_valid(outgoing):
		if _entities != null:
			_entities.unbind_world_root(outgoing)
		outgoing.free()
	if _entities != null:
		_entities.commit_batch()
	_events.world_loaded.emit(_event_context(operation_id, &"load_world", world_id, &"commit"), entry)
	_guard.finish(operation_id)


func _run_unload() -> void:
	var operation_id := _pending_operation_id
	var world_id := _pending_world_id
	_events.world_unloading.emit(_event_context(operation_id, &"unload_world", world_id, &"started"))
	var unload_err := unload_active_owned()
	if unload_err != OK:
		WorldDiagnostics.reject(
			&"unload_world", unload_err, _reject_context(world_id, &"")
		)
		_events.world_unload_failed.emit(
			unload_err, _event_context(operation_id, &"unload_world", world_id, &"unload")
		)
		_guard.finish(operation_id)
		return
	_events.world_unloaded.emit(_event_context(operation_id, &"unload_world", world_id, &"commit"))
	_guard.finish(operation_id)


func unload_active_owned() -> Error:
	if _entities != null:
		_entities.begin_batch()
	var root := _active_root
	_active_root = null
	_active_id = &""
	if root != null and is_instance_valid(root):
		if root.get_parent() == _container:
			_container.remove_child(root)
		if _entities != null:
			_entities.unbind_world_root(root)
		root.free()
	if _entities != null:
		_entities.commit_batch()
	return OK


func activate_prepared_candidate(world_id: StringName, candidate: Node) -> Error:
	var pre := _activate_preconditions(world_id, candidate)
	if pre != OK:
		return WorldDiagnostics.reject(&"activate_prepared", pre, _reject_context(world_id, &""))
	var begin_err := _guard.try_begin(&"activate_prepared")
	if begin_err != OK:
		return WorldDiagnostics.reject(&"activate_prepared", begin_err, _reject_context(world_id, &""))
	var err := _activate_prepared_body(world_id, candidate)
	_guard.finish(_guard.get_operation_id())
	if err != OK:
		return WorldDiagnostics.reject(&"activate_prepared", err, _reject_context(world_id, &""))
	return OK


## Silent owned form for a command that already holds the guard. It must not
## log: the owning command emits exactly one diagnostic of its own.
func activate_prepared_owned(world_id: StringName, candidate: Node) -> Error:
	var pre := _activate_preconditions(world_id, candidate)
	if pre != OK:
		return pre
	return _activate_prepared_body(world_id, candidate)


## Instantiate and validate a detached candidate without attaching it, so a
## load can restore records into it before anything becomes visible.
func instantiate_candidate_owned(world_id: StringName) -> Dictionary:
	if not is_inside_tree() or _container == null:
		return {"error": ERR_UNCONFIGURED, "candidate": null}
	var definition: WorldDefinition = _catalog.get(world_id)
	if definition == null or definition.scene == null:
		return {"error": ERR_DOES_NOT_EXIST, "candidate": null}
	var candidate := definition.scene.instantiate()
	if candidate == null:
		return {"error": ERR_CANT_CREATE, "candidate": null}
	var valid_err := WorldSceneValidator.validate_candidate(candidate, &"")
	if valid_err != OK:
		candidate.free()
		return {"error": valid_err, "candidate": null}
	return {"error": OK, "candidate": candidate}


## Entry-point existence on a candidate that is not in the tree yet. Deliberately
## returns no WorldEntryPointData: a global transform is meaningless while the
## root is detached, so travel validates the entry here -- before anything is
## torn down -- and snapshots it through resolve_entry_point after activation.
##
## Separate from instantiate_candidate_owned rather than a parameter on it, so a
## missing entry point and an unregistered world stay distinguishable: both are
## ERR_DOES_NOT_EXIST, and the only thing telling them apart in a diagnostic is
## which stage reported it. Silent: the owning command logs.
func verify_entry_owned(candidate: Node, entry_id: StringName) -> Error:
	if entry_id == &"":
		return OK
	if candidate == null or not is_instance_valid(candidate):
		return ERR_INVALID_PARAMETER
	return WorldSceneValidator.validate_candidate(candidate, entry_id)


## The travel swap: identical to activate_prepared_owned except that the outgoing
## root is handed back alive instead of being freed. A load frees its outgoing
## root at activation, which is right for a load and wrong for a travel -- travel
## commits only after the project's placement hook has run, and that is reachable
## only while the outgoing world is still reattachable. Undo by activating the
## retained root back: it is parentless, so it is a valid prepared candidate, and
## doing so frees the destination on the way through.
##
## The detach must stay inside this call rather than being a separate step: the
## outgoing root's entities unregister from _exit_tree when it leaves the
## container, and those events belong in the same entity batch as the incoming
## root's registrations. Silent: the owning command logs.
## -> {error, retained}
func activate_retaining_owned(world_id: StringName, candidate: Node) -> Dictionary:
	var pre := _activate_preconditions(world_id, candidate)
	if pre != OK:
		return {"error": pre, "retained": null}
	var retained: Array[Node] = []
	var err := _activate_prepared_body(world_id, candidate, true, retained)
	if err != OK or retained.is_empty():
		return {"error": err, "retained": null}
	return {"error": OK, "retained": retained[0]}


func _activate_preconditions(world_id: StringName, candidate: Node) -> Error:
	if not is_inside_tree() or _guard == null or _container == null:
		return ERR_UNCONFIGURED
	if candidate == null or candidate.get_parent() != null or candidate.is_inside_tree():
		return ERR_INVALID_PARAMETER
	return OK


func _activate_prepared_body(
	world_id: StringName,
	candidate: Node,
	retain_outgoing: bool = false,
	retained: Array[Node] = []
) -> Error:
	var expected_dim := WorldSceneValidator.dimension_of_root(candidate)
	var outgoing: Node = _active_root
	var outgoing_id := _active_id
	if outgoing != null and not is_instance_valid(outgoing):
		outgoing = null
		outgoing_id = &""
	if _entities != null:
		var pre := _entities.preflight_candidate(candidate, outgoing, world_id)
		if pre == OK and _persistence != null:
			pre = _persistence.preflight_logical_ids(candidate, world_id)
		if pre != OK:
			return pre
		_entities.begin_batch()
		_entities.bind_world_root(world_id, candidate)
	if outgoing != null and is_instance_valid(outgoing):
		if outgoing.get_parent() == _container:
			_container.remove_child(outgoing)
	_active_id = world_id
	_active_root = candidate
	_container.add_child(candidate)
	var inv := _verify_owned_invariants(candidate, expected_dim)
	if inv != OK:
		if _entities != null:
			_entities.unbind_world_root(candidate)
		# Reattaches the outgoing root and frees the candidate, so the caller
		# must not free it again.
		_rollback_activation(outgoing, outgoing_id, candidate)
		if _entities != null:
			_entities.abort_batch()
		return inv
	if outgoing != null and is_instance_valid(outgoing):
		if _entities != null:
			_entities.unbind_world_root(outgoing)
		if retain_outgoing:
			retained.append(outgoing)
		else:
			outgoing.free()
	if _entities != null:
		_entities.commit_batch()
	return OK


func _fail_load(
	operation_id: int,
	world_id: StringName,
	entry_id: StringName,
	reason: Error,
	stage: StringName
) -> void:
	var diagnostic := _reject_context(world_id, entry_id)
	diagnostic["stage"] = stage
	WorldDiagnostics.reject(&"load_world", reason, diagnostic)
	_events.world_load_failed.emit(reason, _event_context(operation_id, &"load_world", world_id, stage))
	_guard.finish(operation_id)


func _fail_activation(
	outgoing: Node,
	outgoing_id: StringName,
	candidate: Node,
	operation_id: int,
	world_id: StringName,
	entry_id: StringName,
	reason: Error
) -> void:
	if _entities != null:
		_entities.unbind_world_root(candidate)
	_rollback_activation(outgoing, outgoing_id, candidate)
	if _entities != null:
		_entities.abort_batch()
	_fail_load(operation_id, world_id, entry_id, reason, &"activate")


func _rollback_activation(outgoing: Node, outgoing_id: StringName, candidate: Node) -> void:
	if candidate != null and is_instance_valid(candidate):
		if candidate.get_parent() == _container:
			_container.remove_child(candidate)
		candidate.free()
	if outgoing != null and is_instance_valid(outgoing):
		if outgoing.get_parent() != _container:
			_container.add_child(outgoing)
		_active_root = outgoing
		_active_id = outgoing_id
	else:
		_active_root = null
		_active_id = &""


func _verify_owned_invariants(candidate: Node, expected_dim: WorldSceneValidator.Dimension) -> Error:
	if candidate == null or not is_instance_valid(candidate):
		return ERR_CANT_CREATE
	if candidate.get_parent() != _container:
		return ERR_CANT_CREATE
	if _container.get_child_count() != 1:
		return ERR_CANT_CREATE
	if not candidate.is_inside_tree():
		return ERR_CANT_CREATE
	if WorldSceneValidator.dimension_of_root(candidate) != expected_dim:
		return ERR_CANT_CREATE
	if expected_dim == WorldSceneValidator.Dimension.NODE_2D and not (candidate is Node2D):
		return ERR_CANT_CREATE
	if expected_dim == WorldSceneValidator.Dimension.NODE_3D and not (candidate is Node3D):
		return ERR_CANT_CREATE
	if _entities != null:
		var registered := _entities.verify_root_registered(candidate)
		if registered != OK:
			return registered
	return OK


func _snapshot_entry(root: Node, world_id: StringName, entry_id: StringName) -> WorldEntryPointData:
	var marker := WorldSceneValidator.find_marker(root, entry_id)
	if marker == null or not marker.is_inside_tree():
		return null
	if marker is WorldEntryPoint2D:
		var data_2d := WorldEntryPoint2DData.new()
		data_2d.world_id = world_id
		data_2d.id = entry_id
		data_2d.transform = (marker as Node2D).global_transform
		return data_2d
	if marker is WorldEntryPoint3D:
		var data_3d := WorldEntryPoint3DData.new()
		data_3d.world_id = world_id
		data_3d.id = entry_id
		data_3d.transform = (marker as Node3D).global_transform
		return data_3d
	return null


func _copy_metadata(source: Dictionary, dest: Dictionary) -> Error:
	var err := WorldValue.validate(source)
	if err != OK:
		dest.clear()
		return err
	var copied: Variant = WorldValue.clone_validated(source)
	dest.clear()
	if typeof(copied) != TYPE_DICTIONARY:
		return ERR_INVALID_PARAMETER
	for key: Variant in copied.keys():
		dest[key] = copied[key]
	return OK


func _event_context(
	operation_id: int,
	operation: StringName,
	world_id: StringName,
	stage: StringName
) -> Dictionary:
	return {
		"operation_id": operation_id,
		"operation": operation,
		"world_id": world_id,
		"stage": stage,
	}.duplicate()


func _reject_context(world_id: StringName, entry_id: StringName) -> Dictionary:
	var context: Dictionary = {}
	if String(world_id) != "":
		context["world_id"] = world_id
	if String(entry_id) != "":
		context["entry_id"] = entry_id
	return context
