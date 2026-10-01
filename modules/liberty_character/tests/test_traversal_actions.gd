extends SceneTree
const Support = preload("res://modules/liberty_character/tests/liberty_test_support.gd")
const Candidate = preload("res://modules/liberty_character/traversal/liberty_traversal_candidate.gd")
var clearance_query := PhysicsShapeQueryParameters3D.new()
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var course = load("res://modules/liberty_character/tests/test_traversal.tscn").instantiate()
	root.add_child(course)
	var character: LibertyCharacter = course.character
	var traversal = character.get_node("Traversal")
	traversal.set_physics_process(false)
	var capsule := CapsuleShape3D.new()
	# Ignore the 2 mm physics contact skin; measure actual geometry overlap.
	capsule.radius = .398
	capsule.height = 1.796
	clearance_query.shape = capsule
	clearance_query.collision_mask = 1
	clearance_query.exclude = [character.get_rid()]

	for index in range(4):
		var accumulated_error := 0.0
		for cycle in range(4 if "--quick" in OS.get_cmdline_user_args() else 20):
			course.reset_station(index)
			await physics_frame
			await process_frame
			var kind = Candidate.Kind.VAULT if index < 2 else Candidate.Kind.MANTLE
			var values: Array[LibertyTraversalCandidate] = traversal.probe.sample(character.global_transform,true)
			var value: LibertyTraversalCandidate
			for c in values:
				if c.kind == kind: value = c;break
			Support.expect_true(value != null,"station %d yields action" % index)
			if value == null: continue
			var accepted: bool = traversal.begin_action(value,false)
			Support.expect_true(accepted,"station %d fits authored correction bounds" % index)
			if not accepted: continue
			var penetrated := false
			for tick in range(125):
				await physics_frame
				await process_frame
				penetrated = penetrated or overlaps_world(character)
				if not character.is_traversal_locked(): break
			Support.expect_false(penetrated,"complete action stays outside world geometry")
			var error := character.global_position.distance_to(value.destination_transform.origin)
			if error >= .01: print("failed cycle ",index,"/",cycle," position=",character.global_position," expected=",value.destination_transform.origin," clip=",traversal.animation.current_clip," progress=",traversal.animation.get_action_progress())
			accumulated_error += error
			Support.expect_true(error < .01,"station %d completes without snap/drift" % index)
			Support.expect_false(character.is_traversal_locked(),"station %d returns locomotion" % index)
		print("20 action cycles ",index," accumulated endpoint error=",accumulated_error)
		Support.expect_true(accumulated_error < .05,"twenty cycles keep accumulated endpoint residual below .05 m")
	course.queue_free()
	quit(Support.exit_code())

func overlaps_world(character: LibertyCharacter) -> bool:
	clearance_query.transform = character.global_transform * Transform3D(Basis.IDENTITY,Vector3.UP*.9)
	return not character.get_world_3d().direct_space_state.intersect_shape(clearance_query,1).is_empty()
