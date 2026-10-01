class_name RERuleEngine
extends RefCounted

signal event_received(event: RERuleEvent)
signal rule_evaluated(rule: RERule, passed: bool)
signal rule_fired(rule: RERule)
signal action_executed(rule: RERule, action: REAction)
signal dispatch_failed(reason: StringName, processed_events: int)

class QueuedEvent extends RefCounted:
	var event: RERuleEvent
	var depth: int

	func _init(p_event: RERuleEvent, p_depth: int) -> void:
		event = p_event
		depth = p_depth

var max_events_per_dispatch: int = 1000:
	set(value):
		max_events_per_dispatch = maxi(1, value)

var max_chain_depth: int = 64:
	set(value):
		max_chain_depth = maxi(1, value)

var _books: Dictionary = {}
var _rules_by_id: Dictionary = {}
var _event_index: Dictionary = {}
var _enabled_overrides: Dictionary = {}
var _queue: Array[QueuedEvent] = []
var _draining: bool = false
var _processing_event: bool = false
var _current_depth: int = 0
var _blackboard := REBlackboard.new()
var _fact_provider: REFactProvider = REFactProvider.new()


func load_book(book: RERuleBook) -> Error:
	if book == null:
		return ERR_INVALID_PARAMETER
	var book_key := book.get_instance_id()
	if _books.has(book_key):
		return OK
	var validation := _validate_incoming_book(book)
	if validation != OK:
		return validation
	var owned_ids: Array[StringName] = []
	for rule: RERule in book.rules:
		_rules_by_id[rule.id] = rule
		owned_ids.append(rule.id)
		if rule.is_reactive():
			if not _event_index.has(rule.event):
				_event_index[rule.event] = []
			_event_index[rule.event].append(rule)
	_books[book_key] = {&"book": book, &"ids": owned_ids}
	return OK


func unload_book(book: RERuleBook) -> void:
	if book == null:
		return
	var book_key := book.get_instance_id()
	if not _books.has(book_key):
		return
	var entry: Dictionary = _books[book_key]
	for id: StringName in entry.ids:
		var rule: RERule = _rules_by_id.get(id)
		if rule != null and rule.is_reactive() and _event_index.has(rule.event):
			var candidates: Array = _event_index[rule.event]
			candidates.erase(rule)
			if candidates.is_empty():
				_event_index.erase(rule.event)
		_rules_by_id.erase(id)
		_enabled_overrides.erase(id)
	_books.erase(book_key)


func emit_event(name: StringName, payload: Dictionary = {}) -> void:
	if name.is_empty():
		push_error("Rule event name cannot be empty.")
		return
	var normalized := REMatchContext.normalize_payload(payload)
	if not normalized.valid:
		push_error("Rule event payload keys must be String or StringName values.")
		return
	var depth := _current_depth + 1 if _processing_event else 0
	_queue.append(QueuedEvent.new(RERuleEvent.new(name, normalized.value), depth))
	if not _draining:
		_drain_queue()


func check(rule_id: StringName, payload: Dictionary = {}) -> bool:
	var rule: RERule = _rules_by_id.get(rule_id)
	if rule == null or rule.is_reactive() or not _is_effectively_enabled(rule):
		return false
	var normalized := REMatchContext.normalize_payload(payload)
	if not normalized.valid:
		return false
	var context := REMatchContext.new(normalized.value, _blackboard.snapshot(), _fact_provider)
	var result := rule.condition.evaluate(context)
	var passed := result.valid and result.matched
	rule_evaluated.emit(rule, passed)
	return passed


func get_rule(rule_id: StringName) -> RERule:
	return _rules_by_id.get(rule_id)


func set_fact_provider(provider: REFactProvider) -> void:
	_fact_provider = provider if provider != null else REFactProvider.new()


func set_rule_enabled(rule_id: StringName, enabled: bool) -> Error:
	if not _rules_by_id.has(rule_id):
		return ERR_DOES_NOT_EXIST
	_enabled_overrides[rule_id] = enabled
	return OK


func clear_rule_enabled_override(rule_id: StringName) -> void:
	_enabled_overrides.erase(rule_id)


func get_blackboard() -> REBlackboard:
	return _blackboard


func _validate_incoming_book(book: RERuleBook) -> Error:
	var seen_ids: Dictionary = {}
	var seen_resources: Dictionary = {}
	for rule: RERule in book.rules:
		if rule == null or rule.id.is_empty() or rule.condition == null:
			return ERR_INVALID_DATA
		var resource_key := rule.get_instance_id()
		if seen_resources.has(resource_key):
			return ERR_INVALID_DATA
		seen_resources[resource_key] = true
		if seen_ids.has(rule.id) or _rules_by_id.has(rule.id):
			return ERR_ALREADY_EXISTS
		seen_ids[rule.id] = true
		if rule.is_reactive() and rule.actions.is_empty():
			return ERR_INVALID_DATA
		if not _condition_tree_is_valid(rule.condition, {}):
			return ERR_INVALID_DATA
		for action: REAction in rule.actions:
			if action == null or not _action_has_valid_configuration(action):
				return ERR_INVALID_DATA
	return OK


func _action_has_valid_configuration(action: REAction) -> bool:
	if action is REEmitEventAction:
		return action.has_valid_configuration()
	if action is RESetBlackboardAction:
		return action.has_valid_configuration()
	return true


func _condition_tree_is_valid(condition: RECondition, active: Dictionary) -> bool:
	var resource_key := condition.get_instance_id()
	if active.has(resource_key):
		return false
	active[resource_key] = true
	var valid := true
	if condition is REAllCondition or condition is REAnyCondition:
		for child: RECondition in condition.conditions:
			if child == null or not _condition_tree_is_valid(child, active):
				valid = false
				break
	elif condition is RENotCondition:
		valid = (
			condition.condition != null
			and _condition_tree_is_valid(condition.condition, active)
		)
	elif condition is RECompareCondition:
		valid = (
			condition.source >= RECompareCondition.Source.FACT
			and condition.source <= RECompareCondition.Source.BLACKBOARD
			and condition.operator >= RECompareCondition.Operator.EQUAL
			and condition.operator <= RECompareCondition.Operator.NOT_CONTAINS
			and not condition.key.is_empty()
		)
		if (
			valid
			and condition.operator >= RECompareCondition.Operator.GREATER
			and condition.operator <= RECompareCondition.Operator.LESS_EQUAL
		):
			valid = typeof(condition.value) in [
				TYPE_INT,
				TYPE_FLOAT,
				TYPE_STRING,
				TYPE_STRING_NAME,
			]
	elif condition is REExistsCondition:
		valid = (
			condition.source >= REExistsCondition.Source.FACT
			and condition.source <= REExistsCondition.Source.BLACKBOARD
			and not condition.key.is_empty()
		)
	active.erase(resource_key)
	return valid


func _is_effectively_enabled(rule: RERule) -> bool:
	return _enabled_overrides.get(rule.id, rule.enabled)


func _drain_queue() -> void:
	_draining = true
	var processed_count := 0
	var last_event: StringName
	var failure_reason: StringName
	var failed_event: QueuedEvent
	while not _queue.is_empty():
		if processed_count == max_events_per_dispatch:
			failure_reason = &"event_limit"
			_queue.clear()
			break
		var queued_event: QueuedEvent = _queue.pop_front()
		if queued_event.depth > max_chain_depth:
			failure_reason = &"chain_depth"
			failed_event = queued_event
			_queue.clear()
			break
		processed_count += 1
		last_event = queued_event.event.name
		failure_reason = _process_event(queued_event.event, queued_event.depth)
		if not failure_reason.is_empty():
			_queue.clear()
			break
	_draining = false
	_processing_event = false
	_current_depth = 0
	if failure_reason.is_empty():
		return
	dispatch_failed.emit(failure_reason, processed_count)
	if failure_reason == &"chain_depth":
		push_error(
			"Rule event chain depth %d exceeds maximum %d for event '%s'." %
			[failed_event.depth, max_chain_depth, failed_event.event.name]
		)
	elif failure_reason == &"event_limit":
		push_error(
			"Rule event limit reached after %d events; last event was '%s'." %
			[processed_count, last_event]
		)
	else:
		push_error("Rule action failed after %d processed events." % processed_count)


func _process_event(event: RERuleEvent, depth: int) -> StringName:
	_processing_event = true
	_current_depth = depth
	event_received.emit(event)
	var candidates: Array = _event_index.get(event.name, []).duplicate()
	candidates.sort_custom(_rule_precedes)
	var context := REMatchContext.new(event.payload, _blackboard.snapshot(), _fact_provider)
	var passing: Array[RERule] = []
	for rule: RERule in candidates:
		if not _is_effectively_enabled(rule):
			continue
		var result := rule.condition.evaluate(context)
		var passed := result.valid and result.matched
		rule_evaluated.emit(rule, passed)
		if passed:
			passing.append(rule)
	for rule: RERule in passing:
		for action: REAction in rule.actions:
			var action_context := REActionContext.new(event, _blackboard, self)
			var error := action.execute(action_context)
			if error != OK:
				_processing_event = false
				_current_depth = 0
				return &"action_failed"
			action_executed.emit(rule, action)
		rule_fired.emit(rule)
	_processing_event = false
	_current_depth = 0
	return &""


func _rule_precedes(left: RERule, right: RERule) -> bool:
	if left.priority != right.priority:
		return left.priority > right.priority
	return String(left.id) < String(right.id)
