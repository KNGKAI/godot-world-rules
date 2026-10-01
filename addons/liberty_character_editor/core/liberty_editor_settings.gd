@tool
extends RefCounted
## Editor view of LibertySettings: defaults come from the runtime scripts themselves, and range
## hints from their @export_range where present, so the addon repeats no tuning value.

## Ranges for settings whose runtime property has no range hint. The motor limits stop at the
## AGENT_PLAN correction stop condition (0.45 m, 25 degrees).
const RANGES := {
	"traversal/probe/forward_reach": "0.1,3.0,0.01",
	"traversal/probe/upward_reach": "0.0,3.0,0.01",
	"traversal/probe/downward_reach": "0.0,3.0,0.01",
	"traversal/probe/hand_spacing": "0.05,1.0,0.01",
	"traversal/probe/foot_spacing": "0.05,1.0,0.01",
	"traversal/probe/hand_height": "0.5,2.5,0.01",
	"traversal/probe/foot_height": "0.0,1.0,0.01",
	"traversal/probe/clearance_margin": "0.0,0.2,0.005",
	"traversal/solver/switch_delay": "0.0,1.0,0.01",
	"traversal/solver/switch_score_margin": "0.0,1.0,0.01",
	"traversal/controller/lost_candidate_grace": "0.0,1.0,0.01",
	"traversal/controller/max_catch_speed": "0.0,30.0,0.1",
	"traversal/controller/max_catch_angle_degrees": "0.0,180.0,1.0",
	"traversal/motor/max_position_correction": "0.0,0.45,0.01",
	"traversal/motor/max_angular_correction_degrees": "0.0,25.0,0.5",
	"traversal/motor/shimmy_speed": "0.05,2.0,0.005",
	"traversal/motor/climb_speed": "0.05,2.0,0.005",
	"traversal/ik/blend_seconds": "0.0,1.0,0.01",
}


static func rows(group: String = "") -> Array:
	return LibertySettings.DEFINITIONS.filter(func(row: Array) -> bool: return String(row[0]).begins_with(group))


static func row_for(setting_name: String) -> Array:
	for row: Array in LibertySettings.DEFINITIONS:
		if LibertySettings.setting_name(row) == setting_name:
			return row
	return []


static func _runtime_property(row: Array) -> Dictionary:
	var script: Script = load(LibertySettings.COMPONENT_SCRIPTS[row[1]])
	for property in script.get_script_property_list():
		if property.name == String(row[2]):
			return property
	return {}


## The runtime default, in the setting's unit.
static func default_value(row: Array) -> Variant:
	var script: Script = load(LibertySettings.COMPONENT_SCRIPTS[row[1]])
	var value: Variant = script.get_property_default_value(row[2])
	if value is Dictionary:
		return value.duplicate()
	return LibertySettings.to_setting(row, value)


static func value(row: Array) -> Variant:
	return ProjectSettings.get_setting(LibertySettings.setting_name(row), default_value(row))


static func is_default(row: Array) -> bool:
	var current: Variant = value(row)
	var fallback: Variant = default_value(row)
	if current is float and fallback is float:
		return is_equal_approx(current, fallback)
	return current == fallback


## ProjectSettings.add_property_info() dictionary.
static func property_info(row: Array) -> Dictionary:
	var fallback: Variant = default_value(row)
	var info := {"name": LibertySettings.setting_name(row), "type": typeof(fallback), "hint": PROPERTY_HINT_NONE, "hint_string": ""}
	if fallback is float:
		info.hint = PROPERTY_HINT_RANGE
		var runtime := _runtime_property(row)
		info.hint_string = runtime.hint_string if runtime.get("hint", PROPERTY_HINT_NONE) == PROPERTY_HINT_RANGE else RANGES.get(row[0], "0.0,100.0,0.01,or_greater")
	elif fallback is Dictionary:
		info.hint = PROPERTY_HINT_DICTIONARY_TYPE
		info.hint_string = "%d:;%d:" % [TYPE_STRING_NAME, TYPE_FLOAT]
	return info


## Registers every setting in the editor. Defaults are initial values, so ProjectSettings.save()
## never writes them to project.godot.
static func register_all() -> void:
	for row: Array in LibertySettings.DEFINITIONS:
		var name := LibertySettings.setting_name(row)
		var fallback: Variant = default_value(row)
		if not ProjectSettings.has_setting(name):
			ProjectSettings.set_setting(name, fallback)
		ProjectSettings.set_initial_value(name, fallback)
		ProjectSettings.add_property_info(property_info(row))


## Removes the settings still at their default. Changed values stay, so disabling the plugin
## never changes what the game reads.
static func unregister_defaults() -> void:
	for row: Array in LibertySettings.DEFINITIONS:
		var name := LibertySettings.setting_name(row)
		if ProjectSettings.has_setting(name) and is_default(row):
			ProjectSettings.set_setting(name, null)
