extends SceneTree
const S = preload("res://modules/liberty_character/tests/liberty_test_support.gd")
const Sedan = preload("res://modules/liberty_vehicle/vehicle/liberty_vehicle.tscn")
const Character = preload("res://modules/liberty_character/character/liberty_character.tscn")
const DRIVER: StringName = &"driver_front_left"
var records: Array = []
var floor_body: StaticBody3D
var character: LibertyCharacter
var vehicle: LibertyVehicle
var adapter: LibertyEventAdapter

func _initialize() -> void: call_deferred("run")
func run() -> void:
	floor_body = box(Vector3(20, -0.5, 0), Vector3(200, 1, 200), 1)
	vehicle = Sedan.instantiate() as LibertyVehicle
	vehicle.get_node("Possession").free()
	var observed := ObservedPossession.new()
	observed.name = "Possession"
	vehicle.add_child(observed)
	vehicle.position = Vector3(20, 0, 0)
	vehicle.freeze = true
	root.add_child(vehicle)
	character = Character.instantiate() as LibertyCharacter
	character.position = Vector3(18.65, 0.02, -0.4)
	root.add_child(character)
	adapter = character.get_node("EventAdapter") as LibertyEventAdapter
	character.get_node("Events").occupancy_changed.connect(func(v, s, o, mounted, cause): records.append([v, s, o, mounted, cause]))
	await frames(20)
	S.expect_true(character.is_on_floor(), "fixture is grounded")
	S.expect_true(vehicle.get_node("DriverSeat").overlaps_body(character), "exterior trigger overlaps capsule resting against chassis")
	S.expect_equal(vehicle.mass, 1320.0, "reference sedan mass")
	S.expect_equal(vehicle.collision_layer, 16, "vehicle uses layer 5 without traversal layer")
	S.expect_equal(vehicle.collision_mask, 7, "vehicle masks world, capsule and ragdoll")
	S.expect_equal(vehicle.request_mount(character, &"passenger_front_right").reason, &"seat not found", "9A rejects passenger")
	S.expect_equal(vehicle.request_dismount(DRIVER).reason, &"dismount requested from an unoccupied seat", "empty seat fails explicitly")
	character.set_traversal_lock(true)
	S.expect_equal(adapter.mount(vehicle, DRIVER).reason, &"occupant busy", "traversal mount rejected")
	S.expect_true(character.is_traversal_locked(), "mount never interrupts traversal")
	character.set_traversal_lock(false)
	character.set_body_suspended(true)
	S.expect_equal(adapter.mount(vehicle, DRIVER).reason, &"occupant busy", "suspended mount rejected")
	character.set_body_suspended(false)
	var ragdoll := character.get_node("Ragdoll") as LibertyRagdoll
	ragdoll.begin_active_simulation([&"LeftUpperArm"])
	S.expect_equal(adapter.mount(vehicle, DRIVER).reason, &"occupant busy", "reacting mount rejected")
	S.expect_true(ragdoll.is_reacting(), "reaction is not interrupted")
	ragdoll.end_active_simulation()
	character.activate_ragdoll(Vector3.ZERO, 0.0, &"test")
	S.expect_equal(adapter.mount(vehicle, DRIVER).reason, &"occupant busy", "active ragdoll mount rejected")
	S.expect_true(ragdoll.is_active(), "ragdoll is not interrupted")
	ragdoll.cancel_ragdoll()
	await frames(5)
	S.expect_equal(records.size(), 0, "rejected mounts never emit occupancy")
	var other := Sedan.instantiate() as LibertyVehicle
	other.position = Vector3(30, 0, 0)
	other.freeze = true
	root.add_child(other)
	S.expect_true(vehicle.request_mount(character, DRIVER).succeeded(), "raw seat claim succeeds")
	S.expect_equal(vehicle.request_mount(character, DRIVER).reason, &"seat already occupied", "duplicate claim rejected")
	S.expect_equal(other.request_mount(character, DRIVER).reason, &"occupant already mounted elsewhere", "cross-vehicle raw claims remain atomic")
	S.expect_true(vehicle.request_dismount(DRIVER).succeeded(), "raw release succeeds")
	other.free()
	var onfoot_camera := get_viewport_camera()
	var mobile := character.get_node("MobileControls") as LibertyMobileControls
	mobile.force_visible = true
	mobile._movement_touch = 7
	mobile._apply_movement(Vector2(0, -1))
	mobile._jump_touch = 8
	Input.action_press(&"liberty_touch_jump")
	var initial := character.global_transform
	observed.unsuspended_query = false
	S.expect_true(adapter.mount(vehicle, DRIVER).succeeded(), "adapter mounts driver")
	S.expect_false(observed.unsuspended_query, "mount exit caching runs only after capsule suspension")
	S.expect_equal(records.size(), 1, "one mount event")
	S.expect_equal(records[0], [vehicle.get_instance_id(), DRIVER, character.get_instance_id(), true, &"mount"], "typed mount payload")
	S.expect_true(character.is_body_suspended() and character.get_node("CollisionShape3D").disabled, "mount suspends capsule")
	S.expect_false(character.get_node("Rig").visible, "only Rig is hidden")
	S.expect_true(character.visible, "character root remains visible")
	S.expect_false(mobile.visible, "on-foot overlay suspended")
	S.expect_false(Input.is_action_pressed(&"liberty_touch_jump"), "held jump released before suspension")
	S.expect_false(Input.is_action_pressed(&"liberty_touch_move_forward"), "held movement released")
	S.expect_true(get_viewport_camera() == vehicle.camera_rig.chase_camera, "vehicle camera current")
	S.expect_false(character.receive_hit(&"Chest", Vector3.RIGHT, 100.0, false), "mounted nonfatal hit rejected")
	S.expect_false(character.receive_hit(&"Chest", Vector3.RIGHT, 100.0, true), "mounted fatal hit rejected")
	S.expect_false(ragdoll.begin_active_simulation([&"LeftUpperArm"]), "mounted reaction direct entry rejected")
	var pivot := character.get_node("CameraPivot") as LibertyCameraPivot
	var yaw := pivot.global_rotation.y
	var look := InputEventMouseMotion.new()
	look.relative = Vector2(100, 0)
	pivot._unhandled_input(look)
	S.expect_equal(pivot.global_rotation.y, yaw, "mounted mouse look does not reach on-foot camera")
	var query := vehicle.camera_rig.make_collision_query(Vector3.ZERO, Vector3.ONE)
	S.expect_equal(query.collision_mask, 17, "vehicle camera world/vehicle mask")
	S.expect_true(query.exclude.has(vehicle.get_rid()), "camera excludes own body")
	var probe := vehicle.possession.probe_exit(Transform3D(Basis.IDENTITY, Vector3(18.4, 0, -0.4)))
	S.expect_true(probe.succeeded(), "floor-contact-origin exit ray succeeds")
	S.expect_true(absf(probe.exit_transform.origin.y) < 0.001, "ray start offset is not applied to feet")
	S.expect_false(vehicle.possession.probe_exit(Transform3D(Basis.IDENTITY, Vector3(20, 0, 0))).succeeded(), "separate capsule query rejects chassis")
	S.expect_true(character.get_node("CollisionShape3D").disabled, "probe keeps live shape disabled")
	# A tilted authored marker must not tilt the character or its query capsule.
	var exit_marker := vehicle.get_node("DriverSeat/ExitMarker") as Node3D
	exit_marker.rotation = Vector3(0.35, 0.4, 0.25)
	var tilted_probe := vehicle.possession.probe_exit(exit_marker.global_transform)
	S.expect_true(tilted_probe.succeeded(), "tilted marker still has a grounded exit")
	S.expect_true(tilted_probe.exit_transform.basis.y.distance_to(Vector3.UP) < 0.001, "exit probe normalizes pitch/roll before checking capsule")
	var projected_forward := Vector3(exit_marker.global_basis.z.x, 0, exit_marker.global_basis.z.z).normalized()
	S.expect_true(tilted_probe.exit_transform.basis.z.distance_to(projected_forward) < 0.001, "exit preserves marker projected yaw")
	S.expect_true(adapter.dismount().succeeded(), "voluntary grounded exit")
	S.expect_true(character.global_basis.y.distance_to(Vector3.UP) < 0.001, "dismount keeps character upright")
	S.expect_equal(records.size(), 2, "one exit event")
	S.expect_true(character.get_node("Rig").visible and not character.is_body_suspended(), "exit restores character")
	S.expect_true(mobile.visible, "force-visible touch policy restored")
	S.expect_true(get_viewport_camera() == onfoot_camera, "exact stored camera restored")
	S.expect_true(pivot.global_position.distance_to(character.global_position + Vector3.UP * pivot.target_height) < 0.001, "near exit snaps top-level camera")
	await frames(1)
	S.expect_false(Input.is_action_pressed(&"liberty_touch_jump"), "touch jump still released first exit frame")
	character.teleport_to(initial)
	await frames(5)
	mobile.force_visible = false
	S.expect_true(adapter.mount(vehicle, DRIVER).succeeded(), "remount for blocked exit")
	floor_body.free()
	await frames(2)
	S.expect_equal(adapter.dismount().reason, &"no valid exit location", "no floor stays mounted")
	S.expect_equal(records.size(), 3, "failed exit emits nothing")
	S.expect_true(character.is_body_suspended() and vehicle.possession.occupant == character, "failed exit preserves claim")
	vehicle.possession.has_cached_exit = false
	vehicle.queue_free()
	await frames(2)
	S.expect_false(character.is_body_suspended(), "teardown always unsuspends")
	S.expect_true(character.global_position.distance_to(initial.origin) < 0.05, "teardown best-effort uses saved transform away from origin")
	S.expect_equal(records[-1][4], &"teardown_best_effort", "best-effort cause is explicit")
	S.expect_equal(records.size(), 4, "teardown emits exactly once")
	S.expect_false(mobile.visible, "desktop overlay policy restored")
	S.expect_true(get_viewport_camera() == onfoot_camera, "teardown restores stored camera")
	character.free()
	print("vehicle possession lifecycle PASS")
	quit(S.exit_code())

func frames(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame

func get_viewport_camera() -> Camera3D: return root.get_camera_3d()
func box(at: Vector3, size: Vector3, layer: int) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = at
	body.collision_layer = layer
	var shape := CollisionShape3D.new()
	var cube := BoxShape3D.new()
	cube.size = size
	shape.shape = cube
	body.add_child(shape)
	root.add_child(body)
	return body

class ObservedPossession extends LibertyVehiclePossession:
	var unsuspended_query := false
	func probe_exit(candidate: Transform3D) -> LibertyVehicleContracts.DismountResult:
		if is_instance_valid(occupant) and not occupant.is_body_suspended(): unsuspended_query = true
		return super.probe_exit(candidate)
