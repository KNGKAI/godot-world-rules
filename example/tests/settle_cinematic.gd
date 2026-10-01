extends RefCounted
## Skips whatever example sequence is running, including a successor started by the skip itself.


static func settle(tree: SceneTree) -> void:
	var director := tree.root.get_node_or_null("NeighborhoodErrand/CinematicDirector") as CinematicDirector
	if director == null:
		return
	for _round in 6:
		if not director.is_sequence_active():
			await tree.physics_frame
			if not director.is_sequence_active():
				return
		var sequence_id := director.current_sequence_id()
		director.skip()
		var frames := 0
		while director.is_sequence_active() and director.current_sequence_id() == sequence_id and frames < 240:
			await tree.physics_frame
			frames += 1
	if director.is_sequence_active():
		push_warning("Cinematic settle left %s active" % director.current_sequence_id())
