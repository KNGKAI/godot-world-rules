class_name WorldEntityManager
extends RefCounted
## Live entity lookup and scene-swap registration batches.


var _guard: WorldOperationGuard
var _events: WorldEvents
var _persistence_ref: WeakRef
var _registry: WorldEntityRegistry = WorldEntityRegistry.new()
var _bound_roots: Dictionary = {}
var _batch_active: bool = false
var _queued_events: Array = []
## Registered spawnable archetypes. Owned here rather than by the persistence
## manager because the dependency already runs this way: persistence holds a
## hard reference to this manager, and this manager holds only a WeakRef back.
## Restoration reaches the catalog along that existing direction.
var _archetypes: WorldArchetypeCatalog = WorldArchetypeCatalog.new()
var _ids: WorldEntityIdGenerator = WorldEntityIdGenerator.new()
## Weak, like _persistence_ref: the facade Node owns this manager, so a strong
## reference back would be a cycle. spawn/despawn are thin forwarders to World,
## which owns the guard and the deferred-command engine -- there must not be a
## second command engine.
var _host_ref: WeakRef = null


func configure(guard: WorldOperationGuard, events: WorldEvents) -> void:
	_guard = guard
	_events = events


func set_persistence(persistence: WorldPersistenceManager) -> void:
	if persistence == null:
		_persistence_ref = null
		return
	_persistence_ref = weakref(persistence)


## Make a scene spawnable. Registration validates the scene's shape by
## instantiating it once, so a malformed archetype is refused at project setup
## rather than during gameplay. Archetypes are process setup, like world
## definitions: new_game does not clear them.
func set_host(host: Node) -> void:
	_host_ref = null if host == null else weakref(host)


## Create one entity from a registered archetype. Accepted synchronously like
## every other coordinated command: OK means accepted, never finished, and the
## generated id arrives in entity_spawned.
func spawn(request: WorldSpawnRequest) -> Error:
	var host := _host()
	if host == null:
		return WorldDiagnostics.reject(&"spawn", ERR_UNCONFIGURED, {})
	return host._begin_spawn(request)


## Deliberate removal of an atomic set. Can remove recorded-but-unloaded
## entities as well as loaded ones, but cannot invent records for unknown ids.
func despawn(entity_ids: Array[StringName]) -> Error:
	var host := _host()
	if host == null:
		return WorldDiagnostics.reject(&"despawn", ERR_UNCONFIGURED, {})
	return host._begin_despawn(entity_ids)


func _host() -> Node:
	if _host_ref == null:
		return null
	var host: Node = _host_ref.get_ref()
	if host == null or not is_instance_valid(host):
		return null
	return host


## Stamp a generated identity onto a freshly instantiated archetype before it
## enters any tree: PersistentEntity freezes both exports once it registers.
func stamp_identity_owned(
	instance: Node, id: StringName, policy: WorldPersistencePolicy.Kind, archetype: StringName
) -> Error:
	if instance == null or not is_instance_valid(instance):
		return ERR_INVALID_DATA
	var found: PersistentEntity = null
	for child in instance.get_children():
		if child is PersistentEntity:
			if found != null:
				return ERR_INVALID_DATA
			found = child
	if found == null:
		return ERR_INVALID_DATA
	if found.registration_id() != &"":
		return ERR_INVALID_DATA
	found.persistent_id = id
	found.persistence_policy = policy
	found._mark_dynamic(archetype)
	return OK


## Detach and free an actor inside the caller's open batch, so the resulting
## entity_unregistered is queued rather than published mid-operation.
func release_actor_owned(actor: Node) -> void:
	if actor == null or not is_instance_valid(actor):
		return
	var parent := actor.get_parent()
	if parent != null:
		parent.remove_child(actor)
	actor.free()


## Drop outstanding id reservations. Archetypes are retained: registration is
## process setup, like world definitions. Reservations are an intra-operation
## construct, so only new_game needs this -- a load's install_owned does not.
func clear_dynamic_owned() -> void:
	_ids.clear()


func register_archetype(definition: WorldEntityDefinition) -> Error:
	if _guard == null:
		return _reject_archetype(ERR_UNCONFIGURED, &"")
	var archetype_id: StringName = &"" if definition == null else definition.id
	var begin_err := _guard.try_begin(&"register_archetype")
	if begin_err != OK:
		return _reject_archetype(begin_err, archetype_id)
	var err := _archetypes.register(definition)
	_guard.finish(_guard.get_operation_id())
	if err != OK:
		return _reject_archetype(err, archetype_id)
	return OK


func archetypes() -> WorldArchetypeCatalog:
	return _archetypes


func has_archetype(archetype_id: StringName) -> bool:
	return _archetypes.has(archetype_id)


func ids() -> WorldEntityIdGenerator:
	return _ids


## Every set a generated ID must avoid, in two lookups: the live registry, and
## the ownership map -- which covers unloaded records and tombstones alike,
## because _rebuild_ownership indexes every record with no removed filter.
## Outstanding reservations are checked inside the generator.
func id_in_use(id: StringName) -> bool:
	if _registry.contains(id):
		return true
	return _owned_world(id) != &""


func _reject_archetype(reason: Error, archetype_id: StringName) -> Error:
	var context: Dictionary = {}
	if String(archetype_id) != "":
		context["archetype_id"] = archetype_id
	return WorldDiagnostics.reject(&"register_archetype", reason, context)


func resolve(id: StringName) -> Node:
	return _registry.resolve(id)


func contains(id: StringName) -> bool:
	return _registry.contains(id)


func bind_world_root(world_id: StringName, root: Node) -> void:
	if root == null or not is_instance_valid(root):
		return
	_bound_roots[root.get_instance_id()] = world_id


func unbind_world_root(root: Node) -> void:
	if root == null:
		return
	_bound_roots.erase(root.get_instance_id())


func begin_batch() -> void:
	_batch_active = true
	_queued_events.clear()


func commit_batch() -> void:
	_batch_active = false
	if _events == null:
		_queued_events.clear()
		return
	for item: Variant in _queued_events:
		var kind: StringName = item["signal"]
		var entity_id: StringName = item["id"]
		var world_id: StringName = item["world_id"]
		if kind == &"entity_unregistered":
			_events.entity_unregistered.emit(entity_id, world_id)
		else:
			_events.entity_registered.emit(entity_id, world_id)
	_queued_events.clear()


func abort_batch() -> void:
	_batch_active = false
	_queued_events.clear()


func preflight_candidate(
	candidate: Node, outgoing_root: Node, world_id: StringName = &""
) -> Error:
	if candidate == null or not is_instance_valid(candidate):
		return ERR_INVALID_DATA
	var components: Array = []
	_collect_components(candidate, components)
	var seen_ids: Dictionary = {}
	var seen_actors: Dictionary = {}
	for component: Variant in components:
		var pe := component as PersistentEntity
		var actor := pe.get_parent()
		if actor == null or actor is PersistentEntity:
			return ERR_INVALID_PARAMETER
		if WorldId.validate(pe.persistent_id) != OK:
			return ERR_INVALID_PARAMETER
		if WorldPersistencePolicy.validate(pe.persistence_policy) != OK:
			return ERR_INVALID_PARAMETER
		if seen_ids.has(pe.persistent_id):
			return ERR_ALREADY_EXISTS
		var actor_key := actor.get_instance_id()
		if seen_actors.has(actor_key):
			return ERR_ALREADY_EXISTS
		seen_ids[pe.persistent_id] = true
		seen_actors[actor_key] = true
		var live := _registry.resolve(pe.persistent_id)
		if live != null and not _is_outgoing_actor(live, outgoing_root):
			return ERR_ALREADY_EXISTS
	return OK


func verify_root_registered(root: Node) -> Error:
	if root == null or not is_instance_valid(root):
		return ERR_CANT_CREATE
	var components: Array = []
	_collect_components(root, components)
	for component: Variant in components:
		var pe := component as PersistentEntity
		var actor := pe.get_parent()
		var expected_id := pe.registration_id()
		if expected_id == &"":
			expected_id = pe.persistent_id
		if _registry.resolve(expected_id) != actor:
			return ERR_CANT_CREATE
	return OK


func register_component(component: PersistentEntity) -> Error:
	if component == null or not is_instance_valid(component):
		return _reject_register(ERR_INVALID_PARAMETER, &"", &"")
	var actor := component.get_parent()
	if actor == null or actor is PersistentEntity:
		return _reject_register(ERR_INVALID_PARAMETER, component.persistent_id, &"")
	var world_id := world_id_for_node(actor)
	if world_id == &"":
		return _reject_register(ERR_UNCONFIGURED, component.persistent_id, &"")
	if WorldId.validate(component.persistent_id) != OK:
		return _reject_register(ERR_INVALID_PARAMETER, component.persistent_id, world_id)
	if WorldPersistencePolicy.validate(component.persistence_policy) != OK:
		return _reject_register(ERR_INVALID_PARAMETER, component.persistent_id, world_id)
	if _guard != null and _guard.is_busy() and not _batch_active:
		return _reject_register(ERR_BUSY, component.persistent_id, world_id)
	var owned := _owned_world(component.persistent_id)
	if owned != &"" and owned != world_id:
		return _reject_register(ERR_ALREADY_EXISTS, component.persistent_id, world_id)
	var current := _registry.resolve(component.persistent_id)
	if current == actor:
		return OK
	var err := _registry.register_entity(component.persistent_id, actor)
	if err != OK:
		return _reject_register(err, component.persistent_id, world_id)
	_emit_or_queue(&"entity_registered", component.persistent_id, world_id)
	return OK


func unregister_component(component: PersistentEntity) -> Error:
	if component == null:
		return ERR_INVALID_PARAMETER
	var actor := component.registered_actor()
	if actor == null:
		actor = component.get_parent()
	var entity_id := component.registration_id()
	if entity_id == &"":
		entity_id = component.persistent_id
	var world_id := component.registered_world_id()
	if world_id == &"":
		world_id = world_id_for_node(actor)
	var err := _registry.unregister_entity(entity_id, actor)
	if err != OK:
		return err
	_emit_or_queue(&"entity_unregistered", entity_id, world_id)
	return OK


func root_for_world(world_id: StringName) -> Node:
	for key: Variant in _bound_roots.keys():
		if _bound_roots[key] != world_id:
			continue
		var found: Object = instance_from_id(key as int)
		if found is Node and is_instance_valid(found):
			return found as Node
	return null


func _owned_world(entity_id: StringName) -> StringName:
	if _persistence_ref == null:
		return &""
	var held: Variant = _persistence_ref.get_ref()
	if held == null or not (held is WorldPersistenceManager):
		return &""
	return (held as WorldPersistenceManager).owned_world(entity_id)


func world_id_for_node(node: Node) -> StringName:
	var current := node
	while current != null:
		var key := current.get_instance_id()
		if _bound_roots.has(key):
			return _bound_roots[key] as StringName
		current = current.get_parent()
	return &""


func _reject_register(reason: Error, entity_id: StringName, world_id: StringName) -> Error:
	if _batch_active:
		return reason
	var context: Dictionary = {}
	if String(entity_id) != "":
		context["entity_id"] = entity_id
	if String(world_id) != "":
		context["world_id"] = world_id
	return WorldDiagnostics.reject(&"register_entity", reason, context)


func _emit_or_queue(kind: StringName, entity_id: StringName, world_id: StringName) -> void:
	if _batch_active:
		_queued_events.append({
			"signal": kind,
			"id": entity_id,
			"world_id": world_id,
		})
		return
	if _events == null:
		return
	if kind == &"entity_unregistered":
		_events.entity_unregistered.emit(entity_id, world_id)
	else:
		_events.entity_registered.emit(entity_id, world_id)


func _is_outgoing_actor(actor: Node, outgoing_root: Node) -> bool:
	if outgoing_root == null or not is_instance_valid(outgoing_root):
		return false
	if actor == outgoing_root:
		return true
	return outgoing_root.is_ancestor_of(actor)


func _collect_components(node: Node, out: Array) -> void:
	if node is PersistentEntity:
		out.append(node)
	for child in node.get_children():
		_collect_components(child, out)
