class_name WorldEvents
extends RefCounted
## World lifecycle and infrastructure events.


## Operation contexts are detached snapshots. Treat them as read-only; listeners
## in one emission still receive the same signal argument instance.
signal world_loading(context: Dictionary)
signal world_loaded(context: Dictionary, entry: WorldEntryPointData)
signal world_unloading(context: Dictionary)
signal world_unloaded(context: Dictionary)
signal world_load_failed(reason: Error, context: Dictionary)
signal world_unload_failed(reason: Error, context: Dictionary)
## Registry and state notifications intentionally retain compact signatures;
## enclosing operation traces provide their association with coordinated work.
signal entity_registered(id: StringName, world_id: StringName)
signal entity_unregistered(id: StringName, world_id: StringName)
signal state_changed(key: StringName, previous: Variant, current: Variant, exists: bool)
signal state_restored()
## Accepted deferred commands emit one started and exactly one terminal signal.
## Synchronous rejection emits none. Failure reasons are separate from context.
signal new_game_started(context: Dictionary)
signal new_game_completed(context: Dictionary)
signal new_game_failed(reason: Error, context: Dictionary)
signal save_started(context: Dictionary)
signal save_completed(context: Dictionary)
signal save_failed(reason: Error, context: Dictionary)
signal load_started(context: Dictionary)
signal load_completed(context: Dictionary)
signal load_failed(reason: Error, context: Dictionary)
signal transition_started(context: Dictionary)
signal transition_completed(context: Dictionary)
signal transition_failed(reason: Error, context: Dictionary)
signal entity_spawn_started(context: Dictionary)
## The generated id arrives here: it is reserved after the started event, so
## entity_spawn_started deliberately carries no entity_id.
signal entity_spawned(id: StringName, world_id: StringName, context: Dictionary)
signal entity_spawn_failed(reason: Error, context: Dictionary)
signal entity_remove_started(context: Dictionary)
## Every requested id this call actually changed -- newly written tombstones
## plus freed live actors. A request of only already-tombstoned ids succeeds
## with an empty list.
signal entities_removed(ids: Array, context: Dictionary)
signal entity_remove_failed(reason: Error, context: Dictionary)
