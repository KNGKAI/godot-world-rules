@tool
class_name REEmitEventAction
extends REAction

@export var event: StringName
@export var payload: Dictionary = {}


func has_valid_configuration() -> bool:
	return not event.is_empty()


func execute(context: REActionContext) -> Error:
	if not has_valid_configuration():
		return ERR_INVALID_PARAMETER
	context.emit_event(event, payload)
	return OK
