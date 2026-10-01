extends SceneTree
const Support = preload("res://modules/liberty_character/tests/liberty_test_support.gd")
const DT := 1.0 / 60.0
func _initialize() -> void: call_deferred("run")
func tick(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame
func run() -> void:
	var gate := LibertyRagdoll.new()
	var ready := false
	for i in 29: # 0.483 s of rest
		ready = gate.advance_settle(DT, .05, .1)
	Support.expect_false(ready, "0.48 s of rest is not settled")
	Support.expect_false(gate.advance_settle(DT, .5, .1), "one fast linear frame is not settled")
	Support.expect_equal(gate.settle_timer, 0.0, "fast linear frame resets the timer")
	for i in 29:
		ready = gate.advance_settle(DT, .05, .1)
	Support.expect_false(ready, "timer restarted after transient motion")
	gate.advance_settle(DT, .05, 2.0)
	Support.expect_equal(gate.settle_timer, 0.0, "fast angular frame also resets the timer")
	var frames := 0
	while not gate.advance_settle(DT, .05, .1):
		frames += 1
	Support.expect_equal(frames + 1, 30, "a new continuous 0.5 s is required")
	gate.free()

	# Live: a kick during settling postpones recovery.
	var fixture := Node3D.new()
	root.add_child(fixture)
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40, .4, 40)
	shape.shape = box
	floor_body.add_child(shape)
	fixture.add_child(floor_body)
	floor_body.position = Vector3(0, -.2, 0)
	var character = load("res://modules/liberty_character/character/liberty_character.tscn").instantiate()
	fixture.add_child(character)
	await tick(3)
	var ragdoll: LibertyRagdoll = character.get_node("Ragdoll")
	character.activate_ragdoll(Vector3.FORWARD, 150.0, &"settle_test")
	var kicked := false
	var kick_timer := 0.0
	for i in 600:
		await tick(1)
		if not kicked and ragdoll.settle_timer > .3:
			kick_timer = ragdoll.settle_timer
			ragdoll.get_physical_bone(&"Hips").apply_central_impulse(Vector3.RIGHT * 40.0)
			kicked = true
			await tick(2)
			Support.expect_equal(ragdoll.state, LibertyRagdoll.State.SIMULATING, "kicked ragdoll keeps simulating")
			Support.expect_true(ragdoll.settle_timer < kick_timer, "kick resets the settle timer")
		if ragdoll.state != LibertyRagdoll.State.SIMULATING:
			break
	Support.expect_true(kicked, "ragdoll approached settling before the kick")
	Support.expect_true(ragdoll.state == LibertyRagdoll.State.BLENDING_OUT, "recovery begins only after renewed settling")
	character.queue_free()
	quit(Support.exit_code())
