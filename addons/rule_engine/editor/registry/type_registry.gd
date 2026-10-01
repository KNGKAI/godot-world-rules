@tool
extends RefCounted

var _entries_override: Array


func _init(entries_override: Array = []) -> void:
	_entries_override = entries_override


func discover(base_name: StringName) -> Array[Dictionary]:
	var entries: Array = (
		_entries_override
		if not _entries_override.is_empty()
		else ProjectSettings.get_global_class_list()
	)
	var by_name: Dictionary = {}
	for entry: Dictionary in entries:
		by_name[StringName(entry.get(&"class", &""))] = entry
	var discovered: Array[Dictionary] = []
	for entry: Dictionary in entries:
		var class_name_value := StringName(entry.get(&"class", &""))
		if class_name_value.is_empty() or class_name_value == base_name:
			continue
		if StringName(entry.get(&"language", &"GDScript")) != &"GDScript":
			continue
		if not _inherits_from(entry, base_name, by_name):
			continue
		var path := String(entry.get(&"path", ""))
		var script: Script = load(path)
		if script == null:
			continue
		var is_tool_script := script.is_tool()
		discovered.append({
			&"name": class_name_value,
			&"path": path,
			&"script": script,
			&"tool": is_tool_script,
			&"warning": "" if is_tool_script else "%s must declare @tool." % class_name_value,
		})
	discovered.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return String(left.name) < String(right.name)
	)
	return discovered


func _inherits_from(entry: Dictionary, target: StringName, by_name: Dictionary) -> bool:
	var current := StringName(entry.get(&"base", &""))
	var visited: Dictionary = {}
	while not current.is_empty():
		if current == target:
			return true
		if visited.has(current) or not by_name.has(current):
			return false
		visited[current] = true
		current = StringName(by_name[current].get(&"base", &""))
	return false

