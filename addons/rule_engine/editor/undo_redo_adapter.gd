@tool
extends RefCounted

var _manager: Variant


func _init(manager: Variant) -> void:
	_manager = manager


func shutdown() -> void:
	_manager = null


func is_shutdown() -> bool:
	return _manager == null


func create_action(action_name: String) -> void:
	_manager.create_action(action_name)


func add_do_method(object: Object, method_name: StringName, arguments: Array) -> void:
	_add_method(&"add_do_method", object, method_name, arguments)


func add_undo_method(object: Object, method_name: StringName, arguments: Array) -> void:
	_add_method(&"add_undo_method", object, method_name, arguments)


func commit_action() -> void:
	_manager.commit_action()


func _add_method(registration_method: StringName, object: Object, method_name: StringName, arguments: Array) -> void:
	if _manager is UndoRedo:
		_manager.call(registration_method, Callable(object, method_name).bindv(arguments))
		return
	_manager.callv(registration_method, [object, method_name] + arguments)
