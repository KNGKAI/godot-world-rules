class_name LibertyRagdollCourse
extends Node3D
## Interactive Phase 6 acceptance course: knock the character down and watch it recover.
const CHARACTER = preload("res://modules/liberty_character/character/liberty_character.tscn")
var character: LibertyCharacter
var ragdoll: LibertyRagdoll
var stations: Array[Dictionary] = []
var rng := RandomNumberGenerator.new()
var _hud: Label
var _station_index := 0

func _ready() -> void:
	_build_world()
	character = CHARACTER.instantiate()
	add_child(character)
	ragdoll = character.get_node("Ragdoll")
	character.teleport_to(stations[0].source)
	_build_ui()

func _build_world() -> void:
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, -30, 0)
	light.light_energy = 1.4
	add_child(light)
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color(.12, .16, .22)
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color(.7, .8, 1)
	settings.ambient_light_energy = .7
	environment.environment = settings
	add_child(environment)
	block("Floor", Transform3D(Basis.IDENTITY, Vector3(20, -.2, 0)), Vector3(70, .4, 30), 1, Color(.18, .22, .27))
	station("Flat floor: R / KNOCK", Transform3D(Basis.IDENTITY, Vector3(0, 0, 0)))
	var ramp := Basis(Vector3.RIGHT, deg_to_rad(20))
	block("Ramp20", Transform3D(ramp, Vector3(10, 1.0, -4) - ramp * Vector3(0, .2, 0)), Vector3(4, .4, 6), 1, Color(.3, .45, .35))
	station("20 degree ramp: recovers", Transform3D(Basis.IDENTITY, Vector3(10, 1.1, -3.6)))
	var slope := Basis(Vector3.RIGHT, deg_to_rad(55))
	block("Slope55", Transform3D(slope, Vector3(20, 2.0, -4) - slope * Vector3(0, .2, 0)), Vector3(4, .4, 6), 1, Color(.6, .3, .22))
	station("55 degree slope: refuses until it slides off", Transform3D(Basis.IDENTITY, Vector3(20, 3.0, -4.2)))
	block("KnockWall", Transform3D(Basis.IDENTITY, Vector3(30, 1.5, -1.5)), Vector3(4, 3, .4), 1)
	station("Wall: knocked toward it", Transform3D(Basis.IDENTITY, Vector3(30, 0, 0)), Vector3.FORWARD)
	block("ClimbingWall", Transform3D(Basis.IDENTITY, Vector3(40, 3, -1.15)), Vector3(5, 6, .6))
	station("Traversal wall: hold E, climb, then knock", Transform3D(Basis.IDENTITY, Vector3(40, 0, 0)))

func block(node_name: String, xf: Transform3D, size: Vector3, layer: int = 9, color: Color = Color(.38, .52, .66)) -> StaticBody3D:
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
	body.transform = xf
	return body

## push is a local direction; zero means random horizontal.
func station(title: String, source: Transform3D, push := Vector3.ZERO) -> void:
	stations.append({"title": title, "source": source, "push": push})
	var label := Label3D.new()
	label.text = title
	label.font_size = 40
	label.pixel_size = .008
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(label)
	label.position = source.origin + Vector3(0, 2.8, -2.5)

func reset_station(index: int) -> void:
	_station_index = clampi(index, 0, stations.size() - 1)
	character.interrupt_traversal(&"reset")
	character.teleport_to(stations[_station_index].source)

## Random horizontal knockdown, or the station's scripted direction.
func knock() -> bool:
	var push: Vector3 = stations[_station_index].push
	var direction := character.global_basis * push
	if push.is_zero_approx():
		var angle := rng.randf_range(-PI, PI)
		direction = Vector3(sin(angle), 0, cos(angle))
	return character.activate_ragdoll(direction, rng.randf_range(120.0, 320.0), &"debug_knock")

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"liberty_debug_ragdoll"):
		knock()
	elif event.is_action_pressed(&"ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var column := VBoxContainer.new()
	column.position = Vector2(16, 16)
	layer.add_child(column)
	_hud = Label.new()
	column.add_child(_hud)
	var controls := HBoxContainer.new()
	column.add_child(controls)
	for title in ["Previous", "Reset", "Next", "KNOCK"]:
		var button := Button.new()
		button.text = title
		button.custom_minimum_size = Vector2(110, 56)
		button.focus_mode = Control.FOCUS_NONE
		controls.add_child(button)
		match title:
			"Previous": button.pressed.connect(func(): reset_station(_station_index - 1))
			"Reset": button.pressed.connect(func(): reset_station(_station_index))
			"Next": button.pressed.connect(func(): reset_station(_station_index + 1))
			"KNOCK": button.pressed.connect(knock)
	# Touch input never reaches these GUI buttons; mirror them in the mobile overlay.
	var mobile := character.get_node_or_null("MobileControls") as LibertyMobileControls
	if mobile != null:
		mobile.add_custom_button("KNOCK", Color(0.85, 0.2, 0.55, 0.78), knock)
		mobile.add_custom_button("NEXT", Color(0.35, 0.45, 0.6, 0.72), func(): reset_station(_station_index + 1))
		mobile.add_custom_button("RESET", Color(0.35, 0.45, 0.6, 0.72), func(): reset_station(_station_index))
		mobile.add_custom_button("PREV", Color(0.35, 0.45, 0.6, 0.72), func(): reset_station(_station_index - 1))

func _process(_delta: float) -> void:
	if _hud == null: return
	var hips := ragdoll.get_physical_bone(&"Hips")
	var linear := hips.linear_velocity.length() if ragdoll.is_active() else 0.0
	var angular := hips.angular_velocity.length() if ragdoll.is_active() else 0.0
	_hud.text = "%s\nR / KNOCK knocks down. Touch: KNOCK, PREV, RESET, NEXT (top right). Esc releases mouse.\nRagdoll: %s | face-up %s | settle %.2f / %.2f s\nHips %.2f m/s, %.2f rad/s | floor %.1f deg %s | influence %.2f" % [
		stations[_station_index].title, ragdoll.state_name, ragdoll.face_up, ragdoll.settle_timer, ragdoll.settle_time,
		linear, angular, ragdoll.last_floor_angle_degrees, ragdoll.last_rejection, ragdoll.simulator.influence]
