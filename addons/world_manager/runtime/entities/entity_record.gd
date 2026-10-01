class_name EntityRecord
extends RefCounted
## Copied entity snapshot. Holds no Node and no manager back-pointer.


var id: StringName = &""
var world_id: StringName = &""
var policy: WorldPersistencePolicy.Kind = WorldPersistencePolicy.Kind.SAVE_GAME
var removed: bool = false
var parent_kind: WorldEntityParent.Kind = WorldEntityParent.Kind.WORLD_ROOT
var parent_id: StringName = &""
var components: Dictionary = {}
## AUTHORED with an empty archetype_id, or DYNAMIC with a valid one -- the
## invariant both wire sides enforce, on tombstones too. The default keeps an
## authored record behaving exactly as it did before the field existed.
var origin: WorldEntityOrigin.Kind = WorldEntityOrigin.Kind.AUTHORED
var archetype_id: StringName = &""


func duplicate_record() -> EntityRecord:
	var copy := EntityRecord.new()
	copy.id = id
	copy.world_id = world_id
	copy.policy = policy
	copy.removed = removed
	copy.parent_kind = parent_kind
	copy.parent_id = parent_id
	copy.origin = origin
	copy.archetype_id = archetype_id
	copy.components = {}
	for component_id: Variant in components.keys():
		copy.components[component_id] = WorldValue.clone_validated(components[component_id])
	return copy
