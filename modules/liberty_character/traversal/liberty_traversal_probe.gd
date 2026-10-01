class_name LibertyTraversalProbe
extends Node3D
## Local tagged-static-geometry observations. Transforms use the character's feet origin.

const Candidate = preload("res://modules/liberty_character/traversal/liberty_traversal_candidate.gd")
@export var forward_reach := 0.9
@export var upward_reach := 1.4
@export var downward_reach := 1.2
@export var hand_spacing := 0.35
@export var foot_spacing := 0.45
@export_flags_3d_physics var collision_mask := 8
@export var capsule_radius := 0.4
@export var capsule_height := 1.8
@export var hand_height := 1.55
@export var foot_height := 0.35
@export var clearance_margin := 0.02
@export var character_body: CharacterBody3D
var capture_debug := false
var debug_rays: Array[Dictionary] = []
var debug_capsules: Array[Transform3D] = []

func sample(character_transform: Transform3D, grounded_entry: bool = false, from_hold: bool = false) -> Array[LibertyTraversalCandidate]:
	var result: Array[LibertyTraversalCandidate] = []
	debug_rays.clear()
	debug_capsules.clear()
	if not is_inside_tree() or not character_transform.is_finite() or not _configuration_is_valid():
		return result
	var forward := -character_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		return result
	forward = forward.normalized()
	var exclude: Array[RID] = []
	if is_instance_valid(character_body):
		exclude.append(character_body.get_rid())
	var hit: Dictionary = {}
	# Low and high rays avoid missing low vaults and chest-height surfaces.
	for height in [1.2, 0.55, hand_height]:
		var start: Vector3 = character_transform.origin + Vector3.UP * height
		hit = _ray(start, start + forward * forward_reach, exclude)
		if _supported_hit(hit):
			break
		hit = {}
	if hit.is_empty():
		return result
	var normal: Vector3 = hit.normal
	if not normal.is_finite() or normal.length_squared() < 0.0001:
		return result
	normal = normal.normalized()
	if absf(normal.y) > 0.35:
		return result
	var tangent := Vector3.UP.cross(normal).normalized()
	var point: Vector3 = hit.position
	var above := point - normal * 0.08
	above.y = character_transform.origin.y + hand_height + upward_reach
	var below := above
	below.y = character_transform.origin.y - downward_reach
	var top := _ray(above, below, exclude)
	if _supported_hit(top) and top.collider == hit.collider and top.normal.dot(Vector3.UP) >= 0.7:
		_sample_ledge(result, character_transform, hit, top, normal, tangent, exclude, from_hold)
	else:
		_sample_virtual(result, character_transform, hit, normal, tangent, exclude, grounded_entry)
	if from_hold:
		_sample_directional_jumps(result, character_transform, exclude)
	return result

func _sample_ledge(result: Array[LibertyTraversalCandidate], source: Transform3D, wall: Dictionary, top: Dictionary, normal: Vector3, tangent: Vector3, exclude: Array[RID], from_hold: bool) -> void:
	var edge: Vector3 = wall.position
	edge.y = top.position.y
	var height := edge.y - source.origin.y
	if height <= 0.1 or height > hand_height + upward_reach:
		return
	var destination := edge - normal * (capsule_radius + clearance_margin)
	destination.y = edge.y + clearance_margin
	if height <= (hand_height + 0.1 if from_hold else upward_reach) + clearance_margin and _floor_supported(destination, exclude):
		_append(result, Candidate.Kind.MANTLE, source, destination, edge, normal, tangent, wall.collider, true, exclude)
	if height <= 1.1:
		# Find the back of a low obstacle locally, then require a landing floor.
		for distance in [0.8 + clearance_margin, 1.1 + clearance_margin, 1.4 + clearance_margin]:
			var beyond: Vector3 = edge - normal * distance
			var floor_hit := _ray(beyond + Vector3.UP * 0.1, beyond - Vector3.UP * (height + downward_reach), exclude, 1)
			if floor_hit.is_empty() or floor_hit.collider == wall.collider or floor_hit.normal.dot(Vector3.UP) < 0.7:
				continue
			beyond.y = floor_hit.position.y + clearance_margin
			var previous_count := result.size()
			_append(result, Candidate.Kind.VAULT, source, beyond, edge, normal, tangent, wall.collider, true, exclude)
			if result.size() > previous_count:
				break
	var hanging := edge + normal * (capsule_radius + clearance_margin)
	hanging.y = edge.y - hand_height
	if _ledge_hold_supported(edge, tangent, normal, exclude):
		_append(result, Candidate.Kind.HANG, source, hanging, edge, normal, tangent, wall.collider, true, exclude)
		_append(result, Candidate.Kind.AIR_CATCH, source, hanging, edge, normal, tangent, wall.collider, true, exclude)
		for side in [-1.0, 1.0]:
			var next_edge: Vector3 = edge + tangent * hand_spacing * side
			if _ledge_hold_supported(next_edge, tangent, normal, exclude):
				_append(result, Candidate.Kind.SHIMMY, source, hanging + tangent * hand_spacing * side, next_edge, normal, tangent, wall.collider, true, exclude)
		_sample_side_transitions(result, source, edge, normal, tangent, true, exclude)

func _sample_virtual(result: Array[LibertyTraversalCandidate], source: Transform3D, wall: Dictionary, normal: Vector3, tangent: Vector3, exclude: Array[RID], grounded_entry: bool) -> void:
	var destination: Vector3 = wall.position + normal * (capsule_radius + clearance_margin)
	destination.y = source.origin.y
	# A floor margin is absolute, not an increment added on every virtual hold.
	var floor_hit := _ray(destination + Vector3.UP * 0.1, destination - Vector3.UP * 0.15, exclude, 1)
	if not floor_hit.is_empty() and floor_hit.normal.dot(Vector3.UP) >= 0.7:
		destination.y = maxf(destination.y, floor_hit.position.y + clearance_margin)
	var contact := destination - normal * (capsule_radius + clearance_margin) + Vector3.UP * hand_height
	if not _wall_contacts_supported(contact, normal, tangent, exclude):
		return
	var entry_destination := destination + Vector3.UP * (0.3 if grounded_entry else 0.0)
	var entry_contact := contact + Vector3.UP * (0.3 if grounded_entry else 0.0)
	if _wall_contacts_supported(entry_contact, normal, tangent, exclude):
		_append(result, Candidate.Kind.HANG, source, entry_destination, entry_contact, normal, tangent, wall.collider, false, exclude)
	_append(result, Candidate.Kind.AIR_CATCH, source, destination, contact, normal, tangent, wall.collider, false, exclude)
	for side in [-1.0, 1.0]:
		var offset: Vector3 = tangent * hand_spacing * side
		if _wall_contacts_supported(contact + offset, normal, tangent, exclude):
			_append(result, Candidate.Kind.SHIMMY, source, destination + offset, contact + offset, normal, tangent, wall.collider, false, exclude)
	_sample_side_transitions(result, source, contact, normal, tangent, false, exclude)
	for side in [-1.0, 1.0]:
		var offset: Vector3 = Vector3.UP * foot_spacing * side
		if _wall_contacts_supported(contact + offset, normal, tangent, exclude):
			_append(result, Candidate.Kind.CLIMB, source, destination + offset, contact + offset, normal, tangent, wall.collider, false, exclude)


func _sample_side_transitions(result: Array[LibertyTraversalCandidate], source: Transform3D, contact: Vector3, normal: Vector3, tangent: Vector3, geometric: bool, exclude: Array[RID]) -> void:
	for side in [-1.0, 1.0]:
		var lateral: Vector3 = tangent * side
		var continuation_contact := contact + lateral * hand_spacing
		var continuous := _ledge_hold_supported(continuation_contact, tangent, normal, exclude) if geometric else _wall_contacts_supported(continuation_contact, normal, tangent, exclude)
		# An inside corner can be encountered before the current wall ends.
		var inside_start := contact + normal * (capsule_radius + clearance_margin)
		var inside := _ray(inside_start, inside_start + lateral * forward_reach, exclude)
		_try_corner(result, source, inside, normal, Candidate.Kind.INNER_CORNER, exclude)
		if continuous:
			continue
		# Probe around the outside edge; this is a local query, not a level scan.
		var outside_start := contact + lateral * (hand_spacing + capsule_radius) - normal * (capsule_radius + clearance_margin)
		var outside := _ray(outside_start, outside_start - lateral * forward_reach, exclude)
		_try_corner(result, source, outside, normal, Candidate.Kind.OUTER_CORNER, exclude)
		for distance in [0.7, 1.05, 1.2, 1.4]:
			var target_contact: Vector3 = contact + lateral * distance
			var target_hit := _ray(target_contact + normal * 0.15, target_contact - normal * 0.15, exclude)
			if geometric:
				if not _ledge_hold_supported(target_contact, tangent, normal, exclude):
					continue
				# The wall immediately under a ledge supplies its static collider identity.
				target_hit = _ray(target_contact - Vector3.UP * 0.05 + normal * 0.15, target_contact - Vector3.UP * 0.05 - normal * 0.15, exclude)
			elif not _wall_contacts_supported(target_contact, normal, tangent, exclude):
				continue
			if not _supported_hit(target_hit) or target_hit.normal.normalized().dot(normal) < 0.9:
				continue
			var destination := target_contact + normal * (capsule_radius + clearance_margin) - Vector3.UP * hand_height
			_append(result, Candidate.Kind.LEDGE_JUMP, source, destination, target_contact, normal, tangent, target_hit.collider, geometric, exclude)

func _try_corner(result: Array[LibertyTraversalCandidate], source: Transform3D, hit: Dictionary, previous_normal: Vector3, kind: Candidate.Kind, exclude: Array[RID]) -> void:
	if not _supported_hit(hit):
		return
	var normal: Vector3 = hit.normal.normalized()
	if absf(normal.y) > 0.35 or absf(normal.dot(previous_normal)) > 0.35:
		return
	var tangent := Vector3.UP.cross(normal).normalized()
	var contact: Vector3 = hit.position
	if not _wall_contacts_supported(contact, normal, tangent, exclude):
		return
	var destination := contact + normal * (capsule_radius + clearance_margin) - Vector3.UP * hand_height
	_append(result, kind, source, destination, contact, normal, tangent, hit.collider, false, exclude)

func _append(result: Array[LibertyTraversalCandidate], kind: Candidate.Kind, source: Transform3D, destination: Vector3, contact: Vector3, normal: Vector3, tangent: Vector3, body: StaticBody3D, geometric: bool, exclude: Array[RID]) -> void:
	var facing := Vector3(-normal.x, 0.0, -normal.z).normalized()
	var target := Transform3D(Basis.looking_at(facing, Vector3.UP), destination)
	if not _destination_is_clear(target, exclude):
		return
	var candidate := Candidate.new()
	candidate.kind = kind
	candidate.source_transform = source
	candidate.destination_transform = target
	candidate.contact_point = contact
	candidate.surface_normal = normal
	candidate.ledge_tangent = tangent
	candidate.collider_instance_id = body.get_instance_id()
	candidate.is_clear = true
	candidate.is_geometric_ledge = geometric
	candidate.confidence = 0.9 if geometric else 0.7
	candidate.left_hand_target = contact + tangent * hand_spacing * 0.5
	candidate.right_hand_target = contact - tangent * hand_spacing * 0.5
	candidate.left_foot_target = contact + tangent * foot_spacing * 0.5 - Vector3.UP * (hand_height - foot_height)
	candidate.right_foot_target = contact - tangent * foot_spacing * 0.5 - Vector3.UP * (hand_height - foot_height)
	if candidate.is_valid():
		result.append(candidate)

func _ray(from: Vector3, to: Vector3, exclude: Array[RID], mask: int = -1) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, collision_mask if mask < 0 else mask, exclude)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if capture_debug: debug_rays.append({"from": from, "to": to, "hit": not hit.is_empty()})
	return hit

func _supported_hit(hit: Dictionary) -> bool:
	if hit.is_empty():
		return false
	var body := hit.collider as StaticBody3D
	return is_instance_valid(body) and not body is AnimatableBody3D \
		and not body.is_queued_for_deletion() and body.get_collision_layer_value(1) and body.get_collision_layer_value(4) \
		and hit.normal.is_finite()

func _destination_is_clear(at: Transform3D, exclude: Array[RID]) -> bool:
	var capsule := CapsuleShape3D.new()
	capsule.radius = capsule_radius
	capsule.height = capsule_height
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.transform = at
	query.transform.origin += Vector3.UP * capsule_height * 0.5
	query.collision_mask = 1
	query.exclude = exclude
	if capture_debug: debug_capsules.append(query.transform)
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

func _floor_supported(destination: Vector3, exclude: Array[RID]) -> bool:
	var hit := _ray(destination + Vector3.UP * 0.1, destination - Vector3.UP * 0.15, exclude, 1)
	return not hit.is_empty() and hit.normal.dot(Vector3.UP) >= 0.7

func _ledge_hold_supported(contact: Vector3, tangent: Vector3, normal: Vector3, exclude: Array[RID]) -> bool:
	return _ledge_hands_supported(contact, tangent, normal, exclude) \
		and _wall_contacts_supported(contact - Vector3.UP * 0.05, normal, tangent, exclude)

func _ledge_hands_supported(contact: Vector3, tangent: Vector3, normal: Vector3, exclude: Array[RID]) -> bool:
	for side in [-1.0, 1.0]:
		var point: Vector3 = contact + tangent * hand_spacing * 0.5 * side - normal * 0.08
		var hit := _ray(point + Vector3.UP * 0.12, point - Vector3.UP * 0.12, exclude)
		if not _supported_hit(hit) or hit.normal.dot(Vector3.UP) < 0.7:
			return false
	return true

func _wall_contacts_supported(contact: Vector3, normal: Vector3, tangent: Vector3, exclude: Array[RID]) -> bool:
	for offset in [-tangent * hand_spacing * 0.5, tangent * hand_spacing * 0.5, -tangent * foot_spacing * 0.5 - Vector3.UP * (hand_height - foot_height), tangent * foot_spacing * 0.5 - Vector3.UP * (hand_height - foot_height)]:
		var point: Vector3 = contact + offset
		var hit := _ray(point + normal * 0.15, point - normal * 0.15, exclude)
		if not _supported_hit(hit) or hit.normal.normalized().dot(normal) < 0.9:
			return false
	return true

func _configuration_is_valid() -> bool:
	for value in [forward_reach, upward_reach, downward_reach, hand_spacing, foot_spacing, capsule_radius, capsule_height, hand_height, foot_height, clearance_margin]:
		if not is_finite(value) or value <= 0.0:
			return false
	return capsule_height >= capsule_radius * 2.0

## Revalidates the occupied contact separately from availability of another hold.
func confirm_support(value: LibertyTraversalCandidate) -> bool:
	if value == null or not value.is_valid() or not value.has_live_static_collider():
		return false
	var exclude: Array[RID] = []
	if is_instance_valid(character_body): exclude.append(character_body.get_rid())
	if value.is_geometric_ledge:
		return _ledge_hold_supported(value.contact_point, value.ledge_tangent, value.surface_normal, exclude)
	return _wall_contacts_supported(value.contact_point, value.surface_normal, value.ledge_tangent, exclude)

func _sample_directional_jumps(result: Array[LibertyTraversalCandidate], source: Transform3D, exclude: Array[RID]) -> void:
	var occupied: LibertyTraversalCandidate
	for value in result:
		if value.kind == Candidate.Kind.HANG:
			occupied = value
			break
	if occupied == null:
		return
	var normal := occupied.surface_normal
	var tangent := occupied.ledge_tangent
	for offset in [Vector3.UP * 0.65, -normal * 1.2]:
		var contact: Vector3 = occupied.contact_point + offset
		var hit := _ray(contact + normal * .15, contact - normal * .15, exclude)
		if not _supported_hit(hit) or hit.normal.normalized().dot(normal) < .9:
			continue
		var geometric := _ledge_hold_supported(contact, tangent, normal, exclude)
		if not geometric and not _wall_contacts_supported(contact, normal, tangent, exclude):
			continue
		var destination := contact + normal * (capsule_radius + clearance_margin) - Vector3.UP * hand_height
		_append(result, Candidate.Kind.LEDGE_JUMP, source, destination, contact, normal, tangent, hit.collider, geometric, exclude)
