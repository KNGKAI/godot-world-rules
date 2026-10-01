extends Node

signal event_received(event: RERuleEvent)
signal rule_evaluated(rule: RERule, passed: bool)
signal rule_fired(rule: RERule)
signal action_executed(rule: RERule, action: REAction)
signal dispatch_failed(reason: StringName, processed_events: int)

var max_events_per_dispatch: int:
	get:
		return _engine.max_events_per_dispatch
	set(value):
		_engine.max_events_per_dispatch = value

var max_chain_depth: int:
	get:
		return _engine.max_chain_depth
	set(value):
		_engine.max_chain_depth = value

var _engine := RERuleEngine.new()


func _init() -> void:
	_engine.event_received.connect(event_received.emit)
	_engine.rule_evaluated.connect(rule_evaluated.emit)
	_engine.rule_fired.connect(rule_fired.emit)
	_engine.action_executed.connect(action_executed.emit)
	_engine.dispatch_failed.connect(dispatch_failed.emit)


func load_book(book: RERuleBook) -> Error:
	return _engine.load_book(book)


func unload_book(book: RERuleBook) -> void:
	_engine.unload_book(book)


func emit_event(name: StringName, payload: Dictionary = {}) -> void:
	_engine.emit_event(name, payload)


func check(rule_id: StringName, payload: Dictionary = {}) -> bool:
	return _engine.check(rule_id, payload)


func get_rule(rule_id: StringName) -> RERule:
	return _engine.get_rule(rule_id)


func set_fact_provider(provider: REFactProvider) -> void:
	_engine.set_fact_provider(provider)


func set_rule_enabled(rule_id: StringName, enabled: bool) -> Error:
	return _engine.set_rule_enabled(rule_id, enabled)


func clear_rule_enabled_override(rule_id: StringName) -> void:
	_engine.clear_rule_enabled_override(rule_id)


func get_blackboard() -> REBlackboard:
	return _engine.get_blackboard()
