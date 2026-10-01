extends Node3D

## Interactive Phase 3 acceptance course; test-only UI and measurements.
const CharacterScene = preload("res://modules/liberty_character/character/liberty_character.tscn")
const Driver = preload("res://modules/liberty_character/animation/liberty_animation_driver.gd")

var character: LibertyCharacter
var _driver: LibertyAnimationDriver
var _tree: AnimationTree
var _skeleton: Skeleton3D
var _diagnostics: Label
var _clip := ""
var _anchors := [Vector3.ZERO, Vector3.ZERO]
var _last := [Vector3.ZERO, Vector3.ZERO]
var _contact := [false, false]
var _cycles := [0, 0]
var _excursion := [0.0, 0.0]
var _residual := [0.0, 0.0]
var _heading := Vector3.FORWARD


func _ready() -> void:
	process_physics_priority = 4
	_build_course()
	character = CharacterScene.instantiate() as LibertyCharacter
	add_child(character)
	_driver = character.get_node("AnimationDriver") as LibertyAnimationDriver
	_tree = character.get_node("AnimationTree") as AnimationTree
	_skeleton = character.get_node("Rig/Skeleton3D") as Skeleton3D
	_build_hud()


func _physics_process(_delta: float) -> void:
	_update_contact_measurement()
	var contact_text := "Hold a steady straight walk or sprint to measure contacts."
	if not _clip.is_empty():
		contact_text = "%s L/R contacts %s | max drift %.4f / %.4f m | sum residual %.4f / %.4f m" % [_clip, _cycles, _excursion[0], _excursion[1], _residual[0], _residual[1]]
	_diagnostics.text = "%s | speed %.2f m/s | playback ×%.3f\n%s" % [_driver.get_state(), character.planar_speed, float(_tree.get(Driver.TIME_SCALE_PARAMETER)), contact_text]
	if character.global_position.y < -5.0:
		reset_character()


func reset_character() -> void:
	character.teleport_to(Transform3D.IDENTITY)
	_clear_measurements("")


func place_on_ledge() -> void:
	character.teleport_to(Transform3D(Basis.IDENTITY, Vector3(8, 2.5, -7)))
	_clear_measurements("")


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()


func _update_contact_measurement() -> void:
	var selected := ""
	if _driver.get_state() == &"Locomotion" and character.is_on_floor():
		if absf(character.planar_speed - 2.2) < 0.001:
			selected = "walk"
		elif absf(character.planar_speed - 7.5) < 0.001:
			selected = "sprint"
	var heading := -character.global_basis.z
	# Turning moves the planted foot laterally: not a straight-gait drift sample.
	if heading.angle_to(_heading) > 0.001:
		selected = ""
	_heading = heading
	if selected != _clip:
		_clear_measurements(selected)
	if _clip.is_empty():
		return
	var duration := 0.8 if _clip == "walk" else 0.46
	var stance := 0.5 if _clip == "walk" else 0.32
	var time := float(_tree.get("parameters/Locomotion/BlendSpace1D/%s/current_position" % _clip))
	for side in 2:
		var phase := fposmod(time / duration + side * 0.5, 1.0)
		var planted := phase >= 0.02 and phase <= stance - 0.02
		var bone := _skeleton.find_bone("LeftFoot" if side == 0 else "RightFoot")
		var point := _skeleton.global_transform * _skeleton.get_bone_global_pose(bone).origin
		if planted:
			if not _contact[side]:
				_anchors[side] = point
				_contact[side] = true
			_last[side] = point
			_excursion[side] = maxf(_excursion[side], point.distance_to(_anchors[side]))
		elif _contact[side]:
			_residual[side] += _last[side].distance_to(_anchors[side])
			_cycles[side] += 1
			_contact[side] = false


func _clear_measurements(clip: String) -> void:
	_clip = clip
	_contact = [false, false]
	_cycles = [0, 0]
	_excursion = [0.0, 0.0]
	_residual = [0.0, 0.0]


func _build_course() -> void:
	_add_box("FlatGround", Vector3(0, -0.25, 0), Vector3(100, 0.5, 100), Color(0.19, 0.23, 0.29))
	_add_box("WalkOffLedge", Vector3(8, 1.25, -8), Vector3(5, 2.5, 6), Color(0.34, 0.46, 0.43))
	for distance in [0, 5, 10, 15, 20, 25]:
		var label := Label3D.new()
		label.name = "SpeedMarker_%d" % distance
		label.text = "%d m" % distance
		label.position = Vector3(3, 0.2, -distance)
		label.rotation_degrees.x = -90
		label.font_size = 96
		label.pixel_size = 0.005
		add_child(label)
	var ledge_label := Label3D.new()
	ledge_label.text = "Walk off this edge → Fall → Land"
	ledge_label.position = Vector3(8, 3.1, -10.5)
	ledge_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(ledge_label)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55, -25, 0)
	light.shadow_enabled = true
	add_child(light)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.09, 0.12, 0.18)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.7, 0.76, 0.85)
	environment.environment.ambient_light_energy = 0.6
	add_child(environment)


func _add_box(node_name: String, center: Vector3, size: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = center
	body.collision_layer = 1
	body.collision_mask = 0
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	var visual := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	mesh.material = material
	visual.mesh = mesh
	body.add_child(visual)
	add_child(body)


func _build_hud() -> void:
	var hud := CanvasLayer.new()
	hud.name = "HUD"
	add_child(hud)
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.position = Vector2(12, 12)
	hud.add_child(panel)
	var controls := VBoxContainer.new()
	controls.name = "Controls"
	panel.add_child(controls)
	var instructions := Label.new()
	instructions.text = "PHASE 3 • WASD move • Alt walk • Shift sprint • Space jump\nMouse / touch orbit • Esc release/capture mouse • Buttons reset position"
	controls.add_child(instructions)
	_diagnostics = Label.new()
	_diagnostics.name = "Diagnostics"
	controls.add_child(_diagnostics)
	var buttons := HBoxContainer.new()
	controls.add_child(buttons)
	var reset := Button.new()
	reset.text = "Flat-ground start"
	reset.pressed.connect(reset_character)
	buttons.add_child(reset)
	var ledge := Button.new()
	ledge.text = "Walk-off ledge"
	ledge.pressed.connect(place_on_ledge)
	buttons.add_child(ledge)
