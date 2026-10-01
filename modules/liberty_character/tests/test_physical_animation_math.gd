extends SceneTree
## Static PD math, stability predicate, bone->chain mapping and closed simulated sets.
const Support = preload("res://modules/liberty_character/tests/liberty_test_support.gd")
const PA = preload("res://modules/liberty_character/ragdoll/liberty_physical_animation.gd")

func _initialize() -> void: call_deferred("run")

func near(a: Vector3, b: Vector3, tolerance := 0.0001) -> bool:
	return a.distance_to(b) < tolerance

func run() -> void:
	# Shortest-path error: a rotation of 179 degrees stays 179, 181 wraps to -179.
	var current := Basis.IDENTITY
	var e179 := PA.rotation_error(current, Basis(Vector3.UP, deg_to_rad(179.0)))
	var e181 := PA.rotation_error(current, Basis(Vector3.UP, deg_to_rad(181.0)))
	Support.expect_true(near(e179, Vector3.UP * deg_to_rad(179.0), .001), "179 degree error keeps its sign (%s)" % e179)
	Support.expect_true(near(e181, Vector3.DOWN * deg_to_rad(179.0), .001), "181 degree error takes the short way (%s)" % e181)
	Support.expect_true(near(PA.rotation_error(Basis(Vector3.RIGHT, .3), Basis(Vector3.RIGHT, .3)), Vector3.ZERO), "zero error on target")
	# Error is expressed in the frame the bases live in: target = error * current.
	var from := Basis(Vector3.FORWARD, .4)
	var to := Basis(Vector3.RIGHT, .25) * from
	Support.expect_true(near(PA.rotation_error(from, to), Vector3.RIGHT * .25), "error is left-multiplied (world-frame) rotation")
	Support.expect_true(PA.rotation_error(current, Basis(Vector3.UP, 1e-7)).is_finite(), "tiny error stays finite")
	# Angular velocity between successive targets.
	var omega := PA.angular_velocity_between(Basis.IDENTITY, Basis(Vector3.UP, .1), .05)
	Support.expect_true(near(omega, Vector3.UP * 2.0), "finite-difference target angular velocity")

	# Spring equilibrium: Jolt settles the child at from_euler(e, XYZ).inverse() (measured).
	for relative: Basis in [Basis(Vector3.RIGHT, .7), Basis(Vector3(1, 2, -1).normalized(), 1.1), Basis.from_euler(Vector3(.4, -.3, 1.2))]:
		var e := PA.equilibrium_for(relative)
		Support.expect_true(PA.rotation_error(Basis.from_euler(e, EULER_ORDER_XYZ).inverse(), relative).length() < .0001, "equilibrium reproduces %s" % e)
	Support.expect_true(PA.drive_frame(&"LeftUpperArm") == PA.ARM_DRIVE_FRAME and PA.drive_frame(&"Spine") == Basis.IDENTITY, "arms use the Z,X,Y drive frame")
	Support.expect_true(PA.ARM_DRIVE_FRAME.determinant() > .999, "arm drive frame is a proper rotation")
	# Lead: aim lead_time * velocity ahead, capped.
	var led := PA.lead_target(Basis.IDENTITY, Vector3.UP * 2.0, .05, 1.0)
	Support.expect_true(near(PA.rotation_error(Basis.IDENTITY, led), Vector3.UP * .1), "lead is velocity times lead time")
	led = PA.lead_target(Basis.IDENTITY, Vector3.UP * 100.0, .05, .5)
	Support.expect_true(is_equal_approx(PA.rotation_error(Basis.IDENTITY, led).length(), .5), "lead is capped")
	Support.expect_true(PA.lead_target(Basis(Vector3.RIGHT, .3), Vector3.ZERO, .05, 1.0).is_equal_approx(Basis(Vector3.RIGHT, .3)), "no velocity, no lead")
	# Torque cap: the target may lead the current pose by at most max_torque / k.
	var capped := PA.limit_step(Basis.IDENTITY, Basis(Vector3.BACK, 1.0), .25)
	Support.expect_true(near(PA.rotation_error(Basis.IDENTITY, capped), Vector3.BACK * .25), "step limited toward the target")
	Support.expect_true(PA.limit_step(Basis.IDENTITY, Basis(Vector3.BACK, .1), .25).is_equal_approx(Basis(Vector3.BACK, .1)), "small steps pass through")
	# Pivot inertia: own inertia plus m (|r|^2 E - r r^T) per body.
	var rod := Basis.IDENTITY * .02
	var loaded := PA.pivot_inertia([rod, Basis.IDENTITY * 0.0], [1.0, 1.5], [Vector3.ZERO, Vector3(.45, 0, 0)])
	Support.expect_true(is_equal_approx(loaded.x.x, .02), "a point mass on the axis adds nothing")
	Support.expect_true(is_equal_approx(loaded.y.y, .02 + 1.5 * .45 * .45), "a point mass adds m r^2 across the axis")
	var diagonal := PA.pivot_inertia([Basis.IDENTITY * 0.0], [2.0], [Vector3(1, 1, 0)])
	Support.expect_true(is_equal_approx(diagonal.x.y, -2.0) and is_equal_approx(diagonal.z.z, 4.0), "off-axis mass uses the full tensor")
	Support.expect_equal(PA.DESCENDANTS[&"Chest"], [&"Head", &"LeftUpperArm", &"RightUpperArm", &"LeftLowerArm", &"RightLowerArm"], "chest carries head and arms")
	Support.expect_equal(PA.DESCENDANTS[&"LeftUpperLeg"], [&"LeftLowerLeg", &"LeftFoot"], "thigh carries shin and foot")

	# Strength recovery curve.
	Support.expect_true(is_equal_approx(PA.strength_at(0.0, .15, .6), .15), "strength starts at hit strength")
	Support.expect_true(absf(PA.strength_at(.3, .15, .6) - .575) < .001, "strength is halfway at half time (smoothstep)")
	Support.expect_true(is_equal_approx(PA.strength_at(.6, .15, .6), 1.0) and is_equal_approx(PA.strength_at(2.0, .15, .6), 1.0), "strength is full at recovery time")
	Support.expect_true(PA.strength_at(.1, .15, .6) < PA.strength_at(.2, .15, .6), "strength rises monotonically")

	# Chains and closed simulated sets.
	var chains := {}
	for body: StringName in LibertyRagdoll.BONE_LAYOUT:
		if body == &"Hips": continue
		chains[PA.CHAIN_OF[body]] = true
	Support.expect_equal(chains.size(), 5, "every non-root body belongs to one of five chains")
	Support.expect_equal(PA.CHAIN_OF[&"Hips"], &"core", "hips belong to the core chain")
	var core := PA.simulated_bodies([&"core"])
	for body: StringName in [&"Spine", &"Chest", &"Head", &"LeftUpperArm", &"LeftLowerArm", &"RightUpperArm", &"RightLowerArm"]:
		Support.expect_true(core.has(body), "core simulates %s" % body)
	Support.expect_false(core.has(&"Hips"), "hips are never simulated in a reaction")
	Support.expect_false(core.has(&"LeftUpperLeg"), "legs are not part of the core subtree")
	var mixed := PA.simulated_bodies([&"left_leg", &"right_arm", &"right_arm"])
	Support.expect_equal(mixed, [&"RightUpperArm", &"RightLowerArm", &"LeftUpperLeg", &"LeftLowerLeg", &"LeftFoot"], "union is deduplicated and parent-first")
	var skeleton := load("res://assets/characters/liberty_mannequin/liberty_mannequin.glb").instantiate().find_child("Skeleton3D", true, false) as Skeleton3D
	var expected := {
		&"LeftHand": &"LeftLowerArm", &"RightToes": &"RightFoot", &"Neck": &"Chest", &"UpperChest": &"Chest",
		&"LeftShoulder": &"Chest", &"Root": &"Hips", &"Hips": &"Hips", &"LeftLowerLeg": &"LeftLowerLeg",
	}
	for bone: StringName in expected:
		Support.expect_equal(PA.resolve_body_bone(skeleton, bone), expected[bone], "%s resolves to its nearest simulated body" % bone)
	Support.expect_equal(PA.resolve_body_bone(skeleton, &"Tail"), &"", "unknown bone resolves to nothing")
	skeleton.get_owner().free()
	quit(Support.exit_code())
