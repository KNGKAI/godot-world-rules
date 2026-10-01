class_name WorldSessionStage
extends RefCounted
## One save or load transaction: staged data, retained rollback material, and
## failure context. Holds no live Node except the detached candidate it owns
## until commit, and that one is never placed in an event payload.


var error: Error = OK
var failed_stage: StringName = &""
var slot_id: StringName = &""
var participant_id: StringName = &""
var world_id: StringName = &""
var entity_id: StringName = &""
var recovered_from: StringName = &""
## Set only by a dynamic materialization failure, so every existing diagnostic
## line is byte-identical.
var archetype_id: StringName = &""
var component_id: StringName = &""
var recovery_required: bool = false
var byte_size: int = 0
var generation: int = 0

## Migration reporting. source_ is the container version on disk and loaded_ is
## the version it was brought to; they differ only when a container migration
## ran. Reported through the existing terminal events -- an upgraded load is not
## a second kind of success and does not get its own signal.
var source_format_version: int = 0
var loaded_format_version: int = 0
var container_migration_steps: int = 0
var participant_migrations: Dictionary = {}
var migration_context: Dictionary = {}

var document: Dictionary = {}
var bytes: PackedByteArray = PackedByteArray()

var has_active_world: bool = false
var active_world: StringName = &""
var staged_state: Dictionary = {}
var staged_records: Dictionary = {}
var staged_systems: Dictionary = {}

var previous_world_id: StringName = &""
var previous_state: Dictionary = {}
var previous_records: Dictionary = {}
var rollback_snapshots: Dictionary = {}
var attempted: Array[StringName] = []
var committed: bool = false

var _candidate: Node = null


func fail(reason: Error, at: StringName) -> Error:
	error = reason
	failed_stage = at
	return reason


func adopt_candidate(node: Node) -> void:
	_candidate = node


func has_candidate() -> bool:
	return _candidate != null and is_instance_valid(_candidate)


func candidate() -> Node:
	return _candidate


## Hands ownership to the director and clears the handle, so a later discard
## cannot double-free a node the director has already taken or freed.
func release_candidate() -> Node:
	var node := _candidate
	_candidate = null
	return node


func discard_candidate() -> void:
	if _candidate != null and is_instance_valid(_candidate):
		_candidate.free()
	_candidate = null


func reject_context() -> Dictionary:
	var context: Dictionary = {}
	if String(slot_id) != "":
		context["slot_id"] = slot_id
	if String(world_id) != "":
		context["world_id"] = world_id
	if String(entity_id) != "":
		context["entity_id"] = entity_id
	if String(participant_id) != "":
		context["participant_id"] = participant_id
	if String(archetype_id) != "":
		context["archetype_id"] = archetype_id
	if String(component_id) != "":
		context["component_id"] = component_id
	if String(failed_stage) != "":
		context["stage"] = failed_stage
	# Names the gap a project has to fill. "A migration is missing between 1 and
	# 2" is actionable; ERR_UNAVAILABLE on its own is not.
	for field: String in ["from_version", "to_version"]:
		if migration_context.has(field) and int(migration_context[field]) > 0:
			context[field] = int(migration_context[field])
	return context


## Copied values only. WorldValue.validate over the result must return OK,
## which is the assertion that no Node handle ever reaches a listener.
func event_context(operation_id: int, operation: StringName, stage: StringName) -> Dictionary:
	var context: Dictionary = {
		"operation_id": operation_id,
		"operation": operation,
		"world_id": world_id,
		"stage": stage,
	}
	# Gated rather than unconditional so a travel, which has no slot, does not
	# report an empty one. Save and load both validate slot_id before taking the
	# guard, so the key is still always present for them.
	if String(slot_id) != "":
		context["slot_id"] = slot_id
	if String(participant_id) != "":
		context["participant_id"] = participant_id
	if String(entity_id) != "":
		context["entity_id"] = entity_id
	if String(archetype_id) != "":
		context["archetype_id"] = archetype_id
	if String(component_id) != "":
		context["component_id"] = component_id
	if String(recovered_from) != "":
		context["recovered_from"] = recovered_from
	if recovery_required:
		context["recovery_required"] = true
	if byte_size > 0:
		context["byte_size"] = byte_size
	if generation > 0:
		context["generation"] = generation
	if source_format_version > 0:
		context["source_format_version"] = source_format_version
	if loaded_format_version > 0:
		context["loaded_format_version"] = loaded_format_version
	if container_migration_steps > 0:
		context["container_migration_steps"] = container_migration_steps
	if not participant_migrations.is_empty():
		context["participant_migrations"] = participant_migrations.duplicate(true)
	return context.duplicate()
