@tool
extends EditorExportPlugin

const EDITOR_PREFIX := "res://addons/rule_engine/editor/"


func _get_name() -> String:
	return "RuleEngineRuntimeBoundary"


func _export_begin(
	_features: PackedStringArray,
	_is_debug: bool,
	_path: String,
	_flags: int,
) -> void:
	var preset := get_export_preset()
	if preset != null and preset.get_script_export_mode() != EditorExportPreset.MODE_SCRIPT_TEXT:
		push_warning(
			"Rule Engine editor filtering requires Text GDScript export mode on Godot 4.7; "
			+ "otherwise add addons/rule_engine/editor/* to the preset's exclude filter."
		)


func _export_file(path: String, _type: String, _features: PackedStringArray) -> void:
	if path.begins_with(EDITOR_PREFIX):
		skip()
