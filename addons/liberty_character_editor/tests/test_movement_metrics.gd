extends SceneTree
## The inspector's derived movement figures reproduce the measured Phase 1 tuning record.
const Support = preload("res://modules/liberty_character/tests/liberty_test_support.gd")
const Metrics = preload("res://addons/liberty_character_editor/core/liberty_movement_metrics.gd")
## modules/liberty_character/README.md "Tuning Record" measurements at 60 ticks/s.
const MEASURED := {
	&"walk": {"top": 0.233, "stop": 0.385},
	&"run": {"top": 0.533, "stop": 2.042, "turn": 0.859},
	&"sprint": {"top": 0.800, "stop": 4.625, "turn": 2.309},
}


func _initialize() -> void: call_deferred("run")


func run() -> void:
	var script: Script = load("res://modules/liberty_character/character/liberty_character.gd")
	var values := {}
	for name in ["walk_speed", "run_speed", "sprint_speed", "ground_acceleration", "ground_deceleration",
			"grounded_turn_rate_degrees", "high_speed_turn_rate_degrees", "gravity", "jump_velocity"]:
		values[name] = script.get_property_default_value(name)
	var summary := Metrics.summarize(values)
	for gait: StringName in MEASURED:
		var measured: Dictionary = MEASURED[gait]
		var derived: Dictionary = summary[gait]
		print("%s top %.3f stop %.3f turn %.3f" % [gait, derived.top, derived.stop, derived.turn])
		Support.expect_true(absf(derived.top - measured.top) <= 1.0 / 60.0 + 0.001, "%s time to 95%% (%.3f vs %.3f)" % [gait, derived.top, measured.top])
		Support.expect_true(absf(derived.stop - measured.stop) <= 0.01, "%s stopping distance (%.3f vs %.3f)" % [gait, derived.stop, measured.stop])
		if measured.has("turn"):
			Support.expect_true(absf(derived.turn - measured.turn) <= 0.01, "%s turn radius (%.3f vs %.3f)" % [gait, derived.turn, measured.turn])
	var jump: Dictionary = summary.jump
	print("jump apex %.3f air %.3f" % [jump.apex, jump.air_time])
	var apex: float = values.jump_velocity * values.jump_velocity / (2.0 * values.gravity)
	var air: float = 2.0 * values.jump_velocity / values.gravity
	Support.expect_true(absf(jump.apex - apex) <= 0.1, "jump apex near v²/2g (%.3f vs %.3f)" % [jump.apex, apex])
	Support.expect_true(absf(jump.air_time - air) <= 2.0 / 60.0, "air time near 2v/g (%.3f vs %.3f)" % [jump.air_time, air])
	quit(Support.exit_code())
