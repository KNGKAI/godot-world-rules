class_name LibertyTraversalCoordinator
extends Node3D
## Owned orchestration: intent before animation, motion through character, then IK.
const Candidate = preload("res://modules/liberty_character/traversal/liberty_traversal_candidate.gd")
const Probe = preload("res://modules/liberty_character/traversal/liberty_traversal_probe.gd")
const Solver = preload("res://modules/liberty_character/traversal/liberty_traversal_solver.gd")
const Controller = preload("res://modules/liberty_character/traversal/liberty_traversal_controller.gd")
const Motor = preload("res://modules/liberty_character/traversal/liberty_traversal_motor.gd")
const AnimationDriver = preload("res://modules/liberty_character/traversal/liberty_traversal_animation_driver.gd")
const IK = preload("res://modules/liberty_character/traversal/liberty_traversal_ik_modifier.gd")
const Debug = preload("res://modules/liberty_character/traversal/liberty_traversal_debug.gd")
const Capture = preload("res://modules/liberty_character/ragdoll/liberty_pose_capture_modifier.gd")
@export var enabled := true
@export var debug_traversal := false
var character: LibertyCharacter
var probe: LibertyTraversalProbe
var solver: LibertyTraversalSolver
var controller: LibertyTraversalController
var motor: LibertyTraversalMotor
var animation: LibertyTraversalAnimationDriver
var ik: LibertyTraversalIKModifier
var pose_capture: LibertyPoseCaptureModifier
var observations: Array[LibertyTraversalCandidate] = []
var debug_view: Debug
var _support_observed := true
var configuration_error := ""
var _action_active := false
var _action_kind: StringName = &""
var _previous_progress := 0.0
var _previous_state: Controller.State = Controller.State.GROUNDED
var _reentry_time := 0.0
var _support_transform := Transform3D.IDENTITY
var _interaction_open := false
var _drop_visual := false

func _ready() -> void:
	character = get_parent() as LibertyCharacter
	if character == null:
		set_physics_process(false)
		return
	process_physics_priority = -30
	character.traversal_coordinator = self
	LibertySettings.apply(&"coordinator", self)
	probe = Probe.new()
	probe.name = "Probe"
	probe.character_body = character
	LibertySettings.apply(&"probe", probe)
	add_child(probe)
	solver = Solver.new()
	LibertySettings.apply(&"solver", solver)
	add_child(solver)
	controller = Controller.new()
	controller.events = character.get_node_or_null(character.events_path) as LibertyEvents
	LibertySettings.apply(&"controller", controller)
	add_child(controller)
	motor = Motor.new()
	LibertySettings.apply(&"motor", motor)
	add_child(motor)
	animation = AnimationDriver.new()
	add_child(animation)
	var tree := character.get_node_or_null("AnimationTree") as AnimationTree
	if tree == null:
		configuration_error = "Missing AnimationTree"
		set_physics_process(false)
		return
	animation.configure(tree)
	configuration_error = animation.configuration_error
	if configuration_error != "":
		push_warning(configuration_error)
		set_physics_process(false)
		return
	var skeleton := character.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null:
		configuration_error = "Missing Skeleton3D"
		set_physics_process(false)
		return
	ik = IK.new()
	ik.name = "TraversalTargets"
	LibertySettings.apply(&"ik", ik)
	skeleton.add_child(ik)
	if not ik.configure(skeleton):
		configuration_error = ik.configuration_error
		set_physics_process(false)
		return
	var look := LookAtModifier3D.new()
	look.name = "HeadLookAt"
	look.active = false
	skeleton.add_child(look)
	pose_capture = Capture.new()
	pose_capture.name = "PoseCapture"
	skeleton.add_child(pose_capture)
	var simulator := PhysicalBoneSimulator3D.new()
	simulator.name = "PhysicalBoneSimulator"
	simulator.active = false
	skeleton.add_child(simulator)
	skeleton.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_PHYSICS
	debug_view = Debug.new()
	debug_view.name = "Debug"
	add_child(debug_view)
	# Normal locomotion retains its existing priorities; traversal uses current-tick roots.

func _physics_process(delta: float) -> void:
	probe.capture_debug = debug_traversal
	if debug_view != null:
		debug_view.draw(probe, observations, controller.selected_candidate, motor.candidate.destination_transform if motor.candidate != null else character.global_transform, debug_traversal)
	_reentry_time = maxf(0.0, _reentry_time - delta)
	if not enabled:
		if character.is_traversal_locked() or _drop_visual: interrupt(&"disabled")
		return
	if _drop_visual:
		if animation.get_action_progress() >= 1.0 - 0.00001 or character.is_on_floor():
			_drop_visual = false
			character.get_node("AnimationDriver").traversal_animation_owned = false
			animation.leave_traversal(not character.is_on_floor())
		else:
			return
	var direction := character.get_world_input_direction()
	var traverse := Input.is_action_pressed(&"liberty_traverse") or _touch_pressed(&"liberty_touch_traverse")
	var jump := Input.is_action_just_pressed(&"liberty_jump") or Input.is_action_just_pressed(&"liberty_touch_jump")
	var mobile := character.get_node_or_null("MobileControls") as LibertyMobileControls
	var touch_drop := mobile.consume_drop_press() if mobile != null else false
	var drop := Input.is_action_just_pressed(&"liberty_drop") or touch_drop or _touch_just_pressed(&"liberty_touch_drop")
	if (character.is_movement_locked() or character.has_scripted_locomotion()) and not character.is_traversal_locked():
		return
	if _reentry_time > 0 and not character.is_traversal_locked():
		return
	if _action_active:
		controller.update_intent(null, traverse, jump, drop, character.is_on_floor(), Vector3.ZERO, character.velocity, delta)
		if not controller.movement_locked:
			interrupt(&"drop" if drop else &"lost_support")
		return
	observations = probe.sample(character.global_transform, character.is_on_floor(), character.is_traversal_locked())
	var from_hold := character.is_traversal_locked()
	var occupied := _occupied_hold()
	_support_observed = not from_hold or occupied != null or probe.confirm_support(controller.selected_candidate)
	var eligible := controller.filter_candidates(observations, character.is_on_floor(), jump, direction)
	var selected := solver.choose(eligible, direction, delta)
	controller.update_intent(selected, traverse, jump, drop, character.is_on_floor(), direction, character.velocity, delta, _support_observed)
	if from_hold and _support_observed and controller.state == Controller.State.HANG and occupied != null:
		controller.settle_hold(occupied)
	if from_hold and not controller.movement_locked:
		interrupt(&"drop" if drop else &"lost_support")
		return
	if not controller.movement_locked:
		return
	if controller.state in [Controller.State.SHIMMY, Controller.State.VERTICAL_CLIMB, Controller.State.HANG] and from_hold:
		var clip := animation.select_clip(controller.selected_candidate, true)
		if controller.state == Controller.State.HANG: clip = &"hang_idle"
		if animation.current_clip != clip: animation.play_clip(clip)
		ik.set_candidate(controller.selected_candidate)
	elif controller.selected_candidate != null:
		if not begin_action(controller.selected_candidate, from_hold):
			interrupt(&"invalid_action")

## Starts only a fully calibrated, live action; useful to owned interaction callers too.
func begin_action(value: LibertyTraversalCandidate, from_hold: bool) -> bool:
	if value == null or not value.is_valid() or not value.has_live_static_collider() or configuration_error != "":
		return false
	_drop_visual = false
	character.get_node("AnimationDriver").traversal_animation_owned = false
	var action := value.duplicate_candidate()
	action.source_transform = character.global_transform
	var clip := animation.select_clip(action, from_hold)
	if clip == &"" or not motor.prepare_action(action, animation.get_authored_terminal(clip)):
		return false
	if not animation.play_clip(clip):
		motor.clear()
		return false
	var state := _state_for_kind(action.kind)
	controller._accept(action, state)
	character.set_traversal_lock(true)
	_set_traversal_priorities(true)
	_action_active = true
	_action_kind = clip
	_previous_progress = 0.0
	_support_transform = (instance_from_id(action.collider_instance_id) as Node3D).global_transform
	_interaction_open = true
	controller.events.interaction_started.emit(clip)
	# Discrete obstacle clips own hand motion; persistent holds use procedural contacts.
	if action.kind in [Candidate.Kind.HANG, Candidate.Kind.AIR_CATCH, Candidate.Kind.INNER_CORNER, Candidate.Kind.OUTER_CORNER, Candidate.Kind.LEDGE_JUMP]:
		ik.set_candidate(action)
	else:
		ik.clear_targets()
	return true

func consume_motion(delta: float) -> void:
	if _action_active:
		var value := motor.candidate
		if value == null or not value.has_live_static_collider():
			return # Controller grace owns collider disappearance; do not use stale roots.
		var body := instance_from_id(value.collider_instance_id) as Node3D
		if not body.global_transform.is_equal_approx(_support_transform):
			interrupt(&"moving_support")
			return
		var progress := animation.get_action_progress()
		var request := motor.compute_request(animation.get_root_motion_delta(), _previous_progress, progress)
		_previous_progress = progress
		if request.accepted: character.submit_traversal_displacement(request.displacement, request.yaw_delta)
	elif _support_observed and controller.state in [Controller.State.SHIMMY, Controller.State.VERTICAL_CLIMB]:
		var request := motor.sustained_request(controller.selected_candidate, character.global_transform, delta)
		if request.accepted: character.submit_traversal_displacement(request.displacement, request.yaw_delta)
	else:
		animation.get_root_motion_delta() # Consume idle root once; never apply a loop reset twice.

func after_motion(_delta: float) -> void:
	if character.traversal_motion_blocked:
		interrupt(&"blocked")
		return
	if _action_active and _previous_progress >= 1.0 - 0.00001:
		_action_active = false
		controller.complete_action()
		motor.clear()
		_finish(_action_kind)
		if controller.movement_locked:
			animation.play_clip(&"hang_idle")
			ik.set_candidate(controller.selected_candidate)
		else:
			character.set_traversal_lock(false)
			_set_traversal_priorities(false)
			animation.leave_traversal(false)
			ik.clear_targets()

func interrupt(reason: StringName) -> void:
	var was_active := character.is_traversal_locked() or _action_active
	_action_active = false
	_previous_progress = 0.0
	solver.clear()
	motor.clear()
	controller.interrupt(reason)
	character.set_traversal_lock(false)
	if ik != null: ik.clear_targets(true)
	_set_traversal_priorities(false)
	_drop_visual = was_active and reason == &"drop"
	character.get_node("AnimationDriver").traversal_animation_owned = _drop_visual
	if _drop_visual:
		animation.play_clip(&"ledge_drop")
	else:
		animation.leave_traversal(not character.is_on_floor())
	_reentry_time = 0.2
	if was_active:
		if _interaction_open: _finish(reason)
		else: controller.events.interaction_finished.emit(reason)

func _finish(kind: StringName) -> void:
	if _interaction_open:
		controller.events.interaction_finished.emit(kind)
	_interaction_open = false

func _set_traversal_priorities(active_traversal: bool) -> void:
	animation.animation_tree.process_physics_priority = -10 if active_traversal else 2
	var driver := character.get_node("AnimationDriver")
	driver.process_physics_priority = -20 if active_traversal else 1
	character.find_child("Skeleton3D", true, false).process_physics_priority = 10 if active_traversal else 3

func _touch_pressed(action: StringName) -> bool:
	return InputMap.has_action(action) and Input.is_action_pressed(action)
func _touch_just_pressed(action: StringName) -> bool:
	return InputMap.has_action(action) and Input.is_action_just_pressed(action)
func _state_for_kind(kind: Candidate.Kind) -> Controller.State:
	match kind:
		Candidate.Kind.VAULT: return Controller.State.VAULT
		Candidate.Kind.MANTLE: return Controller.State.MANTLE
		Candidate.Kind.AIR_CATCH: return Controller.State.AIR_CATCH
		Candidate.Kind.INNER_CORNER: return Controller.State.INNER_CORNER
		Candidate.Kind.OUTER_CORNER: return Controller.State.OUTER_CORNER
		Candidate.Kind.LEDGE_JUMP: return Controller.State.LEDGE_JUMP
	return Controller.State.HANG

func _occupied_hold() -> LibertyTraversalCandidate:
	var best: LibertyTraversalCandidate
	var distance := INF
	for value in observations:
		if value.kind != Candidate.Kind.HANG: continue
		if controller.selected_candidate != null and value.surface_normal.dot(controller.selected_candidate.surface_normal) < .9: continue
		var error := value.destination_transform.origin.distance_to(character.global_position)
		if error < distance:
			best = value
			distance = error
	return best
