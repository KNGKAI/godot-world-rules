extends SceneTree
const Probe = preload("res://modules/liberty_character/traversal/liberty_traversal_probe.gd")
const Candidate = preload("res://modules/liberty_character/traversal/liberty_traversal_candidate.gd")
const Support = preload("res://modules/liberty_character/tests/liberty_test_support.gd")

func box(parent: Node3D, at: Vector3, size: Vector3, layer: int = 9, moving: bool = false) -> StaticBody3D:
	var body: StaticBody3D = AnimatableBody3D.new() if moving else StaticBody3D.new()
	body.collision_layer = layer
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	parent.add_child(body)
	body.position = at
	return body

func has_kind(values: Array[LibertyTraversalCandidate], kind: Candidate.Kind) -> bool:
	for value in values:
		if value.kind == kind:
			return true
	return false

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var fixture := Node3D.new()
	root.add_child(fixture)
	var probe = Probe.new()
	fixture.add_child(probe)
	box(fixture, Vector3(0, -0.2, 0), Vector3(110, 0.4, 20), 1)
	var ledge := box(fixture, Vector3(0, 0.5, -0.95), Vector3(3, 1, 0.7))
	box(fixture, Vector3(5, 0.5, -0.95), Vector3(3, 1, 0.7), 1)
	box(fixture, Vector3(10, 0.5, -0.95), Vector3(3, 1, 0.7))
	box(fixture, Vector3(10, 1.7, -1.05), Vector3(3, 0.3, 3.5), 1)
	box(fixture, Vector3(15, 3, -0.95), Vector3(3, 6, 0.7))
	box(fixture, Vector3(20, 0.5, -0.95), Vector3(3, 1, 0.7), 9, true)
	box(fixture, Vector3(25, 0.5, -2.5), Vector3(3, 1, 0.7))
	# Two tall surfaces with a 0.5 m gap; movement alone must not cross it.
	box(fixture, Vector3(30, 3, -0.95), Vector3(0.7, 6, 0.7))
	box(fixture, Vector3(31.2, 3, -0.95), Vector3(0.7, 6, 0.7))
	# Inside corner, leaving capsule clearance around the hand contacts.
	box(fixture, Vector3(35, 3, -0.95), Vector3(3, 6, 0.7))
	box(fixture, Vector3(35.7, 3, 0.3), Vector3(0.4, 6, 2.5))
	box(fixture, Vector3(45, 1.7, -0.95), Vector3(3, 0.6, 0.7))
	var tilted := box(fixture, Vector3(40, 3, -0.95), Vector3(3, 6, 0.7))
	tilted.rotation.x = deg_to_rad(-2.0)
	var self_body := CharacterBody3D.new()
	self_body.collision_layer = 9
	var self_collision := CollisionShape3D.new()
	var self_capsule := CapsuleShape3D.new()
	self_capsule.radius = 0.4
	self_capsule.height = 1.8
	self_collision.shape = self_capsule
	self_collision.position.y = 0.9
	self_body.add_child(self_collision)
	fixture.add_child(self_body)
	self_body.position.x = -10.0
	box(fixture, Vector3(-10, 0.5, -0.95), Vector3(3, 1, 0.7))
	await physics_frame
	await physics_frame
	var values: Array[LibertyTraversalCandidate] = probe.sample(Transform3D.IDENTITY)
	Support.expect_true(has_kind(values, Candidate.Kind.MANTLE), "tagged ledge has mantle")
	Support.expect_true(has_kind(values, Candidate.Kind.VAULT), "low obstacle has vault")
	for value in values:
		Support.expect_true(value.is_valid(), "all observations validated")
		Support.expect_equal(value.collider_instance_id, ledge.get_instance_id(), "correct collider identity")
		Support.expect_true(value.is_geometric_ledge, "real edge takes precedence")
	Support.expect_true(probe.sample(Transform3D(Basis.IDENTITY, Vector3(5, 0, 0))).is_empty(), "world-only wall ignored")
	var blocked = probe.sample(Transform3D(Basis.IDENTITY, Vector3(10, 0, 0)))
	Support.expect_true(blocked.is_empty(), "blocked destinations rejected")
	var virtual: Array[LibertyTraversalCandidate] = probe.sample(Transform3D(Basis.IDENTITY, Vector3(15, 0, 0)))
	Support.expect_true(has_kind(virtual, Candidate.Kind.HANG), "tall wall yields virtual hang")
	Support.expect_true(has_kind(virtual, Candidate.Kind.SHIMMY), "wall yields lateral continuation")
	Support.expect_true(has_kind(virtual, Candidate.Kind.CLIMB), "wall yields vertical continuation")
	for value in virtual:
		Support.expect_false(value.is_geometric_ledge, "virtual holds not geometric")
		Support.expect_true(value.left_hand_target.distance_to(value.right_hand_target) > 0.3, "hands have spacing")
	Support.expect_true(probe.sample(Transform3D(Basis.IDENTITY, Vector3(20, 0, 0))).is_empty(), "moving tagged geometry ignored")
	Support.expect_true(probe.sample(Transform3D(Basis.IDENTITY, Vector3(25, 0, 0))).is_empty(), "unreachable wall ignored")
	var gap: Array[LibertyTraversalCandidate] = probe.sample(Transform3D(Basis.IDENTITY, Vector3(30, 0, 0)))
	Support.expect_true(has_kind(gap, Candidate.Kind.LEDGE_JUMP), "local gap yields explicit jump opportunity")
	var corner: Array[LibertyTraversalCandidate] = probe.sample(Transform3D(Basis.IDENTITY, Vector3(35, 0, 0)))
	Support.expect_true(has_kind(corner, Candidate.Kind.INNER_CORNER), "perpendicular wall yields inside corner")
	Support.expect_true(has_kind(gap, Candidate.Kind.OUTER_CORNER), "wall end yields outside corner")
	var unsupported_feet: Array[LibertyTraversalCandidate] = probe.sample(Transform3D(Basis.IDENTITY, Vector3(45, 0.3, 0)))
	Support.expect_false(has_kind(unsupported_feet, Candidate.Kind.HANG), "floating ledge without foot support rejects sustained hang")
	var tilted_values: Array[LibertyTraversalCandidate] = probe.sample(Transform3D(Basis.IDENTITY, Vector3(40, 0, 0)))
	Support.expect_true(not tilted_values.is_empty(), "slightly tilted wall remains eligible")
	for value in tilted_values:
		Support.expect_true(value.destination_transform.basis.y.distance_to(Vector3.UP) < 0.000001, "capsule destination remains upright on sloped wall")
	probe.character_body = self_body
	var self_samples: Array[LibertyTraversalCandidate] = probe.sample(Transform3D(Basis.IDENTITY, Vector3(-10, 0, 0)))
	Support.expect_true(has_kind(self_samples, Candidate.Kind.MANTLE), "exclude character RID from capsule/ray queries")
	for value in self_samples:
		Support.expect_true(value.collider_instance_id != self_body.get_instance_id(), "character cannot be its own hold")
	probe.character_body = null
	var invalid := Transform3D.IDENTITY
	invalid.origin.x = NAN
	Support.expect_true(probe.sample(invalid).is_empty(), "invalid source rejected")
	quit(Support.exit_code())
