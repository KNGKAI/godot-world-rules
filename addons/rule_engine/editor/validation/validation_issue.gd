@tool
extends RefCounted

enum Severity { ERROR, WARNING, INFO }

var severity: Severity
var code: StringName
var message: String
var rule: RERule
var rule_id: StringName
var property_path: String


func _init(
	p_severity: Severity = Severity.ERROR,
	p_code: StringName = &"",
	p_message: String = "",
	p_rule: RERule = null,
	p_property_path: String = "",
) -> void:
	severity = p_severity
	code = p_code
	message = p_message
	rule = p_rule
	rule_id = rule.id if rule != null else &""
	property_path = p_property_path


func _to_string() -> String:
	return "%s [%s] %s: %s" % [
		["ERROR", "WARNING", "INFO"][severity],
		code,
		property_path,
		message,
	]
