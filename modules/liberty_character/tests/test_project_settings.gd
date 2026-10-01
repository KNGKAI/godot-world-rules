extends SceneTree
## Phase 8: approved project settings reach the code-built components, and change nothing when absent.
const Support = preload("res://modules/liberty_character/tests/liberty_test_support.gd")
const CHARACTER = preload("res://modules/liberty_character/character/liberty_character.tscn")


func _initialize() -> void: call_deferred("run")


func run() -> void:
	_check_definitions()
	_check_absent_settings_keep_defaults()
	_check_overrides_apply()
	_check_runtime_never_references_addon()
	_check_project_file_has_no_values()
	quit(Support.exit_code())


func _check_definitions() -> void:
	var names := {}
	for row: Array in LibertySettings.DEFINITIONS:
		var name := LibertySettings.setting_name(row)
		Support.expect_true(name.begins_with("liberty_character/"), "%s uses the approved prefix" % name)
		Support.expect_false(names.has(name), "%s is unique" % name)
		names[name] = true
		var script: Script = load(LibertySettings.COMPONENT_SCRIPTS[row[1]])
		var found := false
		for property in script.get_script_property_list():
			found = found or property.name == String(row[2])
		Support.expect_true(found, "%s maps to an existing property %s" % [name, row[2]])
	Support.expect_equal(names.size(), 31, "31 approved settings")


func _components(character: LibertyCharacter) -> Dictionary:
	var coordinator := character.get_node("Traversal") as LibertyTraversalCoordinator
	return {
		&"coordinator": coordinator,
		&"probe": coordinator.probe,
		&"solver": coordinator.solver,
		&"controller": coordinator.controller,
		&"motor": coordinator.motor,
		&"ik": coordinator.ik,
		&"physical_animation": character.physical_animation,
	}


func _check_absent_settings_keep_defaults() -> void:
	for row: Array in LibertySettings.DEFINITIONS:
		Support.expect_false(ProjectSettings.has_setting(LibertySettings.setting_name(row)), "%s absent by default" % row[0])
	var character := CHARACTER.instantiate() as LibertyCharacter
	root.add_child(character)
	var components := _components(character)
	for row: Array in LibertySettings.DEFINITIONS:
		var node: Object = components[row[1]]
		var script: Script = load(LibertySettings.COMPONENT_SCRIPTS[row[1]])
		Support.expect_true(node != null, "%s component exists" % row[1])
		if node == null: continue
		Support.expect_equal(node.get(row[2]), script.get_property_default_value(row[2]), "%s keeps its script default" % row[0])
	character.free()


func _override_for(value: Variant) -> Variant:
	match typeof(value):
		TYPE_BOOL: return not value
		TYPE_DICTIONARY: return {&"LeftFoot": 0.5}
	return value * 1.5 + 0.01


func _check_overrides_apply() -> void:
	var expected := {}
	for row: Array in LibertySettings.DEFINITIONS:
		var script: Script = load(LibertySettings.COMPONENT_SCRIPTS[row[1]])
		var default_value: Variant = script.get_property_default_value(row[2])
		var setting_value: Variant = LibertySettings.to_setting(row, default_value)
		var override: Variant = _override_for(setting_value)
		ProjectSettings.set_setting(LibertySettings.setting_name(row), override)
		expected[row[0]] = override
	var character := CHARACTER.instantiate() as LibertyCharacter
	root.add_child(character)
	var components := _components(character)
	for row: Array in LibertySettings.DEFINITIONS:
		var actual: Variant = components[row[1]].get(row[2])
		var wanted: Variant = expected[row[0]]
		if wanted is Dictionary:
			Support.expect_equal(actual[&"LeftFoot"], 0.5, "%s override merges the named bone" % row[0])
			Support.expect_equal(actual[&"Spine"], 1.0, "%s keeps unnamed bones" % row[0])
			Support.expect_equal(actual.size(), 13, "%s keeps every bone" % row[0])
		elif wanted is float:
			Support.expect_true(is_equal_approx(LibertySettings.to_setting(row, actual), wanted), "%s override applied (%s vs %s)" % [row[0], actual, wanted])
		else:
			Support.expect_equal(actual, wanted, "%s override applied" % row[0])
	character.free()
	for row: Array in LibertySettings.DEFINITIONS:
		ProjectSettings.set_setting(LibertySettings.setting_name(row), null)
	# A per-node debug flag survives an absent setting (the setting can only add the overlay).
	var debug_character := CHARACTER.instantiate() as LibertyCharacter
	(debug_character.get_node("Traversal") as LibertyTraversalCoordinator).debug_traversal = true
	root.add_child(debug_character)
	Support.expect_true((debug_character.get_node("Traversal") as LibertyTraversalCoordinator).debug_traversal, "per-node debug flag kept")
	debug_character.free()


func _check_runtime_never_references_addon() -> void:
	var offenders: Array[String] = []
	_scan("res://modules", offenders)
	Support.expect_true(offenders.is_empty(), "runtime files reference the editor addon: %s" % [offenders])


func _scan(path: String, offenders: Array[String]) -> void:
	for directory in DirAccess.get_directories_at(path):
		_scan(path.path_join(directory), offenders)
	for file in DirAccess.get_files_at(path):
		if not (file.ends_with(".gd") or file.ends_with(".tscn") or file.ends_with(".tres")):
			continue
		var full := path.path_join(file)
		if full == "res://modules/liberty_character/tests/test_project_settings.gd":
			continue
		if FileAccess.get_file_as_string(full).contains("liberty_character_editor"):
			offenders.append(full)


func _check_project_file_has_no_values() -> void:
	var text := FileAccess.get_file_as_string("res://project.godot")
	Support.expect_false(text.contains("[liberty_character]"), "project.godot stores no liberty_character settings")
