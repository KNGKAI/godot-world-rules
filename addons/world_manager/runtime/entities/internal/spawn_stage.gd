class_name WorldSpawnStage
extends WorldSessionStage
## One spawn transaction. Subclasses WorldSessionStage for the candidate
## ownership trio -- a detached archetype instance is exactly a candidate, and
## that trio guards a real double-free.


var operation_id: int = 0
var policy: WorldPersistencePolicy.Kind = WorldPersistencePolicy.Kind.SAVE_GAME
var parent_kind: WorldEntityParent.Kind = WorldEntityParent.Kind.WORLD_ROOT
var parent_id: StringName = &""

var reserved_id: StringName = &""
var batch_open: bool = false
var attached: bool = false
## Null for a NONE spawn: runtime identity without a persistent record is the
## policy contract, not a missing step.
var spawned_record: EntityRecord = null


func reject_context() -> Dictionary:
	var context := super()
	if String(parent_id) != "":
		context["parent_id"] = parent_id
	# entity_id is deliberately absent: a generated dyn:<hex> is random, so an
	# exact expected_error_line would be unassertable, and by the time anyone
	# reads the log the id has been released and names nothing. The failure
	# event keeps it, for correlation.
	context.erase("entity_id")
	return context


func event_context(
	operation_id: int, operation: StringName, stage: StringName
) -> Dictionary:
	var context := super(operation_id, operation, stage)
	context["policy"] = int(policy)
	context["parent_kind"] = int(parent_kind)
	if String(parent_id) != "":
		context["parent_id"] = parent_id
	return context
