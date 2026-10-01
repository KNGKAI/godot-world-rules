class_name LibertyTraversalCourse
extends Node3D
const CHARACTER = preload("res://modules/liberty_character/character/liberty_character.tscn")
var character: LibertyCharacter
var stations: Array[Dictionary] = []
var _hud: Label
var _station_index := 0

func _ready() -> void:
	_build_world()
	character = CHARACTER.instantiate()
	add_child(character)
	character.teleport_to(stations[0].source)
	_build_ui()

func _build_world() -> void:
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45,-30,0)
	light.light_energy = 1.4
	add_child(light)
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color(.12,.16,.22)
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color(.7,.8,1)
	settings.ambient_light_energy = .7
	environment.environment = settings
	add_child(environment)
	block("Floor",Vector3(35,-.2,-3),Vector3(100,.4,45),1,Color(.18,.22,.27))
	for index in range(4):
		var base := float(index)*7
		var height: float = [.65,1.05,.75,1.4][index]
		var depth: float = [.4,.4,1.8,1.8][index]
		block("Obstacle",Vector3(base,height*.5,-.85-depth*.5),Vector3(3,height,depth))
		station(["Low vault","High vault","Low mantle","High mantle"][index],Transform3D(Basis.IDENTITY,Vector3(base,0,0)))
	block("ClimbingWall",Vector3(28,3,-1.15),Vector3(5,6,.6))
	station("Climb / up jump / drop",Transform3D(Basis.IDENTITY,Vector3(28,0,0)))
	block("GapLeft",Vector3(35,3,-1.15),Vector3(.7,6,.6))
	block("GapRight",Vector3(36.2,3,-1.15),Vector3(.7,6,.6))
	station("Lateral gap",Transform3D(Basis.IDENTITY,Vector3(35,0,0)))
	block("CornerFace",Vector3(42,3,-1.15),Vector3(3,6,.6))
	block("CornerSide",Vector3(42.7,3,.25),Vector3(.4,6,2.8))
	station("Inner corner",Transform3D(Basis.IDENTITY,Vector3(42,0,0)))
	block("OuterCorner",Vector3(49,3,-1.45),Vector3(.7,6,1.2))
	station("Outer corner / ledge end",Transform3D(Basis.IDENTITY,Vector3(49,0,0)))
	block("TopOut",Vector3(56,.85,-1.45),Vector3(3,1.7,1.2))
	station("Catch / top-out",Transform3D(Basis.IDENTITY,Vector3(56,0,0)))
	block("SeamA",Vector3(62.4,3,-1.15),Vector3(1.2,6,.6))
	block("SeamB",Vector3(63.6,3,-1.15),Vector3(1.2,6,.6))
	station("Collider seam",Transform3D(Basis.IDENTITY,Vector3(63,0,0)))
	block("ControlWall",Vector3(70,3,-1.15),Vector3(3,6,.6),1,Color(.65,.22,.22))
	station("Untagged control",Transform3D(Basis.IDENTITY,Vector3(70,0,0)))
	block("BlockedObstacle",Vector3(77,.375,-1.75),Vector3(3,.75,1.8))
	block("LowCeiling",Vector3(77,1.7,-1.4),Vector3(3,.3,3.5),1,Color(.6,.22,.22))
	station("Clearance rejection",Transform3D(Basis.IDENTITY,Vector3(77,0,0)))
	block("ForwardSource",Vector3(84,.85,-.9),Vector3(3,1.7,.1))
	block("ForwardTarget",Vector3(84,.85,-2.1),Vector3(3,1.7,.1))
	station("Forward gap",Transform3D(Basis.IDENTITY,Vector3(84,0,0)))

func block(node_name: String, at: Vector3, size: Vector3, layer: int = 9, color: Color = Color(.38,.52,.66)) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.collision_layer = layer
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	body.add_child(collider)
	var visual := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	visual.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	visual.material_override = material
	body.add_child(visual)
	add_child(body)
	body.position = at
	return body

func station(title: String, source: Transform3D) -> void:
	stations.append({"title":title,"source":source})
	var label := Label3D.new()
	label.text = title
	label.font_size = 40
	label.pixel_size = .008
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(label)
	label.position = source.origin + Vector3(0,2.8,-2.5)

func reset_station(index: int) -> void:
	_station_index = clampi(index,0,stations.size()-1)
	character.interrupt_traversal(&"reset")
	character.teleport_to(stations[_station_index].source)

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var column := VBoxContainer.new()
	column.position = Vector2(16,16)
	layer.add_child(column)
	_hud = Label.new()
	column.add_child(_hud)
	var controls := HBoxContainer.new()
	column.add_child(controls)
	for title in ["Previous","Reset","Next","Debug"]:
		var button := Button.new()
		button.text = title
		controls.add_child(button)
		match title:
			"Previous": button.pressed.connect(func(): reset_station(_station_index-1))
			"Reset": button.pressed.connect(func(): reset_station(_station_index))
			"Next": button.pressed.connect(func(): reset_station(_station_index+1))
			"Debug": button.pressed.connect(func(): character.get_node("Traversal").debug_traversal = not character.get_node("Traversal").debug_traversal)
	# Touch input never reaches these GUI buttons; mirror them in the mobile overlay.
	var mobile := character.get_node_or_null("MobileControls") as LibertyMobileControls
	if mobile != null:
		var tint := Color(0.35, 0.45, 0.6, 0.72)
		mobile.add_custom_button("NEXT", tint, func(): reset_station(_station_index + 1))
		mobile.add_custom_button("RESET", tint, func(): reset_station(_station_index))
		mobile.add_custom_button("PREV", tint, func(): reset_station(_station_index - 1))
		mobile.add_custom_button("DEBUG", Color(0.55, 0.45, 0.2, 0.72), func(): character.get_node("Traversal").debug_traversal = not character.get_node("Traversal").debug_traversal)

func _process(_delta: float) -> void:
	if _hud == null: return
	var traversal := character.get_node("Traversal") as LibertyTraversalCoordinator
	var alignment := measure_alignment()
	_hud.text = "%s\nHold E / CLIMB + move. Space / JUMP crosses gaps. Ctrl / DROP releases.\nTouch: PREV, RESET, NEXT, DEBUG (top right). Esc releases mouse for course buttons.\nState: %s | Clip: %s | progress %.2f\nBody alignment %.3f m / %.2f deg | correction %.3f m / %.2f deg" % [stations[_station_index].title, controller_name(traversal), traversal.animation.current_clip, traversal.animation.get_action_progress(), alignment.position, alignment.angle, traversal.motor.candidate.positional_correction if traversal.motor.candidate != null else 0.0, rad_to_deg(traversal.motor.candidate.angular_correction) if traversal.motor.candidate != null else 0.0]

func controller_name(traversal: LibertyTraversalCoordinator) -> StringName:
	return traversal.controller.STATE_NAMES[traversal.controller.state]

func measure_alignment() -> Dictionary:
	var traversal := character.get_node("Traversal") as LibertyTraversalCoordinator
	var target := traversal.controller.selected_candidate
	if target == null: return {"position":0.0,"angle":0.0}
	return {"position":character.global_position.distance_to(target.destination_transform.origin),"angle":absf(rad_to_deg(wrapf(character.global_rotation.y-target.destination_transform.basis.get_euler().y,-PI,PI)))}
