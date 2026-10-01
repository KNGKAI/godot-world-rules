extends SceneTree

const Controller = preload("res://modules/liberty_character/traversal/liberty_traversal_controller.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var scene: PackedScene = load("res://example/scenes/main.tscn")
	root.add_child(scene.instantiate())
	for i in 4:
		await physics_frame
	var neighborhood: Node3D = root.get_node("World").scenes.get_active_world_root()
	var wall: StaticBody3D = neighborhood.get_node("VaultWall")
	var box: BoxShape3D = wall.get_child(0).shape
	var player: LibertyCharacter = neighborhood.get_node("Player")
	var face_z: float = wall.global_position.z + box.size.z * 0.5
	var far_side: float = wall.global_position.z - box.size.z * 0.5
	player.teleport_to(Transform3D(Basis.IDENTITY, Vector3(0, 0.05, face_z + 0.85)))
	for i in 8:
		await physics_frame
	if not player.is_on_floor():
		push_error("Player is not grounded in front of the wall")
		quit(1)
		return
	Input.action_press(&"liberty_traverse")
	Input.action_press(&"liberty_move_forward")
	var saw_vault := false
	var crossed := false
	for i in 240:
		await physics_frame
		var traversal: LibertyTraversalCoordinator = player.get_node("Traversal")
		if traversal.controller.state == Controller.State.VAULT:
			saw_vault = true
		if player.global_position.z < far_side - 0.2 and player.is_on_floor() and not player.is_traversal_locked():
			crossed = true
			break
	Input.action_release(&"liberty_traverse")
	Input.action_release(&"liberty_move_forward")
	if not saw_vault:
		push_error("Holding traverse toward the wall never started a vault at %s" % player.global_position)
		quit(2)
		return
	if not crossed:
		push_error("Vault did not land beyond the wall at %s" % player.global_position)
		quit(3)
		return
	print("EXAMPLE_VAULT_PASS")
	quit()
