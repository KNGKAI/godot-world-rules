class_name WorldDynamicMaterializer
extends RefCounted
## Instantiates dynamic records into a detached candidate, so a record whose
## actor is not in the authored scene can bring its own. Holds no state between
## calls and does not log: the owning command emits one diagnostic.
##
## Each instance is attached **provisionally under the candidate root**, not
## under its eventual parent. Three reasons, in order of severity: the
## tombstone pass frees authored actors, and a dynamic parented under a
## tombstoned one would be freed as collateral; resolving eventual parents needs
## the index, which does not exist yet; and dependency-ordered reparenting is
## already implemented twice, correctly, by the passes that follow.
##
## Attaching before indexing is also why the restore pipeline needs no other
## change: _fill_index walks the candidate and produces entries for these
## instances by the same code that produces them for authored actors, so the
## three existing "does this actor exist" gates pass unchanged. Injecting index
## entries by hand would make this a second source of truth; relaxing the gates
## would let a genuinely broken authored scene through, which is exactly what
## README D8 wrote them to prevent.
##
## _enter_tree never fires here: Godot calls it on entering the SceneTree, not
## on being parented, and the candidate is detached. So registration happens
## once, later, inside the director's batch -- and this produces no diagnostic
## noise, which matters because the runner fails on any raw ERROR line.


## -> {error, stage, entity_id, component_id, archetype_id}
func prepare(
	world_recs: Dictionary, candidate_root: Node, catalog: WorldArchetypeCatalog
) -> Dictionary:
	var dimension := WorldSceneValidator.dimension_of_root(candidate_root)
	if dimension == WorldSceneValidator.Dimension.NONE:
		return _failure(ERR_INVALID_DATA, &"", &"")
	var claimed: Dictionary = {}
	_claimed_ids(candidate_root, claimed)
	# Reused verbatim: removed records are already excluded, so a tombstoned
	# dynamic never reaches archetype resolution and a tombstone for an
	# archetype the project stopped registering stays a clean no-op.
	var order := WorldPersistenceManager.restore_order(world_recs)
	for entity_id: StringName in order:
		var rec: EntityRecord = world_recs[entity_id]
		if rec.origin != WorldEntityOrigin.Kind.DYNAMIC:
			if String(rec.archetype_id) != "":
				return _failure(ERR_INVALID_PARAMETER, rec.id, rec.archetype_id)
			continue
		if String(rec.archetype_id) == "":
			return _failure(ERR_INVALID_PARAMETER, rec.id, &"")
		# A resource path contains "/", which the id grammar refuses, so a save
		# string dies here and never reaches the catalog.
		if WorldId.validate(rec.archetype_id) != OK:
			return _failure(ERR_INVALID_PARAMETER, rec.id, rec.archetype_id)
		if claimed.has(rec.id):
			return _failure(ERR_ALREADY_EXISTS, rec.id, rec.archetype_id)
		if catalog == null:
			return _failure(ERR_UNCONFIGURED, rec.id, rec.archetype_id)
		var definition := catalog.get_definition(rec.archetype_id)
		if definition == null:
			# Retained, not skipped: skipping would leave the record while its
			# actor never returns, and no later capture would clear it.
			return _failure(ERR_DOES_NOT_EXIST, rec.id, rec.archetype_id)
		if definition.dimension != dimension:
			return _failure(ERR_INVALID_DATA, rec.id, rec.archetype_id)
		if definition.scene == null:
			return _failure(ERR_CANT_CREATE, rec.id, rec.archetype_id)
		# The ownership window opens here and closes at add_child. At most one
		# instance is held at a time, and every check that can run before this
		# point does, so the window is as short as it can be.
		var pending := definition.scene.instantiate()
		if pending == null:
			return _failure(ERR_CANT_CREATE, rec.id, rec.archetype_id)
		var shaped := _verify_shape(pending, dimension)
		if shaped != OK:
			pending.free()
			return _failure(shaped, rec.id, rec.archetype_id)
		var entity := _entity_of(pending)
		entity.persistent_id = rec.id
		entity.persistence_policy = rec.policy
		entity._mark_dynamic(rec.archetype_id)
		pending.name = _node_name_for(rec.id)
		candidate_root.add_child(pending)
		claimed[rec.id] = true
	return {"error": OK, "stage": &"", "entity_id": &"", "component_id": &"", "archetype_id": &""}


## Every id the authored scene already claims, so a record cannot produce a
## second actor for one.
static func _claimed_ids(node: Node, out: Dictionary) -> void:
	if node is PersistentEntity:
		out[(node as PersistentEntity).persistent_id] = true
	for child in node.get_children():
		_claimed_ids(child, out)


## A second line of defence: register_archetype checked the same shapes, but a
## catalog entry could have been registered by an older build of the project.
static func _verify_shape(
	instance: Node, dimension: WorldSceneValidator.Dimension
) -> Error:
	if WorldSceneValidator.dimension_of_root(instance) != dimension:
		return ERR_INVALID_DATA
	var entities: Array = []
	_collect(instance, entities, func (node: Node) -> bool:
		return node is PersistentEntity
	)
	if entities.size() != 1:
		return ERR_INVALID_DATA
	var entity: PersistentEntity = entities[0]
	if entity.get_parent() != instance:
		return ERR_INVALID_DATA
	if entity.persistent_id != &"":
		return ERR_INVALID_DATA
	# An entry marker would make resolve_entry_point ambiguous after travel has
	# already validated the entry, and an attachment id would collide between
	# two instances of one archetype.
	var markers: Array = []
	_collect(instance, markers, func (node: Node) -> bool:
		return node is WorldEntryPoint2D or node is WorldEntryPoint3D \
			or node is WorldAttachment
	)
	if not markers.is_empty():
		return ERR_INVALID_DATA
	return OK


static func _entity_of(instance: Node) -> PersistentEntity:
	for child in instance.get_children():
		if child is PersistentEntity:
			return child
	return null


## Deterministic, and legal as a Node name: ":" is not.
static func _node_name_for(entity_id: StringName) -> String:
	return String(entity_id).replace(":", "_")


static func _collect(node: Node, out: Array, matches: Callable) -> void:
	if matches.call(node):
		out.append(node)
	for child in node.get_children():
		_collect(child, out, matches)


static func _failure(
	reason: Error, entity_id: StringName, archetype_id: StringName
) -> Dictionary:
	return {
		"error": reason,
		"stage": &"materialize",
		"entity_id": entity_id,
		"component_id": &"",
		"archetype_id": archetype_id,
	}
