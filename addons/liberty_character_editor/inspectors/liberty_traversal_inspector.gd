@tool
extends EditorInspectorPlugin
## LibertyTraversalCoordinator: its probe, solver, controller, motor and IK are built at runtime,
## so their tuning is edited here as project settings.

const SettingsPanel = preload("res://addons/liberty_character_editor/inspectors/liberty_settings_panel.gd")
const COORDINATOR = preload("res://modules/liberty_character/traversal/liberty_traversal_coordinator.gd")
const GROUPS := [
	["debug/", "Debug"],
	["traversal/probe/", "Probe"],
	["traversal/solver/", "Solver"],
	["traversal/controller/", "Controller"],
	["traversal/motor/", "Motor (correction capped at 0.45 m / 25°)"],
	["traversal/ik/", "IK"],
]


func _can_handle(object: Object) -> bool:
	return object is Node and object.get_script() == COORDINATOR


func _parse_begin(_object: Object) -> void:
	var panel := SettingsPanel.new()
	panel.name = "LibertyTraversalSettings"
	panel.build("Traversal tuning", GROUPS)
	add_custom_control(panel)
