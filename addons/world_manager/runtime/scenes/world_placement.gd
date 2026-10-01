class_name WorldPlacement
extends RefCounted
## An optional project hook that puts the project's own actor where the
## destination's entry point says. The addon does not assume a player object, a
## camera model, or that anything needs placing at all.
##
## This moves one project-owned actor and nothing else. It does not suspend
## input and holds no lock token: a project that needs control suppressed does
## that inside its own adapter. README D18 is still open, and Phase 12 still
## owns it.
##
## All four hooks are synchronous and bounded, must not call a guarded World
## command, and must not touch a managed world root -- the outgoing one is freed
## at the commit point.
##
## The ordering World guarantees:
##
##   prepare  -> after the destination is validated, before anything is hidden
##               or swapped. Capture whatever rollback needs. Change nothing.
##   place    -> after the destination is attached, before the commit point, so
##               global transforms are real and the travel can still be undone.
##   rollback -> only if place was attempted, including a place that failed
##               halfway. Put the actor back where prepare found it.
##   cleanup  -> exactly once per accepted request, before the terminal event.
##
## A rollback that fails is unrecoverable: World enters the recovery-required
## state of README D19, the same one a failed slot load uses, rather than
## pretending the actor is somewhere it is not.


## Capture what rollback will need. Called before any visible change, so that a
## project that cannot describe its actor's current state is discovered before
## the travel has disturbed anything -- the same preflight rule participants get.
func prepare(_context: Dictionary) -> Error:
	return OK


## Position the actor. `entry` is null when the request named no entry point,
## which is a legitimate travel and not an error.
func place(_entry: WorldEntryPointData) -> Error:
	return OK


func rollback() -> Error:
	return OK


func cleanup() -> void:
	pass
