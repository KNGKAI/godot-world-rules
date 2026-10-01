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

	for index in [4,5,8,12,6,7]:
		var accumulated_error := 0.0
		var repetitions := 20 if index in [6,7,8] else 1
		for cycle in range(repetitions):
			course.reset_station(index)
			character.teleport_to(Transform3D(Basis.IDENTITY,course.stations[index].source.origin+Vector3(0,.15 if index in [8,12] else .3,-.43)))
			await physics_frame
			await process_frame
			var values: Array[LibertyTraversalCandidate] = traversal.probe.sample(character.global_transform,false,true)
			var kind = Candidate.Kind.LEDGE_JUMP if index in [4,5,12] else (Candidate.Kind.MANTLE if index==8 else (Candidate.Kind.INNER_CORNER if index==6 else Candidate.Kind.OUTER_CORNER))
			var value: LibertyTraversalCandidate
			for c in values:
				if c.kind==kind and (index!=12 or c.destination_transform.origin.z < character.global_position.z-.8): value=c;break
			Support.expect_true(value!=null,"station %d supplies transition"%index)
			if value==null: continue
			var accepted: bool = traversal.begin_action(value,true)
			print("transition ",index," accepted=",accepted," source=",character.global_position," destination=",value.destination_transform.origin)
			Support.expect_true(accepted,"transition fits authored endpoint")
			if not accepted: continue
			var penetrated := false
			for tick in range(115):
				await physics_frame
				await process_frame
				penetrated = penetrated or overlaps_world(character)
				if traversal.motor.candidate==null: break
			Support.expect_false(penetrated,"complete action stays outside world geometry")
			print("transition endpoint ",index," position=",character.global_position," clip=",traversal.animation.current_clip," locked=",character.is_traversal_locked())
			accumulated_error += character.global_position.distance_to(value.destination_transform.origin)
			var angle_error := absf(wrapf(character.global_rotation.y-value.destination_transform.basis.get_euler().y,-PI,PI))
			Support.expect_true(angle_error < deg_to_rad(5),"transition reaches target yaw")
			Support.expect_true(character.global_position.distance_to(value.destination_transform.origin)<.01,"transition reaches destination safely")
		print("transition cycles ",index," accumulated endpoint error=",accumulated_error)
		Support.expect_true(accumulated_error < .05,"repeated corner and top-out drift stays below .05 m")
	course.queue_free()
	quit(Support.exit_code())

func overlaps_world(character: LibertyCharacter) -> bool:
	clearance_query.transform = character.global_transform * Transform3D(Basis.IDENTITY,Vector3.UP*.9)
	return not character.get_world_3d().direct_space_state.intersect_shape(clearance_query,1).is_empty()
