@tool
extends RefCounted

signal inspect_requested(resource: Resource)
signal selection_changed
signal state_changed
signal issues_changed(issues: Array)
signal issue_activated(rule: RERule, property_path: String)
signal operation_failed(message: String)

var _discovery: Variant
var _commands: Variant
var _validator: Variant
var _selected_book: RERuleBook
var _selected_rule: RERule
var _selected_condition: RECondition
var _selected_condition_path := ""
var _selected_action: REAction
var _selected_action_index := -1
var _issues: Array = []
var _active := true


func _init(discovery: Variant, commands: Variant, validator: Variant) -> void:
	_discovery = discovery
	_commands = commands
	_validator = validator
	if _discovery != null:
		var discovery_changed: Signal = _discovery.changed
		if not discovery_changed.is_connected(_on_discovery_changed):
			discovery_changed.connect(_on_discovery_changed)
	if _commands != null:
		var command_changed: Signal = _commands.changed
		if not command_changed.is_connected(_on_commands_changed):
			command_changed.connect(_on_commands_changed)


func shutdown() -> void:
	if not _active:
		return
	_active = false
	if _discovery != null:
		var discovery_changed: Signal = _discovery.changed
		if discovery_changed.is_connected(_on_discovery_changed):
			discovery_changed.disconnect(_on_discovery_changed)
	if _commands != null:
		var command_changed: Signal = _commands.changed
		if command_changed.is_connected(_on_commands_changed):
			command_changed.disconnect(_on_commands_changed)
	_selected_book = null
	_selected_rule = null
	_clear_detail_selection()
	_issues.clear()
	_discovery = null
	_commands = null
	_validator = null


func stop() -> void:
	shutdown()


func is_shutdown() -> bool:
	return not _active


func get_selected_book() -> RERuleBook:
	return _selected_book


func get_selected_rule() -> RERule:
	return _selected_rule


func get_selected_condition() -> RECondition:
	return _selected_condition


func get_selected_condition_path() -> String:
	return _selected_condition_path


func get_selected_action() -> REAction:
	return _selected_action


func get_selected_action_index() -> int:
	return _selected_action_index


func get_issues() -> Array:
	return _issues.duplicate()


func select_book(book: RERuleBook) -> bool:
	if book == null or not _books().has(book):
		return false
	_selected_book = book
	_selected_rule = null
	_clear_detail_selection()
	selection_changed.emit()
	inspect_requested.emit(book)
	return true


func select_rule(rule: RERule) -> bool:
	var book := _find_book(rule)
	if book == null:
		return false
	_selected_book = book
	_selected_rule = rule
	_clear_detail_selection()
	selection_changed.emit()
	inspect_requested.emit(rule)
	return true


func select_condition(condition: RECondition, property_path: String = "") -> bool:
	if _selected_rule == null or condition == null:
		return false
	if not _condition_contains(_selected_rule.condition, condition, {}):
		return false
	var resolved_path := _find_condition_path(
		_selected_rule.condition,
		condition,
		"condition",
		{},
	)
	if resolved_path.is_empty():
		return false
	if not property_path.is_empty() and property_path != resolved_path:
		return false
	_selected_condition = condition
	_selected_condition_path = resolved_path
	inspect_requested.emit(condition)
	return true


func select_action(index: int) -> bool:
	if _selected_rule == null or index < 0 or index >= _selected_rule.actions.size():
		return false
	var action: REAction = _selected_rule.actions[index]
	if action == null:
		return false
	_selected_action = action
	_selected_action_index = index
	inspect_requested.emit(action)
	return true


func clear_selection() -> void:
	_selected_book = null
	_selected_rule = null
	_clear_detail_selection()
	selection_changed.emit()


func get_default_rules_directory() -> String:
	_reconcile_selection()
	if _selected_book == null or _selected_book.resource_path.is_empty():
		return "res://rules"
	return _selected_book.resource_path.get_base_dir().path_join("rules")


func create_rule(target_path: String, rule_id: StringName) -> RERule:
	_reconcile_selection()
	if _selected_book == null or _commands == null:
		return null
	var created: RERule = _commands.create_rule(_selected_book, target_path, rule_id)
	if created != null:
		select_rule(created)
	else:
		operation_failed.emit("Could not create Rule at '%s'." % target_path)
	return created


func duplicate_selected_rule(target_path: String) -> RERule:
	_reconcile_selection()
	if _selected_book == null or _selected_rule == null or _commands == null:
		return null
	var duplicate: RERule = _commands.duplicate_rule(
		_selected_book,
		_selected_rule,
		target_path,
		_discovered_ids(),
	)
	if duplicate != null:
		select_rule(duplicate)
	else:
		operation_failed.emit("Could not duplicate Rule to '%s'." % target_path)
	return duplicate


func unlink_selected_rule() -> bool:
	_reconcile_selection()
	if _selected_book == null or _selected_rule == null or _commands == null:
		return false
	if not _commands.unlink_rule(_selected_book, _selected_rule):
		return false
	_selected_rule = null
	_clear_detail_selection()
	selection_changed.emit()
	return true


func set_rule_enabled(value: bool) -> bool:
	return _can_mutate_rule() and _commands.set_rule_enabled(_selected_rule, value)


func set_rule_id(value: StringName) -> bool:
	return _can_mutate_rule() and _commands.set_rule_id(_selected_rule, value)


func set_rule_event(value: StringName) -> bool:
	return _can_mutate_rule() and _commands.set_rule_event(_selected_rule, value)


func set_rule_priority(value: int) -> bool:
	return _can_mutate_rule() and _commands.set_rule_priority(_selected_rule, value)


func set_rule_tags(value: PackedStringArray) -> bool:
	return _can_mutate_rule() and _commands.set_rule_tags(_selected_rule, value)


func set_condition(property_path: String, script: Script) -> bool:
	return _can_mutate_rule() and _commands.set_condition(_selected_rule, property_path, script)


func append_condition(composite_path: String, script: Script) -> bool:
	return _can_mutate_rule() and _commands.append_condition(
		_selected_rule,
		composite_path,
		script,
	)


func set_condition_child(parent_path: String, child_index: int, script: Script) -> bool:
	return _can_mutate_rule() and _commands.set_condition_child(
		_selected_rule,
		parent_path,
		child_index,
		script,
	)


func replace_condition(property_path: String, script: Script) -> bool:
	return _can_mutate_rule() and _commands.replace_condition(_selected_rule, property_path, script)


func remove_condition(property_path: String) -> bool:
	return _can_mutate_rule() and _commands.remove_condition(_selected_rule, property_path)


func wrap_condition(property_path: String, script: Script) -> bool:
	return _can_mutate_rule() and _commands.wrap_condition(_selected_rule, property_path, script)


func convert_condition(property_path: String) -> bool:
	return _can_mutate_rule() and _commands.convert_all_any(_selected_rule, property_path)


func add_action(script: Script, index: int = -1) -> bool:
	return _can_mutate_rule() and _commands.add_action(_selected_rule, script, index)


func remove_action(index: int) -> bool:
	return _can_mutate_rule() and _commands.remove_action(_selected_rule, index)


func move_action(from_index: int, to_index: int) -> bool:
	return _can_mutate_rule() and _commands.move_action(_selected_rule, from_index, to_index)


func validate() -> Array:
	_issues = _validator.validate_books(_books()) if _validator != null else []
	issues_changed.emit(_issues.duplicate())
	return _issues.duplicate()


func activate_issue(index: int) -> bool:
	if index < 0 or index >= _issues.size():
		return false
	var issue: Variant = _issues[index]
	if issue.rule == null or not select_rule(issue.rule):
		return false
	issue_activated.emit(issue.rule, issue.property_path)
	return true


func _books() -> Array[RERuleBook]:
	var books: Array[RERuleBook] = []
	if _discovery != null:
		books.assign(_discovery.get_books())
	return books


func _find_book(rule: RERule) -> RERuleBook:
	if rule == null:
		return null
	for book: RERuleBook in _books():
		if book != null and book.rules.has(rule):
			return book
	return null


func _can_mutate_rule() -> bool:
	_reconcile_selection()
	return _commands != null and _selected_rule != null


func _discovered_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	for book: RERuleBook in _books():
		if book == null:
			continue
		for rule: RERule in book.rules:
			if rule != null:
				ids.append(rule.id)
	return ids


func _on_commands_changed() -> void:
	_reconcile_selection()
	state_changed.emit()


func _on_discovery_changed() -> void:
	_reconcile_selection()
	state_changed.emit()


func _reconcile_selection() -> void:
	var selection_was_changed := false
	var books := _books()
	if _selected_book != null and not books.has(_selected_book):
		_selected_book = null
		_selected_rule = null
		_clear_detail_selection()
		selection_was_changed = true
	elif _selected_rule != null and (
		_selected_book == null or not _selected_book.rules.has(_selected_rule)
	):
		_selected_rule = null
		_clear_detail_selection()
		selection_was_changed = true
	elif _selected_rule != null:
		if (
			_selected_condition != null
			and not _condition_contains(_selected_rule.condition, _selected_condition, {})
		):
			_selected_condition = null
			_selected_condition_path = ""
			selection_was_changed = true
		elif _selected_condition != null:
			var current_path := _find_condition_path(
				_selected_rule.condition,
				_selected_condition,
				"condition",
				{},
			)
			if current_path != _selected_condition_path:
				_selected_condition_path = current_path
				selection_was_changed = true
		if _selected_action != null:
			var current_index := _selected_rule.actions.find(_selected_action)
			if current_index < 0:
				_selected_action = null
				_selected_action_index = -1
				selection_was_changed = true
			elif current_index != _selected_action_index:
				_selected_action_index = current_index
				selection_was_changed = true
	if selection_was_changed:
		selection_changed.emit()


func _clear_detail_selection() -> void:
	_selected_condition = null
	_selected_condition_path = ""
	_selected_action = null
	_selected_action_index = -1


func _condition_contains(root: RECondition, target: RECondition, visited: Dictionary) -> bool:
	if root == null:
		return false
	if root == target:
		return true
	var key := root.get_instance_id()
	if visited.has(key):
		return false
	visited[key] = true
	if root is RENotCondition:
		return _condition_contains(root.condition, target, visited)
	if root is REAllCondition or root is REAnyCondition:
		for child: RECondition in root.conditions:
			if _condition_contains(child, target, visited):
				return true
	return false


func _find_condition_path(
	root: RECondition,
	target: RECondition,
	property_path: String,
	visited: Dictionary,
) -> String:
	if root == null:
		return ""
	if root == target:
		return property_path
	var key := root.get_instance_id()
	if visited.has(key):
		return ""
	visited[key] = true
	if root is RENotCondition:
		return _find_condition_path(root.condition, target, property_path + ".condition", visited)
	if root is REAllCondition or root is REAnyCondition:
		for index: int in root.conditions.size():
			var found := _find_condition_path(
				root.conditions[index],
				target,
				property_path + ".conditions[%d]" % index,
				visited,
			)
			if not found.is_empty():
				return found
	return ""
