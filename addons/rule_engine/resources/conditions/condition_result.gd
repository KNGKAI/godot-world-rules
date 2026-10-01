class_name REConditionResult
extends RefCounted

var matched: bool
var valid: bool


func _init(p_matched: bool = false, p_valid: bool = true) -> void:
	matched = p_matched
	valid = p_valid

