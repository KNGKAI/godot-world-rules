@tool
class_name WorldDiagnostics
extends RefCounted
## Internal helper for one public-command rejection diagnostic.
## Editor registration uses this script, so it is @tool with no Node lifecycle.


static func reject(operation: StringName, reason: Error, context: Dictionary) -> Error:
	var message := "WorldManager[%s] code=%d" % [String(operation), reason as int]
	var ordered: Dictionary = {}
	for key: Variant in context.keys():
		ordered[str(key)] = context[key]
	var names: Array = ordered.keys()
	names.sort()
	for key_text: Variant in names:
		message += " %s=%s" % [str(key_text), str(ordered[key_text])]
	push_error(message)
	return reason
