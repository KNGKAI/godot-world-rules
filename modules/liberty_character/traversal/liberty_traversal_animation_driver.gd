class_name LibertyTraversalAnimationDriver
extends Node
## Owns the nested traversal animations, not geometry or character movement.
const Controller = preload("res://modules/liberty_character/traversal/liberty_traversal_controller.gd")
const Candidate = preload("res://modules/liberty_character/traversal/liberty_traversal_candidate.gd")
const TRAVERSAL_CLIPS: Array[StringName] = [&"vault_low", &"vault_high", &"mantle_low", &"mantle_high", &"climb_enter", &"hang_idle", &"shimmy_left", &"shimmy_right", &"climb_up", &"climb_down", &"corner_inner_left", &"corner_inner_right", &"corner_outer_left", &"corner_outer_right", &"ledge_jump_up", &"ledge_jump_left", &"ledge_jump_right", &"ledge_jump_forward", &"ledge_catch", &"ledge_drop", &"climb_top_out"]
var animation_tree: AnimationTree
var animation_player: AnimationPlayer
var current_clip: StringName = &""
var configuration_error := ""
var _last_consumed_frame := -1
var _last_progress := 0.0
var _awaiting_restart := false

func configure(tree: AnimationTree) -> void:
	animation_tree = tree
	animation_player = tree.get_node_or_null(tree.anim_player) as AnimationPlayer
	var missing := missing_required_clips()
	if not missing.is_empty():
		configuration_error = "Missing traversal clips: " + ", ".join(missing)
		return
	if not tree.tree_root is AnimationNodeStateMachine:
		configuration_error = "Missing animation state machine foundation"
		return
	var nested := AnimationNodeStateMachine.new()
	nested.state_machine_type = AnimationNodeStateMachine.STATE_MACHINE_TYPE_NESTED
	for clip in TRAVERSAL_CLIPS:
		var node := AnimationNodeAnimation.new()
		node.animation = clip
		nested.add_node(clip, node)
	nested.add_transition(&"Start", &"hang_idle", _transition(0.0))
	for clip in TRAVERSAL_CLIPS:
		if clip == &"hang_idle":
			continue
		nested.add_transition(&"hang_idle", clip, _transition(0.15))
		var finish := _transition(0.15)
		finish.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_AT_END if animation_player.get_animation(clip).loop_mode == Animation.LOOP_NONE else AnimationNodeStateMachineTransition.SWITCH_MODE_IMMEDIATE
		nested.add_transition(clip, &"hang_idle", finish)
	for from_clip in TRAVERSAL_CLIPS:
		if animation_player.get_animation(from_clip).loop_mode == Animation.LOOP_NONE: continue
		for to_clip in TRAVERSAL_CLIPS:
			if from_clip != to_clip and to_clip != &"hang_idle" and from_clip != &"hang_idle" and animation_player.get_animation(to_clip).loop_mode != Animation.LOOP_NONE:
				nested.add_transition(from_clip, to_clip, _transition(0.15))
	var root := tree.tree_root as AnimationNodeStateMachine
	root.replace_node(&"Traversal", nested)
	for state in [&"Locomotion", &"Airborne"]:
		if not root.has_transition(state, &"Traversal"):
			root.add_transition(state, &"Traversal", _transition(0.15))
		if not root.has_transition(&"Traversal", state):
			root.add_transition(&"Traversal", state, _transition(0.15))
	tree.root_motion_track = NodePath("Skeleton3D:Root")

func missing_required_clips() -> PackedStringArray:
	var missing := PackedStringArray()
	for clip in TRAVERSAL_CLIPS:
		if animation_player == null or not animation_player.has_animation(clip):
			missing.append(String(clip))
	return missing

func get_authored_terminal(clip: StringName) -> Transform3D:
	return sample_authored_root(clip, animation_player.get_animation(clip).length)

func sample_authored_root(clip: StringName, time: float) -> Transform3D:
	var result := Transform3D.IDENTITY
	if animation_player == null or not animation_player.has_animation(clip):
		return result
	var animation := animation_player.get_animation(clip)
	for track in animation.get_track_count():
		if not String(animation.track_get_path(track)).ends_with(":Root"):
			continue
		match animation.track_get_type(track):
			Animation.TYPE_POSITION_3D: result.origin = animation.position_track_interpolate(track, time)
			Animation.TYPE_ROTATION_3D: result.basis = Basis(animation.rotation_track_interpolate(track, time))
	return result

func select_clip(candidate: LibertyTraversalCandidate, from_hold: bool) -> StringName:
	var travel := candidate.source_transform.affine_inverse() * candidate.destination_transform
	match candidate.kind:
		Candidate.Kind.HANG: return &"hang_idle" if from_hold else &"climb_enter"
		Candidate.Kind.AIR_CATCH: return &"ledge_catch"
		Candidate.Kind.SHIMMY: return &"shimmy_left" if travel.origin.x > 0 else &"shimmy_right"
		Candidate.Kind.CLIMB: return &"climb_up" if travel.origin.y > 0 else &"climb_down"
		Candidate.Kind.MANTLE:
			if from_hold: return &"climb_top_out"
			return _best_fit(candidate, [&"mantle_low", &"mantle_high"])
		Candidate.Kind.VAULT: return _best_fit(candidate, [&"vault_low", &"vault_high"])
		Candidate.Kind.INNER_CORNER: return _best_fit(candidate, [&"corner_inner_left", &"corner_inner_right"])
		Candidate.Kind.OUTER_CORNER: return _best_fit(candidate, [&"corner_outer_left", &"corner_outer_right"])
		Candidate.Kind.LEDGE_JUMP: return _best_fit(candidate, [&"ledge_jump_up", &"ledge_jump_left", &"ledge_jump_right", &"ledge_jump_forward"])
		Candidate.Kind.DROP: return &"ledge_drop"
	return &""

func _best_fit(candidate: LibertyTraversalCandidate, clips: Array[StringName]) -> StringName:
	var best: StringName = &""
	var best_score := INF
	for clip in clips:
		var terminal := candidate.source_transform * get_authored_terminal(clip)
		var angle := absf(wrapf(candidate.destination_transform.basis.get_euler().y - terminal.basis.get_euler().y, -PI, PI))
		var score := terminal.origin.distance_to(candidate.destination_transform.origin) + angle
		# Both vault clips land at ground height; obstacle height selects the arc.
		if candidate.kind == Candidate.Kind.VAULT:
			var height := candidate.contact_point.y - candidate.source_transform.origin.y
			score += absf(height - (0.65 if clip == &"vault_low" else 1.05)) * 3.0
		if score < best_score:
			best_score = score
			best = clip
	return best

func play_clip(clip: StringName) -> bool:
	if animation_tree == null or not missing_required_clips().is_empty() or clip not in TRAVERSAL_CLIPS:
		return false
	var root := animation_tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
	var nested := animation_tree.get("parameters/Traversal/playback") as AnimationNodeStateMachinePlayback
	if root.get_current_node() != &"Traversal":
		root.start(&"Traversal", false)
	if current_clip != &"" and is_looping() and animation_player.get_animation(clip).loop_mode != Animation.LOOP_NONE:
		nested.travel(clip)
	else:
		nested.start(clip)
	current_clip = clip
	_awaiting_restart = animation_player.get_animation(clip).loop_mode == Animation.LOOP_NONE
	_last_progress = 0.0
	return true

func travel_to(state: Controller.State, candidate: LibertyTraversalCandidate = null, from_hold: bool = false) -> bool:
	if candidate != null:
		return play_clip(select_clip(candidate, from_hold))
	if state == Controller.State.HANG:
		return play_clip(&"hang_idle")
	if state == Controller.State.DROP:
		return play_clip(&"ledge_drop")
	return false

func get_root_motion_delta() -> Transform3D:
	var frame := Engine.get_physics_frames()
	if animation_tree == null or frame == _last_consumed_frame:
		return Transform3D.IDENTITY
	_last_consumed_frame = frame
	return Transform3D(Basis(animation_tree.get_root_motion_rotation()), animation_tree.get_root_motion_position())

func get_action_progress() -> float:
	if current_clip == &"" or animation_tree == null:
		return 0.0
	var nested := animation_tree.get("parameters/Traversal/playback") as AnimationNodeStateMachinePlayback
	if nested.get_current_node() != current_clip:
		return _last_progress
	var length := animation_player.get_animation(current_clip).length
	if _awaiting_restart:
		# start() is queued: repeated clips may still expose the previous end time
		# until the tree evaluates. Never finish a new action from that old time.
		if nested.get_current_play_position() > length * 0.5: return 0.0
		_awaiting_restart = false
	_last_progress = maxf(_last_progress, clampf(nested.get_current_play_position() / length, 0.0, 1.0))
	return _last_progress

func is_looping() -> bool:
	return current_clip != &"" and animation_player.get_animation(current_clip).loop_mode != Animation.LOOP_NONE

func leave_traversal(falling: bool) -> void:
	current_clip = &""
	_last_progress = 0.0
	if animation_tree == null:
		return
	var root := animation_tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
	if root == null: return
	root.start(&"Airborne" if falling else &"Locomotion")
	if falling:
		var airborne := animation_tree.get("parameters/Airborne/playback") as AnimationNodeStateMachinePlayback
		airborne.start(&"Fall")
	current_clip = &""
	_last_progress = 0.0

static func _transition(fade: float) -> AnimationNodeStateMachineTransition:
	var transition := AnimationNodeStateMachineTransition.new()
	transition.xfade_time = fade
	return transition
