@tool
class_name RESetBlackboardAction
extends REAction

@export var key: StringName
@export var value: Variant


func has_valid_configuration() -> bool:
	return not key.is_empty()


func execute(context: REActionContext) -> Error:
	if not has_valid_configuration():
		return ERR_INVALID_PARAMETER
	context.blackboard.set_value(key, value)
	return OK
