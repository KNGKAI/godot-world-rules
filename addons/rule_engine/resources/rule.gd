@tool
class_name RERule
extends Resource

@export var id: StringName
@export var enabled: bool = true
@export var priority: int = 0
@export var tags: PackedStringArray = []
@export var event: StringName
@export var condition: RECondition
@export var actions: Array[REAction] = []


func is_queryable() -> bool:
	return event.is_empty()


func is_reactive() -> bool:
	return not event.is_empty()

