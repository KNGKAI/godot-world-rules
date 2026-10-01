class_name LibertyTraversalSolver
extends Node
## Selects local observations only; a missing sample returns null for controller grace handling.

@export var switch_delay := 0.12
@export var switch_score_margin := 0.15
var _current: LibertyTraversalCandidate
var _challenger: LibertyTraversalCandidate
var _challenger_time := 0.0
var _missing_time := 0.0

func choose(candidates: Array[LibertyTraversalCandidate], input_direction: Vector3, delta: float) -> LibertyTraversalCandidate:
	if not input_direction.is_finite() or not is_finite(delta) or delta < 0.0:
		clear()
		return null
	if _current != null and (not _current.is_valid() or not _current.has_live_static_collider()):
		clear()
	var best: LibertyTraversalCandidate
	var current_observation: LibertyTraversalCandidate
	var best_score := -INF
	for candidate in candidates:
		if candidate == null or not candidate.is_valid() or not candidate.has_live_static_collider():
			continue
		if _current != null and _current.same_opportunity(candidate):
			current_observation = candidate
		var score := _score(candidate, input_direction)
		if score > best_score or (is_equal_approx(score, best_score) and _comes_before(candidate, best)):
			best = candidate
			best_score = score
	if current_observation == null and _current != null:
		_missing_time += delta
		if _missing_time >= switch_delay:
			clear()
	else:
		_missing_time = 0.0
	if best == null:
		_reset_challenger()
		return null
	if current_observation != null:
		_current = current_observation
	if _current == null or _current.same_opportunity(best):
		_current = best
		_reset_challenger()
		return _current
	if best_score < _score(_current, input_direction) + switch_score_margin:
		_reset_challenger()
		return _current
	if _challenger == null or not _challenger.same_opportunity(best):
		_challenger = best.duplicate_candidate()
		_challenger_time = 0.0
	_challenger_time += delta
	if _challenger_time >= switch_delay:
		_current = best
		_reset_challenger()
	return _current

func clear() -> void:
	_current = null
	_missing_time = 0.0
	_reset_challenger()

func _reset_challenger() -> void:
	_challenger = null
	_challenger_time = 0.0

func _score(candidate: LibertyTraversalCandidate, direction: Vector3) -> float:
	var travel := candidate.destination_transform.origin - candidate.source_transform.origin
	var distance := travel.length()
	if travel.is_zero_approx() and candidate.kind == LibertyTraversalCandidate.Kind.SHIMMY:
		travel = candidate.ledge_tangent
	var scoring_direction := direction
	if candidate.kind == LibertyTraversalCandidate.Kind.CLIMB or (candidate.kind == LibertyTraversalCandidate.Kind.LEDGE_JUMP and absf(travel.y) > travel.length() * 0.7):
		var vertical := direction.y if absf(direction.y) > 0.001 else direction.dot(-candidate.surface_normal)
		scoring_direction = Vector3.UP * vertical
	var direction_score := maxf(0.0, travel.normalized().dot(scoring_direction.normalized()))
	var facing := -candidate.source_transform.basis.z.normalized()
	var facing_score := maxf(0.0, facing.dot(-candidate.surface_normal))
	return candidate.confidence + direction_score + facing_score * 0.1 \
		- distance * 0.05 + (2.0 if candidate.is_geometric_ledge else 0.0)

func _comes_before(candidate: LibertyTraversalCandidate, other: LibertyTraversalCandidate) -> bool:
	if other == null:
		return true
	if candidate.collider_instance_id != other.collider_instance_id:
		return candidate.collider_instance_id < other.collider_instance_id
	if candidate.kind != other.kind:
		return candidate.kind < other.kind
	if candidate.contact_point.x != other.contact_point.x:
		return candidate.contact_point.x < other.contact_point.x
	if candidate.contact_point.y != other.contact_point.y:
		return candidate.contact_point.y < other.contact_point.y
	return candidate.contact_point.z < other.contact_point.z
