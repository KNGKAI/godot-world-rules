@tool
extends Control

enum SaveOperation { CREATE, DUPLICATE }

var _controller: Variant
var _discovery: Variant
var _filter: Variant
var _menu_model: Variant
var _editor_interface: EditorInterface
var _updating := false
var _save_operation := SaveOperation.CREATE
var _selected_condition_path := "condition"
var _selected_condition: RECondition
var _selected_missing_parent_path := ""
var _selected_missing_child_index := -2
var _selected_action_index := -1

var _search: LineEdit
var _book_tree: Tree
var _create_button: Button
var _duplicate_button: Button
var _unlink_button: Button
var _enabled_field: CheckButton
var _id_field: LineEdit
var _event_field: LineEdit
var _priority_field: SpinBox
var _tags_field: LineEdit
var _condition_tree: Tree
var _condition_menu: MenuButton
var _append_condition_menu: MenuButton
var _wrap_menu: MenuButton
var _remove_condition_button: Button
var _convert_condition_button: Button
var _action_list: ItemList
var _action_menu: MenuButton
var _remove_action_button: Button
var _move_up_button: Button
var _move_down_button: Button
var _issue_tree: Tree
var _status_label: Label
var _save_dialog: EditorFileDialog


func setup(
	controller: Variant,
	discovery: Variant,
	filter: Variant,
	menu_model: Variant,
	editor_interface: EditorInterface,
) -> void:
	_controller = controller
	_discovery = discovery
	_filter = filter
	_menu_model = menu_model
	_editor_interface = editor_interface
	_connect_external_signals()
	if is_node_ready():
		_refresh_all()


func _ready() -> void:
	_build_ui()
	_refresh_all()


func shutdown() -> void:
	_disconnect_external_signals()
	_controller = null
	_discovery = null
	_filter = null
	_menu_model = null
	_editor_interface = null


func _connect_external_signals() -> void:
	if _discovery != null:
		var discovery_changed: Signal = _discovery.changed
		if not discovery_changed.is_connected(_on_discovery_changed):
			discovery_changed.connect(_on_discovery_changed)
	if _controller != null:
		var selection_changed: Signal = _controller.selection_changed
		if not selection_changed.is_connected(_on_selection_changed):
			selection_changed.connect(_on_selection_changed)
		var state_changed: Signal = _controller.state_changed
		if not state_changed.is_connected(_on_state_changed):
			state_changed.connect(_on_state_changed)
		var issues_changed: Signal = _controller.issues_changed
		if not issues_changed.is_connected(_on_issues_changed):
			issues_changed.connect(_on_issues_changed)
		var inspect_requested: Signal = _controller.inspect_requested
		if not inspect_requested.is_connected(_on_inspect_requested):
			inspect_requested.connect(_on_inspect_requested)
		var operation_failed: Signal = _controller.operation_failed
		if not operation_failed.is_connected(_on_operation_failed):
			operation_failed.connect(_on_operation_failed)


func _disconnect_external_signals() -> void:
	if _discovery != null:
		var discovery_changed: Signal = _discovery.changed
		if discovery_changed.is_connected(_on_discovery_changed):
			discovery_changed.disconnect(_on_discovery_changed)
	if _controller == null:
		return
	var selection_changed: Signal = _controller.selection_changed
	if selection_changed.is_connected(_on_selection_changed):
		selection_changed.disconnect(_on_selection_changed)
	var state_changed: Signal = _controller.state_changed
	if state_changed.is_connected(_on_state_changed):
		state_changed.disconnect(_on_state_changed)
	var issues_changed: Signal = _controller.issues_changed
	if issues_changed.is_connected(_on_issues_changed):
		issues_changed.disconnect(_on_issues_changed)
	var inspect_requested: Signal = _controller.inspect_requested
	if inspect_requested.is_connected(_on_inspect_requested):
		inspect_requested.disconnect(_on_inspect_requested)
	var operation_failed: Signal = _controller.operation_failed
	if operation_failed.is_connected(_on_operation_failed):
		operation_failed.disconnect(_on_operation_failed)


func _build_ui() -> void:
	var layout := HSplitContainer.new()
	layout.name = "Layout"
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(layout)

	var browser_pane := VBoxContainer.new()
	browser_pane.name = "BrowserPane"
	browser_pane.custom_minimum_size = Vector2(300.0, 0.0)
	layout.add_child(browser_pane)

	_search = LineEdit.new()
	_search.name = "Search"
	_search.placeholder_text = "Search ID, event, or tag"
	_search.clear_button_enabled = true
	_search.text_changed.connect(_on_search_changed)
	browser_pane.add_child(_search)

	var browser_toolbar := HBoxContainer.new()
	browser_toolbar.name = "BrowserToolbar"
	browser_pane.add_child(browser_toolbar)
	_create_button = _button("Create", _on_create_pressed)
	_duplicate_button = _button("Duplicate", _on_duplicate_pressed)
	_unlink_button = _button("Unlink", _on_unlink_pressed)
	browser_toolbar.add_child(_create_button)
	browser_toolbar.add_child(_duplicate_button)
	browser_toolbar.add_child(_unlink_button)

	_book_tree = Tree.new()
	_book_tree.name = "BookTree"
	_book_tree.hide_root = true
	_book_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_book_tree.item_selected.connect(_on_browser_item_selected)
	browser_pane.add_child(_book_tree)

	var workspace_pane := VBoxContainer.new()
	workspace_pane.name = "WorkspacePane"
	workspace_pane.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.add_child(workspace_pane)

	var heading := Label.new()
	heading.text = "Selected Rule"
	heading.add_theme_font_size_override("font_size", 18)
	workspace_pane.add_child(heading)
	_build_rule_fields(workspace_pane)
	_build_condition_editor(workspace_pane)
	_build_action_editor(workspace_pane)
	_build_validation(workspace_pane)

	_save_dialog = EditorFileDialog.new()
	_save_dialog.name = "RuleSaveDialog"
	_save_dialog.access = EditorFileDialog.ACCESS_RESOURCES
	_save_dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
	_save_dialog.filters = PackedStringArray(["*.tres ; Rule Resource"])
	_save_dialog.file_selected.connect(_on_save_path_selected)
	add_child(_save_dialog)


func _build_rule_fields(parent: VBoxContainer) -> void:
	var fields := GridContainer.new()
	fields.name = "RuleFields"
	fields.columns = 2
	parent.add_child(fields)
	_enabled_field = CheckButton.new()
	_add_field(fields, "Enabled", _enabled_field)
	_enabled_field.toggled.connect(_on_enabled_toggled)
	_id_field = LineEdit.new()
	_add_field(fields, "ID", _id_field)
	_id_field.text_submitted.connect(_on_id_submitted)
	_id_field.focus_exited.connect(_on_id_focus_exited)
	_event_field = LineEdit.new()
	_add_field(fields, "Event", _event_field)
	_event_field.text_submitted.connect(_on_event_submitted)
	_event_field.focus_exited.connect(_on_event_focus_exited)
	_priority_field = SpinBox.new()
	_priority_field.allow_greater = true
	_priority_field.allow_lesser = true
	_priority_field.step = 1.0
	_add_field(fields, "Priority", _priority_field)
	_priority_field.value_changed.connect(_on_priority_changed)
	_tags_field = LineEdit.new()
	_tags_field.placeholder_text = "tag_one, tag_two"
	_add_field(fields, "Tags", _tags_field)
	_tags_field.text_submitted.connect(_on_tags_submitted)
	_tags_field.focus_exited.connect(_on_tags_focus_exited)


func _build_condition_editor(parent: VBoxContainer) -> void:
	var header := Label.new()
	header.text = "Condition Tree"
	parent.add_child(header)
	_condition_tree = Tree.new()
	_condition_tree.name = "ConditionTree"
	_condition_tree.hide_root = true
	_condition_tree.custom_minimum_size = Vector2(0.0, 130.0)
	_condition_tree.item_selected.connect(_on_condition_selected)
	parent.add_child(_condition_tree)
	var toolbar := HBoxContainer.new()
	toolbar.name = "ConditionToolbar"
	parent.add_child(toolbar)
	_condition_menu = MenuButton.new()
	_condition_menu.text = "Add / Replace"
	toolbar.add_child(_condition_menu)
	_append_condition_menu = MenuButton.new()
	_append_condition_menu.name = "AppendChild"
	_append_condition_menu.text = "Append Child"
	toolbar.add_child(_append_condition_menu)
	_wrap_menu = MenuButton.new()
	_wrap_menu.text = "Wrap"
	toolbar.add_child(_wrap_menu)
	_remove_condition_button = _button("Remove", _on_remove_condition_pressed)
	_convert_condition_button = _button("Convert All/Any", _on_convert_condition_pressed)
	toolbar.add_child(_remove_condition_button)
	toolbar.add_child(_convert_condition_button)
	_populate_type_menu(_condition_menu.get_popup(), _menu_model.get_condition_entries())
	_condition_menu.get_popup().id_pressed.connect(_on_condition_type_selected)
	_populate_type_menu(_append_condition_menu.get_popup(), _menu_model.get_condition_entries())
	_append_condition_menu.get_popup().id_pressed.connect(_on_append_condition_type_selected)
	var wrapper_entries: Array = _menu_model.get_condition_entries().filter(
		func(entry: Dictionary) -> bool:
			return entry.name in [&"REAllCondition", &"REAnyCondition", &"RENotCondition"]
	)
	_populate_type_menu(_wrap_menu.get_popup(), wrapper_entries)
	_wrap_menu.get_popup().id_pressed.connect(_on_wrapper_type_selected)


func _build_action_editor(parent: VBoxContainer) -> void:
	var header := Label.new()
	header.text = "Ordered Actions"
	parent.add_child(header)
	_action_list = ItemList.new()
	_action_list.name = "ActionList"
	_action_list.custom_minimum_size = Vector2(0.0, 100.0)
	_action_list.item_selected.connect(_on_action_selected)
	parent.add_child(_action_list)
	var toolbar := HBoxContainer.new()
	toolbar.name = "ActionToolbar"
	parent.add_child(toolbar)
	_action_menu = MenuButton.new()
	_action_menu.text = "Add Action"
	toolbar.add_child(_action_menu)
	_remove_action_button = _button("Remove", _on_remove_action_pressed)
	_move_up_button = _button("Move Up", _on_move_action_up)
	_move_down_button = _button("Move Down", _on_move_action_down)
	toolbar.add_child(_remove_action_button)
	toolbar.add_child(_move_up_button)
	toolbar.add_child(_move_down_button)
	_populate_type_menu(_action_menu.get_popup(), _menu_model.get_action_entries())
	_action_menu.get_popup().id_pressed.connect(_on_action_type_selected)


func _build_validation(parent: VBoxContainer) -> void:
	var validate_button := _button("Validate Discovered Books", _on_validate_pressed)
	validate_button.name = "ValidateButton"
	parent.add_child(validate_button)
	_issue_tree = Tree.new()
	_issue_tree.name = "IssueTree"
	_issue_tree.columns = 4
	_issue_tree.set_column_title(0, "Severity")
	_issue_tree.set_column_title(1, "Rule")
	_issue_tree.set_column_title(2, "Property")
	_issue_tree.set_column_title(3, "Message")
	_issue_tree.column_titles_visible = true
	_issue_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_issue_tree.item_activated.connect(_on_issue_activated)
	parent.add_child(_issue_tree)
	_status_label = Label.new()
	_status_label.name = "StatusLabel"
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(_status_label)


func _button(label: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = label
	button.pressed.connect(callback)
	return button


func _add_field(grid: GridContainer, label_text: String, field: Control) -> void:
	var label := Label.new()
	label.text = label_text
	grid.add_child(label)
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(field)


func _populate_type_menu(popup: PopupMenu, entries: Array) -> void:
	popup.clear()
	for entry: Dictionary in entries:
		var id := popup.item_count
		popup.add_item(String(entry.name), id)
		popup.set_item_metadata(id, entry)
		popup.set_item_disabled(id, not entry.enabled)
		popup.set_item_tooltip(id, entry.tooltip)


func _refresh_all() -> void:
	if not is_node_ready() or _book_tree == null:
		return
	_refresh_browser()
	_refresh_selected_rule()
	_refresh_issues(_controller.get_issues() if _controller != null else [])


func _refresh_browser() -> void:
	_book_tree.clear()
	var root := _book_tree.create_item()
	if _discovery == null or _filter == null:
		_add_empty_tree_item(_book_tree, root, "Rules workspace is unavailable.")
		return
	var groups: Array = _filter.filter(_discovery.get_groups(), _search.text)
	if groups.is_empty():
		_add_empty_tree_item(_book_tree, root, "No matching RuleBooks found.")
		return
	for group: Dictionary in groups:
		var directory_item := _book_tree.create_item(root)
		directory_item.set_text(0, group.directory)
		directory_item.set_selectable(0, false)
		for entry: Dictionary in group.books:
			var book_item := _book_tree.create_item(directory_item)
			book_item.set_text(0, entry.path.get_file())
			book_item.set_tooltip_text(0, entry.path)
			book_item.set_metadata(0, {&"kind": &"book", &"resource": entry.book})
			for rule: RERule in entry.rules:
				var rule_item := _book_tree.create_item(book_item)
				rule_item.set_text(0, String(rule.id) if not rule.id.is_empty() else "<unnamed rule>")
				rule_item.set_metadata(0, {&"kind": &"rule", &"resource": rule})


func _refresh_selected_rule() -> void:
	var rule: RERule = _controller.get_selected_rule() if _controller != null else null
	var has_book := _controller != null and _controller.get_selected_book() != null
	var has_rule := rule != null
	_updating = true
	_create_button.disabled = not has_book
	_duplicate_button.disabled = not has_rule
	_unlink_button.disabled = not has_rule
	_enabled_field.disabled = not has_rule
	_enabled_field.button_pressed = rule.enabled if has_rule else false
	_id_field.editable = has_rule
	_id_field.text = String(rule.id) if has_rule else ""
	_event_field.editable = has_rule
	_event_field.text = String(rule.event) if has_rule else ""
	_priority_field.editable = has_rule
	_priority_field.value = rule.priority if has_rule else 0
	_tags_field.editable = has_rule
	_tags_field.text = ", ".join(rule.tags) if has_rule else ""
	_updating = false
	_refresh_condition_tree(rule)
	_refresh_action_list(rule)


func _refresh_condition_tree(rule: RERule) -> void:
	_condition_tree.clear()
	var root := _condition_tree.create_item()
	_selected_condition_path = "condition"
	_selected_condition = rule.condition if rule != null else null
	_selected_missing_parent_path = ""
	_selected_missing_child_index = -2
	if rule == null:
		_add_empty_tree_item(_condition_tree, root, "Select a Rule to edit conditions.")
	elif rule.condition == null:
		_add_empty_tree_item(_condition_tree, root, "No condition. Choose Add / Replace.")
	else:
		_add_condition_item(root, rule.condition, "condition", {})
	_condition_menu.disabled = rule == null
	_append_condition_menu.disabled = not (
		_selected_condition is REAllCondition or _selected_condition is REAnyCondition
	)
	_wrap_menu.disabled = _selected_condition == null
	_remove_condition_button.disabled = _selected_condition == null
	_convert_condition_button.disabled = not (
		_selected_condition is REAllCondition or _selected_condition is REAnyCondition
	)


func _add_condition_item(
	parent: TreeItem,
	condition: RECondition,
	property_path: String,
	visited: Dictionary,
	missing_parent_path: String = "",
	missing_child_index: int = -2,
) -> void:
	var item := _condition_tree.create_item(parent)
	if condition == null:
		item.set_text(0, "<missing - choose Add / Replace>")
		item.set_metadata(0, {
			&"resource": null,
			&"property_path": property_path,
			&"missing_parent_path": missing_parent_path,
			&"missing_child_index": missing_child_index,
		})
		return
	item.set_text(0, _resource_type_name(condition))
	item.set_metadata(0, {
		&"resource": condition,
		&"property_path": property_path,
	})
	var key := condition.get_instance_id()
	if visited.has(key):
		item.set_text(0, "%s [cycle]" % item.get_text(0))
		return
	visited[key] = true
	if condition is RENotCondition:
		_add_condition_item(
			item,
			condition.condition,
			property_path + ".condition",
			visited,
			property_path,
			-1,
		)
	elif condition is REAllCondition or condition is REAnyCondition:
		for index: int in condition.conditions.size():
			_add_condition_item(
				item,
				condition.conditions[index],
				property_path + ".conditions[%d]" % index,
				visited,
				property_path,
				index,
			)
	visited.erase(key)


func _refresh_action_list(rule: RERule) -> void:
	_action_list.clear()
	_selected_action_index = -1
	if rule == null:
		_action_list.add_item("Select a Rule to edit actions.")
		_action_list.set_item_disabled(0, true)
	elif rule.actions.is_empty():
		_action_list.add_item("No actions.")
		_action_list.set_item_disabled(0, true)
	else:
		for index: int in rule.actions.size():
			var action: REAction = rule.actions[index]
			_action_list.add_item(
				"%d. %s" % [index + 1, _resource_type_name(action)]
				if action != null
				else "%d. <missing>" % [index + 1]
			)
	_action_menu.disabled = rule == null
	_update_action_buttons(rule)


func _refresh_issues(issues: Array) -> void:
	_issue_tree.clear()
	var root := _issue_tree.create_item()
	if issues.is_empty():
		_add_empty_tree_item(_issue_tree, root, "No validation results.")
		return
	for index: int in issues.size():
		var issue: Variant = issues[index]
		var item := _issue_tree.create_item(root)
		item.set_text(0, ["Error", "Warning", "Info"][issue.severity])
		item.set_text(1, String(issue.rule_id))
		item.set_text(2, issue.property_path)
		item.set_text(3, issue.message)
		item.set_metadata(0, index)


func _add_empty_tree_item(tree: Tree, parent: TreeItem, text: String) -> void:
	var item := tree.create_item(parent)
	item.set_text(0, text)
	item.set_selectable(0, false)


func _resource_type_name(resource: Resource) -> String:
	if resource == null:
		return "<missing>"
	var script := resource.get_script() as Script
	if script != null and not script.get_global_name().is_empty():
		return String(script.get_global_name())
	return resource.get_class()


func _on_search_changed(_text: String) -> void:
	_refresh_browser()


func _on_browser_item_selected() -> void:
	var item := _book_tree.get_selected()
	if item == null:
		return
	var metadata: Variant = item.get_metadata(0)
	if not metadata is Dictionary:
		return
	if metadata.kind == &"book":
		_controller.select_book(metadata.resource)
	elif metadata.kind == &"rule":
		_controller.select_rule(metadata.resource)


func _on_condition_selected() -> void:
	var item := _condition_tree.get_selected()
	if item == null:
		return
	var metadata: Variant = item.get_metadata(0)
	if not metadata is Dictionary:
		return
	_selected_condition_path = metadata.property_path
	_selected_condition = metadata.resource
	_selected_missing_parent_path = metadata.get(&"missing_parent_path", "")
	_selected_missing_child_index = metadata.get(&"missing_child_index", -2)
	if _selected_condition != null:
		_controller.select_condition(_selected_condition, _selected_condition_path)
	_append_condition_menu.disabled = not (
		_selected_condition is REAllCondition or _selected_condition is REAnyCondition
	)
	_wrap_menu.disabled = _selected_condition == null
	_remove_condition_button.disabled = _selected_condition == null
	_convert_condition_button.disabled = not (
		_selected_condition is REAllCondition or _selected_condition is REAnyCondition
	)


func _on_action_selected(index: int) -> void:
	var rule: RERule = _controller.get_selected_rule()
	if rule == null or index < 0 or index >= rule.actions.size():
		return
	_selected_action_index = index
	_controller.select_action(index)
	_update_action_buttons(rule)


func _update_action_buttons(rule: RERule) -> void:
	var valid := (
		rule != null
		and _selected_action_index >= 0
		and _selected_action_index < rule.actions.size()
	)
	_remove_action_button.disabled = not valid
	_move_up_button.disabled = not valid or _selected_action_index == 0
	_move_down_button.disabled = not valid or _selected_action_index == rule.actions.size() - 1


func _on_create_pressed() -> void:
	if _controller.get_selected_book() == null:
		return
	_save_operation = SaveOperation.CREATE
	_open_save_dialog("Create Rule", "new_rule.tres")


func _on_duplicate_pressed() -> void:
	var rule: RERule = _controller.get_selected_rule()
	if rule == null:
		return
	_save_operation = SaveOperation.DUPLICATE
	_open_save_dialog("Duplicate Rule", "%s_copy.tres" % rule.id)


func _open_save_dialog(title: String, file_name: String) -> void:
	_status_label.text = ""
	_save_dialog.title = title
	_save_dialog.current_path = _controller.get_default_rules_directory().path_join(file_name)
	_save_dialog.popup_centered_ratio(0.55)


func _on_save_path_selected(path: String) -> void:
	var target_path := path if path.get_extension().to_lower() == "tres" else path + ".tres"
	var saved_rule: RERule
	if _save_operation == SaveOperation.CREATE:
		saved_rule = _controller.create_rule(
			target_path,
			StringName(target_path.get_file().get_basename()),
		)
	else:
		saved_rule = _controller.duplicate_selected_rule(target_path)
	if saved_rule != null:
		_status_label.text = "Saved %s" % target_path


func _on_unlink_pressed() -> void:
	_controller.unlink_selected_rule()


func _on_enabled_toggled(value: bool) -> void:
	if not _updating:
		_controller.set_rule_enabled(value)


func _on_id_submitted(value: String) -> void:
	_controller.set_rule_id(StringName(value.strip_edges()))


func _on_id_focus_exited() -> void:
	_on_id_submitted(_id_field.text)


func _on_event_submitted(value: String) -> void:
	_controller.set_rule_event(StringName(value.strip_edges()))


func _on_event_focus_exited() -> void:
	_on_event_submitted(_event_field.text)


func _on_priority_changed(value: float) -> void:
	if not _updating:
		_controller.set_rule_priority(int(value))


func _on_tags_submitted(value: String) -> void:
	var tags := PackedStringArray()
	for tag: String in value.split(",", false):
		var trimmed := tag.strip_edges()
		if not trimmed.is_empty():
			tags.append(trimmed)
	_controller.set_rule_tags(tags)


func _on_tags_focus_exited() -> void:
	_on_tags_submitted(_tags_field.text)


func _on_condition_type_selected(id: int) -> void:
	var entry: Dictionary = _condition_menu.get_popup().get_item_metadata(id)
	if not _selected_missing_parent_path.is_empty():
		_controller.set_condition_child(
			_selected_missing_parent_path,
			_selected_missing_child_index,
			entry.script,
		)
	elif _selected_condition == null:
		_controller.set_condition(_selected_condition_path, entry.script)
	else:
		_controller.replace_condition(_selected_condition_path, entry.script)


func _on_append_condition_type_selected(id: int) -> void:
	var entry: Dictionary = _append_condition_menu.get_popup().get_item_metadata(id)
	_controller.append_condition(_selected_condition_path, entry.script)


func _on_wrapper_type_selected(id: int) -> void:
	var entry: Dictionary = _wrap_menu.get_popup().get_item_metadata(id)
	_controller.wrap_condition(_selected_condition_path, entry.script)


func _on_remove_condition_pressed() -> void:
	_controller.remove_condition(_selected_condition_path)


func _on_convert_condition_pressed() -> void:
	_controller.convert_condition(_selected_condition_path)


func _on_action_type_selected(id: int) -> void:
	var entry: Dictionary = _action_menu.get_popup().get_item_metadata(id)
	_controller.add_action(entry.script)


func _on_remove_action_pressed() -> void:
	if _controller.remove_action(_selected_action_index):
		_selected_action_index = -1


func _on_move_action_up() -> void:
	var target_index := _selected_action_index - 1
	if _controller.move_action(_selected_action_index, target_index):
		_selected_action_index = target_index
		_action_list.select(target_index)
		_update_action_buttons(_controller.get_selected_rule())


func _on_move_action_down() -> void:
	var target_index := _selected_action_index + 1
	if _controller.move_action(_selected_action_index, target_index):
		_selected_action_index = target_index
		_action_list.select(target_index)
		_update_action_buttons(_controller.get_selected_rule())


func _on_validate_pressed() -> void:
	_controller.validate()


func _on_issue_activated() -> void:
	var item := _issue_tree.get_selected()
	if item == null:
		return
	var index: Variant = item.get_metadata(0)
	if index is int:
		_controller.activate_issue(index)


func _on_discovery_changed() -> void:
	_refresh_browser()


func _on_selection_changed() -> void:
	_refresh_selected_rule()


func _on_state_changed() -> void:
	_refresh_browser()
	_refresh_selected_rule()


func _on_issues_changed(issues: Array) -> void:
	_refresh_issues(issues)


func _on_inspect_requested(resource: Resource) -> void:
	if _editor_interface != null and resource != null:
		_editor_interface.edit_resource(resource)


func _on_operation_failed(message: String) -> void:
	_status_label.text = message
	_status_label.add_theme_color_override(
		"font_color",
		get_theme_color("error_color", "Editor"),
	)
