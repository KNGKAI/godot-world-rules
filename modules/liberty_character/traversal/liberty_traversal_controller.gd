class_name LibertyTraversalController
extends Node
## Pure intent/state owner. Phase 5 consumes movement_locked and selected_candidate.

const Candidate = preload("res://modules/liberty_character/traversal/liberty_traversal_candidate.gd")
enum State { GROUNDED, VAULT, MANTLE, HANG, SHIMMY, VERTICAL_CLIMB, INNER_CORNER, OUTER_CORNER, LEDGE_JUMP, DROP, AIR_CATCH, FALLING }
const STATE_NAMES: Array[StringName] = [&"grounded", &"vault", &"mantle", &"hang", &"shimmy", &"vertical_climb", &"inner_corner", &"outer_corner", &"ledge_jump", &"drop", &"airborne_catch", &"falling"]

@export var lost_candidate_grace := 0.12
@export var max_catch_speed := 12.0
@export var max_catch_angle_degrees := 65.0
@export var events: LibertyEvents
var state: State = State.GROUNDED
var selected_candidate: LibertyTraversalCandidate
var movement_locked := false
var _lost_time := 0.0
signal state_changed(old_state: State, new_state: State)

## Apply state eligibility before solver scoring so catch and hang do not compete.
func filter_candidates(candidates: Array[LibertyTraversalCandidate], grounded: bool, jump_pressed: bool, movement_direction: Vector3 = Vector3.ZERO) -> Array[LibertyTraversalCandidate]:
	var result: Array[LibertyTraversalCandidate] = []
	for candidate in candidates:
		if candidate == null or not candidate.is_valid() or not candidate.has_live_static_collider():
			continue
		var allowed := false
		if movement_locked:
			if state in [State.HANG, State.SHIMMY, State.VERTICAL_CLIMB]:
				allowed = candidate.kind in [Candidate.Kind.HANG, Candidate.Kind.SHIMMY, Candidate.Kind.CLIMB, Candidate.Kind.INNER_CORNER, Candidate.Kind.OUTER_CORNER, Candidate.Kind.MANTLE] or (jump_pressed and candidate.kind == Candidate.Kind.LEDGE_JUMP)
		elif grounded:
			allowed = candidate.kind in [Candidate.Kind.VAULT, Candidate.Kind.MANTLE, Candidate.Kind.HANG]
		else:
			allowed = candidate.kind == Candidate.Kind.AIR_CATCH
		if allowed and (movement_direction.is_zero_approx() or not movement_locked or _matches_intent(candidate, movement_direction)):
			result.append(candidate)
	if jump_pressed:
		var jumps: Array[LibertyTraversalCandidate] = []
		for value in result:
			if value.kind == Candidate.Kind.LEDGE_JUMP: jumps.append(value)
		if not jumps.is_empty(): return jumps
	return result

## support_observed describes the current hold, not the proposed continuation.
func update_intent(candidate: LibertyTraversalCandidate, traverse_held: bool, jump_pressed: bool, drop_pressed: bool, grounded: bool, movement_direction: Vector3, airborne_velocity: Vector3, delta: float, support_observed: bool = true) -> void:
	if not is_finite(delta) or delta < 0.0 or not movement_direction.is_finite() or not airborne_velocity.is_finite():
		interrupt(&"invalid_intent")
		return
	if drop_pressed and movement_locked:
		_transition(State.DROP)
		interrupt(&"drop")
		return
	var candidate_alive := candidate != null and candidate.is_valid() and candidate.has_live_static_collider()
	if movement_locked:
		var support_alive := selected_candidate != null and selected_candidate.is_valid() and selected_candidate.has_live_static_collider()
		if not support_alive or not support_observed:
			_lost_time += delta
			if _lost_time >= lost_candidate_grace:
				interrupt(&"lost_support")
			return
		_lost_time = 0.0
		if not candidate_alive or not traverse_held or movement_direction.is_zero_approx():
			if state in [State.SHIMMY, State.VERTICAL_CLIMB]:
				_transition(State.HANG)
			return
		if state not in [State.HANG, State.SHIMMY, State.VERTICAL_CLIMB]:
			return
		if candidate.kind == Candidate.Kind.LEDGE_JUMP:
			if state in [State.SHIMMY, State.VERTICAL_CLIMB]:
				_transition(State.HANG)
			if jump_pressed and _matches_intent(candidate, movement_direction):
				_accept(candidate, State.LEDGE_JUMP)
			return
		var continuation := _state_for_kind(candidate.kind)
		if continuation in [State.HANG, State.SHIMMY, State.VERTICAL_CLIMB, State.INNER_CORNER, State.OUTER_CORNER, State.MANTLE] and _matches_intent(candidate, movement_direction):
			_accept(candidate, continuation)
		elif state in [State.SHIMMY, State.VERTICAL_CLIMB]:
			_transition(State.HANG)
		return
	_transition(State.GROUNDED if grounded else State.FALLING)
	if not candidate_alive or not traverse_held or movement_direction.is_zero_approx():
		return
	if grounded:
		match candidate.kind:
			Candidate.Kind.VAULT: _accept(candidate, State.VAULT)
			Candidate.Kind.MANTLE: _accept(candidate, State.MANTLE)
			Candidate.Kind.HANG: _accept(candidate, State.HANG)
	elif candidate.kind == Candidate.Kind.AIR_CATCH:
		var forward := -candidate.source_transform.basis.z.normalized()
		if airborne_velocity.length() <= max_catch_speed and forward.angle_to(-candidate.surface_normal) <= deg_to_rad(max_catch_angle_degrees):
			_accept(candidate, State.AIR_CATCH)

## Refresh a stationary hold from actual occupied contacts, never a continuation.
func settle_hold(candidate: LibertyTraversalCandidate) -> void:
	if movement_locked and state in [State.HANG, State.SHIMMY, State.VERTICAL_CLIMB] and candidate != null and candidate.kind == Candidate.Kind.HANG and candidate.is_valid() and candidate.has_live_static_collider():
		_accept(candidate, State.HANG)

## Called by the motor after collision-safe completion, never by a timer.
func complete_action() -> void:
	if not movement_locked:
		return
	if selected_candidate == null or not selected_candidate.has_live_static_collider():
		return
	if state in [State.VAULT, State.MANTLE]:
		selected_candidate = null
		_transition(State.GROUNDED)
	else:
		_transition(State.HANG)

func interrupt(_reason: StringName) -> void:
	selected_candidate = null
	_lost_time = 0.0
	_transition(State.FALLING)
	movement_locked = false

func _accept(candidate: LibertyTraversalCandidate, next_state: State) -> void:
	selected_candidate = candidate.duplicate_candidate()
	_lost_time = 0.0
	_transition(next_state)

func _transition(next_state: State) -> void:
	if next_state == state:
		return
	var previous := state
	state = next_state
	movement_locked = state not in [State.GROUNDED, State.FALLING, State.DROP]
	state_changed.emit(previous, state)
	if is_instance_valid(events):
		events.traversal_state_changed.emit(STATE_NAMES[previous], STATE_NAMES[state])

func _state_for_kind(kind: Candidate.Kind) -> State:
	match kind:
		Candidate.Kind.MANTLE: return State.MANTLE
		Candidate.Kind.HANG: return State.HANG
		Candidate.Kind.SHIMMY: return State.SHIMMY
		Candidate.Kind.CLIMB: return State.VERTICAL_CLIMB
		Candidate.Kind.INNER_CORNER: return State.INNER_CORNER
		Candidate.Kind.OUTER_CORNER: return State.OUTER_CORNER
		Candidate.Kind.LEDGE_JUMP: return State.LEDGE_JUMP
	return State.FALLING

func _matches_intent(candidate: LibertyTraversalCandidate, direction: Vector3) -> bool:
	if candidate.kind == Candidate.Kind.HANG:
		return true
	var travel := candidate.destination_transform.origin - candidate.source_transform.origin
	if candidate.kind == Candidate.Kind.CLIMB or (candidate.kind == Candidate.Kind.LEDGE_JUMP and absf(travel.y) > travel.length() * 0.7):
		# Forward into the wall means up; backward means down. Explicit Y also works.
		var vertical_intent := direction.y if absf(direction.y) > 0.001 else direction.dot(-candidate.surface_normal)
		return travel.y * vertical_intent > 0.001
	travel.y = 0.0
	var planar := Vector3(direction.x, 0.0, direction.z)
	return not travel.is_zero_approx() and travel.normalized().dot(planar.normalized()) > 0.1
