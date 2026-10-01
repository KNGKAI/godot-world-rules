@tool
extends EditorPlugin
## Liberty Character editor tooling: approved project settings, tuning inspectors and static
## gizmos. Editor-only; runtime code never loads this addon, and disabling it leaves every
## stored setting (and so the game's behaviour) unchanged.

const EditorSettingsView = preload("res://addons/liberty_character_editor/core/liberty_editor_settings.gd")
const INSPECTORS: Array[Script] = [
	preload("res://addons/liberty_character_editor/inspectors/liberty_movement_inspector.gd"),
	preload("res://addons/liberty_character_editor/inspectors/liberty_traversal_inspector.gd"),
	preload("res://addons/liberty_character_editor/inspectors/liberty_physical_animation_inspector.gd"),
]
const GIZMOS: Array[Script] = [
	preload("res://addons/liberty_character_editor/gizmos/liberty_probe_gizmo.gd"),
	preload("res://addons/liberty_character_editor/gizmos/liberty_ik_gizmo.gd"),
	preload("res://addons/liberty_character_editor/gizmos/liberty_ragdoll_gizmo.gd"),
]
const GIZMO_SCRIPTS: Array[String] = [
	"res://modules/liberty_character/character/liberty_character.gd",
	"res://modules/liberty_character/traversal/liberty_traversal_coordinator.gd",
]
const SELFTEST_PATH := "res://addons/liberty_character_editor/tests/liberty_editor_selftest.gd"

var _inspectors: Array[EditorInspectorPlugin] = []
var _gizmos: Array[EditorNode3DGizmoPlugin] = []


func _enter_tree() -> void:
	EditorSettingsView.register_all()
	for script in INSPECTORS:
		var inspector: EditorInspectorPlugin = script.new()
		add_inspector_plugin(inspector)
		_inspectors.append(inspector)
	for script in GIZMOS:
		var gizmo: EditorNode3DGizmoPlugin = script.new()
		add_node_3d_gizmo_plugin(gizmo)
		_gizmos.append(gizmo)
	ProjectSettings.settings_changed.connect(_refresh_gizmos)
	_start_selftest()


func _exit_tree() -> void:
	ProjectSettings.settings_changed.disconnect(_refresh_gizmos)
	for gizmo in _gizmos:
		remove_node_3d_gizmo_plugin(gizmo)
	_gizmos.clear()
	for inspector in _inspectors:
		remove_inspector_plugin(inspector)
	_inspectors.clear()
	EditorSettingsView.unregister_defaults()


## Probe and IK gizmos draw from settings, so redraw them when a setting changes.
func _refresh_gizmos() -> void:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return
	for node in [root] + root.find_children("*", "Node3D", true, false):
		var script: Script = node.get_script()
		if script != null and script.resource_path in GIZMO_SCRIPTS:
			(node as Node3D).update_gizmos()


## Headless harness hook: LIBERTY_EDITOR_SELFTEST=1 runs the in-editor self-test once. The node
## lives on the editor base control so it survives this plugin disabling itself.
func _start_selftest() -> void:
	if OS.get_environment("LIBERTY_EDITOR_SELFTEST") != "1":
		return
	var base := EditorInterface.get_base_control()
	if base.has_node("LibertyEditorSelftest"):
		return
	var selftest: Node = load(SELFTEST_PATH).new()
	selftest.name = "LibertyEditorSelftest"
	base.add_child.call_deferred(selftest)
