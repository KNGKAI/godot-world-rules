class_name LibertyTraversalCandidate
extends RefCounted
## Snapshot of a locally detected opportunity. Consumers must recheck collider liveness.

enum Kind { NONE, VAULT, MANTLE, HANG, SHIMMY, CLIMB, INNER_CORNER, OUTER_CORNER, LEDGE_JUMP, DROP, AIR_CATCH }

var kind: Kind = Kind.NONE
var source_transform := Transform3D.IDENTITY
var destination_transform := Transform3D.IDENTITY
var contact_point := Vector3.ZERO
var surface_normal := Vector3.ZERO
var ledge_tangent := Vector3.ZERO
var collider_instance_id := 0
var is_clear := false
var positional_correction := 0.0
var angular_correction := 0.0
var confidence := 0.0
var left_hand_target := Vector3.ZERO
var right_hand_target := Vector3.ZERO
var left_foot_target := Vector3.ZERO
var right_foot_target := Vector3.ZERO
var is_geometric_ledge := false

func is_valid() -> bool:
	return kind > Kind.NONE and kind <= Kind.AIR_CATCH \
		and collider_instance_id > 0 and is_clear \
		and source_transform.is_finite() and destination_transform.is_finite() \
		and contact_point.is_finite() and surface_normal.is_finite() and ledge_tangent.is_finite() \
		and absf(surface_normal.length_squared() - 1.0) < 0.01 \
		and absf(ledge_tangent.length_squared() - 1.0) < 0.01 \
		and absf(surface_normal.dot(ledge_tangent)) < 0.01 \
		and is_finite(confidence) and is_finite(positional_correction) and is_finite(angular_correction) \
		and positional_correction >= 0.0 and angular_correction >= 0.0 \
		and left_hand_target.is_finite() and right_hand_target.is_finite() \
		and left_foot_target.is_finite() and right_foot_target.is_finite()

func duplicate_candidate() -> LibertyTraversalCandidate:
	var copy := LibertyTraversalCandidate.new()
	copy.kind = kind
	copy.source_transform = source_transform
	copy.destination_transform = destination_transform
	copy.contact_point = contact_point
	copy.surface_normal = surface_normal
	copy.ledge_tangent = ledge_tangent
	copy.collider_instance_id = collider_instance_id
	copy.is_clear = is_clear
	copy.positional_correction = positional_correction
	copy.angular_correction = angular_correction
	copy.confidence = confidence
	copy.left_hand_target = left_hand_target
	copy.right_hand_target = right_hand_target
	copy.left_foot_target = left_foot_target
	copy.right_foot_target = right_foot_target
	copy.is_geometric_ledge = is_geometric_ledge
	return copy

func same_opportunity(other: LibertyTraversalCandidate, contact_tolerance: float = 0.15) -> bool:
	return other != null and collider_instance_id == other.collider_instance_id \
		and kind == other.kind and contact_point.distance_to(other.contact_point) <= contact_tolerance

func has_live_static_collider() -> bool:
	var body := instance_from_id(collider_instance_id) as StaticBody3D
	return is_instance_valid(body) and not body is AnimatableBody3D \
		and body.is_inside_tree() and not body.is_queued_for_deletion() \
		and body.get_collision_layer_value(1) and body.get_collision_layer_value(4)
