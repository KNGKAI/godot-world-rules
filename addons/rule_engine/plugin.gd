@tool
extends EditorPlugin

const AUTOLOAD_NAME := "Rules"
const AUTOLOAD_PATH := "res://addons/rule_engine/runtime/rules.gd"
const INSPECTOR_PLUGIN_PATH := "res://addons/rule_engine/editor/inspector/rule_inspector_plugin.gd"
const EXPORT_PLUGIN_PATH := "res://addons/rule_engine/editor/export_plugin.gd"
const TYPE_REGISTRY_PATH := "res://addons/rule_engine/editor/registry/type_registry.gd"
const DISCOVERY_PATH := "res://addons/rule_engine/editor/main_screen/rule_book_discovery.gd"
const FILTER_PATH := "res://addons/rule_engine/editor/main_screen/rule_filter.gd"
const MENU_MODEL_PATH := "res://addons/rule_engine/editor/main_screen/type_menu_model.gd"
const CONTROLLER_PATH := "res://addons/rule_engine/editor/main_screen/workspace_controller.gd"
const COMMAND_SERVICE_PATH := "res://addons/rule_engine/editor/rule_command_service.gd"
const VALIDATOR_PATH := "res://addons/rule_engine/editor/validation/validator.gd"
const WORKSPACE_SCENE := preload("res://addons/rule_engine/editor/main_screen/workspace.tscn")

var _inspector_plugin: EditorInspectorPlugin
var _export_plugin: EditorExportPlugin
var _condition_types: Array[Dictionary] = []
var _action_types: Array[Dictionary] = []
var _workspace: Control
var _discovery: Variant
var _controller: Variant
var _commands: Variant


func _enter_tree() -> void:
	if _inspector_plugin == null:
		_refresh_extension_registry()
		_inspector_plugin = load(INSPECTOR_PLUGIN_PATH).new()
		add_inspector_plugin(_inspector_plugin)
	if _export_plugin == null:
		_export_plugin = load(EXPORT_PLUGIN_PATH).new()
		add_export_plugin(_export_plugin)
	if _workspace == null:
		_create_workspace()


func _exit_tree() -> void:
	_destroy_workspace()
	if _export_plugin != null:
		remove_export_plugin(_export_plugin)
		_export_plugin = null
	if _inspector_plugin != null:
		remove_inspector_plugin(_inspector_plugin)
		_inspector_plugin = null
	_condition_types.clear()
	_action_types.clear()


func _has_main_screen() -> bool:
	return true


func _get_plugin_name() -> String:
	return "Rules"


func _make_visible(visible: bool) -> void:
	if _workspace != null:
		_workspace.visible = visible


func get_rules_workspace() -> Control:
	return _workspace


func get_rules_command_service() -> Variant:
	return _commands


func _enable_plugin() -> void:
	if not ProjectSettings.has_setting("autoload/%s" % AUTOLOAD_NAME):
		add_autoload_singleton(AUTOLOAD_NAME, AUTOLOAD_PATH)


func _disable_plugin() -> void:
	var setting := "autoload/%s" % AUTOLOAD_NAME
	if not ProjectSettings.has_setting(setting):
		return
	if _autoload_points_to_runtime(String(ProjectSettings.get_setting(setting))):
		remove_autoload_singleton(AUTOLOAD_NAME)


func _autoload_points_to_runtime(configured_value: String) -> bool:
	var configured_path := configured_value.trim_prefix("*")
	if configured_path == AUTOLOAD_PATH:
		return true
	if configured_path.begins_with("uid://"):
		var resource_id := ResourceUID.text_to_id(configured_path)
		return ResourceUID.get_id_path(resource_id) == AUTOLOAD_PATH
	return false


func get_discovered_conditions() -> Array[Dictionary]:
	return _condition_types.duplicate()


func get_discovered_actions() -> Array[Dictionary]:
	return _action_types.duplicate()


func _refresh_extension_registry() -> void:
	var registry: Variant = load(TYPE_REGISTRY_PATH).new()
	_condition_types = registry.discover(&"RECondition")
	_action_types = registry.discover(&"REAction")
	for entry: Dictionary in _condition_types + _action_types:
		if not entry.warning.is_empty():
			push_warning(entry.warning)


func _create_workspace() -> void:
	var editor_interface := get_editor_interface()
	_commands = load(COMMAND_SERVICE_PATH).new(
		get_undo_redo(),
		_persist_resource,
	)
	_discovery = load(DISCOVERY_PATH).new(editor_interface.get_resource_filesystem())
	_controller = load(CONTROLLER_PATH).new(
		_discovery,
		_commands,
		load(VALIDATOR_PATH).new(),
	)
	_workspace = WORKSPACE_SCENE.instantiate()
	_workspace.call(
		"setup",
		_controller,
		_discovery,
		load(FILTER_PATH).new(),
		load(MENU_MODEL_PATH).new(_condition_types, _action_types),
		editor_interface,
	)
	editor_interface.get_editor_main_screen().add_child(_workspace)
	_workspace.visible = false
	_discovery.start()


func _destroy_workspace() -> void:
	if _workspace != null:
		_workspace.call("shutdown")
	if _controller != null:
		_controller.shutdown()
	if _discovery != null:
		_discovery.stop()
	if _commands != null:
		_commands.shutdown()
	if _workspace != null:
		var parent := _workspace.get_parent()
		if parent != null:
			parent.remove_child(_workspace)
		_workspace.free()
	_workspace = null
	_controller = null
	_discovery = null
	_commands = null


func _persist_resource(resource: Resource) -> void:
	if resource == null or resource.resource_path.is_empty():
		return
	ResourceSaver.save(resource, resource.resource_path)
	get_editor_interface().get_resource_filesystem().update_file(resource.resource_path)
