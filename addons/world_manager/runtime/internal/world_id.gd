class_name WorldId
extends RefCounted
## Shared ID syntax for worlds and entry points. Does not log.


const MAX_LENGTH := 128
const _PATTERN := "^[A-Za-z0-9][A-Za-z0-9_.:-]*$"


static func validate(id: StringName) -> Error:
	var text := String(id)
	if text.is_empty():
		return ERR_INVALID_PARAMETER
	if text.length() > MAX_LENGTH:
		return ERR_INVALID_PARAMETER
	var regex := RegEx.create_from_string(_PATTERN)
	if regex.search(text) == null:
		return ERR_INVALID_PARAMETER
	return OK
