extends RefCounted
## Visual neighborhood around the errand coordinates. Collision stays off the
## package, contact, home door, sedan door, and the sedan's forward road.

const WORLD_LAYER := 1
const VAULT_LAYER := 9


static func build(parent: Node3D) -> void:
	_solid(parent, Vector3(0, -0.5, -10), Vector3(52, 1, 56), WORLD_LAYER, Color(0.34, 0.46, 0.27), &"Ground")
	_visual(parent, Vector3(0, 0.02, 8.6), Vector3(50, 0.04, 14.4), Color(0.67, 0.65, 0.6))
	_visual(parent, Vector3(8, 0.025, -18), Vector3(8, 0.04, 32), Color(0.17, 0.18, 0.2))
	for z in range(-30, -4, 4):
		_visual(parent, Vector3(8, 0.05, z), Vector3(0.14, 0.02, 1.5), Color(0.86, 0.82, 0.55))
	_visual(parent, Vector3(-8, 0.03, -24), Vector3(6.5, 0.05, 7.5), Color(0.42, 0.3, 0.14))
	# Liberty's grounded vault accepts a ledge up to 1.1 m and needs a landing past a
	# depth of about 0.4 m. The traversal course's high vault is 1.05 m by 0.4 m.
	# The previous 1.5 m by 0.8 m wall was above both the vault and mantle limits.
	_solid(parent, Vector3(0, 0.525, 0), Vector3(50, 1.05, 0.4), VAULT_LAYER, Color(0.55, 0.4, 0.26), &"VaultWall")
	_solid(parent, Vector3(0, 1.1, 17.3), Vector3(52, 2.2, 0.45), WORLD_LAYER, Color(0.45, 0.47, 0.5), &"SouthFence")
	_solid(parent, Vector3(0, 1.1, -37.3), Vector3(52, 2.2, 0.45), WORLD_LAYER, Color(0.45, 0.47, 0.5), &"NorthFence")
	_solid(parent, Vector3(-25.3, 1.1, -10), Vector3(0.45, 2.2, 56), WORLD_LAYER, Color(0.45, 0.47, 0.5), &"WestFence")
	_solid(parent, Vector3(25.3, 1.1, -10), Vector3(0.45, 2.2, 56), WORLD_LAYER, Color(0.45, 0.47, 0.5), &"EastFence")
	_house(parent, Vector3(-16.5, 0, 8.5), Vector3(7, 3.4, 6), Color(0.74, 0.58, 0.45), Color(0.4, 0.24, 0.22), &"HomeHouse")
	_visual(parent, Vector3(-11.2, 2.55, 7.2), Vector3(2.4, 0.12, 2.8), Color(0.32, 0.2, 0.18))
	_house(parent, Vector3(18.5, 0, 9), Vector3(6, 3.2, 7), Color(0.63, 0.68, 0.72), Color(0.3, 0.33, 0.38), &"EastHouse")
	_house(parent, Vector3(-17, 0, -14), Vector3(7, 3.6, 8), Color(0.58, 0.64, 0.5), Color(0.28, 0.33, 0.26), &"NorthWestHouse")
	_house(parent, Vector3(19, 0, -18), Vector3(6, 3.3, 10), Color(0.7, 0.63, 0.52), Color(0.36, 0.28, 0.24), &"NorthEastHouse")
	_solid(parent, Vector3(0, 0.85, -9.15), Vector3(1.7, 1.7, 0.7), WORLD_LAYER, Color(0.25, 0.38, 0.28), &"ContactCounter")
	_tree(parent, Vector3(-5, 0, 14))
	_tree(parent, Vector3(21.5, 0, -30))
	_tree(parent, Vector3(-20, 0, -28))
	_beacon(parent, Vector3(2, 0, 7), Color.GOLD, "PACKAGE")
	_beacon(parent, Vector3(0, 0, -7), Color.GREEN, "DELIVER")
	_beacon(parent, Vector3(-8, 0, 7), Color.CORNFLOWER_BLUE, "HOME")
	_beacon(parent, Vector3(-8, 0, -24), Color(0.95, 0.62, 0.16), "PARK")


static func _house(parent: Node3D, origin: Vector3, size_value: Vector3, wall: Color, roof: Color, house_name: StringName) -> void:
	_solid(parent, origin + Vector3(0, size_value.y * 0.5, 0), size_value, WORLD_LAYER, wall, house_name)
	_visual(parent, origin + Vector3(0, size_value.y + 0.18, 0), Vector3(size_value.x + 0.6, 0.36, size_value.z + 0.6), roof)


static func _tree(parent: Node3D, at: Vector3) -> void:
	var trunk := StaticBody3D.new()
	trunk.position = at + Vector3(0, 0.8, 0)
	trunk.collision_layer = WORLD_LAYER
	trunk.collision_mask = 0
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = 0.18
	cylinder.height = 1.6
	shape.shape = cylinder
	trunk.add_child(shape)
	var trunk_mesh := MeshInstance3D.new()
	var trunk_cylinder := CylinderMesh.new()
	trunk_cylinder.top_radius = 0.16
	trunk_cylinder.bottom_radius = 0.2
	trunk_cylinder.height = 1.6
	trunk_mesh.mesh = trunk_cylinder
	trunk_mesh.material_override = _material(Color(0.38, 0.26, 0.16))
	trunk.add_child(trunk_mesh)
	parent.add_child(trunk)
	_visual(parent, at + Vector3(0, 2.15, 0), Vector3(1.5, 1.5, 1.5), Color(0.24, 0.42, 0.22))


static func _beacon(parent: Node3D, at: Vector3, color: Color, text: String) -> void:
	_visual(parent, at + Vector3(0, 0.55, 0), Vector3(0.16, 1.1, 0.16), color)
	_visual(parent, at + Vector3(0, 1.16, 0), Vector3(0.5, 0.1, 0.5), color)
	var label := Label3D.new()
	label.text = text
	label.font_size = 42
	label.modulate = color
	label.position = at + Vector3(0, 1.7, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.outline_size = 8
	label.outline_modulate = Color(0.05, 0.05, 0.05)
	label.no_depth_test = true
	parent.add_child(label)


static func _solid(parent: Node3D, at: Vector3, size_value: Vector3, layer_value: int, color: Color, body_name: StringName) -> void:
	var body := StaticBody3D.new()
	body.name = body_name
	body.position = at
	body.collision_layer = layer_value
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size_value
	shape.shape = box_shape
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = size_value
	mesh.mesh = box_mesh
	mesh.material_override = _material(color)
	body.add_child(mesh)
	parent.add_child(body)


static func _visual(parent: Node3D, at: Vector3, size_value: Vector3, color: Color) -> void:
	var mesh := MeshInstance3D.new()
	mesh.position = at
	var box_mesh := BoxMesh.new()
	box_mesh.size = size_value
	mesh.mesh = box_mesh
	mesh.material_override = _material(color)
	parent.add_child(mesh)


static func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.86
	return material
