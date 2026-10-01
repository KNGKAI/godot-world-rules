@tool
extends RefCounted
## Static line geometry for the editor gizmos. Everything is derived from settings, script
## defaults and the skeleton rest pose, so nothing here needs the game running. Segment arrays
## hold consecutive point pairs, the format EditorNode3DGizmo.add_lines expects.

## Forward ray heights before hand_height and the ledge-ray inset, from LibertyTraversalProbe.sample().
const PROBE_RAY_HEIGHTS: Array[float] = [1.2, 0.55]
const LEDGE_INSET := 0.08
## Pole offset along the skeleton's Z, from LibertyTraversalIKModifier (arms +, legs -).
const POLE_OFFSET := 0.6
const LIMBS := [
	[&"LeftUpperArm", &"LeftLowerArm", &"LeftHand", 1.0],
	[&"RightUpperArm", &"RightLowerArm", &"RightHand", 1.0],
	[&"LeftUpperLeg", &"LeftLowerLeg", &"LeftFoot", -1.0],
	[&"RightUpperLeg", &"RightLowerLeg", &"RightFoot", -1.0],
]
const LIMIT_RADIUS := 0.12
const AXIS_LENGTH := 0.08
const ARC_STEPS := 16


# --- Traversal probe ------------------------------------------------------------------------

## `values` holds LibertyTraversalProbe property names. Character space: feet at the origin,
## facing -Z, with a nominal wall at forward_reach whose normal faces the character.
static func probe_layout(values: Dictionary) -> Dictionary:
	var reach: float = values.forward_reach
	var hand_height: float = values.hand_height
	var rays := []
	for height in PROBE_RAY_HEIGHTS + [hand_height]:
		rays.append([Vector3(0.0, height, 0.0), Vector3(0.0, height, -reach)])
	var normal := Vector3.BACK
	var tangent := Vector3.UP.cross(normal).normalized()
	var contact := Vector3(0.0, hand_height, -reach)
	var ledge_x := contact - normal * LEDGE_INSET
	var drop := Vector3.UP * (hand_height - float(values.foot_height))
	return {
		"forward_rays": rays,
		"ledge_ray": [Vector3(ledge_x.x, hand_height + float(values.upward_reach), ledge_x.z), Vector3(ledge_x.x, -float(values.downward_reach), ledge_x.z)],
		"contact": contact,
		"normal": normal,
		"tangent": tangent,
		# Same template as LibertyTraversalProbe._append().
		"left_hand": contact + tangent * float(values.hand_spacing) * 0.5,
		"right_hand": contact - tangent * float(values.hand_spacing) * 0.5,
		"left_foot": contact + tangent * float(values.foot_spacing) * 0.5 - drop,
		"right_foot": contact - tangent * float(values.foot_spacing) * 0.5 - drop,
	}


static func probe_segments(values: Dictionary, to_node: Transform3D) -> Dictionary:
	var layout := probe_layout(values)
	var rays := PackedVector3Array()
	for ray: Array in layout.forward_rays:
		rays.append_array([ray[0], ray[1]])
	var ledge := PackedVector3Array(layout.ledge_ray)
	var holds := PackedVector3Array()
	for key in ["left_hand", "right_hand", "left_foot", "right_foot"]:
		holds.append_array(cross(layout[key], 0.05))
	holds.append_array([layout.contact, layout.contact + layout.normal * 0.35])
	var reach := PackedVector3Array()
	var top: float = layout.ledge_ray[0].y
	var bottom: float = layout.ledge_ray[1].y
	var far: float = layout.contact.z
	reach.append_array([Vector3(0, bottom, 0), Vector3(0, bottom, far), Vector3(0, bottom, far), Vector3(0, top, far),
		Vector3(0, top, far), Vector3(0, top, 0), Vector3(0, top, 0), Vector3(0, bottom, 0)])
	var body := capsule_wire(Transform3D(Basis.IDENTITY, Vector3.UP * float(values.capsule_height) * 0.5), values.capsule_radius, values.capsule_height)
	return {
		"rays": transformed(rays, to_node),
		"ledge": transformed(ledge, to_node),
		"holds": transformed(holds, to_node),
		"reach": transformed(reach, to_node),
		"capsule": transformed(body, to_node),
	}


# --- IK --------------------------------------------------------------------------------------

## Rest-pose limb chains in skeleton space, with the runtime pole placement.
static func ik_chains(skeleton: Skeleton3D) -> Array[Dictionary]:
	var chains: Array[Dictionary] = []
	for limb: Array in LIMBS:
		var points := PackedVector3Array()
		for bone_index in 3:
			var index := skeleton.find_bone(limb[bone_index])
			if index < 0:
				points.clear()
				break
			points.append(skeleton.get_bone_global_rest(index).origin)
		if points.is_empty():
			continue
		chains.append({"bones": limb.slice(0, 3), "points": points, "pole": points[0] + Vector3(0.0, 0.0, POLE_OFFSET * limb[3])})
	return chains


## `targets` maps an end bone to a node-space point (the nominal hold template), or is empty.
static func ik_segments(skeleton: Skeleton3D, to_node: Transform3D, targets: Dictionary) -> Dictionary:
	var chains := PackedVector3Array()
	var poles := PackedVector3Array()
	var reach := PackedVector3Array()
	for chain in ik_chains(skeleton):
		var points: PackedVector3Array = chain.points
		chains.append_array([points[0], points[1], points[1], points[2]])
		chains.append_array(cross(points[2], 0.03))
		poles.append_array([points[1], chain.pole])
		poles.append_array(cross(chain.pole, 0.04))
		if targets.has(chain.bones[2]):
			reach.append_array([to_node * points[2], targets[chain.bones[2]]])
			reach.append_array(cross(targets[chain.bones[2]], 0.04))
	return {"chains": transformed(chains, to_node), "poles": transformed(poles, to_node), "reach": reach}


# --- Ragdoll ---------------------------------------------------------------------------------

## Per-body description matching LibertyRagdoll._build_bodies(), in skeleton rest space.
static func ragdoll_bodies(skeleton: Skeleton3D) -> Array[Dictionary]:
	var bodies: Array[Dictionary] = []
	for bone: StringName in LibertyRagdoll.BONE_LAYOUT:
		var index := skeleton.find_bone(bone)
		if index < 0:
			continue
		var layout: Array = LibertyRagdoll.BONE_LAYOUT[bone]
		var segment: Vector3 = layout[2]
		var radius: float = layout[3]
		var center := segment * 0.5
		var joint_type: int = layout[1]
		var axis: Vector3 = layout[5] if layout.size() > 5 else segment.normalized()
		bodies.append({
			"bone": bone,
			"rest": skeleton.get_bone_global_rest(index),
			"segment": segment,
			"mass": layout[0],
			"joint_type": joint_type,
			"limits": layout[4],
			"body_offset": Transform3D(Basis.IDENTITY, center),
			"joint_offset": Transform3D(LibertyRagdoll.joint_basis(bone), -center) if joint_type != PhysicalBone3D.JOINT_TYPE_NONE else Transform3D.IDENTITY,
			"capsule_radius": radius,
			"capsule_height": 0.36 if bone == &"Hips" else maxf(segment.length() + radius * 2.0, radius * 2.0 + 0.01),
			"capsule_basis": basis_from_to(Vector3.UP, axis),
			"drive_frame": LibertyPhysicalAnimation.drive_frame(bone) if LibertyPhysicalAnimation.PHYSICAL_PARENT.has(bone) else null,
		})
	return bodies


## Bone-space tip directions a hinge child can reach. Jolt measures hinge angles opposite to the
## child's rotation about the hinge axis, so a configured angle θ rotates the child by -θ.
static func hinge_arc(bone: StringName) -> PackedVector3Array:
	var layout: Array = LibertyRagdoll.BONE_LAYOUT[bone]
	var axis: Vector3 = LibertyRagdoll.HINGE_AXES[bone]
	var direction := (layout[2] as Vector3).normalized()
	var points := PackedVector3Array()
	for step in ARC_STEPS + 1:
		var angle := deg_to_rad(lerpf(layout[4][0], layout[4][1], float(step) / ARC_STEPS))
		points.append(Basis(axis, -angle) * direction)
	return points


static func ragdoll_segments(skeleton: Skeleton3D, to_node: Transform3D) -> Dictionary:
	var capsules := PackedVector3Array()
	var axes := PackedVector3Array()
	var limits := PackedVector3Array()
	var drives := PackedVector3Array()
	for body in ragdoll_bodies(skeleton):
		var rest: Transform3D = body.rest
		var body_transform: Transform3D = rest * body.body_offset
		capsules.append_array(capsule_wire(body_transform * Transform3D(body.capsule_basis), body.capsule_radius, body.capsule_height))
		if body.joint_type == PhysicalBone3D.JOINT_TYPE_NONE:
			continue
		var joint: Transform3D = body_transform * body.joint_offset
		axes.append_array([joint.origin, joint * (Vector3.RIGHT * AXIS_LENGTH), joint.origin, joint * (Vector3.BACK * AXIS_LENGTH)])
		if body.joint_type == PhysicalBone3D.JOINT_TYPE_CONE:
			limits.append_array(cone_limit(joint, body.limits[0], body.limits[1]))
		else:
			var arc := hinge_arc(body.bone)
			for index in arc.size() - 1:
				limits.append_array([rest * (arc[index] * LIMIT_RADIUS), rest * (arc[index + 1] * LIMIT_RADIUS)])
			limits.append_array([rest.origin, rest * (arc[0] * LIMIT_RADIUS), rest.origin, rest * (arc[-1] * LIMIT_RADIUS)])
		if body.drive_frame != null:
			var frame := Transform3D(rest.basis * body.drive_frame, rest.origin)
			for column in 3:
				drives.append_array([frame.origin, frame.origin + frame.basis[column].normalized() * AXIS_LENGTH * 0.6])
	return {
		"capsules": transformed(capsules, to_node),
		"axes": transformed(axes, to_node),
		"limits": transformed(limits, to_node),
		"drives": transformed(drives, to_node),
	}


## Swing cone about the joint's X (twist) axis plus the twist arc in its YZ plane.
static func cone_limit(joint: Transform3D, swing_degrees: float, twist_degrees: float) -> PackedVector3Array:
	var lines := PackedVector3Array()
	var swing := deg_to_rad(swing_degrees)
	var rim := PackedVector3Array()
	for step in ARC_STEPS + 1:
		var phi := TAU * step / ARC_STEPS
		rim.append(joint * (Vector3(cos(swing), sin(swing) * cos(phi), sin(swing) * sin(phi)) * LIMIT_RADIUS))
	for index in ARC_STEPS:
		lines.append_array([rim[index], rim[index + 1]])
	for index in range(0, ARC_STEPS, ARC_STEPS / 4):
		lines.append_array([joint.origin, rim[index]])
	var twist := deg_to_rad(twist_degrees)
	var previous := Vector3.ZERO
	for step in ARC_STEPS + 1:
		var angle := lerpf(-twist, twist, float(step) / ARC_STEPS)
		var point := joint * (Vector3(0.0, cos(angle), sin(angle)) * LIMIT_RADIUS * 0.5)
		if step > 0:
			lines.append_array([previous, point])
		previous = point
	return lines


# --- Primitives ------------------------------------------------------------------------------

static func cross(center: Vector3, size: float) -> PackedVector3Array:
	return PackedVector3Array([
		center - Vector3.RIGHT * size, center + Vector3.RIGHT * size,
		center - Vector3.UP * size, center + Vector3.UP * size,
		center - Vector3.BACK * size, center + Vector3.BACK * size,
	])


## Wire capsule along the transform's Y axis, total height `height` (CapsuleShape3D convention).
static func capsule_wire(transform: Transform3D, radius: float, height: float) -> PackedVector3Array:
	var lines := PackedVector3Array()
	var half := maxf(height * 0.5 - radius, 0.0)
	for side in [-1.0, 1.0]:
		var previous := Vector3.ZERO
		for step in ARC_STEPS + 1:
			var phi := TAU * step / ARC_STEPS
			var point := Vector3(cos(phi) * radius, half * side, sin(phi) * radius)
			if step > 0:
				lines.append_array([transform * previous, transform * point])
			previous = point
		for plane in 2:
			previous = Vector3.ZERO
			for step in ARC_STEPS / 2 + 1:
				var angle := PI * step / (ARC_STEPS / 2)
				var across := cos(angle) * radius
				var point := Vector3(across if plane == 0 else 0.0, half * side + sin(angle) * radius * side, across if plane == 1 else 0.0)
				if step > 0:
					lines.append_array([transform * previous, transform * point])
				previous = point
	for corner in [Vector3.RIGHT, Vector3.LEFT, Vector3.BACK, Vector3.FORWARD]:
		lines.append_array([transform * (corner * radius + Vector3.UP * half), transform * (corner * radius - Vector3.UP * half)])
	return lines


static func transformed(points: PackedVector3Array, to_node: Transform3D) -> PackedVector3Array:
	var result := PackedVector3Array()
	result.resize(points.size())
	for index in points.size():
		result[index] = to_node * points[index]
	return result


## Same construction as LibertyRagdoll._basis_from_to (pinned by test_editor_geometry.gd).
static func basis_from_to(from: Vector3, to: Vector3) -> Basis:
	if from.is_equal_approx(to):
		return Basis.IDENTITY
	if from.is_equal_approx(-to):
		return Basis(from.cross(Vector3.UP if absf(from.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT).normalized(), PI)
	return Basis(Quaternion(from, to))
