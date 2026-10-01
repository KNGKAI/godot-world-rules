class_name LibertyActiveRagdollCourse
extends Node3D
## Interactive Phase 7 acceptance course: hit the character and watch the active reaction.
const CHARACTER = preload("res://modules/liberty_character/character/liberty_character.tscn")
const PA = preload("res://modules/liberty_character/ragdoll/liberty_physical_animation.gd")
## Selectable hit targets; "random" picks any rig bone.
const TARGETS: Array[StringName] = [&"random", &"Head", &"Chest", &"Hips", &"LeftHand", &"RightHand", &"LeftUpperLeg", &"RightFoot"]
var character: LibertyCharacter
var ragdoll: LibertyRagdoll
var stage: LibertyPhysicalAnimation
var stations: Array[Dictionary] = []
var rng := RandomNumberGenerator.new()
var target_index := 0
var last_hit := ""
var _hud: Label
var _station_index := 0
var _peak_error := 0.0
var _peak_omega := 0.0
var _peak_separation := 0.0

func _ready() -> void:
	_build_world()
	character = CHARACTER.instantiate()
	add_child(character)
	ragdoll = character.get_node("Ragdoll")
	stage = ragdoll.physical_animation
	character.teleport_to(stations[0].source)
	character.get_node("Events").hit_received.connect(_on_hit)
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
	block("Floor", Transform3D(Basis.IDENTITY, Vector3(15, -.2, -20)), Vector3(60, .4, 80), 1, Color(.18, .22, .27))
	station("Standing: F / HIT, R / FATAL", Transform3D(Basis.IDENTITY, Vector3(0, 0, 0)))
	for i in 8:
		block("LaneMark%d" % i, Transform3D(Basis.IDENTITY, Vector3(10, .01, -4.0 * i)), Vector3(3, .02, .15), 1, Color(.5, .55, .6))
	station("Run lane: hold W (+Shift), hit while running", Transform3D(Basis.IDENTITY, Vector3(10, 0, 2)))
	block("HitWall", Transform3D(Basis.IDENTITY, Vector3(20.9, 1.2, -3)), Vector3(.1, 2.4, 12), 1)
	station("Beside a wall: hits push toward it", Transform3D(Basis.IDENTITY, Vector3(20, 0, 0)), Vector3.RIGHT)
	block("ClimbingWall", Transform3D(Basis.IDENTITY, Vector3(30, 3, -1.15)), Vector3(5, 6, .6))
	station("Traversal wall: hold E, climb, then hit (knocks off)", Transform3D(Basis.IDENTITY, Vector3(30, 0, 0)))

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

## push is a world direction; zero means random horizontal.
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
	_peak_error = 0.0
	_peak_omega = 0.0
	_peak_separation = 0.0

func cycle_target() -> void:
	target_index = (target_index + 1) % TARGETS.size()

func _hit_direction() -> Vector3:
	var push: Vector3 = stations[_station_index].push
	if not push.is_zero_approx():
		return push
	var angle := rng.randf_range(-PI, PI)
	return Vector3(sin(angle), rng.randf_range(-.2, .2), cos(angle)).normalized()

func _hit_bone() -> StringName:
	if TARGETS[target_index] != &"random":
		return TARGETS[target_index]
	var skeleton := ragdoll.skeleton
	return StringName(skeleton.get_bone_name(rng.randi_range(0, skeleton.get_bone_count() - 1)))

## Non-fatal hit on the selected (or a random) bone.
func hit() -> bool:
	return character.receive_hit(_hit_bone(), _hit_direction(), rng.randf_range(20.0, 300.0), false)

## Fatal hit: hands over to the Phase 6 passive ragdoll and get-up.
func fatal_hit() -> bool:
	return character.receive_hit(_hit_bone(), _hit_direction(), rng.randf_range(120.0, 320.0), true)

func _on_hit(bone: StringName, _direction: Vector3, force: float, fatal: bool) -> void:
	last_hit = "%s %s %.0f N·s" % ["FATAL" if fatal else "hit", bone, force]

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"liberty_debug_hit"):
		hit()
	elif event.is_action_pressed(&"liberty_debug_ragdoll"):
		fatal_hit()
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
	for title in ["Previous", "Reset", "Next", "Target", "HIT", "FATAL"]:
		var button := Button.new()
		button.text = title
		button.custom_minimum_size = Vector2(100, 56)
		button.focus_mode = Control.FOCUS_NONE
		controls.add_child(button)
		match title:
			"Previous": button.pressed.connect(func(): reset_station(_station_index - 1))
			"Reset": button.pressed.connect(func(): reset_station(_station_index))
			"Next": button.pressed.connect(func(): reset_station(_station_index + 1))
			"Target": button.pressed.connect(cycle_target)
			"HIT": button.pressed.connect(hit)
			"FATAL": button.pressed.connect(fatal_hit)
	# Touch input never reaches these GUI buttons; mirror them in the mobile overlay.
	var mobile := character.get_node_or_null("MobileControls") as LibertyMobileControls
	if mobile != null:
		mobile.add_custom_button("HIT", Color(0.85, 0.45, 0.2, 0.78), hit)
		mobile.add_custom_button("FATAL", Color(0.85, 0.2, 0.55, 0.78), fatal_hit)
		mobile.add_custom_button("TARGET", Color(0.35, 0.45, 0.6, 0.72), cycle_target)
		mobile.add_custom_button("NEXT", Color(0.35, 0.45, 0.6, 0.72), func(): reset_station(_station_index + 1))
		mobile.add_custom_button("RESET", Color(0.35, 0.45, 0.6, 0.72), func(): reset_station(_station_index))
		mobile.add_custom_button("PREV", Color(0.35, 0.45, 0.6, 0.72), func(): reset_station(_station_index - 1))

func _process(_delta: float) -> void:
	if _hud == null: return
	var strengths := ""
	for chain in PA.CHAINS:
		strengths += " %s %.2f" % [chain, stage.chain_strength[chain]]
	var separation := 0.0
	for bone in stage.last_separations: separation = maxf(separation, stage.last_separations[bone])
	if stage.is_tracking():
		_peak_error = maxf(_peak_error, stage.max_error_degrees)
		_peak_omega = maxf(_peak_omega, stage.max_body_angular_speed)
		_peak_separation = maxf(_peak_separation, separation)
	var mode := "passive ragdoll: %s" % ragdoll.state_name if ragdoll.is_active() else ("reacting (%d bodies)" % ragdoll.get_reaction_bones().size() if ragdoll.is_reacting() else "animated")
	_hud.text = "%s\nF / HIT: hit %s   R / FATAL: fatal hit   Target button cycles bones. Touch: top-right buttons. Esc releases mouse.\n%s | last: %s | influence %.2f\nstrength:%s\nnow: error %.1f deg, w %.1f rad/s, joint sep %.3f m, PD %d us | peak since reset: %.1f deg, %.1f rad/s, %.3f m\nphysics %d Hz, %d fps%s" % [
		stations[_station_index].title, TARGETS[target_index], mode, last_hit, ragdoll.simulator.influence, strengths,
		stage.max_error_degrees, stage.max_body_angular_speed, separation, stage.last_update_usec, _peak_error, _peak_omega, _peak_separation,
		Engine.physics_ticks_per_second, Engine.get_frames_per_second(), "\nGUARD: " + stage.last_guard_trip if stage.last_guard_trip != "" else ""]
