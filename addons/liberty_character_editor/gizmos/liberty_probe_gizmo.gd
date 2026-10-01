@tool
extends EditorNode3DGizmoPlugin
## Traversal probe on LibertyTraversalCoordinator: forward ray fan, ledge ray, reach window,
## capsule and the hand/foot hold template against a nominal wall at forward_reach. Live
## candidates only exist in the running game (LibertyTraversalDebug overlay).

const Geometry = preload("res://addons/liberty_character_editor/core/liberty_editor_geometry.gd")
const EditorSettingsView = preload("res://addons/liberty_character_editor/core/liberty_editor_settings.gd")
const COORDINATOR = preload("res://modules/liberty_character/traversal/liberty_traversal_coordinator.gd")
const PROBE_PATH := "res://modules/liberty_character/traversal/liberty_traversal_probe.gd"
const COLORS := {
	"rays": Color(0.35, 0.95, 0.45),
	"ledge": Color(1.0, 0.8, 0.2),
	"holds": Color(0.25, 0.8, 1.0),
	"reach": Color(0.7, 0.7, 0.7, 0.5),
	"capsule": Color(0.9, 0.9, 0.9, 0.35),
}


func _init() -> void:
	for key: String in COLORS:
		create_material(key, COLORS[key], false, true)


func _get_gizmo_name() -> String:
	return "Liberty Traversal Probe"


func _has_gizmo(node: Node3D) -> bool:
	return node.get_script() == COORDINATOR


## Probe values in effect: approved settings, plus the probe's own capsule defaults.
static func probe_values() -> Dictionary:
	var values := {}
	for row: Array in EditorSettingsView.rows("traversal/probe/"):
		values[String(row[2])] = EditorSettingsView.value(row)
	var probe: Script = load(PROBE_PATH)
	for name in ["capsule_radius", "capsule_height"]:
		values[name] = probe.get_property_default_value(name)
	return values


func _redraw(gizmo: EditorNode3DGizmo) -> void:
	gizmo.clear()
	var node := gizmo.get_node_3d()
	var segments := Geometry.probe_segments(probe_values(), node.transform.affine_inverse())
	for key: String in segments:
		gizmo.add_lines(segments[key], get_material(key, gizmo))
