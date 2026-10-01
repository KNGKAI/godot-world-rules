class_name WorldTravelHooks
extends RefCounted
## The two optional adapters for one travel, and the guarantee that both are
## cleaned up exactly once.
##
## Cleanup is the load-bearing part. Research note 13 records that a full-screen
## overlay at the default mouse_filter swallows every mouse event and marks it
## handled, so a transition left up by a failure path leaves the game
## permanently unclickable. That is why cleanup runs from a single finaliser
## every exit funnels through, before the terminal event and before the guard is
## released -- which is also what makes "no successful new_game leaves an
## adapter overlay active" structurally true rather than merely intended.
##
## Does not log: the owning command emits one diagnostic of its own.


var _transition: WorldTransition = null
var _placement: WorldPlacement = null
var _operation_id: int = 0
var _waiter: WorldStageWaiter = null
var _place_attempted: bool = false
var _finalized: bool = false


func configure(
	transition: WorldTransition, placement: WorldPlacement, operation_id: int
) -> void:
	_transition = transition
	_placement = placement
	_operation_id = operation_id


func has_transition() -> bool:
	return _transition != null


func is_awaiting() -> bool:
	return _waiter != null and _waiter.is_awaiting()


## Run one transition stage. With no adapter the stage is an immediate success,
## still reported through the continuation so both paths through World are one
## path. The continuation receives (operation_id, stage, reason).
func run_stage(
	tree: SceneTree, stage: StringName, timeout_seconds: float, continuation: Callable
) -> void:
	if _finalized or _transition == null:
		continuation.call_deferred(_operation_id, stage, OK)
		return
	_waiter = WorldStageWaiter.new()
	_waiter.begin(tree, _transition, _operation_id, stage, timeout_seconds, continuation)


## Abandon the stage in flight, if there is one. Safe to call when there is not.
func cancel_current_stage(reason: Error) -> void:
	if _waiter != null:
		_waiter.cancel(reason)


func prepare(context: Dictionary) -> Error:
	if _finalized or _placement == null:
		return OK
	return _placement.prepare(context)


## The attempt is recorded before the call, so a place that fails halfway is
## still rolled back -- the same rule participant restore uses.
func place(entry: WorldEntryPointData) -> Error:
	if _finalized or _placement == null:
		return OK
	_place_attempted = true
	return _placement.place(entry)


func place_attempted() -> bool:
	return _place_attempted


## Only meaningful when place was attempted; World checks that before calling.
func rollback() -> Error:
	if _finalized or _placement == null:
		return OK
	return _placement.rollback()


func is_finalized() -> bool:
	return _finalized


## Exactly once, on every accepted request, including one where neither adapter
## was ever successfully started.
func finalize() -> void:
	if _finalized:
		return
	# Set before the first project call, so a re-entrant travel_to or
	# cancel_travel from inside cleanup cannot re-enter this.
	_finalized = true
	var transition := _transition
	var placement := _placement
	# Dropped before the calls, so no adapter reference survives finalize even
	# if a project cleanup reaches back into World.
	_transition = null
	_placement = null
	_waiter = null
	if transition != null:
		transition.cleanup(_operation_id)
	# A separate statement sharing no state with the one above: a runtime error
	# in the transition's cleanup must not cost the placement its own.
	if placement != null:
		placement.cleanup()
