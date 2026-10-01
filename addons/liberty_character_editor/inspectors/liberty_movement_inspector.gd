@tool
extends EditorInspectorPlugin
## LibertyCharacter: read-only movement figures derived from the exports being edited (95% top
## speed time, stopping distance, 180° turn radius, jump apex and air time).

const Metrics = preload("res://addons/liberty_character_editor/core/liberty_movement_metrics.gd")
const CHARACTER = preload("res://modules/liberty_character/character/liberty_character.gd")


func _can_handle(object: Object) -> bool:
	return object is Node and object.get_script() == CHARACTER


func _parse_begin(object: Object) -> void:
	var panel := MetricsPanel.new()
	panel.name = "LibertyMovementMetrics"
	panel.target = object
	add_custom_control(panel)


class MetricsPanel extends VBoxContainer:
	const Metrics = preload("res://addons/liberty_character_editor/core/liberty_movement_metrics.gd")
	const INPUTS: Array[String] = ["walk_speed", "run_speed", "sprint_speed", "ground_acceleration",
		"ground_deceleration", "grounded_turn_rate_degrees", "high_speed_turn_rate_degrees", "gravity", "jump_velocity"]

	var target: Object
	var summary := {}
	var _signature := []
	var _grid := GridContainer.new()
	var _jump := Label.new()

	func _ready() -> void:
		var heading := Label.new()
		heading.text = "Derived movement (%d Hz flat-ground model)" % Engine.physics_ticks_per_second
		heading.add_theme_font_size_override(&"font_size", 15)
		add_child(heading)
		_grid.columns = 4
		add_child(_grid)
		add_child(_jump)
		var timer := Timer.new()
		timer.wait_time = 0.25
		timer.autostart = true
		timer.timeout.connect(_update)
		add_child(timer)
		_update()

	## Recomputes only when an input export changed (edits, undo and redo alike).
	func _update() -> void:
		if not is_instance_valid(target):
			return
		var values := {}
		var signature := []
		for name in INPUTS:
			values[name] = float(target.get(name))
			signature.append(values[name])
		if signature == _signature:
			return
		_signature = signature
		summary = Metrics.summarize(values)
		for child in _grid.get_children():
			child.queue_free()
		for text in ["Gait", "95% speed", "Stop", "180° turn r"]:
			_cell(text, Color(1, 1, 1, 0.65))
		for gait in Metrics.GAITS:
			var figures: Dictionary = summary[gait]
			_cell(String(gait).capitalize(), Color.WHITE)
			_cell("%.3f s" % figures.top, Color.WHITE)
			_cell("%.3f m" % figures.stop, Color.WHITE)
			_cell("%.3f m" % figures.turn, Color.WHITE)
		_jump.text = "Jump apex %.2f m, air time %.2f s" % [summary.jump.apex, summary.jump.air_time]

	func _cell(text: String, color: Color) -> void:
		var label := Label.new()
		label.text = text
		label.modulate = color
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_grid.add_child(label)
