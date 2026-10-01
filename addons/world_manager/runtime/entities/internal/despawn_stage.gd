class_name WorldDespawnStage
extends WorldSessionStage
## One despawn transaction: the requested set, the staged record tables it is
## validated against, and the actors to free once the tombstones commit.


var operation_id: int = 0
var requested: Array[StringName] = []
## Every requested id this call actually changed. A request of only
## already-tombstoned ids succeeds with this empty, which is the idempotent case.
var removed_ids: Array[StringName] = []
## Requested ids grouped by the world that owns their record.
var by_world: Dictionary = {}
var live_actors: Dictionary = {}
var staged: Dictionary = {}
var batch_open: bool = false


func reject_context() -> Dictionary:
	var context := super()
	# requested is deliberately absent: WorldDiagnostics.reject stringifies every
	# value into one sorted line that the negative harness asserts exactly, and a
	# caller-sized array there would be unassertable.
	return context


func event_context(
	operation_id: int, operation: StringName, stage: StringName
) -> Dictionary:
	var context := super(operation_id, operation, stage)
	var ids: Array = []
	for id: StringName in requested:
		ids.append(id)
	context["requested_ids"] = ids
	return context
