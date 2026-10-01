class_name REActionContext
extends RefCounted

var event: RERuleEvent:
	get:
		return RERuleEvent.new(_event_name, _payload)
var payload: Dictionary:
	get:
		return _payload
var blackboard: REBlackboard:
	get:
		return _blackboard

var _event_name: StringName
var _payload: Dictionary
var _blackboard: REBlackboard
var _engine: Variant


func _init(
	p_event: RERuleEvent = null,
	p_blackboard: REBlackboard = null,
	p_engine: Variant = null,
) -> void:
	_event_name = p_event.name if p_event != null else &""
	_payload = REMatchContext.freeze_dictionary(p_event.payload if p_event != null else {})
	_blackboard = p_blackboard
	_engine = p_engine


func emit_event(name: StringName, p_payload: Dictionary = {}) -> void:
	if _engine != null:
		_engine.emit_event(name, p_payload)
