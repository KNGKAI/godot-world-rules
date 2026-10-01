class_name RERuleEvent
extends RefCounted

var name: StringName:
	get:
		return _name
var payload: Dictionary:
	get:
		return _payload

var _name: StringName
var _payload: Dictionary

func _init(p_name: StringName = &"", p_payload: Dictionary = {}) -> void:
	_name = p_name
	_payload = p_payload
