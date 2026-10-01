class_name WorldPersistenceManager
extends RefCounted
## Per-world entity records. Live lookup stays on WorldEntityManager.


var _guard: WorldOperationGuard
var _entities: WorldEntityManager
var _records: Dictionary = {}
var _ownership: Dictionary = {}
var _participants: WorldParticipantRegistry = WorldParticipantRegistry.new()
var _store: WorldSaveSlotStore = WorldSaveSlotStore.new()

## Container migrations, addon-owned (README D21). One real step, registered by
## Phase 9 when the format advanced to 2: it marks every version-one record
## authored. A test asserts the exact contents rather than the size -- the whole
## load pipeline behaves differently depending on what is in here, and there is
## deliberately no 0 -> 1 step, because format 0 never shipped.
var _migrations: WorldMigrationManager = _container_migrations()
var _materializer := WorldDynamicMaterializer.new()


## A builder rather than an inline new(), so register_migration's Error is
## inspected instead of discarded.
static func _container_migrations() -> WorldMigrationManager:
	var manager := WorldMigrationManager.new()
	var err := manager.register_migration(1, WorldSaveV1ToV2.new())
	assert(err == OK, "the production container migration chain is malformed")
	return manager


func configure(guard: WorldOperationGuard, entities: WorldEntityManager) -> void:
	_guard = guard
	_entities = entities


func preflight_logical_ids(candidate: Node, world_id: StringName) -> Error:
	var entities: Array = []
	_collect_entities(candidate, entities)
	for item: Variant in entities:
		var pe := item as PersistentEntity
		var owned := owned_world(pe.persistent_id)
		if owned != &"" and owned != world_id:
			return ERR_ALREADY_EXISTS
	return OK


func owned_world(entity_id: StringName) -> StringName:
	if _ownership.has(entity_id):
		return _ownership[entity_id] as StringName
	return &""


func get_record(world_id: StringName, entity_id: StringName) -> EntityRecord:
	if not _records.has(world_id):
		return null
	var world_recs: Dictionary = _records[world_id]
	if not world_recs.has(entity_id):
		return null
	var rec: EntityRecord = world_recs[entity_id]
	return rec.duplicate_record()


func snapshot_records() -> Dictionary:
	var out: Dictionary = {}
	for world_id: Variant in _records.keys():
		var inner: Dictionary = {}
		var world_recs: Dictionary = _records[world_id]
		for entity_id: Variant in world_recs.keys():
			var rec: EntityRecord = world_recs[entity_id]
			inner[entity_id] = rec.duplicate_record()
		out[world_id] = inner
	return out


func clear_owned() -> void:
	_records.clear()
	_ownership.clear()


## Replace the authoritative record tables wholesale. Used inside a load's
## commit window, which is why it takes no guard and emits nothing.
func install_owned(records: Dictionary) -> void:
	_records = records
	_rebuild_ownership()


func participants() -> WorldParticipantRegistry:
	return _participants


func has_participant(id: StringName) -> bool:
	return _participants.has(id)


func register_participant(id: StringName, participant: PersistenceParticipant) -> Error:
	if _guard == null:
		return _reject(&"register_participant", ERR_UNCONFIGURED, _participant_ctx(id))
	if WorldId.validate(id) != OK:
		return _reject(&"register_participant", ERR_INVALID_PARAMETER, _participant_ctx(id))
	var begin_err := _guard.try_begin(&"register_participant")
	if begin_err != OK:
		return _reject(&"register_participant", begin_err, _participant_ctx(id))
	var err := _participants.register(id, participant)
	_guard.finish(_guard.get_operation_id())
	if err != OK:
		return _reject(&"register_participant", err, _participant_ctx(id))
	return OK


func unregister_participant(id: StringName, participant: PersistenceParticipant) -> Error:
	if _guard == null:
		return _reject(&"unregister_participant", ERR_UNCONFIGURED, _participant_ctx(id))
	var begin_err := _guard.try_begin(&"unregister_participant")
	if begin_err != OK:
		return _reject(&"unregister_participant", begin_err, _participant_ctx(id))
	var err := _participants.unregister(id, participant)
	_guard.finish(_guard.get_operation_id())
	if err != OK:
		return _reject(&"unregister_participant", err, _participant_ctx(id))
	return OK


func list_slots() -> Array[WorldSaveSlotInfo]:
	return _store.list_slots()


func store() -> WorldSaveSlotStore:
	return _store


func migrations() -> WorldMigrationManager:
	return _migrations


## Private test seam: point the store at an isolated save root. Nothing in
## runtime/ calls this and the adapter itself refuses a root outside user://.
func _configure_store(slot_store: WorldSaveSlotStore) -> void:
	_store = slot_store


## Everything a slot carries from the record tables: SAVE_GAME records and
## their tombstones only. SESSION and NONE are dropped from the copy, so they
## survive in memory while being excluded from the file.
## -> {error, world_id, entity_id, records}
func snapshot_save_records() -> Dictionary:
	var out: Dictionary = {}
	for world_id: Variant in _records.keys():
		var kept: Dictionary = {}
		var world_recs: Dictionary = _records[world_id]
		for entity_id: Variant in world_recs.keys():
			var record: EntityRecord = world_recs[entity_id]
			if record.policy != WorldPersistencePolicy.Kind.SAVE_GAME:
				continue
			kept[entity_id] = record.duplicate_record()
		if kept.is_empty():
			continue
		# A record whose persistent parent was excluded by policy or is only a
		# tombstone cannot be reconstructed, so it must not reach a slot.
		for entity_id: Variant in kept.keys():
			var record: EntityRecord = kept[entity_id]
			if record.removed:
				continue
			if record.parent_kind != WorldEntityParent.Kind.PERSISTENT_ENTITY:
				continue
			if not kept.has(record.parent_id):
				return {
					"error": ERR_INVALID_PARAMETER,
					"world_id": StringName(world_id),
					"entity_id": record.id,
					"records": {},
				}
			var parent: EntityRecord = kept[record.parent_id]
			if parent.removed:
				return {
					"error": ERR_INVALID_PARAMETER,
					"world_id": StringName(world_id),
					"entity_id": record.id,
					"records": {},
				}
		out[StringName(world_id)] = kept
	return {"error": OK, "world_id": &"", "entity_id": &"", "records": out}


func capture_world(world_id: StringName) -> Error:
	if _guard == null or _entities == null:
		return _reject(&"capture_world", ERR_UNCONFIGURED, _ctx(world_id, &"", &""))
	if WorldId.validate(world_id) != OK:
		return _reject(&"capture_world", ERR_INVALID_PARAMETER, _ctx(world_id, &"", &""))
	var root := _entities.root_for_world(world_id)
	if root == null:
		return _reject(&"capture_world", ERR_DOES_NOT_EXIST, _ctx(world_id, &"", &""))
	var begin_err := _guard.try_begin(&"capture_world")
	if begin_err != OK:
		return _reject(&"capture_world", begin_err, _ctx(world_id, &"", &""))
	var err := capture_world_owned(world_id)
	_guard.finish(_guard.get_operation_id())
	if err != OK:
		return _reject(&"capture_world", err, _ctx(world_id, &"", &""))
	return OK


## Silent owned form for a command that already holds the guard.
func capture_world_owned(world_id: StringName) -> Error:
	if _guard == null or _entities == null:
		return ERR_UNCONFIGURED
	if WorldId.validate(world_id) != OK:
		return ERR_INVALID_PARAMETER
	var root := _entities.root_for_world(world_id)
	if root == null:
		return ERR_DOES_NOT_EXIST
	var captured: Dictionary = {}
	var err := _collect_live_records(world_id, root, captured)
	if err != OK:
		return err
	_commit_capture(world_id, captured)
	return OK


## Capture the live world into a copy of the record tables and hand it back
## unpublished. The committed store is left byte-identical, which is what lets a
## travel restore its destination from the very pass that captured its origin --
## the case that matters is travelling to the world you are already in, where
## restoring from the committed store would silently revert to the last explicit
## capture_world. Silent: the owning command logs.
## -> {error, records}
func capture_world_staged_owned(world_id: StringName) -> Dictionary:
	if _guard == null or _entities == null:
		return {"error": ERR_UNCONFIGURED, "records": {}}
	if WorldId.validate(world_id) != OK:
		return {"error": ERR_INVALID_PARAMETER, "records": {}}
	var root := _entities.root_for_world(world_id)
	if root == null:
		return {"error": ERR_DOES_NOT_EXIST, "records": {}}
	var captured: Dictionary = {}
	var failure: Dictionary = {}
	var err := _collect_live_records(world_id, root, captured, failure)
	if err != OK:
		# Named, so a travel that fails the durability rule says which entity
		# rather than reporting a bare code=31.
		return {
			"error": err,
			"world_id": world_id,
			"entity_id": failure.get("entity_id", &""),
			"records": {},
		}
	# snapshot_records duplicates every record, and `captured` holds records built
	# moments ago, so the staged table shares no EntityRecord with _records.
	var staged: Dictionary = snapshot_records()
	var world_recs: Dictionary = {}
	if staged.has(world_id):
		world_recs = staged[world_id]
	staged[world_id] = _merge_capture(world_recs, captured)
	return {"error": OK, "world_id": &"", "entity_id": &"", "records": staged}


func restore_world(world_id: StringName, candidate_root: Node) -> Error:
	if _guard == null:
		return _reject(&"restore_world", ERR_UNCONFIGURED, _ctx(world_id, &"", &""))
	if WorldId.validate(world_id) != OK:
		return _reject(&"restore_world", ERR_INVALID_PARAMETER, _ctx(world_id, &"", &""))
	if candidate_root == null or candidate_root.get_parent() != null or candidate_root.is_inside_tree():
		return _reject(&"restore_world", ERR_INVALID_PARAMETER, _ctx(world_id, &"", &""))
	var begin_err := _guard.try_begin(&"restore_world")
	if begin_err != OK:
		return _reject(&"restore_world", begin_err, _ctx(world_id, &"", &""))
	var world_recs: Dictionary = {}
	if _records.has(world_id):
		world_recs = _records[world_id]
	var result := _restore_into(world_recs, candidate_root)
	_guard.finish(_guard.get_operation_id())
	var err: Error = result["error"]
	# Deliberately not enriched: three negative cases assert this exact line, and
	# the structured detail is what the owned form exists to carry.
	if err != OK:
		return _reject(&"restore_world", err, _ctx(world_id, &"", &""))
	return OK


## Restore from a caller-supplied record table. This is how a staged load
## applies a decoded slot to its detached candidate without ever swapping the
## authoritative store to drive the restore. Silent: the owning command logs.
## -> {error, stage, entity_id, component_id, archetype_id}. Structured because
## a materialization failure has to name the archetype it could not resolve, and
## the stage distinguishes "this record's actor could not be built" from "the
## authored scene does not match its records".
func restore_world_owned(
	world_id: StringName, candidate_root: Node, records: Dictionary
) -> Dictionary:
	if _guard == null:
		return _restore_result(ERR_UNCONFIGURED, &"restore", {})
	if WorldId.validate(world_id) != OK:
		return _restore_result(ERR_INVALID_PARAMETER, &"restore", {})
	if candidate_root == null or candidate_root.get_parent() != null \
			or candidate_root.is_inside_tree():
		return _restore_result(ERR_INVALID_PARAMETER, &"restore", {})
	return _restore_into(records, candidate_root)


## Read-only over world_recs: only _mark_removed_body ever writes a record, so
## a staged table is safe to pass straight through.
## -> {error, stage, entity_id, component_id, archetype_id}
func _restore_into(world_recs: Dictionary, candidate_root: Node) -> Dictionary:
	# Hoisted ahead of everything: _restore_order breaks out of an unresolvable
	# wave and returns a *partial* order, so a cyclic pair would never be
	# materialized and would then be misreported as a missing actor -- the wrong
	# error naming the wrong problem. Rejecting first also means the cyclic case
	# has no cleanup path to get wrong, because nothing was instantiated.
	var cycle := _parent_cycle(world_recs)
	if cycle != OK:
		return _restore_result(cycle, &"restore", {})
	var prepared: Dictionary = _materializer.prepare(
		world_recs, candidate_root, null if _entities == null else _entities.archetypes()
	)
	if int(prepared["error"]) != OK:
		return prepared
	var index := _index_candidate(candidate_root)
	var index_err: Error = index["error"]
	if index_err != OK:
		return _restore_result(index_err, &"restore", {})
	var failure: Dictionary = {}
	var pre := _preflight_restore(world_recs, index, failure)
	if pre != OK:
		return _restore_result(pre, &"restore", failure)
	var extract_err := _extract_survivors(world_recs, index, candidate_root)
	if extract_err != OK:
		return _restore_result(extract_err, &"restore", failure)
	_apply_tombstones(world_recs, index)
	var applied := _apply_records(world_recs, index, candidate_root, failure)
	return _restore_result(applied, &"restore", failure)


static func _restore_result(
	reason: Error, at: StringName, failure: Dictionary
) -> Dictionary:
	return {
		"error": reason,
		"stage": &"" if reason == OK else at,
		"entity_id": failure.get("entity_id", &""),
		"component_id": failure.get("component_id", &""),
		"archetype_id": &"",
	}


func mark_removed(world_id: StringName, entity_ids: Array[StringName]) -> Error:
	if _guard == null:
		return _reject(&"mark_removed", ERR_UNCONFIGURED, _ctx(world_id, &"", &""))
	if WorldId.validate(world_id) != OK:
		return _reject(&"mark_removed", ERR_INVALID_PARAMETER, _ctx(world_id, &"", &""))
	var begin_err := _guard.try_begin(&"mark_removed")
	if begin_err != OK:
		return _reject(&"mark_removed", begin_err, _ctx(world_id, &"", &""))
	var err := _mark_removed_body(world_id, entity_ids)
	_guard.finish(_guard.get_operation_id())
	if err != OK:
		return _reject(&"mark_removed", err, _ctx(world_id, &"", &""))
	return OK


## `failure` receives {entity_id} when a check names one offender; `captured` is
## only ever the record table, so a diagnostic detail never pollutes it.
func _collect_live_records(
	world_id: StringName, root: Node, captured: Dictionary, failure: Dictionary = {}
) -> Error:
	var entities: Array = []
	_collect_entities(root, entities)
	# Over the full walk, before the NONE skip below: a NONE parent is exactly
	# the case the durability rule has to catch, and the capture loop never sees
	# one.
	var policies: Dictionary = {}
	for item: Variant in entities:
		var walked := item as PersistentEntity
		policies[walked.persistent_id] = int(walked.persistence_policy)
	var attachment_ids: Dictionary = {}
	var att_err := _collect_attachment_ids(root, attachment_ids)
	if att_err != OK:
		return att_err
	var pending: Dictionary = {}
	for item: Variant in entities:
		var pe := item as PersistentEntity
		if pe.persistence_policy == WorldPersistencePolicy.Kind.NONE:
			continue
		var actor := pe.get_parent()
		if actor == null:
			return ERR_INVALID_PARAMETER
		if WorldId.validate(pe.persistent_id) != OK:
			return ERR_INVALID_PARAMETER
		var owned := owned_world(pe.persistent_id)
		if owned != &"" and owned != world_id:
			return ERR_ALREADY_EXISTS
		if _has_tombstone(world_id, pe.persistent_id):
			continue
		var parent := _parent_context(actor, root)
		if int(parent["error"]) != OK:
			return parent["error"] as Error
		var rec := EntityRecord.new()
		rec.id = pe.persistent_id
		rec.world_id = world_id
		rec.policy = pe.persistence_policy
		rec.removed = false
		rec.parent_kind = parent["kind"]
		rec.parent_id = parent["id"]
		# From the node, never from a table lookup. See PersistentEntity.
		rec.origin = pe.origin()
		rec.archetype_id = pe.archetype_id()
		var comps: Dictionary = {}
		var seen_cids: Dictionary = {}
		for child in pe.get_children():
			if not (child is PersistentComponent):
				continue
			var component := child as PersistentComponent
			if WorldId.validate(component.component_id) != OK:
				return ERR_INVALID_PARAMETER
			if seen_cids.has(component.component_id):
				return ERR_ALREADY_EXISTS
			seen_cids[component.component_id] = true
			var raw: Dictionary = component.capture_state()
			var valid := component.validate_state(raw)
			if valid != OK:
				return valid
			if WorldValue.validate(raw) != OK:
				return ERR_INVALID_PARAMETER
			comps[component.component_id] = WorldValue.clone_validated(raw)
		rec.components = comps
		pending[rec.id] = rec
	var cycle := _parent_cycle(pending)
	if cycle != OK:
		return cycle
	var durable := _validate_parent_durability(pending, policies)
	if durable["error"] != OK:
		failure["entity_id"] = durable["entity_id"]
		return durable["error"]
	for entity_id: Variant in pending.keys():
		captured[entity_id] = pending[entity_id]
	return OK


## A persistent entity whose structural parent is another persistent entity must
## have a parent at least as durable as itself -- NONE < SESSION < SAVE_GAME --
## so no record can outlive the parent it needs for reconstruction.
##
## Checked here as well as at spawn, because an authored scene can nest a
## SESSION actor under a NONE one with no spawn involved, and project code may
## reparent a registered actor at runtime. One check here covers both the save
## path and travel, since capture_world_owned and capture_world_staged_owned
## both funnel through _collect_live_records.
##
## Without it the failure is latent, late and misattributed: the child's record
## survives with a parent_id that has no record, and every travel back fails the
## restore with ERR_DOES_NOT_EXIST naming the child.
## -> {error, entity_id}
static func _validate_parent_durability(
	pending: Dictionary, policies: Dictionary
) -> Dictionary:
	for entity_id: Variant in pending.keys():
		var rec: EntityRecord = pending[entity_id]
		if rec.parent_kind != WorldEntityParent.Kind.PERSISTENT_ENTITY:
			continue
		if not policies.has(rec.parent_id):
			continue
		if int(policies[rec.parent_id]) < int(rec.policy):
			return {"error": ERR_INVALID_PARAMETER, "entity_id": rec.id}
	return {"error": OK, "entity_id": &""}


func _commit_capture(world_id: StringName, captured: Dictionary) -> void:
	var world_recs: Dictionary = {}
	if _records.has(world_id):
		world_recs = _records[world_id]
	_records[world_id] = _merge_capture(world_recs, captured)
	_rebuild_ownership()


## Pure merge of a fresh capture over one world's existing table. A tombstone
## always wins, and a record the pass did not see is carried forward untouched.
## Extracted so the staged capture travel needs and the committed capture a save
## needs cannot drift apart: the tombstone rule is the subtle part, and two
## copies of it would be two chances to lose a deliberate removal.
static func _merge_capture(world_recs: Dictionary, captured: Dictionary) -> Dictionary:
	var next: Dictionary = {}
	for entity_id: Variant in world_recs.keys():
		var existing: EntityRecord = world_recs[entity_id]
		if existing.removed or not captured.has(entity_id):
			next[entity_id] = existing
	for entity_id: Variant in captured.keys():
		if world_recs.has(entity_id):
			var existing: EntityRecord = world_recs[entity_id]
			if existing.removed:
				next[entity_id] = existing
				continue
		next[entity_id] = captured[entity_id]
	return next


func _rebuild_ownership() -> void:
	_ownership.clear()
	for world_id: Variant in _records.keys():
		var world_recs: Dictionary = _records[world_id]
		for entity_id: Variant in world_recs.keys():
			_ownership[entity_id] = world_id


func _has_tombstone(world_id: StringName, entity_id: StringName) -> bool:
	if not _records.has(world_id):
		return false
	var world_recs: Dictionary = _records[world_id]
	if not world_recs.has(entity_id):
		return false
	var rec: EntityRecord = world_recs[entity_id]
	return rec.removed


func _parent_context(actor: Node, world_root: Node) -> Dictionary:
	if actor == world_root:
		return {"error": OK, "kind": WorldEntityParent.Kind.WORLD_ROOT, "id": &""}
	var parent := actor.get_parent()
	if parent == null:
		return {"error": ERR_INVALID_PARAMETER, "kind": WorldEntityParent.Kind.WORLD_ROOT, "id": &""}
	if parent == world_root:
		return {"error": OK, "kind": WorldEntityParent.Kind.WORLD_ROOT, "id": &""}
	var parent_pe := _entity_of_actor(parent)
	if parent_pe != null:
		return {
			"error": OK,
			"kind": WorldEntityParent.Kind.PERSISTENT_ENTITY,
			"id": parent_pe.persistent_id,
		}
	var attachment := _attachment_of(parent)
	if attachment != null:
		if WorldId.validate(attachment.id) != OK:
			return {"error": ERR_INVALID_PARAMETER, "kind": WorldEntityParent.Kind.ATTACHMENT, "id": &""}
		return {"error": OK, "kind": WorldEntityParent.Kind.ATTACHMENT, "id": attachment.id}
	return {"error": ERR_INVALID_PARAMETER, "kind": WorldEntityParent.Kind.WORLD_ROOT, "id": &""}


func _entity_of_actor(actor: Node) -> PersistentEntity:
	for child in actor.get_children():
		if child is PersistentEntity:
			return child as PersistentEntity
	return null


func _attachment_of(node: Node) -> WorldAttachment:
	for child in node.get_children():
		if child is WorldAttachment:
			return child as WorldAttachment
	return null


func _collect_entities(node: Node, out: Array) -> void:
	if node is PersistentEntity:
		out.append(node)
	for child in node.get_children():
		_collect_entities(child, out)


func _collect_attachment_ids(node: Node, seen: Dictionary) -> Error:
	if node is WorldAttachment:
		var att := node as WorldAttachment
		if WorldId.validate(att.id) != OK:
			return ERR_INVALID_PARAMETER
		if seen.has(att.id):
			return ERR_ALREADY_EXISTS
		seen[att.id] = true
	for child in node.get_children():
		var err := _collect_attachment_ids(child, seen)
		if err != OK:
			return err
	return OK


func _parent_cycle(pending: Dictionary) -> Error:
	for entity_id: Variant in pending.keys():
		var seen: Dictionary = {}
		var current: StringName = entity_id
		while true:
			if seen.has(current):
				return ERR_INVALID_PARAMETER
			seen[current] = true
			if not pending.has(current):
				break
			var rec: EntityRecord = pending[current]
			if rec.parent_kind != WorldEntityParent.Kind.PERSISTENT_ENTITY:
				break
			if rec.parent_id == &"":
				break
			current = rec.parent_id
	return OK


func _mark_removed_body(world_id: StringName, entity_ids: Array[StringName]) -> Error:
	var err := mark_removed_in(_records, world_id, entity_ids, {})
	if err != OK:
		return err
	_rebuild_ownership()
	return OK


## The same closure predicate applied to any record table, so despawn's preflight
## and its commit provably cannot disagree about what a subtree is. `failure`
## receives {entity_id} naming the offender. Silent: the owning command logs.
static func mark_removed_in(
	records: Dictionary,
	world_id: StringName,
	entity_ids: Array[StringName],
	failure: Dictionary
) -> Error:
	if not records.has(world_id):
		return ERR_DOES_NOT_EXIST
	var world_recs: Dictionary = records[world_id]
	var requested: Dictionary = {}
	for entity_id: StringName in entity_ids:
		if not world_recs.has(entity_id):
			failure["entity_id"] = entity_id
			return ERR_DOES_NOT_EXIST
		requested[entity_id] = true
	var needed: Dictionary = requested.duplicate()
	var growing := true
	while growing:
		growing = false
		for entity_id: Variant in world_recs.keys():
			var rec: EntityRecord = world_recs[entity_id]
			if rec.parent_kind != WorldEntityParent.Kind.PERSISTENT_ENTITY:
				continue
			# An already-removed descendant strands nothing, so it need not be
			# named again.
			if rec.removed:
				continue
			if needed.has(rec.parent_id) and not needed.has(rec.id):
				needed[rec.id] = true
				growing = true
	for entity_id: Variant in needed.keys():
		if not requested.has(entity_id):
			failure["entity_id"] = entity_id
			return ERR_INVALID_PARAMETER
	for entity_id: Variant in requested.keys():
		var rec: EntityRecord = world_recs[entity_id]
		rec.removed = true
	return OK


## Silent owned form for a command that already holds the guard.
## One record for one freshly spawned actor, without touching the store. Reuses
## the capture pass over a one-actor subtree so a spawned record and a captured
## record of the same actor cannot differ -- the parent context, the component
## capture and the WorldValue isolation are the subtle parts, and one copy of
## them is the point.
## -> {error, record, entity_id}
func build_spawn_record_owned(
	world_id: StringName, actor: Node, world_root: Node
) -> Dictionary:
	if _entities == null:
		return {"error": ERR_UNCONFIGURED, "record": null, "entity_id": &""}
	var captured: Dictionary = {}
	var failure: Dictionary = {}
	var err := _collect_live_records(world_id, actor, captured, failure)
	if err != OK:
		return {"error": err, "record": null, "entity_id": failure.get("entity_id", &"")}
	# A NONE actor yields no record at all, which is exactly the policy contract.
	if captured.is_empty():
		return {"error": OK, "record": null, "entity_id": &""}
	var only: EntityRecord = null
	for entity_id: Variant in captured.keys():
		only = captured[entity_id]
	# The parent context is derived relative to the world root, not the actor,
	# because _collect_live_records walked the actor as its own root.
	var parent := _parent_context(actor, world_root)
	if int(parent["error"]) != OK:
		return {"error": parent["error"], "record": null, "entity_id": only.id}
	only.parent_kind = parent["kind"]
	only.parent_id = parent["id"]
	return {"error": OK, "record": only, "entity_id": only.id}


## Install one record. A dictionary write, so it cannot fail -- which is what
## lets a spawn have no postcommit failure path at all.
func commit_record_owned(record: EntityRecord) -> void:
	var world_recs: Dictionary = {}
	if _records.has(record.world_id):
		world_recs = _records[record.world_id]
	world_recs[record.id] = record
	_records[record.world_id] = world_recs
	_rebuild_ownership()


## The durability rule, for the spawn path: a child may not be more durable than
## the parent it will need for reconstruction.
static func validate_parent_policy(child: int, parent: int) -> Error:
	if parent < child:
		return ERR_INVALID_PARAMETER
	return OK


func mark_removed_owned(world_id: StringName, entity_ids: Array[StringName]) -> Error:
	return _mark_removed_body(world_id, entity_ids)


## Apply tombstones to a caller-owned table, so a despawn can validate and mutate
## a staged copy and commit the whole set with one install_owned.
static func mark_removed_staged(
	staged: Dictionary,
	world_id: StringName,
	entity_ids: Array[StringName],
	failure: Dictionary
) -> Error:
	return mark_removed_in(staged, world_id, entity_ids, failure)


func _index_candidate(root: Node) -> Dictionary:
	var index := {
		"entities": {},
		"actors": {},
		"components": {},
		"attachments": {},
		"attachment_parents": {},
		"error": OK,
	}
	index["error"] = _fill_index(root, index)
	return index


func _fill_index(node: Node, index: Dictionary) -> Error:
	if node is PersistentEntity:
		var pe := node as PersistentEntity
		if index["entities"].has(pe.persistent_id) or index["actors"].has(pe.persistent_id):
			return ERR_ALREADY_EXISTS
		index["entities"][pe.persistent_id] = pe
		var actor := pe.get_parent()
		if actor != null:
			index["actors"][pe.persistent_id] = actor
		var comps: Dictionary = {}
		for child in pe.get_children():
			if child is PersistentComponent:
				var component := child as PersistentComponent
				if comps.has(component.component_id):
					return ERR_ALREADY_EXISTS
				comps[component.component_id] = component
		index["components"][pe.persistent_id] = comps
	if node is WorldAttachment:
		var att := node as WorldAttachment
		if index["attachments"].has(att.id):
			return ERR_ALREADY_EXISTS
		index["attachments"][att.id] = att
		index["attachment_parents"][att.id] = att.get_parent()
	for child in node.get_children():
		var err := _fill_index(child, index)
		if err != OK:
			return err
	return OK


func _preflight_restore(
	world_recs: Dictionary, index: Dictionary, failure: Dictionary = {}
) -> Error:
	for entity_id: Variant in world_recs.keys():
		var rec: EntityRecord = world_recs[entity_id]
		if rec.removed:
			continue
		if not index["actors"].has(rec.id):
			return ERR_DOES_NOT_EXIST
		if rec.parent_kind == WorldEntityParent.Kind.PERSISTENT_ENTITY:
			if not world_recs.has(rec.parent_id):
				return ERR_DOES_NOT_EXIST
			var parent_rec: EntityRecord = world_recs[rec.parent_id]
			if parent_rec.removed:
				return ERR_INVALID_PARAMETER
			if not index["actors"].has(rec.parent_id):
				return ERR_DOES_NOT_EXIST
		elif rec.parent_kind == WorldEntityParent.Kind.ATTACHMENT:
			if not index["attachment_parents"].has(rec.parent_id):
				return ERR_DOES_NOT_EXIST
		var comps: Dictionary = index["components"].get(rec.id, {})
		for component_id: Variant in rec.components.keys():
			if not comps.has(component_id):
				return ERR_DOES_NOT_EXIST
			var component: PersistentComponent = comps[component_id]
			var payload: Dictionary = rec.components[component_id]
			var valid := component.validate_state(payload)
			if valid != OK:
				return valid
	return _parent_cycle(world_recs)


func _extract_survivors(world_recs: Dictionary, index: Dictionary, root: Node) -> Error:
	var order: Array[StringName] = _restore_order(world_recs)
	for entity_id: StringName in order:
		var rec: EntityRecord = world_recs[entity_id]
		if rec.removed:
			continue
		if not index["actors"].has(entity_id):
			return ERR_DOES_NOT_EXIST
		var held: Variant = index["actors"][entity_id]
		if held == null or not is_instance_valid(held):
			return ERR_DOES_NOT_EXIST
		var actor := held as Node
		var parent := _restore_parent(rec, index, root)
		if parent == null or not is_instance_valid(parent):
			return ERR_DOES_NOT_EXIST
		if actor == parent:
			continue
		if actor.get_parent() != parent:
			if actor.get_parent() != null:
				actor.get_parent().remove_child(actor)
			parent.add_child(actor)
	return OK


func _apply_tombstones(world_recs: Dictionary, index: Dictionary) -> void:
	for entity_id: Variant in world_recs.keys():
		var rec: EntityRecord = world_recs[entity_id]
		if not rec.removed:
			continue
		if not index["actors"].has(rec.id):
			continue
		var held: Variant = index["actors"][rec.id]
		if held == null or not is_instance_valid(held):
			index["actors"].erase(rec.id)
			index["entities"].erase(rec.id)
			index["components"].erase(rec.id)
			continue
		var actor := held as Node
		if actor.get_parent() != null:
			actor.get_parent().remove_child(actor)
		actor.free()
		index["actors"].erase(rec.id)
		index["entities"].erase(rec.id)
		index["components"].erase(rec.id)


func _apply_records(
	world_recs: Dictionary, index: Dictionary, root: Node, failure: Dictionary = {}
) -> Error:
	var order: Array[StringName] = _restore_order(world_recs)
	for entity_id: StringName in order:
		var rec: EntityRecord = world_recs[entity_id]
		if rec.removed:
			continue
		if not index["actors"].has(entity_id):
			return ERR_DOES_NOT_EXIST
		var held_actor: Variant = index["actors"][entity_id]
		if held_actor == null or not is_instance_valid(held_actor):
			return ERR_DOES_NOT_EXIST
		var actor := held_actor as Node
		var parent := _restore_parent(rec, index, root)
		if parent == null or not is_instance_valid(parent):
			return ERR_DOES_NOT_EXIST
		if actor != parent and actor.get_parent() != parent:
			if actor.get_parent() != null:
				actor.get_parent().remove_child(actor)
			parent.add_child(actor)
		var comps: Dictionary = index["components"].get(entity_id, {})
		for component_id: Variant in rec.components.keys():
			if not comps.has(component_id):
				return ERR_DOES_NOT_EXIST
			var component: PersistentComponent = comps[component_id]
			var payload: Variant = WorldValue.clone_validated(rec.components[component_id])
			var err := component.restore_state(payload)
			if err != OK:
				return err
	return OK


func _restore_parent(rec: EntityRecord, index: Dictionary, root: Node) -> Node:
	match rec.parent_kind:
		WorldEntityParent.Kind.WORLD_ROOT:
			return root
		WorldEntityParent.Kind.PERSISTENT_ENTITY:
			if index["actors"].has(rec.parent_id):
				return index["actors"][rec.parent_id]
			return null
		WorldEntityParent.Kind.ATTACHMENT:
			if index["attachment_parents"].has(rec.parent_id):
				return index["attachment_parents"][rec.parent_id]
			return null
		_:
			return null


## Public for the materializer, which needs the same parent-before-child order
## and the same removed-record exclusion.
static func restore_order(world_recs: Dictionary) -> Array[StringName]:
	return _restore_order(world_recs)


static func _restore_order(world_recs: Dictionary) -> Array[StringName]:
	var remaining: Dictionary = {}
	for entity_id: Variant in world_recs.keys():
		var rec: EntityRecord = world_recs[entity_id]
		if rec.removed:
			continue
		remaining[entity_id] = true
	var order: Array[StringName] = []
	while remaining.size() > 0:
		var ready: Array[StringName] = []
		for entity_id: Variant in remaining.keys():
			var rec: EntityRecord = world_recs[entity_id]
			if rec.parent_kind != WorldEntityParent.Kind.PERSISTENT_ENTITY:
				ready.append(entity_id)
				continue
			if not remaining.has(rec.parent_id):
				ready.append(entity_id)
		if ready.is_empty():
			break
		ready.sort_custom(func (a: StringName, b: StringName) -> bool:
			return String(a) < String(b)
		)
		for entity_id: StringName in ready:
			order.append(entity_id)
			remaining.erase(entity_id)
	return order


func _reject(operation: StringName, reason: Error, context: Dictionary) -> Error:
	return WorldDiagnostics.reject(operation, reason, context)


func _participant_ctx(id: StringName) -> Dictionary:
	var context: Dictionary = {}
	if String(id) != "":
		context["participant_id"] = id
	return context


func _ctx(world_id: StringName, entity_id: StringName, component_id: StringName) -> Dictionary:
	var context: Dictionary = {}
	if String(world_id) != "":
		context["world_id"] = world_id
	if String(entity_id) != "":
		context["entity_id"] = entity_id
	if String(component_id) != "":
		context["component_id"] = component_id
	return context
