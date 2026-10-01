extends Node
## Public World facade. Do not declare class_name World: that name belongs to the autoload.

signal initialized()

var _events: WorldEvents
var _operation_guard: WorldOperationGuard
var _state: WorldState
var _entities: WorldEntityManager
var _persistence: WorldPersistenceManager
var _scenes: WorldSceneDirector
var _initialized: bool = false
var _pending_new_game_id: int = 0
var _pending_save_id: int = 0
var _pending_save_slot: StringName = &""
var _pending_load_id: int = 0
var _pending_load_slot: StringName = &""
## The in-flight travel, from acceptance until its terminal event. Held on World
## rather than stashed as scalars because Phase 8.2 cancellation has to find it
## by operation id before the deferred body has even run.
var _travel: WorldTravelStage = null
var _spawn: WorldSpawnStage = null
var _pending_spawn_request: WorldSpawnRequest = null
var _despawn: WorldDespawnStage = null

var events: WorldEvents:
	get:
		return _events

var state: WorldState:
	get:
		return _state

var entities: WorldEntityManager:
	get:
		return _entities

var persistence: WorldPersistenceManager:
	get:
		return _persistence

var scenes: WorldSceneDirector:
	get:
		return _scenes


func is_initialized() -> bool:
	return _initialized


## True after a load failed and could not be undone. Ordinary mutations are
## rejected with ERR_UNAVAILABLE until new_game succeeds.
func is_recovery_required() -> bool:
	if _operation_guard == null:
		return false
	return _operation_guard.is_recovery_required()


func _enter_tree() -> void:
	_events = WorldEvents.new()
	_operation_guard = WorldOperationGuard.new()
	_state = WorldState.new()
	_state.configure(_operation_guard, _events)
	_entities = WorldEntityManager.new()
	_entities.configure(_operation_guard, _events)
	_persistence = WorldPersistenceManager.new()
	_persistence.configure(_operation_guard, _entities)
	_entities.set_persistence(_persistence)
	# So World.entities.spawn/despawn can forward to the one guard and the one
	# deferred-command engine, which both live here.
	_entities.set_host(self)
	_scenes = WorldSceneDirector.new()
	_scenes.configure(_operation_guard, _events, _entities, _persistence)
	add_child(_scenes)
	_initialized = true
	initialized.emit()


func new_game() -> Error:
	if not is_inside_tree() or not _initialized or _scenes == null or _state == null:
		return WorldDiagnostics.reject(&"new_game", ERR_UNCONFIGURED, {})
	var begin_err := _operation_guard.try_begin(&"new_game")
	if begin_err != OK:
		return WorldDiagnostics.reject(&"new_game", begin_err, {})
	_pending_new_game_id = _operation_guard.get_operation_id()
	call_deferred("_run_new_game")
	return OK


func _run_new_game() -> void:
	var operation_id := _pending_new_game_id
	var world_id := _scenes.get_active_world_id()
	_events.new_game_started.emit(
		_event_context(operation_id, &"new_game", world_id, &"started")
	)
	if _scenes.get_active_world_root() != null:
		var unload_err: Error = _scenes.unload_active_owned()
		if unload_err != OK:
			var diagnostic: Dictionary = {}
			if String(world_id) != "":
				diagnostic["world_id"] = world_id
			diagnostic["stage"] = &"unload"
			WorldDiagnostics.reject(&"new_game", unload_err, diagnostic)
			_events.new_game_failed.emit(
				unload_err, _event_context(operation_id, &"new_game", world_id, &"unload")
			)
			_operation_guard.finish(operation_id)
			return
	if _persistence != null:
		_persistence.clear_owned()
	if _entities != null:
		# clear_owned already dropped every record and tombstone; only the id
		# reservations are left. Archetypes are retained, like world definitions.
		_entities.clear_dynamic_owned()
	_state.restore_owned({})
	if _persistence != null:
		var reset: Dictionary = _persistence.participants().reset_all()
		if int(reset["error"]) != OK:
			# A failed reset leaves recovery required, if it already was: the
			# managed contents are not known to be back at defaults.
			var reason: Error = reset["error"]
			var diagnostic: Dictionary = {"stage": &"reset"}
			if String(reset["participant_id"]) != "":
				diagnostic["participant_id"] = reset["participant_id"]
			WorldDiagnostics.reject(&"new_game", reason, diagnostic)
			var context := _event_context(operation_id, &"new_game", &"", &"reset")
			context["participant_id"] = reset["participant_id"]
			_events.new_game_failed.emit(reason, context)
			_operation_guard.finish(operation_id)
			return
	_operation_guard.clear_recovery()
	_events.new_game_completed.emit(_event_context(operation_id, &"new_game", &"", &"commit"))
	_operation_guard.finish(operation_id)


# --- save ---------------------------------------------------------------------


func save_game(slot_id: StringName) -> Error:
	if not is_inside_tree() or not _initialized or _persistence == null \
			or _state == null or _scenes == null:
		return WorldDiagnostics.reject(&"save_game", ERR_UNCONFIGURED, _slot_context(slot_id))
	var slot_err := WorldSaveSlotStore.validate_slot_id(slot_id)
	if slot_err != OK:
		return WorldDiagnostics.reject(&"save_game", slot_err, _slot_context(slot_id))
	var begin_err := _operation_guard.try_begin(&"save_game")
	if begin_err != OK:
		return WorldDiagnostics.reject(&"save_game", begin_err, _slot_context(slot_id))
	_pending_save_id = _operation_guard.get_operation_id()
	_pending_save_slot = slot_id
	call_deferred("_run_save_game")
	return OK


func _run_save_game() -> void:
	var operation_id := _pending_save_id
	var stage := WorldSessionStage.new()
	stage.slot_id = _pending_save_slot
	stage.world_id = _scenes.get_active_world_id()
	_events.save_started.emit(
		stage.event_context(operation_id, &"save_game", &"started")
	)
	var store := _persistence.store()
	# The envelope pass, not a full decode: metadata is readable at every
	# container version (README D7), so saving over an outdated slot continues
	# its generation rather than restarting at 1.
	var existing := store.open_slot(stage.slot_id)
	var created_at := int(Time.get_unix_time_from_system())
	var generation := 1
	if existing.error == OK:
		created_at = int(existing.context["created_at"])
		generation = int(existing.context["generation"]) + 1
	var captured := _capture_for_save(stage, created_at, generation)
	if captured != OK:
		_finish_save_failure(stage, operation_id, captured)
		return
	var write_err: Error = await store.write_slot(stage.slot_id, stage.bytes)
	if write_err != OK:
		_finish_save_failure(stage, operation_id, stage.fail(write_err, &"write"))
		return
	stage.generation = generation
	stage.byte_size = stage.bytes.size()
	_events.save_completed.emit(stage.event_context(operation_id, &"save_game", &"commit"))
	_operation_guard.finish(operation_id)


## One straight-line synchronous pass. Everything reaching the document is
## already a detached copy, and WorldValue.validate over the whole document is
## the mechanical proof that no live container is aliased into it, so later
## mutations cannot change the bytes written.
func _capture_for_save(stage: WorldSessionStage, created_at: int, generation: int) -> Error:
	var active := _scenes.get_active_world_id()
	if String(active) != "":
		var capture_err := _persistence.capture_world_owned(active)
		if capture_err != OK:
			stage.world_id = active
			return stage.fail(capture_err, &"capture")
	var records: Dictionary = _persistence.snapshot_save_records()
	if int(records["error"]) != OK:
		stage.world_id = records["world_id"]
		stage.entity_id = records["entity_id"]
		return stage.fail(records["error"], &"capture")
	var systems: Dictionary = _persistence.participants().capture_all()
	if int(systems["error"]) != OK:
		stage.participant_id = systems["participant_id"]
		return stage.fail(systems["error"], &"capture")
	var worlds: Dictionary = {}
	var source: Dictionary = records["records"]
	for world_id: Variant in source.keys():
		var entities_out: Dictionary = {}
		var world_recs: Dictionary = source[world_id]
		for entity_id: Variant in world_recs.keys():
			var record: EntityRecord = world_recs[entity_id]
			entities_out[entity_id] = {
				"archetype_id": String(record.archetype_id),
				"components": record.components,
				"origin": int(record.origin),
				"parent_id": String(record.parent_id),
				"parent_kind": int(record.parent_kind),
				"policy": int(record.policy),
				"removed": record.removed,
			}
		worlds[world_id] = entities_out
	var snapshot: Dictionary = {
		"active_world": null if String(active) == "" else active,
		"created_at": created_at,
		"updated_at": int(Time.get_unix_time_from_system()),
		"generation": generation,
		"world_state": _state.snapshot(),
		"worlds": worlds,
		"systems": systems["systems"],
	}
	var encoded := WorldSaveSerializer.encode(snapshot)
	if encoded.error != OK:
		if encoded.context.has("field"):
			stage.entity_id = StringName(str(encoded.context["field"]))
		return stage.fail(encoded.error, &"encode")
	stage.bytes = encoded.bytes
	return OK


func _finish_save_failure(stage: WorldSessionStage, operation_id: int, reason: Error) -> void:
	WorldDiagnostics.reject(&"save_game", reason, stage.reject_context())
	_events.save_failed.emit(
		reason, stage.event_context(operation_id, &"save_game", stage.failed_stage)
	)
	_operation_guard.finish(operation_id)


# --- load ---------------------------------------------------------------------


func load_game(slot_id: StringName) -> Error:
	if not is_inside_tree() or not _initialized or _persistence == null \
			or _state == null or _scenes == null:
		return WorldDiagnostics.reject(&"load_game", ERR_UNCONFIGURED, _slot_context(slot_id))
	var slot_err := WorldSaveSlotStore.validate_slot_id(slot_id)
	if slot_err != OK:
		return WorldDiagnostics.reject(&"load_game", slot_err, _slot_context(slot_id))
	var begin_err := _operation_guard.try_begin(&"load_game")
	if begin_err != OK:
		return WorldDiagnostics.reject(&"load_game", begin_err, _slot_context(slot_id))
	_pending_load_id = _operation_guard.get_operation_id()
	_pending_load_slot = slot_id
	call_deferred("_run_load_game")
	return OK


func _run_load_game() -> void:
	var operation_id := _pending_load_id
	var stage := WorldSessionStage.new()
	stage.slot_id = _pending_load_slot
	_events.load_started.emit(stage.event_context(operation_id, &"load_game", &"started"))
	var prepared := _load_preflight(stage)
	if prepared != OK:
		_load_unwind(stage)
		_finish_load_failure(stage, operation_id, prepared)
		return
	var committed := _load_commit(stage)
	if committed != OK:
		_load_unwind(stage)
		_finish_load_failure(stage, operation_id, committed)
		return
	_publish_load_commit(stage, operation_id)


## Everything that can fail without mutating anything live. On return the
## candidate is prepared but still detached and the old session is untouched.
func _load_preflight(stage: WorldSessionStage) -> Error:
	var opened := _persistence.store().open_slot(stage.slot_id)
	if opened.error != OK:
		return stage.fail(opened.error, &"read")
	if bool(opened.context.get("recovered", false)):
		stage.recovered_from = opened.context["source"]
	stage.source_format_version = int(opened.context["format_version"])
	# Container migrations run on the parsed payload, where value leaves are
	# still encoded, and only then is the result validated and decoded by the
	# current format's validator. See README D21.
	var migrated := _persistence.migrations().migrate(
		opened.payload, WorldSaveDocument.FORMAT_VERSION
	)
	if migrated.error != OK:
		stage.migration_context = migrated.context.duplicate(true)
		return stage.fail(migrated.error, &"migrate")
	stage.container_migration_steps = int(migrated.context["steps"])
	var decoded := WorldSaveSerializer.decode_payload(
		migrated.document, int(opened.context["byte_size"])
	)
	if decoded.error != OK:
		return stage.fail(decoded.error, &"decode")
	stage.loaded_format_version = int(decoded.context["format_version"])
	stage.document = decoded.document
	var active: Variant = stage.document["active_world"]
	stage.has_active_world = active != null
	if stage.has_active_world:
		stage.active_world = StringName(active)
		stage.world_id = stage.active_world
		if not _scenes.has_world(stage.active_world):
			return stage.fail(ERR_DOES_NOT_EXIST, &"validate")
	var built := _build_staged_records(stage)
	if built != OK:
		return built
	var registry := _persistence.participants()
	# Participant schemas advance on decoded state, before validate_all's strict
	# equality check -- which is the post-condition of this pass, not a
	# substitute for it.
	var advanced: Dictionary = registry.migrate_all(stage.document["systems"])
	if int(advanced["error"]) != OK:
		stage.participant_id = advanced["participant_id"]
		stage.migration_context = {
			"from_version": advanced.get("from_version", 0),
			"to_version": advanced.get("to_version", 0),
		}
		return stage.fail(advanced["error"], &"migrate")
	stage.staged_systems = advanced["systems"]
	stage.participant_migrations = advanced["migrations"]
	var validated: Dictionary = registry.validate_all(stage.staged_systems)
	if int(validated["error"]) != OK:
		stage.participant_id = validated["participant_id"]
		return stage.fail(validated["error"], &"validate")
	# Rollback material is captured and validated before any hook runs: a
	# participant that cannot describe its own state cannot be rolled back.
	var snapshots: Dictionary = registry.snapshot_all()
	if int(snapshots["error"]) != OK:
		stage.participant_id = snapshots["participant_id"]
		return stage.fail(snapshots["error"], &"validate")
	stage.rollback_snapshots = snapshots["snapshots"]
	stage.staged_state = stage.document["world_state"]
	stage.previous_world_id = _scenes.get_active_world_id()
	stage.previous_state = _state.snapshot()
	stage.previous_records = _persistence.snapshot_records()
	if stage.has_active_world:
		var instantiated: Dictionary = _scenes.instantiate_candidate_owned(stage.active_world)
		if int(instantiated["error"]) != OK:
			return stage.fail(instantiated["error"], &"instantiate")
		stage.adopt_candidate(instantiated["candidate"])
		var restored: Dictionary = _persistence.restore_world_owned(
			stage.active_world,
			stage.candidate(),
			stage.staged_records.get(stage.active_world, {}),
		)
		if int(restored["error"]) != OK:
			return _fail_restore(stage, restored)
	var applied: Dictionary = registry.restore_all(stage.staged_systems, stage.attempted)
	if int(applied["error"]) != OK:
		stage.participant_id = applied["participant_id"]
		return stage.fail(applied["error"], &"participant")
	return OK


func _build_staged_records(stage: WorldSessionStage) -> Error:
	var worlds: Dictionary = stage.document["worlds"]
	for world_key: Variant in worlds.keys():
		var entities: Dictionary = {}
		var source: Dictionary = worlds[world_key]
		for entity_key: Variant in source.keys():
			var fields: Dictionary = source[entity_key]
			var record := EntityRecord.new()
			record.id = StringName(entity_key)
			record.world_id = StringName(world_key)
			record.policy = int(fields["policy"]) as WorldPersistencePolicy.Kind
			record.removed = bool(fields["removed"])
			record.parent_kind = int(fields["parent_kind"]) as WorldEntityParent.Kind
			record.parent_id = StringName(fields["parent_id"])
			record.origin = int(fields["origin"]) as WorldEntityOrigin.Kind
			record.archetype_id = StringName(fields["archetype_id"])
			var components: Dictionary = {}
			var source_components: Dictionary = fields["components"]
			for component_key: Variant in source_components.keys():
				components[StringName(component_key)] = source_components[component_key]
			record.components = components
			entities[record.id] = record
		stage.staged_records[StringName(world_key)] = entities
	return OK


## The commit window. Records are installed before activation because attaching
## the candidate fires PersistentEntity._enter_tree, which consults the
## authoritative ownership map: with the old map still in place, a save that
## moves an entity between worlds would fail activation as a duplicate.
func _load_commit(stage: WorldSessionStage) -> Error:
	stage.committed = true
	_state.restore_owned(stage.staged_state, false)
	_persistence.install_owned(stage.staged_records)
	if stage.has_active_world:
		var activated := _scenes.activate_prepared_owned(
			stage.active_world, stage.release_candidate()
		)
		if activated != OK:
			return stage.fail(activated, &"activate")
		return OK
	var unloaded := _scenes.unload_active_owned()
	if unloaded != OK:
		return stage.fail(unloaded, &"activate")
	return OK


func _publish_load_commit(stage: WorldSessionStage, operation_id: int) -> void:
	_state.notify_restored_owned()
	if stage.has_active_world:
		_events.world_loaded.emit(
			stage.event_context(operation_id, &"load_game", &"commit"), null
		)
	_events.load_completed.emit(
		stage.event_context(operation_id, &"load_game", &"commit")
	)
	_operation_guard.finish(operation_id)


## Restore the old session in reverse of however far the commit got. Any
## failure here is unrecoverable and escalates to recovery-required.
func _load_unwind(stage: WorldSessionStage) -> void:
	if stage.committed:
		_persistence.install_owned(stage.previous_records)
		_state.restore_owned(stage.previous_state, false)
	var registry := _persistence.participants()
	var rolled_back: Dictionary = registry.rollback(stage.attempted, stage.rollback_snapshots)
	# activate_prepared_owned already freed the candidate on its own failure,
	# and release_candidate() cleared the handle, so this cannot double free.
	stage.discard_candidate()
	var reactivation_failed := stage.committed \
		and _scenes.get_active_world_id() != stage.previous_world_id
	if int(rolled_back["error"]) != OK or reactivation_failed:
		stage.recovery_required = true
		if String(rolled_back["participant_id"]) != "":
			stage.participant_id = rolled_back["participant_id"]
		_operation_guard.enter_recovery({
			"operation": &"load_game",
			"slot_id": stage.slot_id,
			"stage": stage.failed_stage,
			"participant_id": stage.participant_id,
		})


func _finish_load_failure(stage: WorldSessionStage, operation_id: int, reason: Error) -> void:
	WorldDiagnostics.reject(&"load_game", reason, stage.reject_context())
	_events.load_failed.emit(
		reason, stage.event_context(operation_id, &"load_game", stage.failed_stage)
	)
	_operation_guard.finish(operation_id)


# --- travel -------------------------------------------------------------------


## Move to another world, or reload the current one, as one guarded request.
## Accepted synchronously: OK means accepted, never finished. Exactly one
## transition_completed or transition_failed follows. See README D22.
func travel_to(
	world_id: StringName, entry_id: StringName = &"", options: Dictionary = {}
) -> Error:
	if not is_inside_tree() or not _initialized or _scenes == null \
			or _persistence == null or _state == null:
		return WorldDiagnostics.reject(
			&"travel_to", ERR_UNCONFIGURED, _travel_context(world_id, &"")
		)
	var parsed := WorldTravelRequest.parse(world_id, entry_id, options)
	if int(parsed["error"]) != OK:
		var context := _travel_context(world_id, entry_id)
		if String(parsed["field"]) != "":
			context["field"] = parsed["field"]
		return WorldDiagnostics.reject(&"travel_to", parsed["error"], context)
	# Checked before the guard, matching load_world: an unregistered destination
	# is rejected with no events and no guard churn at all. A request rejected
	# here never reaches an adapter, so nothing needs cleaning up.
	if not _scenes.has_world(world_id):
		return WorldDiagnostics.reject(
			&"travel_to", ERR_DOES_NOT_EXIST, _travel_context(world_id, entry_id)
		)
	var begin_err := _operation_guard.try_begin(&"travel_to")
	if begin_err != OK:
		return WorldDiagnostics.reject(
			&"travel_to", begin_err, _travel_context(world_id, entry_id)
		)
	var request: WorldTravelRequest = parsed["request"]
	var stage := WorldTravelStage.new()
	stage.operation_id = _operation_guard.get_operation_id()
	stage.world_id = request.world_id
	stage.entry_id = request.entry_id
	stage.payload = request.payload
	stage.timeout_seconds = request.timeout_seconds
	# Recorded here, not in the preflight, so transition_started and a cancel
	# taken at the very first checkpoint still name where the travel came from.
	# Nothing can change it in between: the guard is already held.
	stage.previous_world_id = _scenes.get_active_world_id()
	stage.hooks.configure(request.transition, request.placement, stage.operation_id)
	# Built here rather than inside the deferred body, unlike save and load: a
	# cancel issued between acceptance and the first frame would otherwise have
	# nothing to find.
	_travel = stage
	call_deferred("_run_travel")
	return OK


## The in-flight travel's operation id, or 0. travel_to returns an acceptance
## Error rather than an id, and the id is not otherwise visible until
## transition_started -- one frame too late to cancel. Read it at the moment you
## intend to cancel; never cache it, or a stale UI will cancel a later travel.
func current_travel_id() -> int:
	if _travel == null:
		return 0
	return _travel.operation_id


## Ask the in-flight travel to stop. OK means recorded, not stopped: the
## travel's own transition_failed is the outcome, and this adds no event.
##
## The one World-mutating command that does not pass through the guard. It
## acquires nothing, queues nothing, and starts nothing -- it sets a flag on the
## operation already holding the guard -- which is why it is the only command
## accepted from inside a travel callback. See README D2 and D22.
func cancel_travel(operation_id: int) -> Error:
	if not is_inside_tree() or not _initialized:
		return WorldDiagnostics.reject(
			&"cancel_travel", ERR_UNCONFIGURED, {"operation_id": operation_id}
		)
	if operation_id <= 0:
		return WorldDiagnostics.reject(
			&"cancel_travel", ERR_INVALID_PARAMETER, {"operation_id": operation_id}
		)
	# No travel with that id: idle, or a save/load/new_game is in flight. Those
	# are not cancellable in these phases.
	if _travel == null or _travel.operation_id != operation_id:
		return WorldDiagnostics.reject(
			&"cancel_travel", ERR_DOES_NOT_EXIST, {"operation_id": operation_id}
		)
	if _travel.phase == WorldTravelStage.Phase.TERMINAL:
		# The operation still exists, so ERR_DOES_NOT_EXIST would be a lie.
		return WorldDiagnostics.reject(
			&"cancel_travel", ERR_UNAVAILABLE, {"operation_id": operation_id}
		)
	if _travel.cancel_requested:
		# A second cancel has no distinct effect, and a UI spamming it is a
		# project bug worth seeing.
		return WorldDiagnostics.reject(
			&"cancel_travel", ERR_ALREADY_EXISTS, {"operation_id": operation_id}
		)
	_travel.cancel_requested = true
	# Abandon a stage in flight now; otherwise the next checkpoint observes it.
	_travel.hooks.cancel_current_stage(ERR_SKIP)
	return OK


func _run_travel() -> void:
	var stage := _travel
	if stage == null:
		return
	stage.phase = WorldTravelStage.Phase.STARTED
	_events.transition_started.emit(
		stage.event_context(stage.operation_id, &"travel_to", &"started")
	)
	if _travel_cancelled(stage, &"started"):
		return
	stage.phase = WorldTravelStage.Phase.PREFLIGHT
	var prepared := _travel_preflight(stage)
	if prepared != OK:
		_travel_fail_precommit(stage, prepared)
		return
	if _travel_cancelled(stage, &"validate"):
		return
	stage.phase = WorldTravelStage.Phase.PREPARE
	# Rollback material before any visible change: a project that cannot
	# describe its actor's state is discovered before anything is disturbed.
	var prepare_err := stage.hooks.prepare(_travel_hook_context(stage))
	if prepare_err != OK:
		_travel_fail_precommit(stage, stage.fail(prepare_err, &"prepare"))
		return
	stage.phase = WorldTravelStage.Phase.TRANSITION_OUT
	stage.hooks.run_stage(
		get_tree(),
		WorldTransition.STAGE_OUT,
		stage.timeout_seconds,
		_on_travel_out_finished
	)


func _on_travel_out_finished(
	operation_id: int, _stage_name: StringName, reason: Error
) -> void:
	var stage := _travel
	if stage == null or stage.operation_id != operation_id:
		return
	if stage.phase != WorldTravelStage.Phase.TRANSITION_OUT:
		return
	if reason != OK:
		stage.cancelled = reason == ERR_SKIP
		_travel_fail_precommit(stage, stage.fail(reason, &"transition_out"))
		return
	if _travel_cancelled(stage, &"transition_out"):
		return
	stage.phase = WorldTravelStage.Phase.SWAP
	var swapped := _travel_swap(stage)
	if swapped != OK:
		_travel_fail_precommit(stage, swapped)
		return
	if _travel_cancelled(stage, &"activate"):
		return
	stage.phase = WorldTravelStage.Phase.PLACE
	var entry := _travel_resolve_entry(stage)
	if entry != OK:
		_travel_fail_precommit(stage, entry)
		return
	var placed := stage.hooks.place(stage.entry)
	if placed != OK:
		_travel_fail_precommit(stage, stage.fail(placed, &"place"))
		return
	if _travel_cancelled(stage, &"place"):
		return
	_travel_commit(stage)
	# The destination is already public, so this reports failure and keeps it
	# rather than starting a reveal it is about to abandon.
	if _travel_cancelled(stage, &"transition_in"):
		return
	stage.phase = WorldTravelStage.Phase.TRANSITION_IN
	stage.hooks.run_stage(
		get_tree(),
		WorldTransition.STAGE_IN,
		stage.timeout_seconds,
		_on_travel_in_finished
	)


func _on_travel_in_finished(
	operation_id: int, _stage_name: StringName, reason: Error
) -> void:
	var stage := _travel
	if stage == null or stage.operation_id != operation_id:
		return
	if stage.phase != WorldTravelStage.Phase.TRANSITION_IN:
		return
	if reason != OK:
		stage.cancelled = reason == ERR_SKIP
		# Past the commit point: the destination stays, and this is reported as
		# a failure rather than rolled back.
		_travel_fail_postcommit(stage, stage.fail(reason, &"transition_in"))
		return
	_publish_travel_commit(stage)


## Everything that can fail while the outgoing world is still active. On return
## the destination candidate is prepared and restored but still detached, and
## the committed record store has not been touched.
func _travel_preflight(stage: WorldTravelStage) -> Error:
	stage.previous_state = _state.snapshot()
	stage.previous_records = _persistence.snapshot_records()
	var outgoing := _scenes.get_active_world_root()
	if outgoing != null:
		stage.previous_root_id = outgoing.get_instance_id()
		# Frozen before the capture, so nothing can run a physics frame between
		# reading the outgoing world and swapping it out.
		stage.suspension().suspend(outgoing)
		var captured: Dictionary = _persistence.capture_world_staged_owned(
			stage.previous_world_id
		)
		if int(captured["error"]) != OK:
			return stage.fail(captured["error"], &"capture")
		stage.staged_records = captured["records"]
	else:
		stage.staged_records = _persistence.snapshot_records()
	var instantiated: Dictionary = _scenes.instantiate_candidate_owned(stage.world_id)
	if int(instantiated["error"]) != OK:
		return stage.fail(instantiated["error"], &"instantiate")
	stage.adopt_candidate(instantiated["candidate"])
	# Validated before anything is torn down or hidden, so a typo'd entry point
	# costs the player nothing and never shows a fade.
	var entry_err := _scenes.verify_entry_owned(stage.candidate(), stage.entry_id)
	if entry_err != OK:
		return stage.fail(entry_err, &"validate")
	stage.suspension().suspend(stage.candidate())
	# From the staged table, not the committed store. For travel to the current
	# world this is the pass that just read the live values, which is what makes
	# a door opened one frame ago still open on arrival.
	var restored: Dictionary = _persistence.restore_world_owned(
		stage.world_id, stage.candidate(), stage.staged_records.get(stage.world_id, {})
	)
	if int(restored["error"]) != OK:
		return _fail_restore(stage, restored)
	return OK


## Attach the destination and retain the outgoing root. Reversible: the retained
## root is still a valid prepared candidate until the commit point.
func _travel_swap(stage: WorldTravelStage) -> Error:
	stage.committed = true
	# Records are installed before activation because attaching fires
	# PersistentEntity._enter_tree against the authoritative ownership map; with
	# the old map in place, an entity that moved worlds fails as a duplicate.
	_persistence.install_owned(stage.staged_records)
	var activated: Dictionary = _scenes.activate_retaining_owned(
		stage.world_id, stage.release_candidate()
	)
	if int(activated["error"]) != OK:
		return stage.fail(activated["error"], &"activate")
	stage.retain_outgoing(activated["retained"])
	return OK


## Legal only once the destination is attached: _snapshot_entry reads a global
## transform. Still precommit, so a marker destroyed by authored _ready fails
## with the outgoing world recoverable.
func _travel_resolve_entry(stage: WorldTravelStage) -> Error:
	if stage.entry_id == &"":
		return OK
	var entry := _scenes.resolve_entry_point(stage.entry_id)
	if entry == null:
		return stage.fail(ERR_DOES_NOT_EXIST, &"entry")
	stage.entry = entry
	return OK


## The commit point. Drops the rollback material, frees the outgoing world, and
## restores the destination's own process mode. Nothing here can fail, which is
## what lets `committed` be an honest claim rather than a hope.
func _travel_commit(stage: WorldTravelStage) -> void:
	stage.phase = WorldTravelStage.Phase.COMMIT
	stage.free_retained()
	stage.previous_records = {}
	stage.published = true
	stage.suspension().restore_all()
	var context := stage.event_context(stage.operation_id, &"travel_to", &"commit")
	# Published at the commit point, before transition-in, so it fires exactly
	# once whether or not the reveal succeeds. world_loaded already means "a
	# managed world root became active" -- a slot load emits it too -- and it is
	# the established typed channel for the resolved entry point.
	_events.world_loaded.emit(context, stage.entry)


func _publish_travel_commit(stage: WorldTravelStage) -> void:
	stage.phase = WorldTravelStage.Phase.TERMINAL
	stage.hooks.finalize()
	_events.transition_completed.emit(
		stage.event_context(stage.operation_id, &"travel_to", &"commit")
	)
	_travel = null
	_operation_guard.finish(stage.operation_id)


## Checkpoint. Cooperative because GDScript offers no way to abort anything from
## outside. -> true when the travel has been terminated by this call.
func _travel_cancelled(stage: WorldTravelStage, at: StringName) -> bool:
	if not stage.cancel_requested:
		return false
	stage.cancelled = true
	if stage.published:
		_travel_fail_postcommit(stage, stage.fail(ERR_SKIP, at))
	else:
		_travel_fail_precommit(stage, stage.fail(ERR_SKIP, at))
	return true


## Put the outgoing world back, in reverse of however far the swap got, then
## report. Any failure in the rollback itself is unrecoverable and escalates,
## exactly as a load's unwind does.
func _travel_fail_precommit(stage: WorldTravelStage, reason: Error) -> void:
	stage.phase = WorldTravelStage.Phase.TERMINAL
	# Only if it was attempted, and including a place that failed halfway -- the
	# same rule participant restore uses.
	var rollback_failed := false
	if stage.hooks.place_attempted():
		rollback_failed = stage.hooks.rollback() != OK
	if stage.committed:
		_persistence.install_owned(stage.previous_records)
		if stage.has_retained():
			# Reactivating the retained root frees the destination on the way
			# through, so the candidate is not discarded separately here.
			_scenes.activate_prepared_owned(
				stage.previous_world_id, stage.release_retained()
			)
	# activate_retaining_owned already freed the candidate on its own failure,
	# and release_candidate() cleared the handle, so this cannot double free.
	stage.discard_candidate()
	var root := _scenes.get_active_world_root()
	var restored_id := 0 if root == null else root.get_instance_id()
	var reactivation_failed := stage.committed and restored_id != stage.previous_root_id
	if rollback_failed or reactivation_failed:
		stage.recovery_required = true
		_operation_guard.enter_recovery({
			"operation": &"travel_to",
			"world_id": stage.world_id,
			"from_world_id": stage.previous_world_id,
			"stage": stage.failed_stage,
		})
	# Before the terminal event and before the guard is released, so by the time
	# new_game can be accepted no adapter overlay is still held.
	stage.hooks.finalize()
	# Last, and on the recovery path too: a permanently frozen world root would
	# be a second failure stacked invisibly on top of the first.
	stage.suspension().restore_all()
	_finish_travel(stage, reason)


## Past the commit point: the destination stays active and usable. An
## already-visible world is never silently rolled back, and this is not a
## recovery condition -- the session is fine, only the presentation failed.
func _travel_fail_postcommit(stage: WorldTravelStage, reason: Error) -> void:
	stage.phase = WorldTravelStage.Phase.TERMINAL
	stage.hooks.finalize()
	stage.suspension().restore_all()
	_finish_travel(stage, reason)


func _finish_travel(stage: WorldTravelStage, reason: Error) -> void:
	WorldDiagnostics.reject(&"travel_to", reason, stage.reject_context())
	_events.transition_failed.emit(
		reason, stage.event_context(stage.operation_id, &"travel_to", stage.failed_stage)
	)
	_travel = null
	_operation_guard.finish(stage.operation_id)


## Ids and copied values only -- never a Node, and never the live payload.
func _travel_hook_context(stage: WorldTravelStage) -> Dictionary:
	var context: Dictionary = {
		"operation_id": stage.operation_id,
		"to_world_id": stage.world_id,
	}
	if String(stage.previous_world_id) != "":
		context["from_world_id"] = stage.previous_world_id
	if String(stage.entry_id) != "":
		context["entry_id"] = stage.entry_id
	if not stage.payload.is_empty():
		context["payload"] = WorldValue.clone_validated(stage.payload)
	return context


# --- spawn --------------------------------------------------------------------


## Reached through World.entities.spawn, which is a thin forwarder: the guard and
## the deferred-command engine live here, so there is one of each.
func _begin_spawn(request: WorldSpawnRequest) -> Error:
	if not is_inside_tree() or not _initialized or _entities == null \
			or _persistence == null or _scenes == null:
		return WorldDiagnostics.reject(&"spawn", ERR_UNCONFIGURED, {})
	if request == null:
		return WorldDiagnostics.reject(&"spawn", ERR_INVALID_PARAMETER, {})
	var context: Dictionary = {}
	if String(request.archetype_id) != "":
		context["archetype_id"] = request.archetype_id
	var invalid := request.validate()
	if invalid != OK:
		return WorldDiagnostics.reject(&"spawn", invalid, context)
	# Everything statically wrong is refused before the guard, matching
	# travel_to's has_world check: no guard churn and no events.
	var world_id := _scenes.get_active_world_id()
	if String(world_id) == "":
		return WorldDiagnostics.reject(&"spawn", ERR_DOES_NOT_EXIST, context)
	context["world_id"] = world_id
	if not _entities.has_archetype(request.archetype_id):
		return WorldDiagnostics.reject(&"spawn", ERR_DOES_NOT_EXIST, context)
	var root := _scenes.get_active_world_root()
	var dimension := WorldSceneValidator.dimension_of_root(root)
	if _entities.archetypes().dimension_of(request.archetype_id) != dimension:
		return WorldDiagnostics.reject(&"spawn", ERR_INVALID_PARAMETER, context)
	var begin_err := _operation_guard.try_begin(&"spawn")
	if begin_err != OK:
		return WorldDiagnostics.reject(&"spawn", begin_err, context)
	var stage := WorldSpawnStage.new()
	stage.operation_id = _operation_guard.get_operation_id()
	stage.world_id = world_id
	stage.archetype_id = request.archetype_id
	stage.policy = request.persistence_policy as WorldPersistencePolicy.Kind
	stage.parent_kind = request.parent_kind
	stage.parent_id = request.parent_id
	_spawn = stage
	_pending_spawn_request = request
	call_deferred("_run_spawn")
	return OK


func _run_spawn() -> void:
	var stage := _spawn
	var request := _pending_spawn_request
	if stage == null or request == null:
		return
	_events.entity_spawn_started.emit(
		stage.event_context(stage.operation_id, &"spawn", &"started")
	)
	var prepared := _spawn_prepare(stage, request)
	if prepared != OK:
		_fail_spawn(stage, prepared)
		return
	var committed := _spawn_commit(stage)
	if committed != OK:
		_fail_spawn(stage, committed)
		return
	_publish_spawn(stage)


## Everything up to and including attachment. Reversible throughout: on failure
## the instance is detached inside the batch, the batch is aborted, the instance
## is freed and the reservation released.
func _spawn_prepare(stage: WorldSpawnStage, request: WorldSpawnRequest) -> Error:
	var reserved: Dictionary = _entities.ids().reserve(_entities.id_in_use)
	if int(reserved["error"]) != OK:
		return stage.fail(reserved["error"], &"reserve")
	stage.reserved_id = reserved["id"]
	stage.entity_id = stage.reserved_id
	var definition := _entities.archetypes().get_definition(stage.archetype_id)
	if definition == null or definition.scene == null:
		return stage.fail(ERR_CANT_CREATE, &"instantiate")
	var instance := definition.scene.instantiate()
	if instance == null:
		return stage.fail(ERR_CANT_CREATE, &"instantiate")
	stage.adopt_candidate(instance)
	# Before any tree entry: PersistentEntity freezes its exports once it
	# registers, and registration happens on _enter_tree.
	var stamped := _entities.stamp_identity_owned(
		instance, stage.reserved_id, stage.policy, stage.archetype_id
	)
	if stamped != OK:
		return stage.fail(stamped, &"identity")
	var applied := _spawn_apply_state(stage, request, instance, definition.dimension)
	if applied != OK:
		return applied
	var parent := _spawn_resolve_parent(stage)
	if parent == null:
		return stage.error if stage.error != OK else stage.fail(ERR_DOES_NOT_EXIST, &"parent")
	var pre := _entities.preflight_candidate(instance, null, stage.world_id)
	if pre != OK:
		return stage.fail(pre, &"validate")
	# The batch is what makes this attach legal at all: register_component
	# refuses with ERR_BUSY while the guard is held and no batch is open. It also
	# queues entity_registered rather than publishing it before the spawn commits.
	_entities.begin_batch()
	stage.batch_open = true
	parent.add_child(stage.release_candidate())
	stage.attached = true
	var registered := _entities.verify_root_registered(instance)
	if registered != OK:
		stage.adopt_candidate(instance)
		return stage.fail(registered, &"register")
	var built: Dictionary = _persistence.build_spawn_record_owned(
		stage.world_id, instance, _scenes.get_active_world_root()
	)
	if int(built["error"]) != OK:
		stage.adopt_candidate(instance)
		if String(built["entity_id"]) != "":
			stage.entity_id = built["entity_id"]
		return stage.fail(built["error"], &"capture")
	stage.spawned_record = built["record"]
	return OK


func _spawn_apply_state(
	stage: WorldSpawnStage,
	request: WorldSpawnRequest,
	instance: Node,
	dimension: WorldSceneValidator.Dimension
) -> Error:
	# Only the transform matching the archetype's dimension is consumed; the
	# other is ignored entirely and never validated.
	if dimension == WorldSceneValidator.Dimension.NODE_2D and instance is Node2D:
		(instance as Node2D).transform = request.transform_2d
	elif dimension == WorldSceneValidator.Dimension.NODE_3D and instance is Node3D:
		(instance as Node3D).transform = request.transform_3d
	var payloads := request.copied_components()
	if payloads.is_empty():
		return OK
	var components: Dictionary = {}
	for child in instance.get_children():
		if not (child is PersistentEntity):
			continue
		for component in child.get_children():
			if component is PersistentComponent:
				components[(component as PersistentComponent).component_id] = component
	for component_id: Variant in payloads.keys():
		var key := StringName(component_id)
		if not components.has(key):
			stage.component_id = key
			return stage.fail(ERR_DOES_NOT_EXIST, &"components")
		var component: PersistentComponent = components[key]
		var payload: Dictionary = payloads[component_id]
		var valid := component.validate_state(payload)
		if valid != OK:
			stage.component_id = key
			return stage.fail(valid, &"components")
		var restored := component.restore_state(payload)
		if restored != OK:
			stage.component_id = key
			return stage.fail(restored, &"components")
	return OK


## Resolves the request's parent against the live world and applies the
## durability rule. Returns null on failure, with the stage already failed.
func _spawn_resolve_parent(stage: WorldSpawnStage) -> Node:
	var root := _scenes.get_active_world_root()
	if root == null:
		stage.fail(ERR_DOES_NOT_EXIST, &"parent")
		return null
	if stage.parent_kind == WorldEntityParent.Kind.WORLD_ROOT:
		return root
	if stage.parent_kind == WorldEntityParent.Kind.ATTACHMENT:
		var attachment := _find_attachment(root, stage.parent_id)
		if attachment == null:
			stage.fail(ERR_DOES_NOT_EXIST, &"parent")
			return null
		return attachment
	var actor := _entities.resolve(stage.parent_id)
	if actor == null or not root.is_ancestor_of(actor):
		stage.fail(ERR_DOES_NOT_EXIST, &"parent")
		return null
	var record: EntityRecord = _persistence.get_record(stage.world_id, stage.parent_id)
	if record != null and record.removed:
		stage.fail(ERR_INVALID_PARAMETER, &"parent")
		return null
	var parent_entity := _entity_of(actor)
	if parent_entity == null:
		stage.fail(ERR_DOES_NOT_EXIST, &"parent")
		return null
	# No record may outlive the parent it needs for reconstruction.
	var durable := WorldPersistenceManager.validate_parent_policy(
		int(stage.policy), int(parent_entity.persistence_policy)
	)
	if durable != OK:
		stage.fail(durable, &"parent")
		return null
	return actor


## The commit point. Record first, so the entity_registered the batch replays
## finds get_record already answering. Both steps are dictionary writes and a
## queue flush, so neither can fail -- spawn has no postcommit failure path.
func _spawn_commit(stage: WorldSpawnStage) -> Error:
	stage.committed = true
	if stage.spawned_record != null:
		_persistence.commit_record_owned(stage.spawned_record)
	_entities.commit_batch()
	stage.batch_open = false
	# Converted rather than kept: the registry and the record table cover the id
	# from here on, so the reservation has no job left.
	_entities.ids().release(stage.reserved_id)
	return OK


func _publish_spawn(stage: WorldSpawnStage) -> void:
	var context := stage.event_context(stage.operation_id, &"spawn", &"commit")
	_events.entity_spawned.emit(stage.reserved_id, stage.world_id, context)
	_spawn = null
	_pending_spawn_request = null
	_operation_guard.finish(stage.operation_id)


func _fail_spawn(stage: WorldSpawnStage, reason: Error) -> void:
	# Detach before aborting: abort_batch clears the queue, so a remove_child
	# after it would publish an entity_unregistered for an entity whose
	# entity_registered was never published.
	if stage.attached and stage.has_candidate():
		var instance := stage.candidate()
		var parent := instance.get_parent()
		if parent != null:
			parent.remove_child(instance)
	if stage.batch_open:
		_entities.abort_batch()
		stage.batch_open = false
	stage.discard_candidate()
	_entities.ids().release(stage.reserved_id)
	WorldDiagnostics.reject(&"spawn", reason, stage.reject_context())
	_events.entity_spawn_failed.emit(
		reason, stage.event_context(stage.operation_id, &"spawn", stage.failed_stage)
	)
	_spawn = null
	_pending_spawn_request = null
	_operation_guard.finish(stage.operation_id)


func _find_attachment(node: Node, id: StringName) -> Node:
	if node is WorldAttachment and (node as WorldAttachment).id == id:
		return node.get_parent()
	for child in node.get_children():
		var found := _find_attachment(child, id)
		if found != null:
			return found
	return null


func _entity_of(actor: Node) -> PersistentEntity:
	for child in actor.get_children():
		if child is PersistentEntity:
			return child
	return null


# --- despawn ------------------------------------------------------------------


func _begin_despawn(entity_ids: Array[StringName]) -> Error:
	if not is_inside_tree() or not _initialized or _entities == null \
			or _persistence == null or _scenes == null:
		return WorldDiagnostics.reject(&"despawn", ERR_UNCONFIGURED, {})
	if entity_ids.is_empty():
		return WorldDiagnostics.reject(&"despawn", ERR_INVALID_PARAMETER, {})
	var seen: Dictionary = {}
	for entity_id: StringName in entity_ids:
		if WorldId.validate(entity_id) != OK:
			return WorldDiagnostics.reject(
				&"despawn", ERR_INVALID_PARAMETER, {"entity_id": entity_id}
			)
		# Refused rather than collapsed: a repeated id is a project bug, and
		# ERR_ALREADY_EXISTS keeps it distinguishable from a malformed one.
		if seen.has(entity_id):
			return WorldDiagnostics.reject(
				&"despawn", ERR_ALREADY_EXISTS, {"entity_id": entity_id}
			)
		seen[entity_id] = true
	var begin_err := _operation_guard.try_begin(&"despawn")
	if begin_err != OK:
		return WorldDiagnostics.reject(&"despawn", begin_err, {})
	var stage := WorldDespawnStage.new()
	stage.operation_id = _operation_guard.get_operation_id()
	stage.world_id = _scenes.get_active_world_id()
	stage.requested = entity_ids.duplicate()
	_despawn = stage
	call_deferred("_run_despawn")
	return OK


func _run_despawn() -> void:
	var stage := _despawn
	if stage == null:
		return
	_events.entity_remove_started.emit(
		stage.event_context(stage.operation_id, &"despawn", &"started")
	)
	var prepared := _despawn_preflight(stage)
	if prepared != OK:
		_fail_despawn(stage, prepared)
		return
	_despawn_commit(stage)
	_publish_despawn(stage)


## Validates the whole set against a staged copy of the record tables, so
## nothing is mutated until the one install_owned in _despawn_commit.
func _despawn_preflight(stage: WorldDespawnStage) -> Error:
	# A full staged capture first. That is what makes recorded-but-unloaded
	# records and live actors uniform: afterwards every live non-NONE actor has
	# a record, so the closure predicate's precondition holds without inventing
	# anything. It also closes a durability hole -- freeing a live but
	# never-captured authored SESSION actor without a tombstone would let the
	# authored scene re-instantiate it on the next travel back.
	if String(stage.world_id) != "":
		var captured: Dictionary = _persistence.capture_world_staged_owned(stage.world_id)
		if int(captured["error"]) != OK:
			stage.entity_id = captured["entity_id"]
			return stage.fail(captured["error"], &"capture")
		stage.staged = captured["records"]
	else:
		stage.staged = _persistence.snapshot_records()
	for entity_id: StringName in stage.requested:
		var actor := _entities.resolve(entity_id)
		var owner_world := _owning_world(stage.staged, entity_id)
		if String(owner_world) == "":
			if actor == null:
				stage.entity_id = entity_id
				return stage.fail(ERR_DOES_NOT_EXIST, &"preflight")
			# A live NONE actor: runtime identity, no record, so it is freed
			# without a tombstone.
			stage.live_actors[entity_id] = actor
			stage.removed_ids.append(entity_id)
			continue
		var record: EntityRecord = (stage.staged[owner_world] as Dictionary)[entity_id]
		if record.removed:
			# Idempotent: already removed, so it contributes nothing and is not
			# required in any closure set.
			continue
		var group: Array[StringName] = stage.by_world.get(owner_world, [] as Array[StringName])
		group.append(entity_id)
		stage.by_world[owner_world] = group
		stage.removed_ids.append(entity_id)
		if actor != null:
			stage.live_actors[entity_id] = actor
	for world_key: Variant in stage.by_world.keys():
		var failure: Dictionary = {}
		# The same predicate the commit uses, so preflight and commit provably
		# cannot disagree about what a subtree is.
		var closure := WorldPersistenceManager.mark_removed_in(
			_persistence.snapshot_records(), world_key, stage.by_world[world_key], failure
		)
		if closure != OK:
			stage.entity_id = failure.get("entity_id", &"")
			return stage.fail(closure, &"closure")
	return OK


## The commit point: tombstones are applied to the staged tables and the whole
## set is installed with one swap, then loaded actors are freed inside a batch.
func _despawn_commit(stage: WorldDespawnStage) -> void:
	stage.committed = true
	for world_key: Variant in stage.by_world.keys():
		var failure: Dictionary = {}
		WorldPersistenceManager.mark_removed_staged(
			stage.staged, world_key, stage.by_world[world_key], failure
		)
	_persistence.install_owned(stage.staged)
	_entities.begin_batch()
	stage.batch_open = true
	for entity_id: Variant in stage.live_actors.keys():
		# Read untyped: freeing a parent takes its descendants, so an entry for a
		# child in the same set is already dangling, and assigning that to a
		# typed Node throws before any validity check could run.
		var stored: Variant = stage.live_actors[entity_id]
		if stored == null or not is_instance_valid(stored):
			continue
		_entities.release_actor_owned(stored as Node)
	_entities.commit_batch()
	stage.batch_open = false


func _publish_despawn(stage: WorldDespawnStage) -> void:
	var ids: Array = []
	for id: StringName in stage.removed_ids:
		ids.append(id)
	_events.entities_removed.emit(
		ids, stage.event_context(stage.operation_id, &"despawn", &"commit")
	)
	_despawn = null
	_operation_guard.finish(stage.operation_id)


func _fail_despawn(stage: WorldDespawnStage, reason: Error) -> void:
	# Nothing was mutated: the staged tables die with the stage.
	if stage.batch_open:
		_entities.abort_batch()
		stage.batch_open = false
	WorldDiagnostics.reject(&"despawn", reason, stage.reject_context())
	_events.entity_remove_failed.emit(
		reason, stage.event_context(stage.operation_id, &"despawn", stage.failed_stage)
	)
	_despawn = null
	_operation_guard.finish(stage.operation_id)


func _owning_world(records: Dictionary, entity_id: StringName) -> StringName:
	for world_key: Variant in records.keys():
		if (records[world_key] as Dictionary).has(entity_id):
			return StringName(world_key)
	return &""


## One place to turn a structured restore result into a failed stage. The stage
## string comes from the restore rather than being hardcoded, so a dynamic
## materialization failure reports "materialize" while everything else still
## reports "restore" -- leaving existing expected lines untouched.
func _fail_restore(stage: WorldSessionStage, result: Dictionary) -> Error:
	if String(result["entity_id"]) != "":
		stage.entity_id = result["entity_id"]
	if String(result["component_id"]) != "":
		stage.component_id = result["component_id"]
	if String(result["archetype_id"]) != "":
		stage.archetype_id = result["archetype_id"]
	return stage.fail(result["error"], result["stage"])


func _travel_context(world_id: StringName, entry_id: StringName) -> Dictionary:
	var context: Dictionary = {}
	if String(world_id) != "":
		context["world_id"] = world_id
	if String(entry_id) != "":
		context["entry_id"] = entry_id
	return context


func _slot_context(slot_id: StringName) -> Dictionary:
	var context: Dictionary = {}
	if String(slot_id) != "":
		context["slot_id"] = slot_id
	return context


func _event_context(
	operation_id: int, operation: StringName, world_id: StringName, stage: StringName
) -> Dictionary:
	return {
		"operation_id": operation_id,
		"operation": operation,
		"world_id": world_id,
		"stage": stage,
	}.duplicate()
