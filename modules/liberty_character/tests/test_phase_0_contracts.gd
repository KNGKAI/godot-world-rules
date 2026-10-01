extends SceneTree

const Support = preload("res://modules/liberty_character/tests/liberty_test_support.gd")

const EXPECTED_ACTIONS: Array[StringName] = [
	&"liberty_vehicle_steer_left",
	&"liberty_vehicle_steer_right",
	&"liberty_vehicle_throttle",
	&"liberty_vehicle_brake",
	&"liberty_vehicle_handbrake",
	&"liberty_vehicle_reset",
	&"liberty_vehicle_toggle_camera",

	&"liberty_move_forward",
	&"liberty_move_back",
	&"liberty_move_left",
	&"liberty_move_right",
	&"liberty_walk",
	&"liberty_sprint",
	&"liberty_jump",
	&"liberty_traverse",
	&"liberty_drop",
	&"liberty_interact",
	&"liberty_debug_ragdoll",
	&"liberty_debug_hit",
]

const EXPECTED_KEYS := {
	&"liberty_vehicle_steer_left": KEY_A,
	&"liberty_vehicle_steer_right": KEY_D,
	&"liberty_vehicle_throttle": KEY_W,
	&"liberty_vehicle_brake": KEY_S,
	&"liberty_vehicle_handbrake": KEY_SPACE,
	&"liberty_vehicle_reset": KEY_R,
	&"liberty_vehicle_toggle_camera": KEY_C,

	&"liberty_move_forward": KEY_W,
	&"liberty_move_back": KEY_S,
	&"liberty_move_left": KEY_A,
	&"liberty_move_right": KEY_D,
	&"liberty_walk": KEY_ALT,
	&"liberty_sprint": KEY_SHIFT,
	&"liberty_jump": KEY_SPACE,
	&"liberty_traverse": KEY_E,
	&"liberty_drop": KEY_CTRL,
	&"liberty_interact": KEY_Q,
	&"liberty_debug_ragdoll": KEY_R,
	&"liberty_debug_hit": KEY_F,
}

const EXPECTED_SIGNALS := {
	&"occupancy_changed": [TYPE_INT, TYPE_STRING_NAME, TYPE_INT, TYPE_BOOL, TYPE_STRING_NAME],
	&"movement_state_changed": [TYPE_STRING_NAME, TYPE_STRING_NAME],
	&"landed": [TYPE_FLOAT],
	&"ragdoll_started": [TYPE_STRING_NAME],
	&"ragdoll_recovered": [TYPE_BOOL],
	&"hit_received": [TYPE_STRING_NAME, TYPE_VECTOR3, TYPE_FLOAT, TYPE_BOOL],
	&"interaction_started": [TYPE_STRING_NAME],
	&"interaction_finished": [TYPE_STRING_NAME],
	&"traversal_state_changed": [TYPE_STRING_NAME, TYPE_STRING_NAME],
}


func _initialize() -> void:
	_test_engine_configuration()
	_test_input_contract()
	_test_left_alt_binding()
	_test_typed_event_contract()
	_test_event_adapter_resolution()
	quit(Support.exit_code())


func _test_engine_configuration() -> void:
	var project_features: PackedStringArray = ProjectSettings.get_setting("application/config/features")
	Support.expect_true(project_features.has("Forward Plus"), "project feature must select Forward+")
	Support.expect_equal(
		ProjectSettings.get_setting("physics/3d/physics_engine"),
		"Jolt Physics",
		"3D physics must use Jolt Physics"
	)
	Support.expect_equal(
		ProjectSettings.get_setting("physics/common/physics_ticks_per_second"),
		60,
		"physics must run at 60 ticks per second"
	)
	Support.expect_equal(
		ProjectSettings.get_setting("rendering/renderer/rendering_method"),
		"forward_plus",
		"renderer must be Forward+"
	)
	Support.expect_equal(ProjectSettings.get_setting("layer_names/3d_physics/layer_5"), "vehicle_body", "layer 5 name")
	var project_config := ConfigFile.new()
	Support.expect_equal(project_config.load("res://project.godot"), OK, "project.godot must parse")
	Support.expect_false(
		project_config.has_section_key("rendering", "renderer/rendering_method.mobile"),
		"project must not override Forward+ on mobile"
	)
	Support.expect_equal(ProjectSettings.get_setting("layer_names/3d_physics/layer_1"), "world", "layer 1 name")
	Support.expect_equal(ProjectSettings.get_setting("layer_names/3d_physics/layer_2"), "character_body", "layer 2 name")
	Support.expect_equal(ProjectSettings.get_setting("layer_names/3d_physics/layer_3"), "ragdoll", "layer 3 name")
	Support.expect_equal(ProjectSettings.get_setting("layer_names/3d_physics/layer_4"), "interactable", "layer 4 name")


func _test_input_contract() -> void:
	for action in EXPECTED_ACTIONS:
		Support.expect_true(InputMap.has_action(action), "missing input action: %s" % action)
		var bindings := InputMap.action_get_events(action)
		Support.expect_equal(bindings.size(), 1, "%s must have exactly one default binding" % action)
		if bindings.is_empty():
			continue
		var key_event := bindings[0] as InputEventKey
		Support.expect_true(key_event != null, "%s binding must be a keyboard key" % action)
		if key_event == null:
			continue
		Support.expect_equal(key_event.device, -1, "%s keyboard binding accepts every device" % action)
		var expected_key: Key = EXPECTED_KEYS[action]
		Support.expect_true(
			key_event.keycode == expected_key or key_event.physical_keycode == expected_key,
			"%s must use its documented default key" % action
		)


func _test_left_alt_binding() -> void:
	var left_alt := InputEventKey.new()
	left_alt.keycode = KEY_ALT
	left_alt.physical_keycode = KEY_ALT
	left_alt.location = KEY_LOCATION_LEFT
	Support.expect_true(
		InputMap.event_is_action(left_alt, &"liberty_walk", true),
		"Left Alt must activate liberty_walk"
	)
	var right_alt := InputEventKey.new()
	right_alt.keycode = KEY_ALT
	right_alt.physical_keycode = KEY_ALT
	right_alt.location = KEY_LOCATION_RIGHT
	Support.expect_false(
		InputMap.event_is_action(right_alt, &"liberty_walk", true),
		"Right Alt must not activate liberty_walk"
	)


func _test_typed_event_contract() -> void:
	var events := LibertyEvents.new()
	var signals_by_name := {}
	for description in events.get_signal_list():
		signals_by_name[description.name] = description
	for signal_name: StringName in EXPECTED_SIGNALS:
		Support.expect_true(signals_by_name.has(signal_name), "missing event signal: %s" % signal_name)
		if not signals_by_name.has(signal_name):
			continue
		var arguments: Array = signals_by_name[signal_name].args
		var expected_types: Array = EXPECTED_SIGNALS[signal_name]
		Support.expect_equal(arguments.size(), expected_types.size(), "%s argument count" % signal_name)
		for index in mini(arguments.size(), expected_types.size()):
			Support.expect_equal(arguments[index].type, expected_types[index], "%s argument %d type" % [signal_name, index])
	events.free()


func _test_event_adapter_resolution() -> void:
	var owner := Node.new()
	var events := LibertyEvents.new()
	var adapter := LibertyEventAdapter.new()
	events.name = "Events"
	adapter.name = "EventAdapter"
	adapter.events_path = NodePath("../Events")
	owner.add_child(events)
	owner.add_child(adapter)
	Support.expect_true(adapter.events == events, "adapter must resolve the configured LibertyEvents node")
	owner.free()
