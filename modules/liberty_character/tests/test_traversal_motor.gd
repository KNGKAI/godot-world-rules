extends SceneTree
const Motor = preload("res://modules/liberty_character/traversal/liberty_traversal_motor.gd")
const Candidate = preload("res://modules/liberty_character/traversal/liberty_traversal_candidate.gd")
const Support = preload("res://modules/liberty_character/tests/liberty_test_support.gd")

func value(destination: Vector3) -> LibertyTraversalCandidate:
	var c := Candidate.new()
	c.kind = Candidate.Kind.MANTLE
	c.surface_normal = Vector3.BACK
	c.ledge_tangent = Vector3.RIGHT
	c.collider_instance_id = 42
	c.is_clear = true
	c.destination_transform.origin = destination
	return c

func _initialize() -> void:
	var motor = Motor.new()
	var c := value(Vector3(0.45, 0.75, -0.95))
	var authored := Transform3D(Basis.IDENTITY, Vector3(0, 0.75, -0.95))
	Support.expect_true(motor.prepare_action(c, authored), "inclusive .45 m residual accepted")
	var request = motor.compute_request(Transform3D.IDENTITY, 0.0, 1.0)
	Support.expect_true(request.displacement.is_equal_approx(Vector3.RIGHT * 0.45), "correction adds residual not full authored displacement")
	c.destination_transform.origin.x = 0.451
	Support.expect_false(motor.prepare_action(c, authored), "excessive residual rejected")
	c = value(authored.origin)
	c.destination_transform.basis = Basis(Vector3.UP, deg_to_rad(-25))
	Support.expect_true(motor.prepare_action(c, authored), "inclusive negative 25 degree yaw accepted")
	request = motor.compute_request(Transform3D.IDENTITY, 0.0, 1.0)
	Support.expect_true(absf(request.yaw_delta - deg_to_rad(-25)) < 0.00001, "yaw correction retains sign")
	c.destination_transform.basis = Basis(Vector3.UP, deg_to_rad(25.1))
	Support.expect_false(motor.prepare_action(c, authored), "excessive yaw rejected")
	c = value(Vector3(0.3, 0.75, -0.95))
	motor.prepare_action(c, authored)
	Support.expect_true(motor.compute_request(Transform3D.IDENTITY, 0, 0.15).displacement.is_zero_approx(), "no correction before .15")
	var sum := Vector3.ZERO
	for i in range(60):
		sum += motor.compute_request(Transform3D.IDENTITY, float(i)/60, float(i+1)/60).displacement
	Support.expect_true(sum.is_equal_approx(Vector3.RIGHT * 0.3), "incremental correction does not accumulate extra drift")
	Support.expect_true(motor.compute_request(Transform3D.IDENTITY, 0.75, 1.0).displacement.is_zero_approx(), "no correction after .75")
	c = value(Vector3(.35,0,-.35))
	c.destination_transform.basis = Basis(Vector3.UP,PI/2)
	var corner := c.destination_transform
	motor.prepare_action(c,corner)
	var first := motor.compute_request(Transform3D(Basis(Vector3.UP,PI/4),Vector3(.247487,0,-.102513)),0,.5)
	var second := motor.compute_request(Transform3D(Basis(Vector3.UP,PI/4),Vector3(.102513,0,-.247487)),.5,1)
	Support.expect_true((first.displacement+second.displacement).distance_to(corner.origin)<.00001,"corner authored positions stay in frozen source frame")
	motor.clear()
	Support.expect_false(motor.compute_request(Transform3D.IDENTITY, 0, 1).accepted, "cleared action cannot request stale motion")
	motor.free()
	call_deferred("body_tests")

func body_tests() -> void:
	var fixture := Node3D.new()
	root.add_child(fixture)
	var body := LibertyCharacter.new()
	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = .4
	capsule.height = 1.8
	collision.shape = capsule
	collision.position.y = .9
	body.add_child(collision)
	fixture.add_child(body)
	body.collision_layer = 2
	body.collision_mask = 1
	body.set_physics_process(false)
	var wall := StaticBody3D.new()
	var wall_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(.2,4,4)
	wall_shape.shape = box
	wall.add_child(wall_shape)
	fixture.add_child(wall)
	wall.position = Vector3(.7,1,0)
	await physics_frame
	body.set_traversal_lock(true)
	body.submit_traversal_displacement(Vector3.RIGHT, 0)
	body._physics_process(1.0/60)
	Support.expect_true(body.global_position.is_zero_approx(), "blocked request cannot penetrate wall")
	Support.expect_true(body.traversal_motion_blocked, "body exposes blocked result")
	body.submit_traversal_displacement(Vector3.FORWARD * .1, 0)
	body._physics_process(1.0/60)
	var after := body.global_position
	Support.expect_true(after.distance_to(Vector3.FORWARD * .1) < .001, "safe request goes through sole movement owner")
	body._physics_process(1.0/60)
	Support.expect_true(body.global_position.distance_to(after) < .001, "request consumed once")
	body.set_traversal_lock(false)
	Support.expect_false(body.is_movement_locked(), "traversal unlock does not leave generic lock")
	fixture.queue_free()
	quit(Support.exit_code())
