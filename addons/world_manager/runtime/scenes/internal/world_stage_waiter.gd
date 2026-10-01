class_name WorldStageWaiter
extends RefCounted
## One adapter stage, one instance, exactly one settlement.
##
## The wait is a connect-and-callback state machine rather than an await, and
## that is forced rather than preferred. Research note 07 establishes that
## GDScript exposes no handle to a suspended coroutine: there is no cancel, no
## timeout, no `await ... or timeout`, so a bounded wait cannot be an await at
## all. Note 12 adds that Tween.kill() never emits `finished`, so the most
## likely real adapter -- a fade -- is precisely the one that would strand an
## awaiter forever, with no error in any build.
##
## A stale timer is neutralised by identity, not by a generation counter: the
## timer's Callable binds to this instance, and this instance settles once, so a
## timer left over from an earlier stage can only ever reach its own dead
## waiter. That needs no counter to be maintained correctly.
##
## Does not log: the owning command emits one diagnostic of its own.


enum State {
	IDLE,
	AWAITING,
	SETTLED,
}

## Why the stage ended. Cancellation and timeout are the two that have to tell
## the adapter to stop; a normal completion has nothing to stop, and a refused
## start was never running.
enum Source {
	ADAPTER,
	START_REJECTED,
	TIMEOUT,
	CANCELLED,
}

var _state: State = State.IDLE
var _adapter: WorldTransition = null
var _operation_id: int = 0
var _stage: StringName = &""
var _continuation: Callable = Callable()
var _dispatching_start: bool = false
var _inline_pending: bool = false
var _inline_reason: Error = OK


func is_awaiting() -> bool:
	return _state == State.AWAITING


## Connects before starting, so an adapter that reports completion synchronously
## inside start_* is still heard. The continuation receives
## (operation_id, stage, reason) and is always called deferred.
func begin(
	tree: SceneTree,
	adapter: WorldTransition,
	operation_id: int,
	stage: StringName,
	timeout_seconds: float,
	continuation: Callable
) -> void:
	_adapter = adapter
	_operation_id = operation_id
	_stage = stage
	_continuation = continuation
	_state = State.AWAITING
	# Not CONNECT_ONE_SHOT: a one-shot connection is spent by the first
	# emission, including one rejected as stale or wrong-stage, and the
	# adapter's real completion would then arrive with no receiver and time out.
	adapter.finished.connect(_on_finished)
	if tree != null:
		# process_always so a travel started from a pause menu still times out,
		# and ignore_time_scale so a project at time_scale 0 does not get an
		# infinite timeout. The consequence, documented in D22: this is a
		# wall-clock watchdog, not a presentation budget.
		var timer := tree.create_timer(timeout_seconds, true, false, true)
		timer.timeout.connect(_on_timeout)
	_dispatching_start = true
	var started: Error = _start(adapter, stage, operation_id)
	_dispatching_start = false
	if started != OK:
		_settle(started, Source.START_REJECTED)
		return
	if _inline_pending:
		_settle(_inline_reason, Source.ADAPTER)


## Stop the stage now. World does not then wait for a `finished` that a killed
## tween will never emit.
func cancel(reason: Error) -> void:
	_settle(reason, Source.CANCELLED)


static func _start(
	adapter: WorldTransition, stage: StringName, operation_id: int
) -> Error:
	if stage == WorldTransition.STAGE_IN:
		return adapter.start_in(operation_id)
	return adapter.start_out(operation_id)


func _on_finished(operation_id: int, stage: StringName, reason: Error) -> void:
	if _state != State.AWAITING:
		return
	if operation_id != _operation_id or stage != _stage:
		return
	if _dispatching_start:
		# Deferring the settlement until start_* has returned is what keeps the
		# rest of the travel out of the adapter's own call frame: the outgoing
		# world must not be swapped out from under a start that has not returned.
		if _inline_pending:
			return
		_inline_pending = true
		_inline_reason = reason
		return
	_settle(reason, Source.ADAPTER)


func _on_timeout() -> void:
	_settle(ERR_TIMEOUT, Source.TIMEOUT)


## The one choke point. SETTLED is written before the adapter is called back, so
## a `finished` emitted from inside cancel(), or a re-entrant cancel, is already
## a no-op.
func _settle(reason: Error, source: Source) -> void:
	if _state != State.AWAITING:
		return
	_state = State.SETTLED
	var adapter := _adapter
	var continuation := _continuation
	if adapter != null and adapter.finished.is_connected(_on_finished):
		adapter.finished.disconnect(_on_finished)
	# Released before the callback, so the stale timer that outlives this waiter
	# retains one inert RefCounted and never a project adapter, a world root, or
	# a continuation back into World.
	_adapter = null
	_continuation = Callable()
	if source == Source.CANCELLED or source == Source.TIMEOUT:
		if adapter != null:
			adapter.cancel(_operation_id)
	if continuation.is_valid():
		continuation.call_deferred(_operation_id, _stage, reason)
