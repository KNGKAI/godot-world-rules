@tool
extends EditorNode3DGizmoPlugin
## Traversal IK on LibertyTraversalCoordinator: rest-pose arm and leg chains, the runtime pole
## placement, and a line from each end bone to its nominal hold from the probe template.

const Geometry = preload("res://addons/liberty_character_editor/core/liberty_editor_geometry.gd")
const ProbeGizmo = preload("res://addons/liberty_character_editor/gizmos/liberty_probe_gizmo.gd")
const COORDINATOR = preload("res://modules/liberty_character/traversal/liberty_traversal_coordinator.gd")
const HOLDS := {&"LeftHand": "left_hand", &"RightHand": "right_hand", &"LeftFoot": "left_foot", &"RightFoot": "right_foot"}
const COLORS := {
	"chains": Color(0.3, 1.0, 0.9),
	"poles": Color(1.0, 0.45, 0.85),
	"reach": Color(0.25, 0.8, 1.0, 0.6),
}


func _init() -> void:
	for key: String in COLORS:
		create_material(key, COLORS[key], false, true)


func _get_gizmo_name() -> String:
	return "Liberty IK Targets"


func _has_gizmo(node: Node3D) -> bool:
	return node.get_script() == COORDINATOR


func _redraw(gizmo: EditorNode3DGizmo) -> void:
	gizmo.clear()
	var node := gizmo.get_node_3d()
	var character := node.get_parent() as Node3D
	var skeleton := character.find_child("Skeleton3D", true, false) as Skeleton3D if character != null else null
	if skeleton == null or not node.is_inside_tree():
		return
	var to_node := node.global_transform.affine_inverse() * skeleton.global_transform
	var layout := Geometry.probe_layout(ProbeGizmo.probe_values())
	var from_character := node.transform.affine_inverse()
	var targets := {}
	for bone: StringName in HOLDS:
		targets[bone] = from_character * (layout[HOLDS[bone]] as Vector3)
	var segments := Geometry.ik_segments(skeleton, to_node, targets)
	for key: String in segments:
		if not segments[key].is_empty():
			gizmo.add_lines(segments[key], get_material(key, gizmo))
