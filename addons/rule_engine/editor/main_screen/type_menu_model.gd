@tool
extends RefCounted

const CORE_CONDITION_TYPES: Array[Dictionary] = [
	{&"name": &"REAllCondition", &"path": "res://addons/rule_engine/resources/conditions/all.gd"},
	{&"name": &"REAnyCondition", &"path": "res://addons/rule_engine/resources/conditions/any.gd"},
	{&"name": &"RECompareCondition", &"path": "res://addons/rule_engine/resources/conditions/compare.gd"},
	{&"name": &"REExistsCondition", &"path": "res://addons/rule_engine/resources/conditions/exists.gd"},
	{&"name": &"RENotCondition", &"path": "res://addons/rule_engine/resources/conditions/not.gd"},
]
const CORE_ACTION_TYPES: Array[Dictionary] = [
	{&"name": &"REEmitEventAction", &"path": "res://addons/rule_engine/resources/actions/emit_event.gd"},
	{&"name": &"RESetBlackboardAction", &"path": "res://addons/rule_engine/resources/actions/set_blackboard.gd"},
]

var _condition_entries: Array[Dictionary]
var _action_entries: Array[Dictionary]


func _init(condition_types: Array[Dictionary] = [], action_types: Array[Dictionary] = []) -> void:
	_condition_entries = _combine(CORE_CONDITION_TYPES, condition_types)
	_action_entries = _combine(CORE_ACTION_TYPES, action_types)


func get_condition_entries() -> Array[Dictionary]:
	return _condition_entries.duplicate()


func get_action_entries() -> Array[Dictionary]:
	return _action_entries.duplicate()


func _combine(core_types: Array[Dictionary], registry_types: Array[Dictionary]) -> Array[Dictionary]:
	var by_path: Dictionary = {}
	for core: Dictionary in core_types:
		var path: String = core.path
		by_path[path] = {
			&"name": core.name,
			&"path": path,
			&"script": load(path),
			&"enabled": true,
			&"tooltip": "",
		}
	for registry_entry: Dictionary in registry_types:
		var path := String(registry_entry.get(&"path", ""))
		if path.is_empty() or by_path.has(path):
			continue
		var warning := String(registry_entry.get(&"warning", ""))
		by_path[path] = {
			&"name": StringName(registry_entry.get(&"name", &"")),
			&"path": path,
			&"script": registry_entry.get(&"script") as Script,
			&"enabled": bool(registry_entry.get(&"tool", false)) and warning.is_empty(),
			&"tooltip": warning,
		}
	var combined: Array[Dictionary] = []
	for entry: Dictionary in by_path.values():
		combined.append(entry)
	combined.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return String(left.name) < String(right.name)
	)
	return combined
