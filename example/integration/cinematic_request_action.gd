@tool
class_name CinematicRequestAction
extends REAction
## Asks the example coordinator to play one sequence. It does not name errand keys, World, or the director.

const EVENT := &"cinematic_requested"

@export var sequence_id: StringName


func has_valid_configuration() -> bool:
	return not sequence_id.is_empty()


func execute(context: REActionContext) -> Error:
	if sequence_id.is_empty():
		return ERR_INVALID_PARAMETER
	context.emit_event(EVENT, {&"sequence_id": sequence_id})
	return OK
