extends Node3D

## Standalone asset viewer. This scene never instances LibertyCharacter.
const ASSET = preload("res://assets/characters/liberty_mannequin/liberty_mannequin.glb")
const MANIFEST_PATH := "res://assets/characters/liberty_mannequin/animation_manifest.json"

var rig: Node3D
var manifest: Dictionary
var clip_names: Array[String] = []
var animation_key: StringName
var clip_duration := 0.0
var _player: AnimationPlayer
var _skeleton: Skeleton3D
var _root_bone := -1
var _playing := true
var _show_root_motion := true
var _speed := 1.0
var _selector: OptionButton
var _timeline: HSlider
var _time_label: Label
var _details: Label
var _play_button: Button
var _camera: Camera3D
var _yaw := 0.45
var _distance := 4.3
var _previous_touch_emulation := false


func _ready() -> void:
	# Gameplay uses custom touch controls, but standard popup menus need mouse
	# emulation to select items and dismiss their exclusive input window.
	_previous_touch_emulation = Input.emulate_mouse_from_touch
	Input.emulate_mouse_from_touch = true
	manifest = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	rig = ASSET.instantiate() as Node3D
	add_child(rig)
	_player = rig.find_child("AnimationPlayer", true, false) as AnimationPlayer
	_skeleton = rig.find_child("Skeleton3D", true, false) as Skeleton3D
	_root_bone = _skeleton.find_bone("Root")
	_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	for clip in manifest["clips"]:
		clip_names.append(String(clip))
	_build_stage()
	_build_controls()
	select_clip("idle")
	_update_camera()


func _exit_tree() -> void:
	Input.emulate_mouse_from_touch = _previous_touch_emulation


func _process(delta: float) -> void:
	if _playing:
		_player.advance(delta * _speed)
		if _player.current_animation_position >= clip_duration and not manifest["clips"][String(animation_key).get_file()]["loop"]:
			set_playing(false)
	_update_root_display()
	_timeline.set_value_no_signal(_player.current_animation_position)
	_time_label.text = "%.2f / %.2f s" % [_player.current_animation_position, clip_duration]


func select_clip(clip: String) -> bool:
	if not manifest["clips"].has(clip):
		return false
	var found := false
	for key in _player.get_animation_list():
		if String(key).get_file() == clip:
			animation_key = key
			found = true
			break
	if not found:
		return false
	_player.stop()
	_skeleton.reset_bone_poses()
	rig.transform = Transform3D.IDENTITY
	clip_duration = _player.get_animation(animation_key).length
	_player.play(animation_key)
	_player.seek(0.0, true)
	_player.advance(0.0)
	if not _playing:
		_player.pause()
	_timeline.max_value = clip_duration
	_timeline.set_value_no_signal(0.0)
	_selector.select(clip_names.find(clip))
	var data: Dictionary = manifest["clips"][clip]
	_details.text = "%s • %s • root Δ %s m" % [clip, "loop" if data["loop"] else "one-shot", str(data["root_displacement"])]
	_update_root_display()
	return true


func set_playing(value: bool) -> void:
	_playing = value
	if value:
		if _player.current_animation_position >= clip_duration and _player.get_animation(animation_key).loop_mode == Animation.LOOP_NONE:
			_player.seek(0.0, true)
		_player.play(animation_key)
	else:
		_player.pause()
	_play_button.text = "Pause" if value else "Play"


func scrub(seconds: float) -> void:
	set_playing(false)
	_player.seek(clampf(seconds, 0.0, clip_duration), true)
	_player.advance(0.0)
	_update_root_display()
	_timeline.set_value_no_signal(_player.current_animation_position)
	_time_label.text = "%.2f / %.2f s" % [_player.current_animation_position, clip_duration]


func set_root_motion_visible(value: bool) -> void:
	_show_root_motion = value
	_update_root_display()


func _update_root_display() -> void:
	if _show_root_motion:
		rig.transform = Transform3D.IDENTITY
	else:
		# Cancel both translation and yaw without altering authored bone poses.
		var root_pose := _skeleton.transform * _skeleton.get_bone_global_pose(_root_bone)
		rig.transform = root_pose.affine_inverse()
	_update_camera()


func _update_camera() -> void:
	var target := Vector3(0.0, 1.0, 0.0)
	if _show_root_motion:
		target += _skeleton.get_bone_global_pose(_root_bone).origin
	_camera.position = target + Vector3(sin(_yaw) * _distance, _distance * 0.25, -cos(_yaw) * _distance)
	_camera.look_at(target)


func _build_stage() -> void:
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color(0.045, 0.065, 0.09)
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color(0.68, 0.78, 0.90)
	settings.ambient_light_energy = 0.65
	environment.environment = settings
	add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45.0, -35.0, 0.0)
	light.light_energy = 1.5
	light.shadow_enabled = true
	add_child(light)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-25.0, 145.0, 0.0)
	fill.light_color = Color(0.45, 0.68, 1.0)
	fill.light_energy = 0.6
	add_child(fill)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(12.0, 12.0)
	floor_mesh.mesh = plane
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.12, 0.16, 0.21)
	material.roughness = 0.9
	floor_mesh.material_override = material
	add_child(floor_mesh)
	# Meter lines make root displacement visible in the preview.
	var lines := ImmediateMesh.new()
	lines.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in range(-6, 7):
		lines.surface_add_vertex(Vector3(i, 0.002, -6))
		lines.surface_add_vertex(Vector3(i, 0.002, 6))
		lines.surface_add_vertex(Vector3(-6, 0.002, i))
		lines.surface_add_vertex(Vector3(6, 0.002, i))
	lines.surface_end()
	var grid := MeshInstance3D.new()
	grid.mesh = lines
	var grid_material := StandardMaterial3D.new()
	grid_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	grid_material.albedo_color = Color(0.22, 0.30, 0.38)
	grid.material_override = grid_material
	add_child(grid)
	_camera = Camera3D.new()
	_camera.current = true
	_camera.fov = 45.0
	add_child(_camera)


func _build_controls() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	layer.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	panel.offset_top = -205.0
	var margin := MarginContainer.new()
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 12)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	margin.add_child(column)
	var title := Label.new()
	title.text = "LIBERTY MANNEQUIN  •  30 animations  •  standalone asset preview"
	column.add_child(title)
	var row := HBoxContainer.new()
	column.add_child(row)
	_selector = OptionButton.new()
	_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for clip in clip_names:
		_selector.add_item(clip)
	_selector.item_selected.connect(func(index: int): select_clip(clip_names[index]))
	row.add_child(_selector)
	_play_button = Button.new()
	_play_button.text = "Pause"
	_play_button.pressed.connect(func(): set_playing(not _playing))
	row.add_child(_play_button)
	var restart := Button.new()
	restart.text = "Restart"
	restart.pressed.connect(func(): select_clip(clip_names[_selector.selected]))
	row.add_child(restart)
	var motion := CheckButton.new()
	motion.text = "Root motion"
	motion.button_pressed = true
	motion.toggled.connect(set_root_motion_visible)
	row.add_child(motion)
	var timeline_row := HBoxContainer.new()
	column.add_child(timeline_row)
	_timeline = HSlider.new()
	_timeline.step = 0.001
	_timeline.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_timeline.value_changed.connect(scrub)
	timeline_row.add_child(_timeline)
	_time_label = Label.new()
	_time_label.custom_minimum_size.x = 135.0
	timeline_row.add_child(_time_label)
	var camera_row := HBoxContainer.new()
	column.add_child(camera_row)
	var speed_label := Label.new()
	speed_label.text = "Speed"
	camera_row.add_child(speed_label)
	var speed := OptionButton.new()
	for value in [0.25, 0.5, 1.0, 1.5, 2.0]:
		speed.add_item("%.2f×" % value)
	speed.select(2)
	speed.item_selected.connect(func(index: int): _speed = [0.25, 0.5, 1.0, 1.5, 2.0][index])
	camera_row.add_child(speed)
	var orbit_label := Label.new()
	orbit_label.text = "Orbit"
	camera_row.add_child(orbit_label)
	var orbit := HSlider.new()
	orbit.min_value = -PI
	orbit.max_value = PI
	orbit.step = 0.01
	orbit.value = _yaw
	orbit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	orbit.value_changed.connect(func(value: float): _yaw = value; _update_camera())
	camera_row.add_child(orbit)
	var zoom_label := Label.new()
	zoom_label.text = "Distance"
	camera_row.add_child(zoom_label)
	var zoom := HSlider.new()
	zoom.min_value = 2.5
	zoom.max_value = 7.0
	zoom.step = 0.05
	zoom.value = _distance
	zoom.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	zoom.value_changed.connect(func(value: float): _distance = value; _update_camera())
	camera_row.add_child(zoom)
	_details = Label.new()
	_details.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	column.add_child(_details)
