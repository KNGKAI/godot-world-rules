class_name LibertyAnimationDriver
extends Node

## Reads LibertyCharacter speed and movement state and drives the AnimationTree.
## Animation decisions live here so LibertyCharacter stays animation-agnostic.

const STATE_LOCOMOTION := &"Locomotion"
const STATE_AIRBORNE := &"Airborne"
const STATE_TRAVERSAL := &"Traversal"
const STATE_RECOVERY := &"Recovery"
const STATE_PERFORMANCE := &"Performance"
const AIRBORNE_JUMP := &"Jump"
const AIRBORNE_FALL := &"Fall"
const AIRBORNE_LAND := &"Land"
const RECOVERY_FRONT := &"GetUpFront"
const RECOVERY_BACK := &"GetUpBack"
const RECOVERY_CLIPS := {RECOVERY_FRONT: &"get_up_front", RECOVERY_BACK: &"get_up_back"}
const BLEND_SPACE_NODE := &"BlendSpace1D"
const TIME_SCALE_NODE := &"TimeScale"

const PLAYBACK_PARAMETER := &"parameters/playback"
const BLEND_POSITION_PARAMETER := &"parameters/Locomotion/BlendSpace1D/blend_position"
const TIME_SCALE_PARAMETER := &"parameters/Locomotion/TimeScale/scale"

const LOCOMOTION_CLIPS: Array[StringName] = [&"idle", &"walk", &"run", &"sprint"]
const MIN_EFFECTIVE_AUTHORED_SPEED := 0.01
const TRANSITION_XFADE := 0.15

@export var character_path: NodePath = ^".."
@export var animation_tree_path: NodePath = ^""
@export var events_path: NodePath = ^"../Events"
## Prefix prepended to every clip name, such as the imported library name ("rig/").
@export var clip_prefix: StringName = &""

@export_group("Authored Clip Speeds")
## Backward stance-foot speed as authored in m/s; in-place root speed is zero.
@export_range(0.0, 20.0, 0.01, "or_greater") var idle_authored_speed := 0.0
@export_range(0.0, 20.0, 0.01, "or_greater") var walk_authored_speed := 2.2
@export_range(0.0, 20.0, 0.01, "or_greater") var run_authored_speed := 5.0
@export_range(0.0, 20.0, 0.01, "or_greater") var sprint_authored_speed := 7.5

var _character: LibertyCharacter
var _tree: AnimationTree
var _blend_points := PackedFloat32Array()
var _airborne := false
var _landing_pending := false
var _landing := false
var _was_locked := false
## An owned visual traversal clip may continue after physical release.
var traversal_animation_owned := false
## Full-body performance skips _update_state until stop_performance.
var performance_animation_owned := false
var _performance_animation: AnimationNodeAnimation
## Empty for a valid setup; otherwise names the reason animation was disabled.
var configuration_error := ""


func _ready() -> void:
	_character = get_node_or_null(character_path) as LibertyCharacter
	if not animation_tree_path.is_empty():
		_tree = get_node_or_null(animation_tree_path) as AnimationTree
	if _tree != null:
		_tree.active = false
	if _character == null or _tree == null:
		configuration_error = "Missing character or AnimationTree"
		set_physics_process(false)
		return
	var player := _tree.get_node_or_null(_tree.anim_player) as AnimationPlayer
	var missing := PackedStringArray()
	for clip in [&"idle", &"walk", &"run", &"sprint", &"jump", &"fall", &"land"]:
		var key := StringName(String(clip_prefix) + String(clip))
		if player == null or not player.has_animation(key):
			missing.append(String(key))
	if not missing.is_empty():
		configuration_error = "Missing required animation clips: " + ", ".join(missing)
		push_warning(configuration_error)
		set_physics_process(false)
		return
	if not (0.0 < _character.walk_speed and _character.walk_speed < _character.run_speed and _character.run_speed < _character.sprint_speed):
		configuration_error = "Gait speeds must be positive and strictly increasing"
		push_warning(configuration_error)
		set_physics_process(false)
		return

	_blend_points = PackedFloat32Array([
		0.0,
		_character.walk_speed,
		_character.run_speed,
		_character.sprint_speed,
	])
	if _tree.tree_root == null:
		_tree.tree_root = build_tree_root(clip_prefix, _blend_points, _has_clips(player, RECOVERY_CLIPS.values()))
	var machine := _tree.tree_root as AnimationNodeStateMachine
	if machine != null and machine.has_node(STATE_PERFORMANCE):
		_performance_animation = machine.get_node(STATE_PERFORMANCE) as AnimationNodeAnimation
	_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS
	# Character moves first, the driver reads it, then the tree evaluates.
	process_physics_priority = _character.process_physics_priority + 1
	_tree.process_physics_priority = process_physics_priority + 1
	var skeleton := _character.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton != null:
		skeleton.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_PHYSICS
		skeleton.process_physics_priority = _tree.process_physics_priority + 1
	_tree.active = true

	var events := get_node_or_null(events_path) as LibertyEvents
	if events != null:
		events.landed.connect(_on_landed)


func _physics_process(delta: float) -> void:
	var speed := _character.planar_speed
	_tree.set(BLEND_POSITION_PARAMETER, clampf(speed, 0.0, _blend_points[_blend_points.size() - 1]))
	_tree.set(TIME_SCALE_PARAMETER, compute_time_scale(speed, _blend_points, get_authored_speeds()))
	if not traversal_animation_owned and not performance_animation_owned:
		_update_state(delta)


func _has_clips(player: AnimationPlayer, clips: Array) -> bool:
	for clip: StringName in clips:
		if player == null or not player.has_animation(StringName(String(clip_prefix) + String(clip))):
			return false
	return true


## True when the tree contains the Phase 6 get-up states.
func has_recovery() -> bool:
	if _tree == null or not _tree.tree_root is AnimationNodeStateMachine:
		return false
	var recovery := (_tree.tree_root as AnimationNodeStateMachine).get_node(STATE_RECOVERY) as AnimationNodeStateMachine
	return recovery != null and recovery.has_node(RECOVERY_FRONT) and recovery.has_node(RECOVERY_BACK)


## Owned ragdoll command: start the matching get-up immediately; physical influence hides the cut.
func play_recovery(face_up: bool) -> bool:
	if configuration_error != "" or not has_recovery():
		return false
	var playback := get_playback()
	var nested := _tree.get("parameters/Recovery/playback") as AnimationNodeStateMachinePlayback
	_airborne = false
	_landing_pending = false
	_landing = false
	traversal_animation_owned = false
	playback.start(STATE_RECOVERY)
	nested.start(RECOVERY_BACK if face_up else RECOVERY_FRONT)
	return true


## Full-body in-place clip. Missing clip, traversal lock, and traversal ownership return false.
func play_performance(clip: StringName) -> bool:
	if configuration_error != "" or clip.is_empty():
		return false
	if _character != null and (_character.is_traversal_locked() or traversal_animation_owned):
		return false
	var key := StringName(String(clip_prefix) + String(clip))
	var player: AnimationPlayer = null
	if _tree != null:
		player = _tree.get_node_or_null(_tree.anim_player) as AnimationPlayer
	if player == null or not player.has_animation(key):
		return false
	if _performance_animation == null or get_playback() == null:
		return false
	_performance_animation.animation = key
	performance_animation_owned = true
	get_playback().start(STATE_PERFORMANCE)
	return true


## Leaves Performance. A still-locked body latches _was_locked and does not travel.
func stop_performance() -> void:
	if not performance_animation_owned:
		return
	performance_animation_owned = false
	if _character != null and _character.is_movement_locked():
		# The owned flag skipped _update_state, so the lock branch never latched this.
		_was_locked = true
		return
	if _character != null and not _character.is_on_floor():
		_travel(_airborne_path(AIRBORNE_FALL))
	else:
		_travel(STATE_LOCOMOTION)


func is_performance_playing() -> bool:
	return performance_animation_owned


## Normalized progress of the active get-up clip; 0 outside Recovery.
func get_recovery_progress() -> float:
	var playback := get_playback()
	if playback == null or playback.get_current_node() != STATE_RECOVERY:
		return 0.0
	var nested := _tree.get("parameters/Recovery/playback") as AnimationNodeStateMachinePlayback
	var clip: StringName = RECOVERY_CLIPS.get(nested.get_current_node(), &"")
	var length := _clip_length(clip)
	if length <= 0.0:
		return 0.0
	return clampf(nested.get_current_play_position() / length, 0.0, 1.0)


## Authored local pose of a bone track at time, from the imported clip data.
func sample_bone_pose(clip: StringName, bone: StringName, time: float) -> Transform3D:
	var result := Transform3D.IDENTITY
	var animation := _tree.get_animation(StringName(String(clip_prefix) + String(clip))) if _tree != null else null
	if animation == null:
		return result
	var suffix := ":" + String(bone)
	for track in animation.get_track_count():
		if not String(animation.track_get_path(track)).ends_with(suffix):
			continue
		match animation.track_get_type(track):
			Animation.TYPE_POSITION_3D: result.origin = animation.position_track_interpolate(track, time)
			Animation.TYPE_ROTATION_3D: result.basis = Basis(animation.rotation_track_interpolate(track, time))
	return result


func get_playback() -> AnimationNodeStateMachinePlayback:
	if _tree == null:
		return null
	return _tree.get(PLAYBACK_PARAMETER) as AnimationNodeStateMachinePlayback


func get_authored_speeds() -> PackedFloat32Array:
	return PackedFloat32Array([
		idle_authored_speed,
		walk_authored_speed,
		run_authored_speed,
		sprint_authored_speed,
	])


func _update_state(delta: float) -> void:
	if _character.movement_state == LibertyCharacter.MovementState.MOVEMENT_LOCKED:
		_was_locked = true
		return
	if _was_locked:
		_was_locked = false
		_airborne = false
		_landing_pending = false
		_landing = false
		if _character.movement_state != LibertyCharacter.MovementState.AIRBORNE:
			_travel(STATE_LOCOMOTION)
	match _character.movement_state:
		LibertyCharacter.MovementState.AIRBORNE:
			_landing_pending = false
			_landing = false
			if not _airborne:
				_airborne = true
				var clip := AIRBORNE_JUMP if _character.velocity.y > 0.0 else AIRBORNE_FALL
				_travel(_airborne_path(clip))
			elif get_state() == _airborne_path(AIRBORNE_JUMP):
				var playback := _tree.get("parameters/Airborne/playback") as AnimationNodeStateMachinePlayback
				if _character.velocity.y <= 0.0 or playback.get_current_play_position() >= _clip_length(&"jump") - delta * 0.5:
					_travel(_airborne_path(AIRBORNE_FALL))
		_:
			if _airborne:
				_airborne = false
				if _landing_pending:
					_landing_pending = false
					_landing = true
					_travel(_airborne_path(AIRBORNE_LAND))
				else:
					_travel(STATE_LOCOMOTION)
			elif _landing:
				var playback := _tree.get("parameters/Airborne/playback") as AnimationNodeStateMachinePlayback
				if playback.get_current_node() == AIRBORNE_LAND and playback.get_current_play_position() >= _clip_length(&"land") - delta * 0.5:
					_landing = false
					_travel(STATE_LOCOMOTION)


## Current state path for diagnostics and later owned animation components.
func get_state() -> StringName:
	var playback := get_playback()
	if playback == null:
		return &""
	var state := playback.get_current_node()
	if state == STATE_AIRBORNE:
		var nested := _tree.get("parameters/Airborne/playback") as AnimationNodeStateMachinePlayback
		return _airborne_path(nested.get_current_node())
	return state


func _on_landed(_impact_speed: float) -> void:
	_landing_pending = true


func _travel(state: StringName) -> void:
	var playback := get_playback()
	if playback == null:
		return
	if String(state).begins_with("Airborne/"):
		var nested := _tree.get("parameters/Airborne/playback") as AnimationNodeStateMachinePlayback
		var clip := StringName(String(state).get_slice("/", 1))
		if playback.get_current_node() != STATE_AIRBORNE:
			if playback.get_fading_from_node() == STATE_AIRBORNE:
				# Reenter immediately instead of queuing behind the parent exit fade.
				playback.start(STATE_AIRBORNE)
			else:
				playback.travel(STATE_AIRBORNE)
			nested.start(clip)
		elif clip == AIRBORNE_JUMP:
			# A new takeoff interrupts even an unfinished landing crossfade.
			nested.start(clip)
		else:
			nested.travel(clip)
	else:
		playback.travel(state)


func _clip_length(clip: StringName) -> float:
	var animation := _tree.get_animation(StringName(String(clip_prefix) + String(clip)))
	return animation.length if animation != null else 0.0


static func _airborne_path(clip: StringName) -> StringName:
	return StringName("%s/%s" % [STATE_AIRBORNE, clip])


## Builds the Phase 3 state machine. Blend coordinates are character gait speeds in m/s.
static func build_tree_root(prefix: StringName, blend_points: PackedFloat32Array, include_recovery: bool = false) -> AnimationNodeStateMachine:
	var root := AnimationNodeStateMachine.new()
	root.state_machine_type = AnimationNodeStateMachine.STATE_MACHINE_TYPE_ROOT
	root.add_node(STATE_LOCOMOTION, _build_locomotion(prefix, blend_points), Vector2(200.0, 0.0))
	root.add_node(STATE_AIRBORNE, _build_airborne(prefix), Vector2(400.0, 0.0))
	# Future phases fill these; they carry no behavior yet.
	root.add_node(STATE_TRAVERSAL, AnimationNodeStateMachine.new(), Vector2(200.0, 200.0))
	root.add_node(STATE_RECOVERY, _build_recovery(prefix) if include_recovery else AnimationNodeStateMachine.new(), Vector2(400.0, 200.0))
	var performance := AnimationNodeAnimation.new()
	root.add_node(STATE_PERFORMANCE, performance, Vector2(600.0, 0.0))
	root.add_transition(&"Start", STATE_LOCOMOTION, _transition(0.0, true))
	root.add_transition(STATE_LOCOMOTION, STATE_AIRBORNE, _transition(TRANSITION_XFADE))
	root.add_transition(STATE_AIRBORNE, STATE_LOCOMOTION, _transition(TRANSITION_XFADE))
	# Entered with playback.start(). Direct exits so travel() does not walk through Locomotion to reach Fall.
	root.add_transition(STATE_PERFORMANCE, STATE_LOCOMOTION, _transition(TRANSITION_XFADE))
	root.add_transition(STATE_PERFORMANCE, STATE_AIRBORNE, _transition(TRANSITION_XFADE))
	if include_recovery:
		# Recovery is entered with playback.start(); it only ever leaves to Locomotion.
		root.add_transition(STATE_RECOVERY, STATE_LOCOMOTION, _transition(TRANSITION_XFADE))
	return root


static func _build_recovery(prefix: StringName) -> AnimationNodeStateMachine:
	var recovery := AnimationNodeStateMachine.new()
	recovery.state_machine_type = AnimationNodeStateMachine.STATE_MACHINE_TYPE_NESTED
	recovery.add_node(RECOVERY_FRONT, _clip(prefix, RECOVERY_CLIPS[RECOVERY_FRONT]), Vector2(200.0, 0.0))
	recovery.add_node(RECOVERY_BACK, _clip(prefix, RECOVERY_CLIPS[RECOVERY_BACK]), Vector2(200.0, 100.0))
	recovery.add_transition(&"Start", RECOVERY_FRONT, _transition(0.0))
	recovery.add_transition(&"Start", RECOVERY_BACK, _transition(0.0))
	return recovery


static func _build_locomotion(prefix: StringName, blend_points: PackedFloat32Array) -> AnimationNodeBlendTree:
	var blend_space := AnimationNodeBlendSpace1D.new()
	blend_space.min_space = 0.0
	blend_space.max_space = blend_points[blend_points.size() - 1]
	blend_space.value_label = "m/s"
	blend_space.sync_mode = AnimationNodeBlendSpace1D.SYNC_MODE_CYCLIC_MUTABLE
	for index in LOCOMOTION_CLIPS.size():
		blend_space.add_blend_point(_clip(prefix, LOCOMOTION_CLIPS[index]), blend_points[index], -1, LOCOMOTION_CLIPS[index])

	var blend_tree := AnimationNodeBlendTree.new()
	blend_tree.add_node(BLEND_SPACE_NODE, blend_space, Vector2(0.0, 0.0))
	blend_tree.add_node(TIME_SCALE_NODE, AnimationNodeTimeScale.new(), Vector2(250.0, 0.0))
	blend_tree.connect_node(TIME_SCALE_NODE, 0, BLEND_SPACE_NODE)
	blend_tree.connect_node(&"output", 0, TIME_SCALE_NODE)
	return blend_tree


static func _build_airborne(prefix: StringName) -> AnimationNodeStateMachine:
	var airborne := AnimationNodeStateMachine.new()
	airborne.state_machine_type = AnimationNodeStateMachine.STATE_MACHINE_TYPE_NESTED
	airborne.add_node(AIRBORNE_JUMP, _clip(prefix, &"jump"), Vector2(200.0, 0.0))
	airborne.add_node(AIRBORNE_FALL, _clip(prefix, &"fall"), Vector2(400.0, 0.0))
	airborne.add_node(AIRBORNE_LAND, _clip(prefix, &"land"), Vector2(600.0, 0.0))
	airborne.add_transition(&"Start", AIRBORNE_FALL, _transition(0.0, true))
	airborne.add_transition(&"Start", AIRBORNE_JUMP, _transition(0.0))
	airborne.add_transition(&"Start", AIRBORNE_LAND, _transition(0.0))
	# Driver requests this at the apex or clip completion, whichever occurs first.
	airborne.add_transition(AIRBORNE_JUMP, AIRBORNE_FALL, _transition(TRANSITION_XFADE))
	airborne.add_transition(AIRBORNE_JUMP, AIRBORNE_LAND, _transition(0.1))
	airborne.add_transition(AIRBORNE_FALL, AIRBORNE_LAND, _transition(0.1))
	airborne.add_transition(AIRBORNE_LAND, AIRBORNE_JUMP, _transition(0.1))
	airborne.add_transition(AIRBORNE_LAND, AIRBORNE_FALL, _transition(TRANSITION_XFADE))
	return airborne


static func _clip(prefix: StringName, clip: StringName) -> AnimationNodeAnimation:
	var node := AnimationNodeAnimation.new()
	node.animation = StringName(String(prefix) + String(clip))
	return node


static func _transition(xfade: float, auto: bool = false) -> AnimationNodeStateMachineTransition:
	var transition := AnimationNodeStateMachineTransition.new()
	transition.xfade_time = xfade
	if auto:
		transition.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO
	return transition


## Returns actual_speed / effective_authored_speed, where the effective speed blends the
## authored speeds of the two neighboring blend points by their linear blend weights.
static func compute_time_scale(
	speed: float,
	points: PackedFloat32Array,
	authored: PackedFloat32Array
) -> float:
	if points.is_empty() or points.size() != authored.size() or speed <= 0.0:
		return 1.0
	var effective := authored[authored.size() - 1]
	if speed <= points[0]:
		effective = authored[0]
	else:
		for index in range(1, points.size()):
			if speed <= points[index]:
				var span := points[index] - points[index - 1]
				var weight := 1.0 if span <= 0.0 else (speed - points[index - 1]) / span
				effective = lerpf(authored[index - 1], authored[index], weight)
				break
	if effective < MIN_EFFECTIVE_AUTHORED_SPEED:
		return 1.0
	return speed / effective
