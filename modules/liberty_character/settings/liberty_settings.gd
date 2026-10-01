class_name LibertySettings
extends RefCounted
## Approved project settings (README "Project Settings") for the components that are built in
## code and so cannot be tuned per scene. Each is read once, right after the component is
## created, as ProjectSettings.get_setting(name, <the component's current value>): an absent
## setting changes nothing, so runtime needs neither the editor plugin nor stored values.

const PREFIX := "liberty_character/"
const DEG := PI / 180.0

const COMPONENT_SCRIPTS := {
	&"coordinator": "res://modules/liberty_character/traversal/liberty_traversal_coordinator.gd",
	&"probe": "res://modules/liberty_character/traversal/liberty_traversal_probe.gd",
	&"solver": "res://modules/liberty_character/traversal/liberty_traversal_solver.gd",
	&"controller": "res://modules/liberty_character/traversal/liberty_traversal_controller.gd",
	&"motor": "res://modules/liberty_character/traversal/liberty_traversal_motor.gd",
	&"ik": "res://modules/liberty_character/traversal/liberty_traversal_ik_modifier.gd",
	&"physical_animation": "res://modules/liberty_character/ragdoll/liberty_physical_animation.gd",
}

## [name after PREFIX, component, property, scale]; property value = setting value * scale.
const DEFINITIONS := [
	["debug/draw_traversal", &"coordinator", &"debug_traversal", 1.0],
	["traversal/probe/forward_reach", &"probe", &"forward_reach", 1.0],
	["traversal/probe/upward_reach", &"probe", &"upward_reach", 1.0],
	["traversal/probe/downward_reach", &"probe", &"downward_reach", 1.0],
	["traversal/probe/hand_spacing", &"probe", &"hand_spacing", 1.0],
	["traversal/probe/foot_spacing", &"probe", &"foot_spacing", 1.0],
	["traversal/probe/hand_height", &"probe", &"hand_height", 1.0],
	["traversal/probe/foot_height", &"probe", &"foot_height", 1.0],
	["traversal/probe/clearance_margin", &"probe", &"clearance_margin", 1.0],
	["traversal/solver/switch_delay", &"solver", &"switch_delay", 1.0],
	["traversal/solver/switch_score_margin", &"solver", &"switch_score_margin", 1.0],
	["traversal/controller/lost_candidate_grace", &"controller", &"lost_candidate_grace", 1.0],
	["traversal/controller/max_catch_speed", &"controller", &"max_catch_speed", 1.0],
	["traversal/controller/max_catch_angle_degrees", &"controller", &"max_catch_angle_degrees", 1.0],
	["traversal/motor/max_position_correction", &"motor", &"max_position_correction", 1.0],
	["traversal/motor/max_angular_correction_degrees", &"motor", &"max_angular_correction", DEG],
	["traversal/motor/shimmy_speed", &"motor", &"shimmy_speed", 1.0],
	["traversal/motor/climb_speed", &"motor", &"climb_speed", 1.0],
	["traversal/ik/blend_seconds", &"ik", &"blend_seconds", 1.0],
	["physical_animation/stiffness", &"physical_animation", &"stiffness", 1.0],
	["physical_animation/damping", &"physical_animation", &"damping", 1.0],
	["physical_animation/max_lead", &"physical_animation", &"max_lead", 1.0],
	["physical_animation/max_torque", &"physical_animation", &"max_torque", 1.0],
	["physical_animation/bone_multipliers", &"physical_animation", &"bone_multipliers", 1.0],
	["physical_animation/hit_strength", &"physical_animation", &"hit_strength", 1.0],
	["physical_animation/hit_recovery_time", &"physical_animation", &"hit_recovery_time", 1.0],
	["physical_animation/fade_out_time", &"physical_animation", &"fade_out_time", 1.0],
	["physical_animation/max_hit_delta_v", &"physical_animation", &"max_hit_delta_v", 1.0],
	["physical_animation/max_angular_speed", &"physical_animation", &"max_angular_speed", 1.0],
	["physical_animation/max_joint_separation", &"physical_animation", &"max_joint_separation", 1.0],
	["physical_animation/max_relative_speed", &"physical_animation", &"max_relative_speed", 1.0],
]


static func setting_name(row: Array) -> String:
	return PREFIX + row[0]


## Converts a property value to the unit the setting stores (degrees for angles).
static func to_setting(row: Array, property_value: Variant) -> Variant:
	if property_value is float:
		return property_value / row[3]
	return property_value


## Applies every stored setting for `component` onto `node`. Absent settings leave the node's
## own value. A bool setting can only enable a flag, so a per-node `true` survives; a Dictionary
## setting merges over the node's entries, so naming one bone keeps the others.
static func apply(component: StringName, node: Object) -> void:
	for row: Array in DEFINITIONS:
		if row[1] != component:
			continue
		var property: StringName = row[2]
		var current: Variant = node.get(property)
		var value: Variant = ProjectSettings.get_setting(setting_name(row), to_setting(row, current))
		match typeof(current):
			TYPE_BOOL:
				node.set(property, current or bool(value))
			TYPE_FLOAT:
				if value is float or value is int:
					node.set(property, float(value) * row[3])
				else:
					push_warning("%s must be a number, got %s" % [setting_name(row), type_string(typeof(value))])
			TYPE_DICTIONARY:
				if value is Dictionary:
					var merged: Dictionary = current.duplicate()
					for key: Variant in value:
						merged[StringName(key)] = float(value[key])
					node.set(property, merged)
				else:
					push_warning("%s must be a Dictionary, got %s" % [setting_name(row), type_string(typeof(value))])
