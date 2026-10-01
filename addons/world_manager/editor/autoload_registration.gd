@tool
extends RefCounted
## Editor-only World autoload ownership. Used from _enable_plugin/_disable_plugin.

const AUTOLOAD_NAME := "World"
const AUTOLOAD_SETTING := "autoload/World"
const CANONICAL_PATH := "res://addons/world_manager/runtime/world.gd"


static func resolve_autoload_script_path(value: String) -> String:
	var path := value.trim_prefix("*")
	if path.is_empty():
		return ""
	if path == CANONICAL_PATH:
		return CANONICAL_PATH
	if path.begins_with("uid://"):
		var id := ResourceUID.text_to_id(path)
		if id == ResourceUID.INVALID_ID or not ResourceUID.has_id(id):
			return path
		return ResourceUID.get_id_path(id)
	return ResourceUID.ensure_path(path)


static func canonical_uid_text() -> String:
	var uid := ResourceUID.path_to_uid(CANONICAL_PATH)
	if uid.begins_with("uid://"):
		return uid
	return ""


static func is_owned_world_autoload(value: String) -> bool:
	var path := value.trim_prefix("*")
	if path.is_empty():
		return false
	if path == CANONICAL_PATH:
		return true
	var owned_uid := canonical_uid_text()
	if not owned_uid.is_empty() and path == owned_uid:
		return true
	if path.begins_with("uid://"):
		var id := ResourceUID.text_to_id(path)
		if id == ResourceUID.INVALID_ID or not ResourceUID.has_id(id):
			return false
		return ResourceUID.get_id_path(id) == CANONICAL_PATH
	return ResourceUID.ensure_path(path) == CANONICAL_PATH


static func has_global_class_named_world() -> bool:
	for info: Dictionary in ProjectSettings.get_global_class_list():
		if str(info.get("class", "")) == AUTOLOAD_NAME:
			return true
	return false


static func current_autoload_value() -> String:
	if not ProjectSettings.has_setting(AUTOLOAD_SETTING):
		return ""
	return str(ProjectSettings.get_setting(AUTOLOAD_SETTING, ""))


static func restore_autoload_value(previous: String) -> void:
	if previous.is_empty():
		if ProjectSettings.has_setting(AUTOLOAD_SETTING):
			ProjectSettings.set_setting(AUTOLOAD_SETTING, null)
		return
	ProjectSettings.set_setting(AUTOLOAD_SETTING, previous)


static func enable(plugin: EditorPlugin) -> Error:
	var previous := current_autoload_value()
	if not previous.is_empty() and is_owned_world_autoload(previous):
		return OK
	if has_global_class_named_world():
		return WorldDiagnostics.reject(
			&"register_autoload",
			ERR_ALREADY_EXISTS,
			{"class": AUTOLOAD_NAME}
		)
	if not previous.is_empty():
		return WorldDiagnostics.reject(
			&"register_autoload",
			ERR_ALREADY_EXISTS,
			{"path": previous.trim_prefix("*")}
		)
	plugin.add_autoload_singleton(AUTOLOAD_NAME, CANONICAL_PATH)
	var after := current_autoload_value()
	if after.begins_with("*") and is_owned_world_autoload(after):
		return OK
	restore_autoload_value(previous)
	return WorldDiagnostics.reject(&"register_autoload", FAILED, {})


static func disable(plugin: EditorPlugin) -> Error:
	var previous := current_autoload_value()
	if previous.is_empty():
		return OK
	if not is_owned_world_autoload(previous):
		return WorldDiagnostics.reject(
			&"unregister_autoload",
			ERR_INVALID_PARAMETER,
			{"path": previous.trim_prefix("*")}
		)
	plugin.remove_autoload_singleton(AUTOLOAD_NAME)
	var after := current_autoload_value()
	if after.is_empty() or not is_owned_world_autoload(after):
		return OK
	restore_autoload_value(previous)
	return WorldDiagnostics.reject(&"unregister_autoload", FAILED, {})
