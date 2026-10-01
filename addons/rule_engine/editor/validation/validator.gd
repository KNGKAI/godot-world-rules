@tool
extends RefCounted

const ValidationIssue := preload("validation_issue.gd")


func validate_books(books: Array, event_catalog: RENameCatalog = null, fact_catalog: RENameCatalog = null) -> Array:
	var issues: Array = []
	var seen_ids: Dictionary = {}
	var seen_resources: Dictionary = {}
	for book_index: int in books.size():
		var book: RERuleBook = books[book_index]
		if book == null:
			_add_issue(issues, ValidationIssue.Severity.ERROR, &"null_book", "Rule book reference is null.", null, "books[%d]" % book_index)
			continue
		for rule_index: int in book.rules.size():
			var rule: RERule = book.rules[rule_index]
			var path := "books[%d].rules[%d]" % [book_index, rule_index]
			if rule == null:
				_add_issue(issues, ValidationIssue.Severity.ERROR, &"null_rule", "Rule reference is null.", null, path)
				continue
			_validate_rule(rule, path, issues, seen_ids, seen_resources, event_catalog, fact_catalog)
	_validate_event_cycles(books, issues)
	issues.sort_custom(_issue_precedes)
	return issues


func _validate_rule(rule: RERule, path: String, issues: Array, seen_ids: Dictionary, seen_resources: Dictionary, event_catalog: RENameCatalog, fact_catalog: RENameCatalog) -> void:
	var resource_key := rule.get_instance_id()
	if seen_resources.has(resource_key):
		_add_issue(issues, 0, &"duplicate_reference", "Rule Resource is referenced more than once.", rule, path)
	else:
		seen_resources[resource_key] = path
	if rule.id.is_empty():
		_add_issue(issues, 0, &"empty_id", "Rule ID cannot be empty.", rule, path + ".id")
	elif seen_ids.has(rule.id):
		_add_issue(issues, 0, &"duplicate_id", "Rule ID must be unique.", rule, path + ".id")
	else:
		seen_ids[rule.id] = path
	if rule.condition == null:
		_add_issue(issues, 0, &"missing_condition", "Rule must have a condition.", rule, path + ".condition")
	else:
		_validate_condition(rule.condition, issues, rule, path + ".condition", {}, fact_catalog)
	if rule.is_reactive() and rule.actions.is_empty():
		_add_issue(issues, 0, &"missing_actions", "Reactive rule must have an action.", rule, path + ".actions")
	for action_index: int in rule.actions.size():
		var action: REAction = rule.actions[action_index]
		var action_path := path + ".actions[%d]" % action_index
		if action == null:
			_add_issue(issues, 0, &"null_action", "Action reference is null.", rule, action_path)
		elif action is REEmitEventAction and not action.has_valid_configuration():
			_add_issue(issues, 0, &"empty_action_event", "Emitted event cannot be empty.", rule, action_path + ".event")
		elif action is RESetBlackboardAction and not action.has_valid_configuration():
			_add_issue(issues, 0, &"empty_action_key", "Blackboard key cannot be empty.", rule, action_path + ".key")
	if event_catalog != null and rule.is_reactive() and not event_catalog.names.has(rule.event):
		_add_issue(issues, 1, &"unknown_event", "Event '%s' is not present in the supplied catalog." % rule.event, rule, path + ".event")


func _validate_condition(condition: RECondition, issues: Array, rule: RERule, path: String, active: Dictionary, fact_catalog: RENameCatalog) -> void:
	var resource_key := condition.get_instance_id()
	if active.has(resource_key):
		_add_issue(issues, 0, &"condition_cycle", "Condition graph contains a cycle.", rule, path)
		return
	active[resource_key] = true
	if condition is REAllCondition or condition is REAnyCondition:
		if condition.conditions.is_empty():
			_add_issue(issues, 1, &"empty_composite", "Composite condition has no children.", rule, path)
		for index: int in condition.conditions.size():
			var child: RECondition = condition.conditions[index]
			var child_path := path + ".conditions[%d]" % index
			if child == null:
				_add_issue(issues, 0, &"null_condition_child", "Condition child is null.", rule, child_path)
			else:
				_validate_condition(child, issues, rule, child_path, active, fact_catalog)
	elif condition is RENotCondition:
		if condition.condition == null:
			_add_issue(issues, 0, &"null_condition_child", "NOT condition child is null.", rule, path + ".condition")
		else:
			_validate_condition(condition.condition, issues, rule, path + ".condition", active, fact_catalog)
	elif condition is RECompareCondition:
		_validate_compare(condition, issues, rule, path, fact_catalog)
	elif condition is REExistsCondition:
		_validate_exists(condition, issues, rule, path, fact_catalog)
	active.erase(resource_key)


func _validate_compare(condition: RECompareCondition, issues: Array, rule: RERule, path: String, fact_catalog: RENameCatalog) -> void:
	if condition.source < 0 or condition.source > RECompareCondition.Source.BLACKBOARD:
		_add_issue(issues, 0, &"invalid_source", "Comparison source is invalid.", rule, path + ".source")
	if condition.operator < 0 or condition.operator > RECompareCondition.Operator.NOT_CONTAINS:
		_add_issue(issues, 0, &"invalid_operator", "Comparison operator is invalid.", rule, path + ".operator")
	if condition.key.is_empty():
		_add_issue(issues, 0, &"empty_key", "Comparison key cannot be empty.", rule, path + ".key")
	if condition.operator >= RECompareCondition.Operator.GREATER and condition.operator <= RECompareCondition.Operator.LESS_EQUAL and not _is_ordered_value(condition.value):
		_add_issue(issues, 0, &"invalid_compare_value", "Ordered comparison value must be numeric or text.", rule, path + ".value")
	_validate_fact_catalog(condition.source, condition.key, issues, rule, path, fact_catalog)


func _validate_exists(condition: REExistsCondition, issues: Array, rule: RERule, path: String, fact_catalog: RENameCatalog) -> void:
	if condition.source < 0 or condition.source > REExistsCondition.Source.BLACKBOARD:
		_add_issue(issues, 0, &"invalid_source", "Exists source is invalid.", rule, path + ".source")
	if condition.key.is_empty():
		_add_issue(issues, 0, &"empty_key", "Exists key cannot be empty.", rule, path + ".key")
	_validate_fact_catalog(condition.source, condition.key, issues, rule, path, fact_catalog)


func _validate_fact_catalog(source: int, key: StringName, issues: Array, rule: RERule, path: String, fact_catalog: RENameCatalog) -> void:
	if fact_catalog != null and source == REMatchContext.Source.FACT and not key.is_empty() and not fact_catalog.names.has(key):
		_add_issue(issues, 1, &"unknown_fact", "Fact '%s' is not present in the supplied catalog." % key, rule, path + ".key")


func _validate_event_cycles(books: Array, issues: Array) -> void:
	var edges: Array = []
	var adjacency: Dictionary = {}
	for book_index: int in books.size():
		var book: RERuleBook = books[book_index]
		if book == null:
			continue
		for rule_index: int in book.rules.size():
			var rule: RERule = book.rules[rule_index]
			if rule == null or not rule.is_reactive():
				continue
			for action_index: int in rule.actions.size():
				var action: REAction = rule.actions[action_index]
				if action is REEmitEventAction and action.has_valid_configuration():
					edges.append({&"from": rule.event, &"to": action.event, &"rule": rule, &"path": "books[%d].rules[%d].actions[%d]" % [book_index, rule_index, action_index]})
					if not adjacency.has(rule.event):
						adjacency[rule.event] = []
					adjacency[rule.event].append(action.event)
	for edge: Dictionary in edges:
		if _event_reaches(edge.to, edge.from, adjacency):
			_add_issue(issues, ValidationIssue.Severity.WARNING, &"potential_event_cycle", "Emitted event can re-trigger this reactive event.", edge.rule, edge.path + ".event")


func _event_reaches(start: StringName, target: StringName, adjacency: Dictionary) -> bool:
	var pending: Array[StringName] = [start]
	var visited: Dictionary = {}
	while not pending.is_empty():
		var current: StringName = pending.pop_back()
		if current == target:
			return true
		if visited.has(current):
			continue
		visited[current] = true
		for next_event: StringName in adjacency.get(current, []):
			pending.append(next_event)
	return false


func _is_ordered_value(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_STRING_NAME]


func _add_issue(issues: Array, severity: int, code: StringName, message: String, rule: RERule, property_path: String) -> void:
	issues.append(ValidationIssue.new(severity, code, message, rule, property_path))


func _issue_precedes(left: Variant, right: Variant) -> bool:
	if left.severity != right.severity:
		return left.severity < right.severity
	if left.rule_id != right.rule_id:
		return String(left.rule_id) < String(right.rule_id)
	if left.property_path != right.property_path:
		return left.property_path < right.property_path
	return String(left.code) < String(right.code)
