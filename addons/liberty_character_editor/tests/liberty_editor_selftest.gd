@tool
extends Node
## In-editor self-test, started by the plugin when LIBERTY_EDITOR_SELFTEST=1:
##   LIBERTY_EDITOR_SELFTEST=1 godot --headless --editor --path . --quit-after 6000
## Prints LIBERTY_EDITOR_SELFTEST PASS or FAIL lines and quits with 0 or 1. The harness also
## greps the log for engine errors.

const EditorSettingsView = preload("res://addons/liberty_character_editor/core/liberty_editor_settings.gd")
const PLUGIN := "liberty_character_editor"
const CHARACTER_SCENE := "res://modules/liberty_character/character/liberty_character.tscn"

var _failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		print("LIBERTY_EDITOR_SELFTEST FAIL: ", message)


func _frames(count: int) -> void:
	for _frame in count:
		await get_tree().process_frame


func _all_registered() -> bool:
	for row: Array in LibertySettings.DEFINITIONS:
		if not ProjectSettings.has_setting(LibertySettings.setting_name(row)) or not EditorSettingsView.is_default(row):
			return false
	return true


func _none_registered() -> bool:
	for row: Array in LibertySettings.DEFINITIONS:
		if ProjectSettings.has_setting(LibertySettings.setting_name(row)):
			return false
	return true


func _run() -> void:
	await _frames(10)
	# Quitting during the first filesystem scan aborts it with a warning; let it finish.
	while EditorInterface.get_resource_filesystem().is_scanning():
		await _frames(1)
	_expect(EditorInterface.is_plugin_enabled(PLUGIN), "plugin enabled from project.godot")
	_expect(_all_registered(), "settings registered at their defaults")
	EditorInterface.set_plugin_enabled(PLUGIN, false)
	await _frames(10)
	_expect(not EditorInterface.is_plugin_enabled(PLUGIN), "plugin disables")
	_expect(_none_registered(), "disabling removes default-valued settings")
	EditorInterface.set_plugin_enabled(PLUGIN, true)
	await _frames(10)
	_expect(EditorInterface.is_plugin_enabled(PLUGIN), "plugin re-enables")
	_expect(_all_registered(), "re-enabling registers settings again")
	await _check_inspectors()
	await _check_gizmos()
	ProjectSettings.save()
	var project := FileAccess.get_file_as_string("res://project.godot")
	_expect(not project.contains("[liberty_character]"), "saving writes no default setting values")
	print("LIBERTY_EDITOR_SELFTEST %s (%d failures)" % ["PASS" if _failures.is_empty() else "FAIL", _failures.size()])
	get_tree().quit(0 if _failures.is_empty() else 1)


func _inspector_control(name: String) -> Node:
	return EditorInterface.get_inspector().find_child(name, true, false)


func _check_inspectors() -> void:
	EditorInterface.open_scene_from_path(CHARACTER_SCENE)
	await _frames(20)
	var open_root := EditorInterface.get_edited_scene_root()
	if open_root != null:
		print("LIBERTY_EDITOR_SELFTEST info: gizmos on a scene left open across re-enable: ", _gizmo_names(open_root) + _gizmo_names(open_root.get_node("Traversal")))
	# Reopen so the nodes enter the tree with this plugin instance's gizmos.
	EditorInterface.close_scene()
	await _frames(10)
	EditorInterface.open_scene_from_path(CHARACTER_SCENE)
	await _frames(20)
	var root := EditorInterface.get_edited_scene_root()
	_expect(root != null and root.scene_file_path == CHARACTER_SCENE, "character scene opens")
	if root == null:
		return
	EditorInterface.edit_node(root)
	await _frames(10)
	var metrics := _inspector_control("LibertyMovementMetrics")
	_expect(metrics != null, "movement metrics shown for LibertyCharacter")
	if metrics != null:
		_expect(is_equal_approx(snappedf(metrics.summary.run.stop, 0.001), 2.042), "metrics use the character's exports")
	EditorInterface.edit_node(root.get_node("Traversal"))
	await _frames(10)
	var traversal := _inspector_control("LibertyTraversalSettings")
	_expect(traversal != null, "traversal settings shown for the coordinator")
	if traversal != null:
		# An edit is undoable and leaves project.godot clean once undone.
		var name := "liberty_character/traversal/probe/forward_reach"
		traversal.set_setting_value(name, 1.1)
		_expect(is_equal_approx(ProjectSettings.get_setting(name), 1.1), "inspector edit sets the setting")
		_expect(FileAccess.get_file_as_string("res://project.godot").contains("traversal/probe/forward_reach=1.1"), "inspector edit is saved")
		EditorInterface.get_editor_undo_redo().get_history_undo_redo(EditorUndoRedoManager.GLOBAL_HISTORY).undo()
		await _frames(2)
		_expect(is_equal_approx(ProjectSettings.get_setting(name), 0.9), "undo restores the default")
		_expect(not FileAccess.get_file_as_string("res://project.godot").contains("[liberty_character]"), "undo leaves no stored value")
	EditorInterface.edit_node(root.get_node("Ragdoll"))
	await _frames(10)
	_expect(_inspector_control("LibertyPhysicalAnimationSettings") != null, "physical animation settings shown for the ragdoll")


func _gizmo_names(node: Node3D) -> Array[String]:
	var names: Array[String] = []
	for gizmo in node.get_gizmos():
		var plugin: EditorNode3DGizmoPlugin = (gizmo as EditorNode3DGizmo).get_plugin() if gizmo is EditorNode3DGizmo else null
		# Built-in plugins have no script and do not expose _get_gizmo_name() to GDScript.
		if plugin != null and plugin.get_script() != null:
			names.append(plugin._get_gizmo_name())
	return names


func _check_gizmos() -> void:
	var root := EditorInterface.get_edited_scene_root() as Node3D
	if root == null:
		return
	var on_character := _gizmo_names(root)
	var on_traversal := _gizmo_names(root.get_node("Traversal") as Node3D)
	print("LIBERTY_EDITOR_SELFTEST gizmos: character ", on_character, " traversal ", on_traversal)
	_expect("Liberty Ragdoll Joints" in on_character, "ragdoll gizmo on the character")
	_expect("Liberty Traversal Probe" in on_traversal, "probe gizmo on the traversal node")
	_expect("Liberty IK Targets" in on_traversal, "IK gizmo on the traversal node")
