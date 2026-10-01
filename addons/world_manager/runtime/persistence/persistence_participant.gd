class_name PersistenceParticipant
extends RefCounted
## A project system that contributes versioned state to save slots.
##
## Hooks are synchronous and bounded, must not call guarded World operations,
## and must be able to restore their own captured state -- a participant that
## cannot describe its current state cannot be rolled back, and a load refuses
## before touching anything rather than discovering that midway. External
## irreversible I/O does not belong here: the addon does not claim arbitrary
## project side effects can be undone.
##
## RefCounted rather than Node so it is testable without a SceneTree and holds
## no tree state. A project whose system is an autoload registers a small
## adapter that forwards to it. The registry holds a strong reference until
## unregister_participant.


## Travels with this participant's state in the save, so participant payloads
## migrate independently of the container format. See README D21.
func schema_version() -> int:
	return 1


## Adjacent upgrade steps for this participant's state, keyed by the version
## each step reads: {1: OneToTwo.new(), 2: TwoToThree.new()}. Each advances
## exactly one version, and the chain must reach schema_version() from every
## version a shipped build ever wrote.
##
## Declared here rather than passed to register_participant so the object that
## says "I am version 3" is the same object that says how to reach 3 -- the two
## cannot drift apart, and unregistering takes the table with it. The registry
## reads and validates this once, at registration, so a malformed table is
## rejected at a boundary the project can see rather than during a load.
##
## Steps receive **decoded native** dictionaries, not the wire encoding:
## `state["health"] = state["hp"]` is the whole of a rename. They must be pure
## -- no clock, RNG, file access, or live Nodes -- and deterministic.
func schema_migrations() -> Dictionary:
	return {}


func capture_state() -> Dictionary:
	return {}


## Checked before any participant is mutated, so a bad payload is rejected
## while the old session is still intact.
func validate_state(_state: Dictionary) -> Error:
	return OK


func restore_state(_state: Dictionary) -> Error:
	return OK


## Called by new_game, including the new_game that recovers from a failed load.
func reset_state() -> Error:
	return OK
