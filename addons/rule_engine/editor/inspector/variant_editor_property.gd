@tool
extends EditorProperty

var _input: LineEdit


func setup() -> void:
	if _input != null:
		return
	_input = LineEdit.new()
	_input.placeholder_text = "Variant value (for example: 42, true, or \"text\")"
	_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input.text_submitted.connect(_commit_text)
	_input.focus_exited.connect(_commit_current_text)
	add_child(_input)
	add_focusable(_input)


func _update_property() -> void:
	var edited := get_edited_object()
	if edited == null:
		return
	var value: Variant = edited.get(get_edited_property())
	var serialized := var_to_str(value)
	if _input.text != serialized:
		_input.text = serialized


func _commit_current_text() -> void:
	_commit_text(_input.text)


func _commit_text(text: String) -> void:
	var value: Variant = str_to_var(text)
	# EditorProperty changes are routed through the Inspector's
	# EditorUndoRedoManager, preserving native undo/redo behavior.
	emit_changed(get_edited_property(), value)
