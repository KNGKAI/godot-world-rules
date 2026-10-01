@tool
extends VBoxContainer
## Inspector section that edits approved liberty_character/* project settings in place. Each
## edit is an undoable action on ProjectSettings followed by a save; values at their default
## are never written to project.godot (they are the registered initial values).

const EditorSettingsView = preload("res://addons/liberty_character_editor/core/liberty_editor_settings.gd")

var _editors := {}


## `groups` is an Array of [setting-name prefix after liberty_character/, heading].
func build(title: String, groups: Array) -> void:
	var heading := Label.new()
	heading.text = title
	heading.add_theme_font_size_override(&"font_size", 15)
	add_child(heading)
	var note := Label.new()
	note.text = "Project settings (liberty_character/*). Applied when the game starts."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.modulate = Color(1, 1, 1, 0.65)
	add_child(note)
	for group: Array in groups:
		var subheading := Label.new()
		subheading.text = group[1]
		subheading.modulate = Color(0.7, 0.85, 1.0)
		add_child(subheading)
		var grid := GridContainer.new()
		grid.columns = 3
		add_child(grid)
		for row: Array in EditorSettingsView.rows(group[0]):
			_add_row(grid, row)
	ProjectSettings.settings_changed.connect(_refresh)
	_refresh()


func _exit_tree() -> void:
	if ProjectSettings.settings_changed.is_connected(_refresh):
		ProjectSettings.settings_changed.disconnect(_refresh)


func _add_row(grid: GridContainer, row: Array) -> void:
	var name := LibertySettings.setting_name(row)
	var fallback: Variant = EditorSettingsView.default_value(row)
	if fallback is Dictionary:
		# One slider per bone, spanning the grid, writing the whole merged dictionary.
		var label := Label.new()
		label.text = String(row[0]).get_file().capitalize()
		grid.add_child(label)
		grid.add_child(Control.new())
		grid.add_child(_reset_button(row))
		for bone: StringName in fallback:
			var bone_label := Label.new()
			bone_label.text = "  " + String(bone)
			grid.add_child(bone_label)
			var slider := _slider("0.0,4.0,0.05,or_greater")
			slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			slider.value_changed.connect(func(value: float) -> void: _set_bone(row, bone, value))
			grid.add_child(slider)
			grid.add_child(Control.new())
			_editors[name + ":" + String(bone)] = slider
		return
	var label := Label.new()
	label.text = String(row[0]).get_file().capitalize()
	label.tooltip_text = name
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(label)
	var editor: Control
	if fallback is bool:
		var check := CheckBox.new()
		check.toggled.connect(func(pressed: bool) -> void: set_setting_value(name, pressed))
		editor = check
	else:
		var slider := _slider(EditorSettingsView.property_info(row).hint_string)
		slider.value_changed.connect(func(value: float) -> void: set_setting_value(name, value))
		editor = slider
	editor.name = String(row[0]).get_file()
	editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	editor.tooltip_text = name
	grid.add_child(editor)
	grid.add_child(_reset_button(row))
	_editors[name] = editor


func _slider(hint_string: String) -> EditorSpinSlider:
	var parts := hint_string.split(",")
	var slider := EditorSpinSlider.new()
	slider.min_value = float(parts[0])
	slider.max_value = float(parts[1]) if parts.size() > 1 else 100.0
	slider.step = float(parts[2]) if parts.size() > 2 else 0.01
	slider.allow_greater = hint_string.contains("or_greater")
	slider.custom_minimum_size.x = 110.0
	return slider


func _reset_button(row: Array) -> Button:
	var button := Button.new()
	button.flat = true
	button.icon = EditorInterface.get_editor_theme().get_icon(&"Reload", &"EditorIcons")
	button.tooltip_text = "Reset to default"
	button.pressed.connect(func() -> void: set_setting_value(LibertySettings.setting_name(row), EditorSettingsView.default_value(row)))
	return button


func _set_bone(row: Array, bone: StringName, value: float) -> void:
	var merged: Dictionary = EditorSettingsView.value(row).duplicate()
	merged[bone] = value
	set_setting_value(LibertySettings.setting_name(row), merged)


## Undoable write of one setting; consecutive slider steps merge into one action.
func set_setting_value(name: String, value: Variant) -> void:
	var row := EditorSettingsView.row_for(name)
	var old: Variant = EditorSettingsView.value(row)
	if typeof(old) == typeof(value) and old == value:
		return
	var undo_redo := EditorInterface.get_editor_undo_redo()
	undo_redo.create_action("Set " + name, UndoRedo.MERGE_ENDS)
	undo_redo.add_do_method(ProjectSettings, &"set_setting", name, value)
	undo_redo.add_do_method(ProjectSettings, &"save")
	undo_redo.add_undo_method(ProjectSettings, &"set_setting", name, old)
	undo_redo.add_undo_method(ProjectSettings, &"save")
	undo_redo.commit_action()


func _refresh() -> void:
	for row: Array in LibertySettings.DEFINITIONS:
		var name := LibertySettings.setting_name(row)
		var current: Variant = EditorSettingsView.value(row)
		if current is Dictionary:
			for bone: Variant in current:
				var slider := _editors.get(name + ":" + String(bone)) as EditorSpinSlider
				if slider != null:
					slider.set_value_no_signal(current[bone])
			continue
		var editor: Control = _editors.get(name)
		if editor is CheckBox:
			(editor as CheckBox).set_pressed_no_signal(current)
		elif editor is EditorSpinSlider:
			(editor as EditorSpinSlider).set_value_no_signal(current)
			editor.modulate = Color.WHITE if EditorSettingsView.is_default(row) else Color(1.0, 0.85, 0.5)
