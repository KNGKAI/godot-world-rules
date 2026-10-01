class_name WorldTravelStage
extends WorldSessionStage
## One travel transaction: staged records, the retained outgoing root, recorded
## process modes, and failure context.
##
## Subclasses WorldSessionStage rather than sitting beside it for one reason
## that matters: the candidate-ownership trio (adopt/release/discard) guards a
## real double-free, because activate_prepared_owned frees the candidate itself
## on its own failure. Travel hits that hazard in the same place a load does, so
## a second copy of the rule would be a second chance to get it wrong. The
## inherited save/load fields cost nothing here -- event_context already gates
## every optional key on a non-default value.


## Strictly linear and never re-entered. TERMINAL is where cleanup and the
## single terminal event happen, and it is the one phase cancellation refuses:
## the travel is already publishing its outcome.
enum Phase {
	CREATED,
	STARTED,
	PREFLIGHT,
	PREPARE,
	TRANSITION_OUT,
	SWAP,
	PLACE,
	COMMIT,
	TRANSITION_IN,
	TERMINAL,
}

var entry_id: StringName = &""
var payload: Dictionary = {}
var operation_id: int = 0
var phase: Phase = Phase.CREATED
var timeout_seconds: float = WorldTravelRequest.DEFAULT_TIMEOUT_SECONDS
var hooks := WorldTravelHooks.new()

## Recorded by cancel_travel, observed at the next checkpoint. Cancellation is
## cooperative because that is the only mechanism GDScript offers -- there is no
## way to abort a suspended anything from outside.
var cancel_requested: bool = false
var cancelled: bool = false

## Snapshotted after attachment, because a global transform is meaningless while
## the destination root is still detached.
var entry: WorldEntryPointData = null

## Instance id, not the world id: travel to the world you are already in has a
## matching world id on both sides, so only identity distinguishes "the outgoing
## root was put back" from "the destination stayed".
var previous_root_id: int = 0

## True once the commit point has passed -- the retained outgoing root is freed
## and the destination is public. Reported as `committed` so a listener can tell
## "nothing happened" from "you are in the destination, but the travel failed".
var published: bool = false

var _retained: Node = null
var _suspension := WorldProcessSuspension.new()


func suspension() -> WorldProcessSuspension:
	return _suspension


## The outgoing root, detached but alive, held until the commit point.
func retain_outgoing(node: Node) -> void:
	_retained = node


func has_retained() -> bool:
	return _retained != null and is_instance_valid(_retained)


func retained() -> Node:
	return _retained


## Hands the retained root back for reactivation and clears the handle, so a
## later free cannot reach a node the director has taken.
func release_retained() -> Node:
	var node := _retained
	_retained = null
	return node


## The commit point's half of the work: the outgoing world is no longer
## reachable and no longer needed.
func free_retained() -> void:
	if _retained != null and is_instance_valid(_retained):
		_suspension.forget(_retained)
		_retained.free()
	_retained = null


func reject_context() -> Dictionary:
	var context := super()
	if String(entry_id) != "":
		context["entry_id"] = entry_id
	if String(previous_world_id) != "":
		context["from_world_id"] = previous_world_id
	# payload is deliberately absent: WorldDiagnostics.reject stringifies every
	# value into one sorted line that tools/test_negative.ps1 asserts exactly,
	# and a project-supplied dictionary there would make it unassertable.
	return context


func event_context(
	operation_id: int, operation: StringName, stage: StringName
) -> Dictionary:
	var context := super(operation_id, operation, stage)
	if String(entry_id) != "":
		context["entry_id"] = entry_id
	if String(previous_world_id) != "":
		context["from_world_id"] = previous_world_id
	if not payload.is_empty():
		# A fresh clone per emission, so the stage's own copy is not reachable
		# from any listener either.
		context["payload"] = WorldValue.clone_validated(payload)
	if published:
		context["committed"] = true
	if cancelled:
		context["cancelled"] = true
	return context
