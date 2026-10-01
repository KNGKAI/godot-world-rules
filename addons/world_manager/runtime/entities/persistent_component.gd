class_name PersistentComponent
extends Node
## Project or addon component under PersistentEntity. Mutates only its actor.


@export var component_id: StringName = &""


func capture_state() -> Dictionary:
	return {}


func validate_state(_state: Dictionary) -> Error:
	return OK


func restore_state(_state: Dictionary) -> Error:
	return OK


func actor() -> Node:
	var pe := get_parent()
	if pe == null:
		return null
	return pe.get_parent()
