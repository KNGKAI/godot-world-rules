class_name LibertyPhysicalAnimation
extends SkeletonModifier3D
## Active ragdoll stage: during a hit reaction, simulated bodies track the captured
## animation-and-IK pose through per-body Generic 6DOF drive joints whose angular springs
## Jolt solves implicitly (user-approved alternative to script-computed PD torques, which
## could not carry a limb's load stably at 60 Hz; see the Phase 7 ledger). Sits after
## PoseCapture and before PhysicalBoneSimulator3D, so it always reads this skeleton
## update's capture; it never reads the simulated pose and never writes bone poses.

## Strength groups. Hips is kinematic during a reaction (the anchor), so a hip hit
## loosens the core chain and its impulse lands on Spine.
const CHAIN_OF := {
	&"Hips": &"core", &"Spine": &"core", &"Chest": &"core", &"Head": &"core",
	&"LeftUpperArm": &"left_arm", &"LeftLowerArm": &"left_arm",
	&"RightUpperArm": &"right_arm", &"RightLowerArm": &"right_arm",
	&"LeftUpperLeg": &"left_leg", &"LeftLowerLeg": &"left_leg", &"LeftFoot": &"left_leg",
	&"RightUpperLeg": &"right_leg", &"RightLowerLeg": &"right_leg", &"RightFoot": &"right_leg",
}
## Closed subtrees to simulate per chain: a kinematic child would pin its dynamic parent.
const CHAIN_BODIES := {
	&"core": [&"Spine", &"Chest", &"Head", &"LeftUpperArm", &"LeftLowerArm", &"RightUpperArm", &"RightLowerArm"],
	&"left_arm": [&"LeftUpperArm", &"LeftLowerArm"],
	&"right_arm": [&"RightUpperArm", &"RightLowerArm"],
	&"left_leg": [&"LeftUpperLeg", &"LeftLowerLeg", &"LeftFoot"],
	&"right_leg": [&"RightUpperLeg", &"RightLowerLeg", &"RightFoot"],
}
const CHAINS: Array[StringName] = [&"core", &"left_arm", &"right_arm", &"left_leg", &"right_leg"]
## Nearest physical ancestor of each jointed body (the body its joint attaches to).
const PHYSICAL_PARENT := {
	&"Spine": &"Hips", &"Chest": &"Spine", &"Head": &"Chest",
	&"LeftUpperArm": &"Chest", &"RightUpperArm": &"Chest",
	&"LeftLowerArm": &"LeftUpperArm", &"RightLowerArm": &"RightUpperArm",
	&"LeftUpperLeg": &"Hips", &"RightUpperLeg": &"Hips",
	&"LeftLowerLeg": &"LeftUpperLeg", &"RightLowerLeg": &"RightUpperLeg",
	&"LeftFoot": &"LeftLowerLeg", &"RightFoot": &"RightLowerLeg",
}
## Physical descendants each body carries, parent-first (BONE_LAYOUT order).
const DESCENDANTS := {
	&"Spine": [&"Chest", &"Head", &"LeftUpperArm", &"RightUpperArm", &"LeftLowerArm", &"RightLowerArm"],
	&"Chest": [&"Head", &"LeftUpperArm", &"RightUpperArm", &"LeftLowerArm", &"RightLowerArm"],
	&"Head": [],
	&"LeftUpperArm": [&"LeftLowerArm"], &"RightUpperArm": [&"RightLowerArm"],
	&"LeftLowerArm": [], &"RightLowerArm": [],
	&"LeftUpperLeg": [&"LeftLowerLeg", &"LeftFoot"], &"RightUpperLeg": [&"RightLowerLeg", &"RightFoot"],
	&"LeftLowerLeg": [&"LeftFoot"], &"RightLowerLeg": [&"RightFoot"],
	&"LeftFoot": [], &"RightFoot": [],
}
## Drive-joint frames (bone space). Spring targets are XYZ Euler angles, so each frame keeps
## the middle (Y) angle of the animated targets far from gimbal lock: arms use Z,X,Y axes
## (measured worst middle angle 29 degrees); every other joint stays within 4 degrees in
## the bone's own axes.
const ARM_DRIVE_FRAME := Basis(Vector3.BACK, Vector3.RIGHT, Vector3.UP)
const ARM_BONES: Array[StringName] = [&"LeftUpperArm", &"RightUpperArm", &"LeftLowerArm", &"RightLowerArm"]

@export_group("Tracking")
## Angular stiffness in s^-2 (natural frequency squared). Each drive axis's spring is this
## times the inertia, about the joint pivot, of the body plus its simulated descendants.
@export_range(0.0, 20000.0, 1.0, "or_greater") var stiffness := 2500.0
## Angular damping in s^-1 on the joint's relative angular velocity; times the same inertia.
## The spring target leads the animation by damping / stiffness to cancel the resulting lag.
@export_range(0.0, 500.0, 0.1, "or_greater") var damping := 20.0
## Largest target lead (radians) used to cancel the spring's damping lag.
@export_range(0.0, 3.0, 0.01) var max_lead := 1.0
## Torque magnitude limit in N·m before the per-bone multiplier. Jolt ignores motor force
## limits on springs, so the limit caps how far the spring target may lead the current pose.
@export_range(0.0, 5000.0, 1.0, "or_greater") var max_torque := 800.0
## Per-bone multiplier: scales stiffness and max torque, and damping by its square root
## (constant damping ratio). Inertia scaling already equalises bone sizes, so the
## defaults are 1.0; lower a bone to make it looser.
@export var bone_multipliers := {
	&"Spine": 1.0, &"Chest": 1.0, &"Head": 1.0,
	&"LeftUpperArm": 1.0, &"RightUpperArm": 1.0, &"LeftLowerArm": 1.0, &"RightLowerArm": 1.0,
	&"LeftUpperLeg": 1.0, &"RightUpperLeg": 1.0, &"LeftLowerLeg": 1.0, &"RightLowerLeg": 1.0,
	&"LeftFoot": 1.0, &"RightFoot": 1.0,
}

@export_group("Hit Reaction")
## Chain strength immediately after a non-fatal hit.
@export_range(0.0, 1.0, 0.01) var hit_strength := 0.15
## Time for a hit chain to smoothstep back to full strength.
@export_range(0.01, 5.0, 0.01, "or_greater") var hit_recovery_time := 0.6
## Simulator influence fade once every chain is back to full strength.
@export_range(0.01, 2.0, 0.01, "or_greater") var fade_out_time := 0.2
## Hit impulses are capped at body mass times this speed change.
@export_range(0.1, 20.0, 0.1, "or_greater") var max_hit_delta_v := 4.0

@export_group("Safety")
## Any body faster than this (rad/s) ends the reaction immediately with a warning. Jolt
## itself caps bodies at 15*PI (47.1) rad/s, and a sprinting foot kept inside its joint
## limits legitimately reaches that cap, so the default sits above it and catches only
## non-physical spin; max_joint_separation is the primary explosion check.
@export_range(1.0, 200.0, 1.0, "or_greater") var max_angular_speed := 60.0
## A body this far (m) from its joint anchor on the parent means the constraint failed.
@export_range(0.01, 1.0, 0.01, "or_greater") var max_joint_separation := 0.1
## Any body this much faster (m/s) than the character capsule ends the reaction.
@export_range(1.0, 100.0, 1.0, "or_greater") var max_relative_speed := 15.0

## Joint-limit margin for clamped targets.
const LIMIT_MARGIN := deg_to_rad(2.0)

var ragdoll: LibertyRagdoll
var character: LibertyCharacter
var events: LibertyEvents
var pose_capture: LibertyPoseCaptureModifier
var configuration_error := ""
## Test/course diagnostic: keep tracking at the current strengths instead of fading out.
var hold_tracking := false
## Per-chain strength in [hit_strength, 1]; scales stiffness and gravity compensation.
var chain_strength := {}
## Diagnostics refreshed every tracked tick.
var last_read_frame := -1
var last_capture_frame := -1
var max_error_degrees := 0.0
## Per-body rotation error (degrees) against the clamped target, last tracked tick.
var last_errors_degrees := {}
var max_body_angular_speed := 0.0
## Fastest clamped-target rotation (rad/s) seen on the last tracked tick.
var max_target_angular_speed := 0.0
var last_target_speeds := {}
## Per-body distance from its joint anchor (m), last tracked tick.
var last_separations := {}
var last_update_usec := 0
var fade_elapsed := -1.0
var last_guard_trip := ""

var _chain_elapsed := {}
var _chain_start := {}
var _previous_targets := {}
var _previous_chain := {}
var _engaged := false
## Drive joint RID per body, created on first use and freed with this node.
var _drives := {}
var _drive_enabled := {}
var _joined_frame := {}


## Called by LibertyRagdoll after it builds the bodies and inserts this stage.
func configure(owner_ragdoll: LibertyRagdoll) -> void:
	ragdoll = owner_ragdoll
	character = ragdoll.character
	events = ragdoll.events
	pose_capture = ragdoll.pose_capture
	if pose_capture == null:
		configuration_error = "Physical animation requires PoseCapture"
		push_warning(configuration_error)
		active = false
		return
	if events != null:
		events.ragdoll_started.connect(_on_ragdoll_started)
	_reset()


func is_tracking() -> bool:
	return ragdoll != null and ragdoll.is_reacting()


## Owned command: simulate and track the closed subtrees of `chains` at their current
## strengths. Starts or extends the ragdoll's reaction simulation.
func track(chains: Array[StringName]) -> bool:
	if configuration_error != "" or ragdoll == null:
		return false
	var bodies := simulated_bodies(chains)
	var poses := _clamped_start_poses(bodies)
	var velocities := {}
	var delta := 1.0 / Engine.physics_ticks_per_second
	for bone: StringName in poses:
		_joined_frame[bone] = Engine.get_physics_frames()
		var body := ragdoll.get_physical_bone(bone)
		velocities[bone] = pose_capture.get_animated_velocity(body.get_bone_id(), body.body_offset, delta)
	var ok := ragdoll.extend_active_simulation(bodies, poses, velocities) if ragdoll.is_reacting() else ragdoll.begin_active_simulation(bodies, poses, velocities)
	if ok:
		_engaged = true
		fade_elapsed = -1.0
		ragdoll.set_reaction_influence(1.0)
	return ok


## Skeleton-space start transforms for bodies about to join: the animated pose with every
## joint clamped into its limits, chained from the parent's pose (kinematic: animated;
## already reacting: its body). Starting outside a limit makes Jolt snap the body back in
## one step (a sprinting foot starts 64 degrees out and spins at the solver's cap).
## New bodies also start with their animated velocity (see LibertyPoseCaptureModifier).
func _clamped_start_poses(bodies: Array[StringName]) -> Dictionary:
	var skeleton := get_skeleton()
	var to_skeleton := skeleton.global_transform.affine_inverse()
	var reacting := ragdoll.get_reaction_bones()
	var poses := {}
	for bone in bodies:
		if reacting.has(bone):
			continue
		var body := ragdoll.get_physical_bone(bone)
		var parent_name: StringName = PHYSICAL_PARENT[bone]
		var parent := ragdoll.get_physical_bone(parent_name)
		var parent_captured := pose_capture.get_captured_pose(parent.get_bone_id())
		var captured := pose_capture.get_captured_pose(body.get_bone_id())
		var parent_pose: Transform3D = parent_captured
		if poses.has(parent_name):
			parent_pose = poses[parent_name]
		elif reacting.has(parent_name):
			var server: Transform3D = PhysicsServer3D.body_get_state(parent.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM)
			parent_pose = to_skeleton * server * parent.body_offset.affine_inverse()
		var local := parent_captured.affine_inverse() * captured
		var relative := (parent_captured.basis.inverse() * clamp_target(bone, parent_captured.basis, captured.basis, LIMIT_MARGIN)).orthonormalized()
		poses[bone] = parent_pose * Transform3D(relative, local.origin)
	return poses


## Hit entry (via LibertyCharacter.receive_hit). Fatal hits hand over to the passive ragdoll.
## Non-fatal hits loosen the hit chain, push its body and recover over hit_recovery_time;
## a hit while traversing knocks the character off first. Emits hit_received on success.
func receive_hit(bone_name: StringName, direction: Vector3, force: float, fatal: bool) -> bool:
	if configuration_error != "" or ragdoll == null or not direction.is_finite() or not is_finite(force):
		return false
	var body_name := resolve_body_bone(get_skeleton(), bone_name)
	if body_name == &"":
		return false
	if fatal:
		if not character.activate_ragdoll(direction, force, &"hit"):
			return false
		_emit_hit(bone_name, direction, force, true)
		return true
	if ragdoll.is_active():
		# Already ragdolled: only a still-simulating body can take the push.
		if ragdoll.state != LibertyRagdoll.State.SIMULATING:
			return false
		_push(ragdoll.get_physical_bone(body_name), direction, force)
		_emit_hit(bone_name, direction, force, false)
		return true
	if character.is_traversal_locked():
		character.interrupt_traversal(&"hit")
	var chain: StringName = CHAIN_OF[body_name]
	if not track([chain]):
		return false
	_chain_start[chain] = hit_strength
	_chain_elapsed[chain] = 0.0
	chain_strength[chain] = hit_strength
	# Hips is the kinematic anchor during a reaction; its push lands on Spine.
	_push(ragdoll.get_physical_bone(&"Spine" if body_name == &"Hips" else body_name), direction, force)
	_emit_hit(bone_name, direction, force, false)
	return true


## Central impulse capped at mass * max_hit_delta_v (bodies already use CCD).
func _push(body: PhysicalBone3D, direction: Vector3, force: float) -> void:
	if direction.is_zero_approx():
		return
	var magnitude := minf(maxf(force, 0.0), body.mass * max_hit_delta_v)
	PhysicsServer3D.body_apply_central_impulse(body.get_rid(), direction.normalized() * magnitude)


func _emit_hit(bone_name: StringName, direction: Vector3, force: float, fatal: bool) -> void:
	if events != null:
		events.hit_received.emit(bone_name, direction, force, fatal)


## Ends tracking immediately (no fade) and returns to pure animation.
func release() -> void:
	if ragdoll != null:
		ragdoll.end_active_simulation()
	_reset()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for joint: RID in _drives.values():
			PhysicsServer3D.free_rid(joint)
		_drives.clear()


func _reset() -> void:
	for bone: StringName in _drive_enabled.keys():
		_set_drive_enabled(bone, false)
	_engaged = false
	fade_elapsed = -1.0
	_previous_targets.clear()
	_previous_chain = {}
	for chain in CHAINS:
		chain_strength[chain] = 1.0
		_chain_elapsed[chain] = INF
		_chain_start[chain] = 1.0


func _on_ragdoll_started(_reason: StringName) -> void:
	# Passive activation owns every body from here; the ragdoll already restored them.
	_reset()


func _process_modification_with_delta(delta: float) -> void:
	if not is_tracking():
		if _engaged:
			_reset()
		return
	var frame := Engine.get_physics_frames()
	if frame == last_read_frame or delta <= 0.0:
		return # One PD application per physics step.
	var started := Time.get_ticks_usec()
	last_read_frame = frame
	last_capture_frame = pose_capture.capture_frame
	_engaged = true
	_advance_strengths(delta)
	if not _apply_tracking(delta):
		return
	_advance_fade(delta)
	last_update_usec = Time.get_ticks_usec() - started


func _advance_strengths(delta: float) -> void:
	for chain in CHAINS:
		var elapsed: float = _chain_elapsed[chain]
		if is_inf(elapsed):
			continue
		elapsed += delta
		_chain_elapsed[chain] = elapsed
		chain_strength[chain] = strength_at(elapsed, _chain_start[chain], hit_recovery_time)
		if elapsed >= hit_recovery_time:
			_chain_elapsed[chain] = INF
			chain_strength[chain] = 1.0


## Spring each reaction joint toward the clamped captured pose. Reads only the capture
## and the physics server; Jolt integrates the springs implicitly in the next step.
func _apply_tracking(delta: float) -> bool:
	var skeleton := get_skeleton()
	var skeleton_basis := skeleton.global_basis.orthonormalized()
	var skeleton_inverse := skeleton_basis.inverse()
	var character_velocity := character.velocity
	max_error_degrees = 0.0
	max_body_angular_speed = 0.0
	max_target_angular_speed = 0.0
	last_errors_degrees.clear()
	last_target_speeds.clear()
	last_separations.clear()
	var reacting := ragdoll.get_reaction_bones()
	var target_chain := {} # Skeleton-space basis each body has with every joint on target.
	for bone in reacting:
		var body := ragdoll.get_physical_bone(bone)
		var parent_name: StringName = PHYSICAL_PARENT[bone]
		var parent := ragdoll.get_physical_bone(parent_name)
		var state := PhysicsServer3D.body_get_direct_state(body.get_rid())
		var parent_state := PhysicsServer3D.body_get_direct_state(parent.get_rid())
		var omega := state.angular_velocity
		var speed := omega.length()
		var relative_speed := (state.linear_velocity - character_velocity).length()
		# A body placed this tick sits at the current pose while its parent's server state is
		# still the previous step's; its separation is only meaningful once both have stepped.
		var separation := 0.0 if Engine.get_physics_frames() - int(_joined_frame.get(bone, -10)) < 2 \
			else _joint_separation(body, parent, state, parent_state)
		last_separations[bone] = separation
		if not (omega.is_finite() and state.transform.origin.is_finite()) \
				or speed > max_angular_speed or relative_speed > max_relative_speed or separation > max_joint_separation:
			_trip_guard(bone, speed, relative_speed, separation)
			return false
		max_body_angular_speed = maxf(max_body_angular_speed, speed)
		# Joint-space target from the animated pair, clamped into the joint limits.
		var parent_animated := pose_capture.get_captured_pose(parent.get_bone_id()).basis
		var animated := pose_capture.get_captured_pose(body.get_bone_id()).basis
		var target_relative := (parent_animated.inverse() * clamp_target(bone, parent_animated, animated, LIMIT_MARGIN)).orthonormalized()
		var target_speed := 0.0
		var led := target_relative
		var strength: float = chain_strength[CHAIN_OF[bone]]
		var multiplier: float = bone_multipliers.get(bone, 1.0)
		var k := stiffness * strength * multiplier
		var d := damping * sqrt(strength * multiplier)
		if _previous_targets.has(bone):
			var step := rotation_error(_previous_targets[bone], target_relative)
			target_speed = step.length() / delta
			led = lead_target(target_relative, step / delta, d / maxf(k, 0.000001), max_lead)
			# Keep the lead inside the joint limits: a spring driven into a hard limit whips.
			led = clamp_target(bone, Basis.IDENTITY, led, LIMIT_MARGIN)
		_previous_targets[bone] = target_relative
		last_target_speeds[bone] = target_speed
		max_target_angular_speed = maxf(max_target_angular_speed, target_speed)
		# Current joint rotation from the bodies (bone frames).
		var parent_body_basis := parent_state.transform.basis * parent.body_offset.basis.inverse()
		var body_basis := state.transform.basis * body.body_offset.basis.inverse()
		var current_relative := (parent_body_basis.inverse() * body_basis).orthonormalized()
		# Spring gains per drive axis from the carried inertia about the pivot.
		var frame := drive_frame(bone)
		var inertia := _pivot_inertia(bone, body, state, reacting)
		var axes := parent_body_basis.orthonormalized() * frame
		var axis_inertia := Vector3(axes.x.dot(inertia * axes.x), axes.y.dot(inertia * axes.y), axes.z.dot(inertia * axes.z))
		var largest := maxf(axis_inertia.x, maxf(axis_inertia.y, axis_inertia.z))
		if k > 0.0 and largest > 0.0:
			led = limit_step(current_relative, led, max_torque * multiplier / (k * largest))
		_drive(bone, parent, body, frame, equilibrium_for(frame.inverse() * led * frame), axis_inertia * k, axis_inertia * d)
		# Diagnostic: skeleton-space error against the on-target chain the springs were driving
		# during the step these bodies come from (last tick's), not this tick's newer target.
		var parent_target: Basis = target_chain.get(parent_name, parent_animated)
		var body_target := (parent_target * target_relative).orthonormalized()
		target_chain[bone] = body_target
		var driven: Basis = _previous_chain.get(bone, body_target)
		last_errors_degrees[bone] = rad_to_deg(rotation_error(skeleton_inverse * body_basis, driven).length())
		max_error_degrees = maxf(max_error_degrees, last_errors_degrees[bone])
		# Gravity compensation: a full-strength chain tracks, a loosened chain sags.
		PhysicsServer3D.body_set_param(body.get_rid(), PhysicsServer3D.BODY_PARAM_GRAVITY_SCALE, 1.0 - strength)
	_previous_chain = target_chain
	return true


## Distance between the body's pivot and where its parent body says the joint anchor is.
func _joint_separation(body: PhysicalBone3D, parent: PhysicalBone3D, state: PhysicsDirectBodyState3D, parent_state: PhysicsDirectBodyState3D) -> float:
	var skeleton := get_skeleton()
	var anchor_rest := skeleton.get_bone_global_rest(body.get_bone_id()).origin
	var parent_rest := skeleton.get_bone_global_rest(parent.get_bone_id()) * parent.body_offset
	var anchor := parent_state.transform * (parent_rest.affine_inverse() * anchor_rest)
	return (state.transform * body.body_offset.affine_inverse()).origin.distance_to(anchor)


## World inertia about the body's joint pivot of the body and its simulated descendants.
## Over-estimating the load is safe here: the springs are solved implicitly.
func _pivot_inertia(bone: StringName, body: PhysicalBone3D, state: PhysicsDirectBodyState3D, reacting: Array[StringName]) -> Basis:
	var pivot := (state.transform * body.body_offset.affine_inverse()).origin
	var inertias: Array[Basis] = [state.inverse_inertia_tensor.inverse()]
	var masses: Array[float] = [body.mass]
	var offsets: Array[Vector3] = [state.transform.origin - pivot]
	for descendant: StringName in DESCENDANTS[bone]:
		if not reacting.has(descendant):
			continue # Kinematic bodies carry themselves.
		var child := ragdoll.get_physical_bone(descendant)
		var child_state := PhysicsServer3D.body_get_direct_state(child.get_rid())
		inertias.append(child_state.inverse_inertia_tensor.inverse())
		masses.append(child.mass)
		offsets.append(child_state.transform.origin - pivot)
	return pivot_inertia(inertias, masses, offsets)


## Creates (once) and updates the body's 6DOF drive joint: free linear axes, no angular
## limits (the ragdoll's own cone/hinge joint keeps anchor and limits), angular springs.
func _drive(bone: StringName, parent: PhysicalBone3D, body: PhysicalBone3D, frame: Basis,
		equilibrium: Vector3, spring_stiffness: Vector3, spring_damping: Vector3) -> void:
	var joint: RID = _drives.get(bone, RID())
	if not joint.is_valid():
		joint = PhysicsServer3D.joint_create()
		var skeleton := get_skeleton()
		var pivot_rest := skeleton.get_bone_global_rest(body.get_bone_id()).origin
		var parent_rest := skeleton.get_bone_global_rest(parent.get_bone_id()) * parent.body_offset
		var local_a := Transform3D(parent.body_offset.basis.inverse() * frame, parent_rest.affine_inverse() * pivot_rest)
		var local_b := Transform3D(body.body_offset.basis.inverse() * frame, body.body_offset.affine_inverse().origin)
		PhysicsServer3D.joint_make_generic_6dof(joint, parent.get_rid(), local_a, body.get_rid(), local_b)
		for axis in [Vector3.AXIS_X, Vector3.AXIS_Y, Vector3.AXIS_Z]:
			PhysicsServer3D.generic_6dof_joint_set_flag(joint, axis, PhysicsServer3D.G6DOF_JOINT_FLAG_ENABLE_LINEAR_LIMIT, false)
			PhysicsServer3D.generic_6dof_joint_set_flag(joint, axis, PhysicsServer3D.G6DOF_JOINT_FLAG_ENABLE_ANGULAR_LIMIT, false)
		_drives[bone] = joint
	if not _drive_enabled.get(bone, false):
		_set_drive_enabled(bone, true)
	for axis in [Vector3.AXIS_X, Vector3.AXIS_Y, Vector3.AXIS_Z]:
		PhysicsServer3D.generic_6dof_joint_set_param(joint, axis, PhysicsServer3D.G6DOF_JOINT_ANGULAR_SPRING_STIFFNESS, spring_stiffness[axis])
		PhysicsServer3D.generic_6dof_joint_set_param(joint, axis, PhysicsServer3D.G6DOF_JOINT_ANGULAR_SPRING_DAMPING, spring_damping[axis])
		PhysicsServer3D.generic_6dof_joint_set_param(joint, axis, PhysicsServer3D.G6DOF_JOINT_ANGULAR_SPRING_EQUILIBRIUM_POINT, equilibrium[axis])


func _set_drive_enabled(bone: StringName, enabled: bool) -> void:
	var joint: RID = _drives.get(bone, RID())
	_drive_enabled[bone] = enabled and joint.is_valid()
	if not joint.is_valid():
		return
	for axis in [Vector3.AXIS_X, Vector3.AXIS_Y, Vector3.AXIS_Z]:
		PhysicsServer3D.generic_6dof_joint_set_flag(joint, axis, PhysicsServer3D.G6DOF_JOINT_FLAG_ENABLE_ANGULAR_SPRING, enabled)


func is_drive_enabled(bone: StringName) -> bool:
	return _drive_enabled.get(bone, false)


## Stop condition: report and end rather than keep simulating an unstable body.
func _trip_guard(bone: StringName, speed: float, relative: float, separation: float) -> void:
	last_guard_trip = "%s: angular %.2f rad/s, relative %.2f m/s, joint separation %.3f m, stiffness %.1f, damping %.1f, physics %d Hz, fps %.1f" % [
		bone, speed, relative, separation, stiffness, damping, Engine.physics_ticks_per_second, Engine.get_frames_per_second()]
	push_warning("Active ragdoll unstable, reaction ended: " + last_guard_trip)
	release()


func _advance_fade(delta: float) -> void:
	var recovering := false
	for chain in CHAINS:
		recovering = recovering or not is_inf(_chain_elapsed[chain])
	if hold_tracking or recovering:
		fade_elapsed = -1.0
		ragdoll.set_reaction_influence(1.0)
		return
	fade_elapsed = maxf(fade_elapsed, 0.0) + delta
	var influence := 1.0 - fade_elapsed / fade_out_time
	if influence <= 0.0:
		release()
	else:
		ragdoll.set_reaction_influence(influence)


## Shortest-path rotation taking `current` to `target`, as a world-frame axis * angle
## (target = error * current).
static func rotation_error(current: Basis, target: Basis) -> Vector3:
	var q := Quaternion(target.orthonormalized()) * Quaternion(current.orthonormalized()).inverse()
	if q.w < 0.0:
		q = -q
	var s := Vector3(q.x, q.y, q.z)
	var sin_half := s.length()
	if sin_half < 0.000001:
		return s * 2.0
	return s / sin_half * (2.0 * atan2(sin_half, q.w))


static func angular_velocity_between(previous: Basis, current: Basis, delta: float) -> Vector3:
	if delta <= 0.0:
		return Vector3.ZERO
	return rotation_error(previous, current) / delta


## Drive-joint frame (bone space) for a body; see ARM_DRIVE_FRAME.
static func drive_frame(bone: StringName) -> Basis:
	return ARM_DRIVE_FRAME if ARM_BONES.has(bone) else Basis.IDENTITY


## Jolt's 6DOF angular spring settles the child frame at from_euler(e, XYZ).inverse()
## relative to the parent frame (measured), so the equilibrium for a desired relative
## rotation is the XYZ Euler of its inverse.
static func equilibrium_for(relative: Basis) -> Vector3:
	return relative.orthonormalized().inverse().get_euler(EULER_ORDER_XYZ)


## A damped spring settles `lead_time * velocity` behind a moving target; aim that far ahead.
static func lead_target(target: Basis, target_velocity: Vector3, lead_time: float, limit: float) -> Basis:
	var lead := (target_velocity * lead_time).limit_length(limit)
	if lead.length() < 0.000001:
		return target
	return (Basis(lead.normalized(), lead.length()) * target).orthonormalized()


## Moves at most `max_angle` from `current` toward `target` (spring torque = k * angle).
static func limit_step(current: Basis, target: Basis, max_angle: float) -> Basis:
	var error := rotation_error(current, target)
	if error.length() <= max_angle:
		return target
	return (Basis(error.normalized(), max_angle) * current).orthonormalized()


## Sum of each body's inertia plus m (|r|^2 E - r r^T) about a common pivot.
static func pivot_inertia(inertias: Array, masses: Array, offsets: Array) -> Basis:
	var result := Basis() * 0.0
	for index in masses.size():
		var m: float = masses[index]
		var r: Vector3 = offsets[index]
		var r2 := r.length_squared()
		var own: Basis = inertias[index]
		result.x += own.x + m * (Vector3(r2, 0, 0) - r * r.x)
		result.y += own.y + m * (Vector3(0, r2, 0) - r * r.y)
		result.z += own.z + m * (Vector3(0, 0, r2) - r * r.z)
	return result


static func strength_at(elapsed: float, start: float, recovery_time: float) -> float:
	return lerpf(start, 1.0, smoothstep(0.0, maxf(recovery_time, 0.000001), elapsed))


## Parent-first union of the closed subtrees for the given chains.
static func simulated_bodies(chains: Array) -> Array[StringName]:
	var wanted := {}
	for chain: StringName in chains:
		for body: StringName in CHAIN_BODIES.get(chain, []):
			wanted[body] = true
	var result: Array[StringName] = []
	for body: StringName in LibertyRagdoll.BONE_LAYOUT:
		if wanted.has(body):
			result.append(body)
	return result


## Nearest physical body at or above a skeleton bone; Hips when none; &"" if unknown.
static func resolve_body_bone(skeleton: Skeleton3D, bone_name: StringName) -> StringName:
	var index := skeleton.find_bone(bone_name)
	if index < 0:
		return &""
	while index >= 0:
		var name := StringName(skeleton.get_bone_name(index))
		if LibertyRagdoll.BONE_LAYOUT.has(name):
			return name
		index = skeleton.get_bone_parent(index)
	return &"Hips"


## Child rotation relative to its physical parent, expressed in the joint frame
## (cone twist about X, hinge about Z), with w >= 0.
static func joint_relative(bone: StringName, parent_basis: Basis, child_basis: Basis) -> Quaternion:
	var frame := LibertyRagdoll.joint_basis(bone)
	var q := Quaternion((frame.inverse() * (parent_basis.inverse() * child_basis).orthonormalized() * frame).orthonormalized())
	return -q if q.w < 0.0 else q


## Signed swing-twist split about a joint-frame axis: [twist angle, swing quaternion].
static func _split(q: Quaternion, axis: Vector3) -> Array:
	var along := Vector3(q.x, q.y, q.z).dot(axis)
	var twist := Quaternion(axis.x * along, axis.y * along, axis.z * along, q.w)
	if twist.length_squared() < 0.0000001:
		return [0.0, q]
	twist = twist.normalized()
	var angle := wrapf(2.0 * atan2(along, q.w), -PI, PI)
	return [angle, q * twist.inverse()]


static func _quaternion_angle(q: Quaternion) -> float:
	return 2.0 * acos(clampf(absf(q.w), 0.0, 1.0))


## Radians beyond the joint limit (negative: distance inside the nearest limit).
## Jolt measures hinge angles with the opposite sign to joint_relative (measured on the rig).
static func limit_excess(bone: StringName, q: Quaternion) -> float:
	var layout: Array = LibertyRagdoll.BONE_LAYOUT[bone]
	var limits: Array = layout[4]
	if layout[1] == PhysicalBone3D.JOINT_TYPE_HINGE:
		var split := _split(q, Vector3.BACK)
		var angle: float = split[0]
		var low := deg_to_rad(-float(limits[1]))
		var high := deg_to_rad(-float(limits[0]))
		var excess := maxf(low - angle, angle - high)
		var off_axis := _quaternion_angle(split[1])
		# Any real off-axis rotation is a violation; numerical residue is not.
		return maxf(excess, off_axis) if off_axis > 0.0005 else excess
	var cone := _split(q, Vector3.RIGHT)
	return maxf(_quaternion_angle(cone[1]) - deg_to_rad(limits[0]), absf(cone[0]) - deg_to_rad(limits[1]))


## Nearest joint-frame rotation inside every limit minus margin; hinges drop off-axis rotation.
static func clamp_relative(bone: StringName, q: Quaternion, margin: float) -> Quaternion:
	var layout: Array = LibertyRagdoll.BONE_LAYOUT[bone]
	var limits: Array = layout[4]
	if layout[1] == PhysicalBone3D.JOINT_TYPE_HINGE:
		var low := deg_to_rad(-float(limits[1])) + margin
		var high := deg_to_rad(-float(limits[0])) - margin
		var angle: float = _split(q, Vector3.BACK)[0]
		return Quaternion(Vector3.BACK, clampf(angle, low, maxf(low, high)))
	var split := _split(q, Vector3.RIGHT)
	var twist_limit := maxf(deg_to_rad(limits[1]) - margin, 0.0)
	var swing_limit := maxf(deg_to_rad(limits[0]) - margin, 0.0)
	var twist := Quaternion(Vector3.RIGHT, clampf(split[0], -twist_limit, twist_limit))
	var swing: Quaternion = split[1]
	var swing_angle := _quaternion_angle(swing)
	if swing_angle > swing_limit:
		var axis := Vector3(swing.x, swing.y, swing.z)
		swing = Quaternion(axis.normalized(), swing_limit) if axis.length() > 0.000001 else Quaternion.IDENTITY
	return swing * twist


## Target child basis (skeleton space) clamped against its physical parent's basis.
## Targets already inside the limits minus margin are returned unchanged.
static func clamp_target(bone: StringName, parent_basis: Basis, child_basis: Basis, margin: float) -> Basis:
	var q := joint_relative(bone, parent_basis, child_basis)
	if limit_excess(bone, q) <= -margin:
		return child_basis
	var frame := LibertyRagdoll.joint_basis(bone)
	return (parent_basis.orthonormalized() * frame * Basis(clamp_relative(bone, q, margin)) * frame.inverse()).orthonormalized()
