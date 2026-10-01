@tool
extends RefCounted

signal changed

const CONDITION_BASE_SCRIPT := preload("res://addons/rule_engine/resources/conditions/condition.gd")
const ACTION_BASE_SCRIPT := preload("res://addons/rule_engine/resources/actions/action.gd")
const UNDO_REDO_ADAPTER_SCRIPT := preload("res://addons/rule_engine/editor/undo_redo_adapter.gd")

var _undo_redo: Variant
var _persist_changed: Callable
var _active := true


func _init(undo_redo: Variant, persist_changed: Callable) -> void:
	_undo_redo = UNDO_REDO_ADAPTER_SCRIPT.new(undo_redo)
	_persist_changed = persist_changed


func shutdown() -> void:
	if not _active:
		return
	_active = false
	_persist_changed = Callable()
	if _undo_redo != null:
		_undo_redo.shutdown()
	_undo_redo = null


func is_shutdown() -> bool:
	return not _active


func add_rule(book: RERuleBook, rule: RERule) -> bool:
	if book == null or rule == null or book.rules.has(rule):
		return false
	return _commit(
		"Add Rule",
		_insert_rule.bind(book, book.rules.size(), rule),
		_remove_rule.bind(book, rule),
		[book],
	)


func unlink_rule(book: RERuleBook, rule: RERule) -> bool:
	if book == null or rule == null:
		return false
	var index := book.rules.find(rule)
	if index < 0:
		return false
	return _commit(
		"Unlink Rule",
		_remove_rule.bind(book, rule),
		_insert_rule.bind(book, index, rule),
		[book],
	)


func create_rule(book: RERuleBook, target_path: String, rule_id: StringName) -> RERule:
	if (
		book == null
		or _undo_redo == null
		or not _is_available_tres_path(target_path)
		or not _ensure_parent_directory(target_path)
	):
		return null
	var rule := RERule.new()
	rule.id = rule_id
	if ResourceSaver.save(rule, target_path, ResourceSaver.FLAG_CHANGE_PATH) != OK:
		return null
	rule.take_over_path(target_path)
	if not _commit(
		"Create Rule",
		_insert_rule.bind(book, book.rules.size(), rule),
		_remove_rule.bind(book, rule),
		[rule, book],
	):
		return null
	return rule


func duplicate_rule(
	book: RERuleBook,
	source: RERule,
	target_path: String,
	discovered_ids: PackedStringArray,
) -> RERule:
	if (
		book == null
		or source == null
		or not book.rules.has(source)
		or _undo_redo == null
		or not _is_available_tres_path(target_path)
		or not _ensure_parent_directory(target_path)
	):
		return null
	var copied_rule := source.duplicate_deep(Resource.DEEP_DUPLICATE_ALL) as RERule
	if copied_rule == null:
		return null
	copied_rule.id = _unique_copy_id(source.id, book, discovered_ids)
	for meta_name: StringName in source.get_meta_list():
		copied_rule.set_meta(meta_name, source.get_meta(meta_name))
	if ResourceSaver.save(copied_rule, target_path, ResourceSaver.FLAG_CHANGE_PATH) != OK:
		return null
	copied_rule.take_over_path(target_path)
	if not _commit(
		"Duplicate Rule",
		_insert_rule.bind(book, book.rules.size(), copied_rule),
		_remove_rule.bind(book, copied_rule),
		[copied_rule, book],
	):
		return null
	return copied_rule


func _is_available_tres_path(target_path: String) -> bool:
	return (
		target_path.get_extension().to_lower() == "tres"
		and (target_path.begins_with("res://") or target_path.begins_with("user://"))
		and not FileAccess.file_exists(ProjectSettings.globalize_path(target_path))
	)


func _ensure_parent_directory(target_path: String) -> bool:
	var absolute_directory := ProjectSettings.globalize_path(target_path.get_base_dir())
	if DirAccess.dir_exists_absolute(absolute_directory):
		return true
	return DirAccess.make_dir_recursive_absolute(absolute_directory) == OK


func _unique_copy_id(source_id: StringName, book: RERuleBook, discovered_ids: PackedStringArray) -> StringName:
	var used: Dictionary = {}
	for discovered_id: String in discovered_ids:
		used[StringName(discovered_id)] = true
	for rule: RERule in book.rules:
		if rule != null:
			used[rule.id] = true
	var base := "%s_copy" % source_id
	var candidate := StringName(base)
	var suffix := 2
	while used.has(candidate):
		candidate = StringName("%s_%d" % [base, suffix])
		suffix += 1
	return candidate


func set_rule_id(rule: RERule, value: StringName) -> bool:
	return _set_rule_property("Set Rule ID", rule, &"id", value)


func set_rule_event(rule: RERule, value: StringName) -> bool:
	return _set_rule_property("Set Rule Event", rule, &"event", value)


func set_rule_priority(rule: RERule, value: int) -> bool:
	return _set_rule_property("Set Rule Priority", rule, &"priority", value)


func set_rule_enabled(rule: RERule, value: bool) -> bool:
	return _set_rule_property("Set Rule Enabled", rule, &"enabled", value)


func set_rule_tags(rule: RERule, value: PackedStringArray) -> bool:
	return _set_rule_property("Set Rule Tags", rule, &"tags", value.duplicate())


func set_condition(rule: RERule, property_path: String, script: Script) -> bool:
	var condition := _instantiate_condition(script)
	if condition == null:
		return false
	return _commit_condition_replacement("Set Condition", rule, property_path, condition, false)


func replace_condition(rule: RERule, property_path: String, script: Script) -> bool:
	var condition := _instantiate_condition(script)
	if condition == null:
		return false
	return _commit_condition_replacement("Replace Condition", rule, property_path, condition, true)


func remove_condition(rule: RERule, property_path: String) -> bool:
	return _commit_condition_replacement("Remove Condition", rule, property_path, null, true)


func append_condition(rule: RERule, composite_path: String, script: Script) -> bool:
	var condition := _instantiate_condition(script)
	var location := _resolve_condition_location(rule, composite_path)
	if condition == null or location.is_empty():
		return false
	var composite: RECondition = _condition_at(location)
	if not (composite is REAllCondition or composite is REAnyCondition):
		return false
	var old_conditions: Array[RECondition] = composite.conditions.duplicate()
	var new_conditions: Array[RECondition] = old_conditions.duplicate()
	new_conditions.append(condition)
	return _commit(
		"Append Condition Child",
		_set_composite_conditions.bind(composite, new_conditions),
		_set_composite_conditions.bind(composite, old_conditions),
		[rule],
	)


func set_condition_child(
	rule: RERule,
	parent_path: String,
	child_index: int,
	script: Script,
) -> bool:
	var condition := _instantiate_condition(script)
	var parent_location := _resolve_condition_location(rule, parent_path)
	if condition == null or parent_location.is_empty():
		return false
	var parent: RECondition = _condition_at(parent_location)
	var child_location: Dictionary
	if parent is RENotCondition:
		if child_index != -1 or parent.condition != null:
			return false
		child_location = {&"owner": parent, &"property": &"condition", &"index": -1}
	elif parent is REAllCondition or parent is REAnyCondition:
		if (
			child_index < 0
			or child_index >= parent.conditions.size()
			or parent.conditions[child_index] != null
		):
			return false
		child_location = {&"owner": parent, &"property": &"conditions", &"index": child_index}
	else:
		return false
	return _commit(
		"Set Condition Child",
		_set_condition_location.bind(child_location, condition),
		_set_condition_location.bind(child_location, null),
		[rule],
	)


func wrap_condition(rule: RERule, property_path: String, wrapper_script: Script) -> bool:
	var wrapper := _instantiate_condition(wrapper_script)
	if wrapper == null or not (wrapper is RENotCondition or wrapper is REAllCondition or wrapper is REAnyCondition):
		return false
	var location := _resolve_condition_location(rule, property_path)
	if location.is_empty():
		return false
	var old_condition: RECondition = _condition_at(location)
	if old_condition == null:
		return false
	if wrapper is RENotCondition:
		(wrapper as RENotCondition).condition = old_condition
	else:
		wrapper.set(&"conditions", [old_condition])
	return _commit(
		"Wrap Condition",
		_set_condition_location.bind(location, wrapper),
		_set_condition_location.bind(location, old_condition),
		[rule],
	)


func convert_all_any(rule: RERule, property_path: String) -> bool:
	var location := _resolve_condition_location(rule, property_path)
	if location.is_empty():
		return false
	var old_condition: RECondition = _condition_at(location)
	var converted: RECondition
	if old_condition is REAllCondition:
		var any := REAnyCondition.new()
		any.conditions = (old_condition as REAllCondition).conditions.duplicate()
		converted = any
	elif old_condition is REAnyCondition:
		var all := REAllCondition.new()
		all.conditions = (old_condition as REAnyCondition).conditions.duplicate()
		converted = all
	else:
		return false
	return _commit(
		"Convert All/Any Condition",
		_set_condition_location.bind(location, converted),
		_set_condition_location.bind(location, old_condition),
		[rule],
	)


func add_action(rule: RERule, action_script: Script, index: int = -1) -> bool:
	if rule == null:
		return false
	var action := _instantiate_action(action_script)
	if action == null:
		return false
	var insertion_index := rule.actions.size() if index == -1 else index
	if insertion_index < 0 or insertion_index > rule.actions.size():
		return false
	var old_actions := rule.actions.duplicate()
	var new_actions := rule.actions.duplicate()
	new_actions.insert(insertion_index, action)
	return _commit(
		"Add Rule Action",
		_set_actions.bind(rule, new_actions),
		_set_actions.bind(rule, old_actions),
		[rule],
	)


func remove_action(rule: RERule, index: int) -> bool:
	if rule == null or index < 0 or index >= rule.actions.size():
		return false
	var old_actions := rule.actions.duplicate()
	var new_actions := rule.actions.duplicate()
	new_actions.remove_at(index)
	return _commit(
		"Remove Rule Action",
		_set_actions.bind(rule, new_actions),
		_set_actions.bind(rule, old_actions),
		[rule],
	)


func move_action(rule: RERule, from_index: int, to_index: int) -> bool:
	if (
		rule == null
		or from_index < 0
		or from_index >= rule.actions.size()
		or to_index < 0
		or to_index >= rule.actions.size()
		or from_index == to_index
	):
		return false
	var old_actions := rule.actions.duplicate()
	var new_actions := rule.actions.duplicate()
	var action: REAction = new_actions.pop_at(from_index)
	new_actions.insert(to_index, action)
	return _commit(
		"Reorder Rule Action",
		_set_actions.bind(rule, new_actions),
		_set_actions.bind(rule, old_actions),
		[rule],
	)


func _instantiate_action(script: Script) -> REAction:
	if not _script_derives_from(script, ACTION_BASE_SCRIPT):
		return null
	var instance: Variant = script.new()
	return instance as REAction


func _set_actions(rule: RERule, actions: Array[REAction]) -> void:
	rule.actions = actions.duplicate()


func _commit_condition_replacement(
	action_name: String,
	rule: RERule,
	property_path: String,
	condition: RECondition,
	require_existing: bool,
) -> bool:
	var location := _resolve_condition_location(rule, property_path)
	if location.is_empty():
		return false
	var old_condition: RECondition = _condition_at(location)
	if require_existing and old_condition == null:
		return false
	if old_condition == condition:
		return false
	return _commit(
		action_name,
		_set_condition_location.bind(location, condition),
		_set_condition_location.bind(location, old_condition),
		[rule],
	)


func _instantiate_condition(script: Script) -> RECondition:
	if not _script_derives_from(script, CONDITION_BASE_SCRIPT):
		return null
	var instance: Variant = script.new()
	return instance as RECondition


func _script_derives_from(script: Script, expected_base: Script) -> bool:
	if script == null or not script.is_tool() or not script.can_instantiate():
		return false
	var current: Script = script
	while current != null:
		if current == expected_base:
			return true
		current = current.get_base_script()
	return false


func _resolve_condition_location(rule: RERule, property_path: String) -> Dictionary:
	if rule == null or (property_path != "condition" and not property_path.begins_with("condition.")):
		return {}
	var parts := property_path.split(".", true)
	for part: String in parts:
		if part.is_empty():
			return {}
	var current: Object = rule
	for part_index: int in range(parts.size() - 1):
		var next := _condition_segment(current, parts[part_index])
		if next == null:
			return {}
		current = next
	var final_part := parts[parts.size() - 1]
	if final_part == "condition" and (current is RERule or current is RENotCondition):
		return {&"owner": current, &"property": &"condition", &"index": -1}
	if final_part.begins_with("conditions[") and final_part.ends_with("]") and (current is REAllCondition or current is REAnyCondition):
		var index_text := final_part.trim_prefix("conditions[").trim_suffix("]")
		if not index_text.is_valid_int():
			return {}
		var index := index_text.to_int()
		var conditions: Array = current.get(&"conditions")
		if index < 0 or index >= conditions.size():
			return {}
		return {&"owner": current, &"property": &"conditions", &"index": index}
	return {}


func _condition_segment(current: Object, segment: String) -> RECondition:
	if segment == "condition" and (current is RERule or current is RENotCondition):
		return current.get(&"condition") as RECondition
	if segment.begins_with("conditions[") and segment.ends_with("]") and (current is REAllCondition or current is REAnyCondition):
		var index_text := segment.trim_prefix("conditions[").trim_suffix("]")
		if not index_text.is_valid_int():
			return null
		var index := index_text.to_int()
		var conditions: Array = current.get(&"conditions")
		if index < 0 or index >= conditions.size():
			return null
		return conditions[index] as RECondition
	return null


func _condition_at(location: Dictionary) -> RECondition:
	var owner: Object = location.owner
	var index: int = location.index
	if index < 0:
		return owner.get(location.property) as RECondition
	var conditions: Array = owner.get(location.property)
	return conditions[index] as RECondition


func _set_condition_location(location: Dictionary, value: RECondition) -> void:
	var owner: Object = location.owner
	var property: StringName = location.property
	var index: int = location.index
	if index < 0:
		owner.set(property, value)
		return
	var conditions: Array = owner.get(property)
	conditions[index] = value
	owner.set(property, conditions)


func _set_composite_conditions(composite: RECondition, conditions: Array[RECondition]) -> void:
	composite.set(&"conditions", conditions.duplicate())


func _set_rule_property(action_name: String, rule: RERule, property: StringName, value: Variant) -> bool:
	if rule == null:
		return false
	var old_value: Variant = rule.get(property)
	if old_value == value:
		return false
	return _commit(
		action_name,
		_set_property.bind(rule, property, value),
		_set_property.bind(rule, property, old_value),
		[rule],
	)


func _commit(action_name: String, do_operation: Callable, undo_operation: Callable, resources: Array) -> bool:
	if not _active or _undo_redo == null or not do_operation.is_valid() or not undo_operation.is_valid():
		return false
	_undo_redo.create_action(action_name)
	_undo_redo.add_do_method(self, &"_execute", [do_operation, resources])
	_undo_redo.add_undo_method(self, &"_execute", [undo_operation, resources])
	_undo_redo.commit_action()
	return true


func _execute(operation: Callable, resources: Array) -> void:
	if not _active:
		return
	operation.call()
	for resource: Resource in resources:
		if resource == null:
			continue
		resource.emit_changed()
		if _persist_changed.is_valid():
			_persist_changed.call(resource)
	changed.emit()


func _insert_rule(book: RERuleBook, index: int, rule: RERule) -> void:
	book.rules.insert(index, rule)


func _remove_rule(book: RERuleBook, rule: RERule) -> void:
	book.rules.erase(rule)


func _set_property(object: Object, property: StringName, value: Variant) -> void:
	object.set(property, value)
