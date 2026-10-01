@tool
extends EditorInspectorPlugin
## LibertyRagdoll: physical-animation tuning (a runtime-built stage) as project settings, the
## hit-recovery strength curve, and the read-only ragdoll body table.

const SettingsPanel = preload("res://addons/liberty_character_editor/inspectors/liberty_settings_panel.gd")
const EditorSettingsView = preload("res://addons/liberty_character_editor/core/liberty_editor_settings.gd")
const RAGDOLL = preload("res://modules/liberty_character/ragdoll/liberty_ragdoll.gd")
const JOINT_NAMES := {
	PhysicalBone3D.JOINT_TYPE_NONE: "root",
	PhysicalBone3D.JOINT_TYPE_CONE: "cone",
	PhysicalBone3D.JOINT_TYPE_HINGE: "hinge",
}


func _can_handle(object: Object) -> bool:
	return object is Node and object.get_script() == RAGDOLL


func _parse_begin(_object: Object) -> void:
	var box := VBoxContainer.new()
	box.name = "LibertyPhysicalAnimationSettings"
	var panel := SettingsPanel.new()
	panel.build("Physical animation tuning", [["physical_animation/", "Tracking, hit reaction and safety"]])
	box.add_child(panel)
	box.add_child(_curve_label())
	var curve := StrengthCurve.new()
	curve.custom_minimum_size = Vector2(0, 70)
	box.add_child(curve)
	box.add_child(_body_table())
	add_custom_control(box)


func _curve_label() -> Label:
	var label := Label.new()
	label.text = "Hit chain strength after a non-fatal hit"
	label.modulate = Color(0.7, 0.85, 1.0)
	return label


func _body_table() -> Control:
	var box := VBoxContainer.new()
	var heading := Label.new()
	heading.text = "Ragdoll bodies (LibertyRagdoll.BONE_LAYOUT, read-only)"
	heading.modulate = Color(0.7, 0.85, 1.0)
	box.add_child(heading)
	var grid := GridContainer.new()
	grid.columns = 4
	for text in ["Bone", "Mass", "Joint", "Limits (°)"]:
		var label := Label.new()
		label.text = text
		label.modulate = Color(1, 1, 1, 0.65)
		grid.add_child(label)
	for bone: StringName in LibertyRagdoll.BONE_LAYOUT:
		var layout: Array = LibertyRagdoll.BONE_LAYOUT[bone]
		var limits: Array = layout[4]
		var limit_text := ""
		match layout[1]:
			PhysicalBone3D.JOINT_TYPE_CONE: limit_text = "swing %d, twist %d" % [limits[0], limits[1]]
			PhysicalBone3D.JOINT_TYPE_HINGE: limit_text = "%d … %d" % [limits[0], limits[1]]
		for text in [String(bone), "%.1f kg" % layout[0], JOINT_NAMES[layout[1]], limit_text]:
			var label := Label.new()
			label.text = text
			grid.add_child(label)
	box.add_child(grid)
	return box


## Plots LibertyPhysicalAnimation.strength_at() for the current hit_strength and recovery time.
class StrengthCurve extends Control:
	const EditorSettingsView = preload("res://addons/liberty_character_editor/core/liberty_editor_settings.gd")

	func _ready() -> void:
		ProjectSettings.settings_changed.connect(queue_redraw)

	func _exit_tree() -> void:
		if ProjectSettings.settings_changed.is_connected(queue_redraw):
			ProjectSettings.settings_changed.disconnect(queue_redraw)

	func _setting(name: String) -> float:
		return EditorSettingsView.value(EditorSettingsView.row_for("liberty_character/physical_animation/" + name))

	func _draw() -> void:
		var start := _setting("hit_strength")
		var recovery := _setting("hit_recovery_time")
		var span := maxf(recovery * 1.25, 0.01)
		var rect := Rect2(Vector2(4, 4), size - Vector2(8, 18))
		draw_rect(rect, Color(1, 1, 1, 0.08))
		var points := PackedVector2Array()
		for step in 49:
			var t := span * step / 48.0
			var strength := LibertyPhysicalAnimation.strength_at(t, start, recovery)
			points.append(rect.position + Vector2(rect.size.x * t / span, rect.size.y * (1.0 - strength)))
		draw_polyline(points, Color(0.4, 0.8, 1.0), 2.0)
		var font := get_theme_default_font()
		draw_string(font, Vector2(4, size.y - 2), "%.2f → 1.0 over %.2f s" % [start, recovery], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.7))
