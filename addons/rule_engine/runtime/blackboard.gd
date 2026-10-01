class_name REBlackboard
extends RefCounted

var _values: Dictionary = {}


func has_value(key: StringName) -> bool:
	return _values.has(key)


func get_value(key: StringName, default: Variant = null) -> Variant:
	return _values.get(key, default)


func set_value(key: StringName, value: Variant) -> void:
	_values[key] = REMatchContext.duplicate_mutable_value(value)


func erase_value(key: StringName) -> bool:
	return _values.erase(key)


func clear() -> void:
	_values.clear()


func snapshot() -> Dictionary:
	return REMatchContext.freeze_dictionary(_values)
