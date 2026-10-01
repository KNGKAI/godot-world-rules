extends SceneTree
## The editor's setting defaults and ranges agree with the runtime scripts, and registering
## then unregistering leaves nothing behind.
const Support = preload("res://modules/liberty_character/tests/liberty_test_support.gd")
const EditorSettingsView = preload("res://addons/liberty_character_editor/core/liberty_editor_settings.gd")


func _initialize() -> void: call_deferred("run")


func run() -> void:
	for row: Array in LibertySettings.DEFINITIONS:
		var script: Script = load(LibertySettings.COMPONENT_SCRIPTS[row[1]])
		var runtime: Variant = script.get_property_default_value(row[2])
		var fallback: Variant = EditorSettingsView.default_value(row)
		if fallback is float:
			Support.expect_true(is_equal_approx(fallback * row[3], runtime), "%s default matches runtime" % row[0])
			var info := EditorSettingsView.property_info(row)
			var range := String(info.hint_string).split(",")
			Support.expect_equal(info.hint, PROPERTY_HINT_RANGE, "%s has a range hint" % row[0])
			var upper_open := String(info.hint_string).contains("or_greater")
			Support.expect_true(fallback >= float(range[0]) and (upper_open or fallback <= float(range[1])), "%s default %s inside %s" % [row[0], fallback, info.hint_string])
		else:
			Support.expect_equal(fallback, runtime, "%s default matches runtime" % row[0])
	var angular := EditorSettingsView.row_for("liberty_character/traversal/motor/max_angular_correction_degrees")
	Support.expect_true(is_equal_approx(EditorSettingsView.default_value(angular), 25.0), "angular correction shown in degrees")
	Support.expect_equal(EditorSettingsView.rows("traversal/").size(), 18, "18 traversal settings")
	Support.expect_equal(EditorSettingsView.rows("physical_animation/").size(), 12, "12 physical animation settings")

	EditorSettingsView.register_all()
	for row: Array in LibertySettings.DEFINITIONS:
		Support.expect_true(ProjectSettings.has_setting(LibertySettings.setting_name(row)), "%s registered" % row[0])
		Support.expect_true(EditorSettingsView.is_default(row), "%s registered at its default" % row[0])
	var changed := EditorSettingsView.row_for("liberty_character/physical_animation/stiffness")
	ProjectSettings.set_setting(LibertySettings.setting_name(changed), 3000.0)
	EditorSettingsView.unregister_defaults()
	for row: Array in LibertySettings.DEFINITIONS:
		var kept := row == changed
		Support.expect_equal(ProjectSettings.has_setting(LibertySettings.setting_name(row)), kept, "%s %s after unregister" % [row[0], "kept" if kept else "removed"])
	ProjectSettings.set_setting(LibertySettings.setting_name(changed), null)
	quit(Support.exit_code())
