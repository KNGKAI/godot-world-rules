@tool
extends EditorNode3DGizmoPlugin
## Ragdoll on LibertyCharacter (LibertyRagdoll is a plain Node): body capsules, joint frames,
## cone and hinge limits and the physical-animation drive frames, all at the rest pose.

const Geometry = preload("res://addons/liberty_character_editor/core/liberty_editor_geometry.gd")
const CHARACTER = preload("res://modules/liberty_character/character/liberty_character.gd")
const COLORS := {
	"capsules": Color(1.0, 0.6, 0.2, 0.7),
	"axes": Color(1.0, 0.3, 0.3),
	"limits": Color(1.0, 0.9, 0.3, 0.8),
	"drives": Color(0.8, 0.4, 1.0),
}


func _init() -> void:
	for key: String in COLORS:
		create_material(key, COLORS[key], false, true)


func _get_gizmo_name() -> String:
	return "Liberty Ragdoll Joints"


func _has_gizmo(node: Node3D) -> bool:
	return node.get_script() == CHARACTER and node.has_node("Ragdoll")


func _redraw(gizmo: EditorNode3DGizmo) -> void:
	gizmo.clear()
	var node := gizmo.get_node_3d()
	var skeleton := node.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null or not node.is_inside_tree():
		return
	var segments := Geometry.ragdoll_segments(skeleton, node.global_transform.affine_inverse() * skeleton.global_transform)
	for key: String in segments:
		if not segments[key].is_empty():
			gizmo.add_lines(segments[key], get_material(key, gizmo))
