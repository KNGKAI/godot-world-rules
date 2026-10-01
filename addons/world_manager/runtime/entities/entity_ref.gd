class_name EntityRef
extends Resource
## Authored ID handle. Stores no Node. Treat loaded .tres files as immutable.


@export var id: StringName = &""


func _init(value: StringName = &"") -> void:
	id = value


func resolve(entities: WorldEntityManager) -> Node:
	if entities == null:
		return null
	return entities.resolve(id)
