class_name WorldTransition
extends RefCounted
## An optional project presentation hook for one travel: a fade, a wipe, a
## loading card. The addon knows nothing about what it draws.
##
## This base class is itself the immediate-success adapter -- start_out and
## start_in report completion synchronously -- so a project that supplies no
## transition and one that supplies a trivial one take the same path through
## World, and the inline-completion case can never rot untested.
##
## RefCounted rather than Node so it is testable without a SceneTree and holds
## no tree state. It is never handed a managed world root, and it must not
## reparent anything into one: those roots are freed at the commit point.
##
## The contract, which World enforces where it can and documents where it
## cannot:
##
## - If start_* returns OK you must emit `finished` for that exact operation_id
##   and stage, or the stage resolves with ERR_TIMEOUT. World cannot detect a
##   tween that will never finish.
## - If start_* returns non-OK, do not emit `finished`. World does not wait for
##   a start it already knows was refused, and a later emission is ignored.
## - cancel(id) means stop now. World does not wait for `finished` afterwards:
##   Tween.kill() never emits its own finished signal (research note 12), so
##   waiting would be a permanent strand.
## - cleanup(id) runs exactly once per accepted request, even one where nothing
##   was ever started, and always before the terminal event. Make it idempotent
##   and have it write neutral state -- killing a tween restores nothing, and an
##   overlay left up swallows every mouse event (research note 13).
## - You may call World.cancel_travel() from a hook; it is ungated. You must not
##   call a guarded World command, which returns ERR_BUSY.


## Emitted when a stage this adapter started has finished, been abandoned, or
## failed. World rejects an emission whose operation_id or stage does not match
## the one it is waiting on, so a stale or duplicate report is inert.
signal finished(operation_id: int, stage: StringName, reason: Error)

const STAGE_OUT: StringName = &"transition_out"
const STAGE_IN: StringName = &"transition_in"


## Hide the outgoing world. Runs before the swap, after the destination has been
## instantiated and validated -- so a travel that was going to fail never shows
## a fade, at the cost of the destination's instantiation hitch landing before
## the screen is covered.
func start_out(operation_id: int) -> Error:
	finished.emit(operation_id, STAGE_OUT, OK)
	return OK


## Reveal the destination. Runs after the commit point, so by the time this is
## called the travel has already succeeded and world_loaded has been published.
func start_in(operation_id: int) -> Error:
	finished.emit(operation_id, STAGE_IN, OK)
	return OK


func cancel(_operation_id: int) -> void:
	pass


func cleanup(_operation_id: int) -> void:
	pass
