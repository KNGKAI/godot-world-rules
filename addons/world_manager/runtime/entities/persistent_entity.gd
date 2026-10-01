class_name PersistentEntity
extends Node
## Direct child of an actor. Registers on tree entry; identity is the ID, not the path.


@export var persistent_id: StringName = &"":
	set(value):
		if _registration_id != &"":
			return
		persistent_id = value
@export var persistence_policy: WorldPersistencePolicy.Kind = WorldPersistencePolicy.Kind.SAVE_GAME:
	set(value):
		if _registration_id != &"":
			return
		persistence_policy = value

var _registration_id: StringName = &""
var _origin: WorldEntityOrigin.Kind = WorldEntityOrigin.Kind.AUTHORED
var _archetype_id: StringName = &""
var _actor: Node = null
var _world_id: StringName = &""


func registration_id() -> StringName:
	return _registration_id


func origin() -> WorldEntityOrigin.Kind:
	return _origin


func archetype_id() -> StringName:
	return _archetype_id


## Addon-internal seam: spawn and dynamic reconstruction stamp this before the
## instance enters any tree, latched like persistent_id. Deliberately not
## @export -- an authored scene must not be able to claim it is dynamic, and a
## save must never be able to name a scene. While an entity is loaded the node
## is the authority for this, not the record table: deriving it from a lookup
## would demote a dynamic actor to authored on any recapture into a world whose
## table had just been replaced.
func _mark_dynamic(archetype: StringName) -> void:
	if _registration_id != &"":
		return
	_origin = WorldEntityOrigin.Kind.DYNAMIC
	_archetype_id = archetype


func registered_actor() -> Node:
	return _actor


func registered_world_id() -> StringName:
	return _world_id


func _enter_tree() -> void:
	var world := _world_node()
	if world == null or not world.has_method("is_initialized") or not world.is_initialized():
		WorldDiagnostics.reject(&"register_entity", ERR_UNCONFIGURED, _reject_context())
		return
	var manager: Variant = world.get("entities")
	if manager == null or not (manager is WorldEntityManager):
		WorldDiagnostics.reject(&"register_entity", ERR_UNCONFIGURED, _reject_context())
		return
	var entities := manager as WorldEntityManager
	var err: Error = entities.register_component(self)
	if err != OK:
		return
	_registration_id = persistent_id
	_actor = get_parent()
	_world_id = entities.world_id_for_node(_actor)


func _exit_tree() -> void:
	var world := _world_node()
	var manager: Variant = null
	if world != null:
		manager = world.get("entities")
	if manager != null and manager is WorldEntityManager:
		(manager as WorldEntityManager).unregister_component(self)
	_registration_id = &""
	_actor = null
	_world_id = &""


func _world_node() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	return tree.root.get_node_or_null("World")


func _reject_context() -> Dictionary:
	var context: Dictionary = {}
	if String(persistent_id) != "":
		context["entity_id"] = persistent_id
	return context
