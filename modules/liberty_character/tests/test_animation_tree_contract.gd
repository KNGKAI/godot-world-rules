extends SceneTree

const Support = preload("res://modules/liberty_character/tests/liberty_test_support.gd")
const Driver = preload("res://modules/liberty_character/animation/liberty_animation_driver.gd")

var POINTS := PackedFloat32Array([0.0, 2.2, 5.0, 7.5])


func _initialize() -> void:
	var root := Driver.build_tree_root(&"rig/", POINTS)
	Support.expect_equal(root.state_machine_type, AnimationNodeStateMachine.STATE_MACHINE_TYPE_ROOT, "root must be a root state machine")
	for state in [Driver.STATE_LOCOMOTION, Driver.STATE_AIRBORNE, Driver.STATE_TRAVERSAL, Driver.STATE_RECOVERY]:
		Support.expect_true(root.has_node(state), "root must contain %s" % state)
	Support.expect_true(root.has_transition(&"Start", Driver.STATE_LOCOMOTION), "Start must enter Locomotion")
	Support.expect_true(root.has_transition(Driver.STATE_LOCOMOTION, Driver.STATE_AIRBORNE), "Locomotion must reach Airborne")
	Support.expect_true(root.has_transition(Driver.STATE_AIRBORNE, Driver.STATE_LOCOMOTION), "Airborne must return to Locomotion")

	for future in [Driver.STATE_TRAVERSAL, Driver.STATE_RECOVERY]:
		var placeholder := root.get_node(future) as AnimationNodeStateMachine
		Support.expect_true(placeholder != null, "%s must be a state machine placeholder" % future)
		if placeholder != null:
			Support.expect_equal(placeholder.get_node_list().size(), 2, "%s must contain only Start and End" % future)

	var full := Driver.build_tree_root(&"rig/", POINTS, true)
	var recovery := full.get_node(Driver.STATE_RECOVERY) as AnimationNodeStateMachine
	Support.expect_true(recovery.has_node(Driver.RECOVERY_FRONT) and recovery.has_node(Driver.RECOVERY_BACK), "Recovery contains both get-up states")
	Support.expect_equal((recovery.get_node(Driver.RECOVERY_FRONT) as AnimationNodeAnimation).animation, &"rig/get_up_front", "front get-up uses its exact clip")
	Support.expect_equal((recovery.get_node(Driver.RECOVERY_BACK) as AnimationNodeAnimation).animation, &"rig/get_up_back", "back get-up uses its exact clip")
	Support.expect_true(full.has_transition(Driver.STATE_RECOVERY, Driver.STATE_LOCOMOTION), "Recovery returns to Locomotion")
	Support.expect_false(full.has_transition(Driver.STATE_RECOVERY, Driver.STATE_TRAVERSAL), "Recovery never enters Traversal")

	_check_locomotion(root.get_node(Driver.STATE_LOCOMOTION) as AnimationNodeBlendTree)
	_check_airborne(root.get_node(Driver.STATE_AIRBORNE) as AnimationNodeStateMachine)
	quit(Support.exit_code())


func _check_locomotion(locomotion: AnimationNodeBlendTree) -> void:
	Support.expect_true(locomotion != null, "Locomotion must be a blend tree")
	if locomotion == null:
		return
	var blend_space := locomotion.get_node(Driver.BLEND_SPACE_NODE) as AnimationNodeBlendSpace1D
	Support.expect_true(blend_space != null, "Locomotion must contain a BlendSpace1D")
	Support.expect_true(locomotion.get_node(Driver.TIME_SCALE_NODE) is AnimationNodeTimeScale, "Locomotion must contain a TimeScale")
	Support.expect_equal(locomotion.get("node_connections"), [
		&"output", 0, Driver.TIME_SCALE_NODE,
		Driver.TIME_SCALE_NODE, 0, Driver.BLEND_SPACE_NODE,
	], "blend space must route through TimeScale to output")
	if blend_space == null:
		return
	Support.expect_equal(blend_space.sync_mode, AnimationNodeBlendSpace1D.SYNC_MODE_CYCLIC_MUTABLE, "blend space must use cyclic mutable sync")
	Support.expect_equal(blend_space.value_label, "m/s", "blend coordinates are meters per second")
	Support.expect_true(is_equal_approx(blend_space.min_space, 0.0), "blend space starts at rest")
	Support.expect_true(is_equal_approx(blend_space.max_space, 7.5), "blend space ends at sprint speed")
	Support.expect_equal(blend_space.get_blend_point_count(), 4, "blend space must have four points")
	var clips := [&"rig/idle", &"rig/walk", &"rig/run", &"rig/sprint"]
	for index in mini(blend_space.get_blend_point_count(), 4):
		Support.expect_true(is_equal_approx(blend_space.get_blend_point_position(index), POINTS[index]), "blend point %d must sit at gait speed" % index)
		var node := blend_space.get_blend_point_node(index) as AnimationNodeAnimation
		Support.expect_true(node != null and node.animation == clips[index], "blend point %d must play %s" % [index, clips[index]])


func _check_airborne(airborne: AnimationNodeStateMachine) -> void:
	Support.expect_true(airborne != null, "Airborne must be a state machine")
	if airborne == null:
		return
	Support.expect_equal(airborne.state_machine_type, AnimationNodeStateMachine.STATE_MACHINE_TYPE_NESTED, "Airborne must permit explicit Jump or Fall entry without grouped boundary mismatches")
	var clips := {Driver.AIRBORNE_JUMP: &"rig/jump", Driver.AIRBORNE_FALL: &"rig/fall", Driver.AIRBORNE_LAND: &"rig/land"}
	for state in clips:
		var node := airborne.get_node(state) as AnimationNodeAnimation if airborne.has_node(state) else null
		Support.expect_true(node != null and node.animation == clips[state], "Airborne/%s must play %s" % [state, clips[state]])
	Support.expect_true(airborne.has_transition(Driver.AIRBORNE_JUMP, Driver.AIRBORNE_FALL), "Jump must flow into Fall")
	Support.expect_true(airborne.has_transition(Driver.AIRBORNE_FALL, Driver.AIRBORNE_LAND), "Fall must reach Land")
	Support.expect_true(airborne.has_transition(Driver.AIRBORNE_JUMP, Driver.AIRBORNE_LAND), "short hops must reach Land")
