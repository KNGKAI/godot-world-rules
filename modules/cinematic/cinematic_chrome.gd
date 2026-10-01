class_name CinematicChrome
extends CanvasLayer
## Letterbox, subtitle, Skip, and the passage fade. Built once. Layer 128 sits above the gameplay overlays.

signal skip_pressed

const OPEN_SECONDS := 0.25
const BAR_FRACTION := 0.12

var _top: ColorRect
var _bottom: ColorRect
var _subtitle: Label
var _skip: Button
var _fade: ColorRect
var _tween: Tween
var _open := false


func _ready() -> void:
	layer = 128
	_top = _make_bar(true)
	_bottom = _make_bar(false)
	add_child(_top)
	add_child(_bottom)
	_subtitle = Label.new()
	_subtitle.name = "Subtitle"
	_subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_subtitle.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_subtitle.offset_left = -280.0
	_subtitle.offset_right = 280.0
	_subtitle.offset_top = -40.0
	_subtitle.offset_bottom = 40.0
	_subtitle.visible = false
	add_child(_subtitle)
	_skip = Button.new()
	_skip.name = "Skip"
	_skip.text = "Skip"
	_skip.mouse_filter = Control.MOUSE_FILTER_STOP
	_skip.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_skip.offset_left = -48.0
	_skip.offset_right = 48.0
	_skip.visible = false
	_skip.pressed.connect(func() -> void: skip_pressed.emit())
	add_child(_skip)
	_fade = ColorRect.new()
	_fade.name = "Fade"
	_fade.color = Color(0.0, 0.0, 0.0, 0.0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_fade)
	_place_skip(0.0)
	var viewport := get_viewport()
	if viewport != null and not viewport.size_changed.is_connected(_on_size_changed):
		viewport.size_changed.connect(_on_size_changed)


func _exit_tree() -> void:
	_kill_tween()


func open() -> void:
	_open = true
	_skip.visible = true
	var height := _bar_height()
	_place_skip(height)
	_kill_tween()
	_tween = create_tween()
	_tween.tween_property(_top, "offset_bottom", height, OPEN_SECONDS)
	_tween.parallel().tween_property(_bottom, "offset_top", -height, OPEN_SECONDS)


func close() -> void:
	_open = false
	_skip.visible = false
	set_subtitle("")
	_kill_tween()
	_tween = create_tween()
	_tween.tween_property(_top, "offset_bottom", 0.0, OPEN_SECONDS)
	_tween.parallel().tween_property(_bottom, "offset_top", 0.0, OPEN_SECONDS)


func set_subtitle(text: String) -> void:
	_subtitle.text = text
	_subtitle.visible = not text.is_empty()


func fade_rect() -> ColorRect:
	return _fade


func _make_bar(top: bool) -> ColorRect:
	var bar := ColorRect.new()
	bar.name = "LetterboxTop" if top else "LetterboxBottom"
	bar.color = Color.BLACK
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.anchor_left = 0.0
	bar.anchor_right = 1.0
	if top:
		bar.anchor_top = 0.0
		bar.anchor_bottom = 0.0
	else:
		bar.anchor_top = 1.0
		bar.anchor_bottom = 1.0
	bar.offset_left = 0.0
	bar.offset_right = 0.0
	bar.offset_top = 0.0
	bar.offset_bottom = 0.0
	return bar


func _bar_height() -> float:
	var viewport := get_viewport()
	if viewport == null:
		return 0.0
	return viewport.get_visible_rect().size.y * BAR_FRACTION


func _place_skip(bar_height: float) -> void:
	_skip.offset_top = -(bar_height + 36.0)
	_skip.offset_bottom = -(bar_height + 4.0)


func _on_size_changed() -> void:
	var height := _bar_height()
	_place_skip(height if _open else 0.0)
	if not _open:
		return
	_kill_tween()
	_top.offset_bottom = height
	_bottom.offset_top = -height


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
