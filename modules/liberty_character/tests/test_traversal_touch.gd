extends SceneTree
const Support = preload("res://modules/liberty_character/tests/liberty_test_support.gd")
func _initialize() -> void:
	call_deferred("run")
func touch(controls: Node, index: int, position: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = position
	event.pressed = pressed
	controls._input(event)
func run() -> void:
	var character = load("res://modules/liberty_character/character/liberty_character.tscn").instantiate()
	root.add_child(character)
	var controls = character.get_node("MobileControls")
	controls.force_visible = true
	var traverse = controls.get_node_or_null("Overlay/TraverseButton")
	var drop = controls.get_node_or_null("Overlay/DropButton")
	Support.expect_true(traverse != null and drop != null, "touch traversal and drop buttons exist")
	if traverse == null or drop == null: quit(Support.exit_code()); return
	Support.expect_true(InputMap.has_action(&"liberty_touch_traverse") and InputMap.has_action(&"liberty_touch_drop"), "separate touch actions")
	touch(controls, 1, traverse.position + traverse.size/2, true)
	touch(controls, 2, controls._jump_center, true)
	Support.expect_true(Input.is_action_pressed(&"liberty_touch_traverse") and Input.is_action_pressed(&"liberty_touch_jump"), "simultaneous traverse and jump")
	Input.action_press(&"liberty_traverse")
	touch(controls, 1, traverse.position + traverse.size/2, false)
	Support.expect_false(Input.is_action_pressed(&"liberty_touch_traverse"), "touch release clears touch hold")
	Support.expect_true(Input.is_action_pressed(&"liberty_traverse"), "touch release cannot release desktop")
	await physics_frame
	touch(controls, 3, drop.position + drop.size/2, true)
	Support.expect_true(controls.consume_drop_press(), "drop edge generated")
	controls._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	Support.expect_false(Input.is_action_pressed(&"liberty_touch_drop"), "focus loss releases drop")
	Support.expect_false(Input.is_action_pressed(&"liberty_touch_jump"), "focus loss releases all action touches")
	Input.action_release(&"liberty_traverse")
	character.queue_free()
	quit(Support.exit_code())
