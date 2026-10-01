@tool
extends EditorInspectorPlugin

const VariantEditorProperty := preload("variant_editor_property.gd")


func _can_handle(object: Object) -> bool:
	return object is RECompareCondition


func _parse_property(
	object: Object,
	_type: Variant.Type,
	name: String,
	_hint_type: PropertyHint,
	_hint_string: String,
	_usage_flags: int,
	_wide: bool,
) -> bool:
	if not object is RECompareCondition or name != "value":
		return false
	var editor: EditorProperty = VariantEditorProperty.new()
	editor.call("setup")
	add_property_editor(name, editor)
	return true
