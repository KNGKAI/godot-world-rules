class_name WorldOperationGuard
extends RefCounted
## Private single-flight guard. Does not log; callers at public boundaries do.
##
## Also owns the recovery-required state. It belongs here because try_begin is
## already the one chokepoint every guarded public mutation passes through, and
## every subsystem already holds the guard, so one check blocks them all.


## The only operation accepted while recovery is required. Owned paths
## (restore_owned, clear_owned, unload_active_owned) deliberately bypass the
## guard entirely, which is how new_game is able to recover.
const RECOVERY_OPERATIONS: Array[StringName] = [&"new_game"]

var _busy: bool = false
var _operation_id: int = 0
var _next_id: int = 1
var _operation: StringName = &""
var _recovery_required: bool = false
var _recovery_context: Dictionary = {}


func try_begin(operation: StringName) -> Error:
	if _busy:
		return ERR_BUSY
	if _recovery_required and not RECOVERY_OPERATIONS.has(operation):
		return ERR_UNAVAILABLE
	_operation = operation
	_operation_id = _next_id
	_next_id += 1
	_busy = true
	return OK


func get_operation_id() -> int:
	return _operation_id


func get_operation() -> StringName:
	if not _busy:
		return &""
	return _operation


func is_busy() -> bool:
	return _busy


func finish(operation_id: int) -> void:
	if not _busy:
		return
	if operation_id != _operation_id:
		return
	_busy = false
	_operation = &""


func is_recovery_required() -> bool:
	return _recovery_required


func recovery_context() -> Dictionary:
	return _recovery_context.duplicate(true)


## Set before finish(), so a mutation attempted from a terminal-event listener
## is already rejected.
func enter_recovery(context: Dictionary) -> void:
	_recovery_required = true
	_recovery_context = context.duplicate(true)


func clear_recovery() -> void:
	_recovery_required = false
	_recovery_context.clear()
