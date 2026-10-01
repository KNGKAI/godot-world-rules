class_name CinematicFadeTransition
extends WorldTransition
## Tweens the director chrome's fade rect. The rect is never parented under a world root.

const FADE_SECONDS := 0.35

var _rect: ColorRect
var _tween: Tween
var _operation_id := 0
var _stage: StringName = &""
var _open := false
var _target_alpha := 0.0


func _init(rect: ColorRect) -> void:
	_rect = rect


func start_out(operation_id: int) -> Error:
	return _start(operation_id, STAGE_OUT, 0.0, 1.0)


func start_in(operation_id: int) -> Error:
	return _start(operation_id, STAGE_IN, 1.0, 0.0)


## Completes the stage already in flight. A killed tween does not emit, so this emits once.
func finish_now() -> void:
	if not _open:
		return
	var operation_id := _operation_id
	var stage := _stage
	_open = false
	_kill_tween()
	_set_alpha(_target_alpha)
	finished.emit(operation_id, stage, OK)


func cancel(_operation_id: int) -> void:
	_open = false
	_kill_tween()


func cleanup(_operation_id: int) -> void:
	_open = false
	_kill_tween()
	_set_alpha(0.0)


func _start(operation_id: int, stage: StringName, from_alpha: float, to_alpha: float) -> Error:
	if _rect == null or not is_instance_valid(_rect) or not _rect.is_inside_tree():
		return ERR_UNAVAILABLE
	_kill_tween()
	_operation_id = operation_id
	_stage = stage
	_target_alpha = to_alpha
	_open = true
	_set_alpha(from_alpha)
	_tween = _rect.create_tween()
	_tween.tween_property(_rect, "color:a", to_alpha, FADE_SECONDS)
	_tween.finished.connect(_on_tween_finished, CONNECT_ONE_SHOT)
	return OK


func _on_tween_finished() -> void:
	if not _open:
		return
	var operation_id := _operation_id
	var stage := _stage
	_open = false
	_tween = null
	finished.emit(operation_id, stage, OK)


func _set_alpha(alpha: float) -> void:
	if _rect == null or not is_instance_valid(_rect):
		return
	var color := _rect.color
	color.a = alpha
	_rect.color = color


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
