class_name LibertyRagdoll
extends Node
## Owned passive ragdoll: collapse from the captured pose, settle, then animated get-up.
## Physical bones are code-built under the skeleton's PhysicalBoneSimulator3D.

enum State {
	INACTIVE,
	SIMULATING,
	BLENDING_OUT,
	GETTING_UP,
}

const STATE_NAMES: Array[StringName] = [&"inactive", &"simulating", &"blending_out", &"getting_up"]
const RECOVERY_CLIPS: Array[StringName] = [&"get_up_front", &"get_up_back"]
const RAGDOLL_LAYER := 1 << 2
const WORLD_MASK := 1
const SIMULATING_MASK := WORLD_MASK | 16

## bone: [mass kg, joint type, end offset (bone-local), capsule radius, limits, capsule axis override]
## Cone limits are [swing, twist] degrees; hinge limits are [lower, upper] degrees about the hinge axis,
## signs measured on the real rig so hands fold forward and shins fold backward.
const BONE_LAYOUT := {
	&"Hips": [12.0, PhysicalBone3D.JOINT_TYPE_NONE, Vector3(0.0, 0.06, 0.0), 0.12, [], Vector3.RIGHT],
	&"Spine": [8.0, PhysicalBone3D.JOINT_TYPE_CONE, Vector3(0.0, 0.17, 0.0), 0.12, [20.0, 10.0]],
	&"Chest": [12.0, PhysicalBone3D.JOINT_TYPE_CONE, Vector3(0.0, 0.28, 0.0), 0.14, [25.0, 15.0]],
	&"Head": [5.0, PhysicalBone3D.JOINT_TYPE_CONE, Vector3(0.0, 0.12, 0.0), 0.1, [40.0, 30.0]],
	&"LeftUpperArm": [2.5, PhysicalBone3D.JOINT_TYPE_CONE, Vector3(0.28, 0.0, 0.0), 0.05, [80.0, 40.0]],
	&"RightUpperArm": [2.5, PhysicalBone3D.JOINT_TYPE_CONE, Vector3(-0.28, 0.0, 0.0), 0.05, [80.0, 40.0]],
	&"LeftLowerArm": [1.5, PhysicalBone3D.JOINT_TYPE_HINGE, Vector3(0.34, 0.0, 0.0), 0.045, [-140.0, 0.0]],
	&"RightLowerArm": [1.5, PhysicalBone3D.JOINT_TYPE_HINGE, Vector3(-0.34, 0.0, 0.0), 0.045, [0.0, 140.0]],
	&"LeftUpperLeg": [8.0, PhysicalBone3D.JOINT_TYPE_CONE, Vector3(0.0, -0.43, 0.0), 0.075, [60.0, 20.0]],
	&"RightUpperLeg": [8.0, PhysicalBone3D.JOINT_TYPE_CONE, Vector3(0.0, -0.43, 0.0), 0.075, [60.0, 20.0]],
	&"LeftLowerLeg": [4.0, PhysicalBone3D.JOINT_TYPE_HINGE, Vector3(0.0, -0.40, 0.0), 0.06, [0.0, 140.0]],
	&"RightLowerLeg": [4.0, PhysicalBone3D.JOINT_TYPE_HINGE, Vector3(0.0, -0.40, 0.0), 0.06, [0.0, 140.0]],
	&"LeftFoot": [1.0, PhysicalBone3D.JOINT_TYPE_CONE, Vector3(0.0, -0.04, -0.14), 0.04, [30.0, 10.0]],
	&"RightFoot": [1.0, PhysicalBone3D.JOINT_TYPE_CONE, Vector3(0.0, -0.04, -0.14), 0.04, [30.0, 10.0]],
}
## Elbows bend around the vertical T-pose axis; knees around the lateral axis.
const HINGE_AXES := {
	&"LeftLowerArm": Vector3.UP,
	&"RightLowerArm": Vector3.UP,
	&"LeftLowerLeg": Vector3.RIGHT,
	&"RightLowerLeg": Vector3.RIGHT,
}

@export_group("Settle")
@export_range(0.0, 5.0, 0.01, "or_greater") var settle_linear_speed := 0.2
@export_range(0.0, 10.0, 0.01, "or_greater") var settle_angular_speed := 0.6
@export_range(0.0, 5.0, 0.01, "or_greater") var settle_time := 0.5

@export_group("Recovery")
@export_range(0.0, 89.0, 1.0) var recovery_max_floor_angle_degrees := 45.0
@export_range(0.1, 5.0, 0.05, "or_greater") var recovery_floor_probe := 1.0
@export_range(0.01, 2.0, 0.01, "or_greater") var physical_blend_time := 0.4

@export_group("Impulse")
@export_range(0.0, 1.0, 0.05) var hip_impulse_share := 0.5

@export_group("Bodies")
@export_range(0.0, 5.0, 0.01, "or_greater") var body_linear_damp := 0.1
@export_range(0.0, 10.0, 0.01, "or_greater") var body_angular_damp := 0.8
@export_range(0.0, 1.0, 0.01) var body_friction := 0.8

var character: LibertyCharacter
var skeleton: Skeleton3D
var simulator: PhysicalBoneSimulator3D
var pose_capture: LibertyPoseCaptureModifier
var rebase: LibertyRagdollRebaseModifier
var physical_animation: LibertyPhysicalAnimation
var animation_driver: LibertyAnimationDriver
var events: LibertyEvents
var state: State = State.INACTIVE
var face_up := false
var settle_timer := 0.0
var configuration_error := ""
## Diagnostics from the most recent recovery attempt, for the course HUD and reports.
var last_floor_angle_degrees := 0.0
var last_rejection: StringName = &""

var _bones: Array[PhysicalBone3D] = []
var _by_name := {}
var _hips_bone := -1
var _belly_local := Vector3.FORWARD
var _spine_local := Vector3.UP
var _blend_elapsed := 0.0
var _reaction_bones: Array[StringName] = []

var state_name: StringName:
	get:
		return STATE_NAMES[state]


func _ready() -> void:
	character = get_parent() as LibertyCharacter
	if character == null:
		_fail("Ragdoll requires a LibertyCharacter parent")
		return
	character.ragdoll = self
	events = character.get_node_or_null(character.events_path) as LibertyEvents
	animation_driver = character.get_node_or_null("AnimationDriver") as LibertyAnimationDriver
	skeleton = character.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null:
		_fail("Missing Skeleton3D")
		return
	process_physics_priority = -5
	simulator = skeleton.get_node_or_null("PhysicalBoneSimulator") as PhysicalBoneSimulator3D
	if simulator == null:
		simulator = PhysicalBoneSimulator3D.new()
		simulator.name = "PhysicalBoneSimulator"
		simulator.active = false
		skeleton.add_child(simulator)
		skeleton.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_PHYSICS
	pose_capture = skeleton.get_node_or_null("PoseCapture") as LibertyPoseCaptureModifier
	rebase = LibertyRagdollRebaseModifier.new()
	rebase.name = "RagdollRebase"
	rebase.ragdoll = self
	skeleton.add_child(rebase)
	_build_bodies()
	if configuration_error != "":
		return
	_standby()
	# Active ragdoll stage: after the pose capture, before the simulator.
	physical_animation = LibertyPhysicalAnimation.new()
	physical_animation.name = "PhysicalAnimation"
	LibertySettings.apply(&"physical_animation", physical_animation)
	skeleton.add_child(physical_animation)
	skeleton.move_child(physical_animation, simulator.get_index())
	physical_animation.configure(self)
	character.physical_animation = physical_animation
	if animation_driver == null or not animation_driver.has_recovery():
		_fail("Missing recovery clips: " + ", ".join(RECOVERY_CLIPS))
		return
	var hips_rest := skeleton.get_bone_global_rest(_hips_bone)
	var foot := skeleton.find_bone("LeftFoot")
	var toes := skeleton.find_bone("LeftToes")
	var spine := skeleton.find_bone("Spine")
	if foot >= 0 and toes >= 0:
		var forward := skeleton.get_bone_global_rest(toes).origin - skeleton.get_bone_global_rest(foot).origin
		forward.y = 0.0
		_belly_local = (hips_rest.basis.inverse() * forward).normalized()
	if spine >= 0:
		_spine_local = (hips_rest.basis.inverse() * (skeleton.get_bone_global_rest(spine).origin - hips_rest.origin)).normalized()


func _fail(message: String) -> void:
	configuration_error = message
	push_warning(message)
	set_physics_process(false)


func _build_bodies() -> void:
	for bone_name: StringName in BONE_LAYOUT:
		var index := skeleton.find_bone(bone_name)
		if index < 0:
			_fail("Missing ragdoll bone: %s" % bone_name)
			return
		var layout: Array = BONE_LAYOUT[bone_name]
		var segment: Vector3 = layout[2]
		var radius: float = layout[3]
		var capsule_axis: Vector3 = layout[5] if layout.size() > 5 else segment.normalized()
		var body := PhysicalBone3D.new()
		body.name = "Physical" + String(bone_name)
		body.bone_name = bone_name
		body.mass = layout[0]
		body.collision_layer = RAGDOLL_LAYER
		body.collision_mask = WORLD_MASK
		body.friction = body_friction
		body.linear_damp = body_linear_damp
		body.angular_damp = body_angular_damp
		var center := segment * 0.5
		body.body_offset = Transform3D(Basis.IDENTITY, center)
		body.joint_type = layout[1]
		if body.joint_type != PhysicalBone3D.JOINT_TYPE_NONE:
			body.joint_offset = Transform3D(joint_basis(bone_name), -center)
		match body.joint_type:
			PhysicalBone3D.JOINT_TYPE_CONE:
				body.set("joint_constraints/swing_span", layout[4][0])
				body.set("joint_constraints/twist_span", layout[4][1])
			PhysicalBone3D.JOINT_TYPE_HINGE:
				body.set("joint_constraints/angular_limit_enabled", true)
				body.set("joint_constraints/angular_limit_lower", layout[4][0])
				body.set("joint_constraints/angular_limit_upper", layout[4][1])
		var collider := CollisionShape3D.new()
		var shape := CapsuleShape3D.new()
		shape.radius = radius
		shape.height = maxf(segment.length() + radius * 2.0, radius * 2.0 + 0.01)
		if bone_name == &"Hips":
			shape.height = 0.36
		collider.shape = shape
		collider.basis = _basis_from_to(Vector3.UP, capsule_axis)
		body.add_child(collider)
		simulator.add_child(body)
		# Thin limb capsules tunnel into the floor on fast impacts without CCD.
		PhysicsServer3D.body_set_enable_continuous_collision_detection(body.get_rid(), true)
		_bones.append(body)
		_by_name[bone_name] = body
	_hips_bone = skeleton.find_bone("Hips")


## Joint frame in bone space: cone twist axis (X) along the segment, hinge axis (Z)
## along HINGE_AXES. Rest bases are identity, so this is also the rest joint frame.
static func joint_basis(bone_name: StringName) -> Basis:
	var layout: Array = BONE_LAYOUT[bone_name]
	if layout[1] == PhysicalBone3D.JOINT_TYPE_HINGE:
		return _basis_from_to(Vector3.BACK, HINGE_AXES[bone_name])
	return _basis_from_to(Vector3.RIGHT, (layout[2] as Vector3).normalized())


static func _basis_from_to(from: Vector3, to: Vector3) -> Basis:
	if from.is_equal_approx(to):
		return Basis.IDENTITY
	if from.is_equal_approx(-to):
		return Basis(from.cross(Vector3.UP if absf(from.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT).normalized(), PI)
	return Basis(Quaternion(from, to))


func get_physical_bones() -> Array[PhysicalBone3D]:
	return _bones


func get_physical_bone(bone_name: StringName) -> PhysicalBone3D:
	return _by_name.get(bone_name) as PhysicalBone3D


func is_active() -> bool:
	return state != State.INACTIVE


## True while a hit reaction simulates part of the body over live animation.
func is_reacting() -> bool:
	return state == State.INACTIVE and not _reaction_bones.is_empty()


func get_reaction_bones() -> Array[StringName]:
	return _reaction_bones


## Owned physical-animation command: simulate the given bodies over live animation.
## Never suspends the character; Hips always stays kinematic as the reaction anchor.
## `poses` optionally overrides the skeleton-space bone transform each new body starts at
## (the physical animation passes joint-limit-clamped poses); others use the capture.
## `velocities` optionally sets each new body's [linear, angular] start velocity (the
## animated limb motion); others inherit the character velocity.
func begin_active_simulation(bones: Array[StringName], poses: Dictionary = {}, velocities: Dictionary = {}) -> bool:
	if configuration_error != "" or state != State.INACTIVE or is_instance_valid(character.vehicle_possession):
		return false
	return extend_active_simulation(bones, poses, velocities)


## Adds bodies to a running reaction without disturbing bodies already simulating.
func extend_active_simulation(bones: Array[StringName], poses: Dictionary = {}, velocities: Dictionary = {}) -> bool:
	if configuration_error != "" or state != State.INACTIVE or is_instance_valid(character.vehicle_possession):
		return false
	var added: Array[StringName] = []
	for bone_name in bones:
		if bone_name != &"Hips" and _by_name.has(bone_name) and not _reaction_bones.has(bone_name) and not added.has(bone_name):
			added.append(bone_name)
	if added.is_empty():
		return not _reaction_bones.is_empty()
	simulator.active = true
	if _reaction_bones.is_empty():
		simulator.influence = 1.0
	simulator.physical_bones_start_simulation(added)
	_sync_body_collision()
	_place_bodies_from_pose(character.velocity, added, poses, velocities)
	for body in _bones:
		# Keep the parent-first body order.
		var body_name := StringName(body.bone_name)
		if added.has(body_name):
			_reaction_bones.insert(_parent_first_index(body_name), body_name)
	return true


func _parent_first_index(bone_name: StringName) -> int:
	var order := BONE_LAYOUT.keys()
	var rank := order.find(bone_name)
	for index in _reaction_bones.size():
		if order.find(_reaction_bones[index]) > rank:
			return index
	return _reaction_bones.size()


func set_reaction_influence(value: float) -> void:
	if is_reacting():
		simulator.influence = clampf(value, 0.0, 1.0)


## Ends a hit reaction immediately and returns every body to animation.
func end_active_simulation() -> void:
	if _reaction_bones.is_empty():
		return
	_reaction_bones.clear()
	_restore_body_params()
	if state == State.INACTIVE:
		if simulator.is_simulating_physics():
			simulator.physical_bones_stop_simulation()
		_standby()


## Simulator on with nothing simulating and zero influence: the skeleton shows pure
## animation while every body follows it kinematically. An inactive simulator leaves the
## bodies at a stale pose, and the first reaction step would yank them into place (the
## hips jumped 0.11 m and kicked a joining leg 0.12 m off its anchor).
func _standby() -> void:
	simulator.influence = 0.0
	simulator.active = true
	_sync_body_collision()


## Physical animation adjusts per-body gravity; every exit path restores it.
func _restore_body_params() -> void:
	for body in _bones:
		PhysicsServer3D.body_set_param(body.get_rid(), PhysicsServer3D.BODY_PARAM_GRAVITY_SCALE, 1.0)


## Knockout/death entry. The requested total impulse is split between hips and chest.
func activate_ragdoll(impulse_direction: Vector3, force: float, reason: StringName) -> bool:
	if configuration_error != "" or not is_instance_valid(character) or is_instance_valid(character.vehicle_possession) or not impulse_direction.is_finite() or not is_finite(force):
		return false
	character.interrupt_traversal(reason)
	var inherited := character.velocity
	character.set_body_suspended(true)
	simulator.active = true
	simulator.influence = 1.0
	if not simulator.is_simulating_physics():
		# Starting resets bodies to the unmodified skeleton pose, so place them afterwards.
		simulator.physical_bones_start_simulation()
		_sync_body_collision()
		_place_bodies_from_pose(inherited)
	elif not _reaction_bones.is_empty():
		# Take over a hit reaction: start the kinematic rest, keep running bodies as they are.
		var remaining: Array[StringName] = []
		for body in _bones:
			if not _reaction_bones.has(StringName(body.bone_name)):
				remaining.append(StringName(body.bone_name))
		simulator.physical_bones_start_simulation(remaining)
		_sync_body_collision()
		_place_bodies_from_pose(inherited, remaining)
		_reaction_bones.clear()
		_restore_body_params()
	var direction := impulse_direction.normalized() if not impulse_direction.is_zero_approx() else Vector3.ZERO
	var impulse := direction * maxf(force, 0.0)
	get_physical_bone(&"Hips").apply_central_impulse(impulse * hip_impulse_share)
	get_physical_bone(&"Chest").apply_central_impulse(impulse * (1.0 - hip_impulse_share))
	state = State.SIMULATING
	settle_timer = 0.0
	_blend_elapsed = 0.0
	last_rejection = &""
	var camera := character.get_node_or_null(character.camera_pivot_path) as LibertyCameraPivot
	if camera != null:
		camera.set_follow_override(get_physical_bone(&"Hips"))
	if events != null:
		events.ragdoll_started.emit(reason)
	return true


## Starts each body at the IK-corrected pose captured before physical simulation.
## Written to the physics server directly; node transforms follow after the next step.
## An empty `only` places every body; `poses` overrides skeleton-space bone transforms.
func _place_bodies_from_pose(velocity: Vector3, only: Array[StringName] = [], poses: Dictionary = {}, velocities: Dictionary = {}) -> void:
	var has_capture := pose_capture != null and pose_capture.capture_frame >= 0
	for body in _bones:
		var body_name := StringName(body.bone_name)
		if not only.is_empty() and not only.has(body_name):
			continue
		var bone := body.get_bone_id()
		var pose: Transform3D = poses.get(body_name, pose_capture.get_captured_pose(bone) if has_capture else skeleton.get_bone_global_pose(bone))
		var placed := skeleton.global_transform * pose * body.body_offset
		body.global_transform = placed
		PhysicsServer3D.body_set_state(body.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, placed)
		var start: Array = velocities.get(body_name, [velocity, Vector3.ZERO])
		PhysicsServer3D.body_set_state(body.get_rid(), PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, start[0])
		PhysicsServer3D.body_set_state(body.get_rid(), PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, start[1])
		body.reset_physics_interpolation()


## Stateful settle gate: true once both hip speeds stay below threshold for settle_time.
func advance_settle(delta: float, linear_speed: float, angular_speed: float) -> bool:
	if linear_speed < settle_linear_speed and angular_speed < settle_angular_speed:
		settle_timer += delta
	else:
		settle_timer = 0.0
	return settle_timer >= settle_time - 0.000001


func _physics_process(delta: float) -> void:
	match state:
		State.SIMULATING:
			var hips := get_physical_bone(&"Hips")
			if advance_settle(delta, hips.linear_velocity.length(), hips.angular_velocity.length()):
				if not try_begin_recovery():
					settle_timer = 0.0
		State.BLENDING_OUT:
			_blend_elapsed += delta
			simulator.influence = clampf(1.0 - _blend_elapsed / physical_blend_time, 0.0, 1.0)
			if simulator.influence <= 0.0:
				simulator.physical_bones_stop_simulation()
				_standby()
				state = State.GETTING_UP
		State.GETTING_UP:
			if animation_driver.get_recovery_progress() >= 1.0 - 0.00001:
				_finish_recovery()


func get_hips_world_transform() -> Transform3D:
	var hips := get_physical_bone(&"Hips")
	return hips.global_transform * hips.body_offset.affine_inverse()


func is_face_up(hips_basis: Basis) -> bool:
	return (hips_basis * _belly_local).y > 0.0


## Validates the floor, aligns the root under the hips and starts the matching get-up clip.
func try_begin_recovery() -> bool:
	var hips_world := get_hips_world_transform()
	var hit := _probe_floor(hips_world.origin)
	if hit.is_empty():
		last_rejection = &"no_floor"
		return false
	last_floor_angle_degrees = rad_to_deg((hit.normal as Vector3).angle_to(Vector3.UP))
	if last_floor_angle_degrees > recovery_max_floor_angle_degrees:
		last_rejection = &"steep_floor"
		return false
	last_rejection = &""
	face_up = is_face_up(hips_world.basis)
	var clip: StringName = RECOVERY_CLIPS[1] if face_up else RECOVERY_CLIPS[0]
	var old_skeleton := skeleton.global_transform
	character.global_transform = compute_recovery_root(hips_world, clip, (hit.position as Vector3).y)
	character.reset_physics_interpolation()
	var simulated := PackedInt32Array()
	for body in _bones:
		simulated.append(body.get_bone_id())
	rebase.rebase(skeleton.global_transform.affine_inverse() * old_skeleton, simulated)
	if not animation_driver.play_recovery(face_up):
		last_rejection = &"animation"
		return false
	_blend_elapsed = 0.0
	state = State.BLENDING_OUT
	return true


## Yaw-only root whose authored first get-up frame places the hips where the ragdoll hips are.
func compute_recovery_root(hips_world: Transform3D, clip: StringName, floor_height: float) -> Transform3D:
	var authored := animation_driver.sample_bone_pose(clip, &"Hips", 0.0)
	var world_axis := hips_world.basis * _spine_local
	var authored_axis := authored.basis * _spine_local
	world_axis.y = 0.0
	authored_axis.y = 0.0
	var yaw := character.global_rotation.y
	if world_axis.length() > 0.2 and authored_axis.length() > 0.2:
		yaw = _yaw_of(world_axis) - _yaw_of(authored_axis)
	var basis := Basis(Vector3.UP, yaw)
	var origin := hips_world.origin - basis * authored.origin
	origin.y = floor_height
	return Transform3D(basis, origin)


static func _yaw_of(direction: Vector3) -> float:
	return atan2(-direction.x, -direction.z)


func _probe_floor(from: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(
		from + Vector3.UP * 0.25,
		from + Vector3.DOWN * recovery_floor_probe,
		WORLD_MASK
	)
	return character.get_world_3d().direct_space_state.intersect_ray(query)


## Immediately returns to animation without a get-up; used by resets and teleports.
func cancel_ragdoll() -> void:
	if state == State.INACTIVE:
		end_active_simulation()
		return
	if simulator.is_simulating_physics():
		simulator.physical_bones_stop_simulation()
	_standby()
	state = State.INACTIVE
	settle_timer = 0.0
	character.set_body_suspended(false)
	var camera := character.get_node_or_null(character.camera_pivot_path) as LibertyCameraPivot
	if camera != null:
		camera.clear_follow_override()


func _finish_recovery() -> void:
	state = State.INACTIVE
	settle_timer = 0.0
	character.set_body_suspended(false)
	var camera := character.get_node_or_null(character.camera_pivot_path) as LibertyCameraPivot
	if camera != null:
		camera.clear_follow_override()
	if events != null:
		events.ragdoll_recovered.emit(face_up)

## Start/stop copies node masks to the RID. Apply the runtime matrix afterwards.
func _sync_body_collision() -> void:
	for body in _bones:
		var simulating := body.is_simulating_physics()
		PhysicsServer3D.body_set_collision_layer(body.get_rid(), RAGDOLL_LAYER if simulating else 0)
		PhysicsServer3D.body_set_collision_mask(body.get_rid(), SIMULATING_MASK if simulating else 0)
