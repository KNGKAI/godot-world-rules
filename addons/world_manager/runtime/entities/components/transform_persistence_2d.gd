class_name TransformPersistence2D
extends PersistentComponent
## Local Transform2D + top_level. RigidBody2D is not supported.


func _init() -> void:
	if component_id == &"":
		component_id = &"transform"


func capture_state() -> Dictionary:
	var node := actor()
	if not (node is Node2D):
		return {}
	var spatial := node as Node2D
	return {
		"transform": spatial.transform,
		"top_level": spatial.top_level,
	}


func validate_state(state: Dictionary) -> Error:
	var node := actor()
	if node is RigidBody2D:
		return ERR_UNAVAILABLE
	if not (node is Node2D):
		return ERR_INVALID_PARAMETER
	if not state.has("transform") or not state.has("top_level"):
		return ERR_INVALID_PARAMETER
	if typeof(state["transform"]) != TYPE_TRANSFORM2D:
		return ERR_INVALID_PARAMETER
	if typeof(state["top_level"]) != TYPE_BOOL:
		return ERR_INVALID_PARAMETER
	return WorldValue.validate(state)


func restore_state(state: Dictionary) -> Error:
	var err := validate_state(state)
	if err != OK:
		return err
	var spatial := actor() as Node2D
	spatial.top_level = bool(state["top_level"])
	spatial.transform = state["transform"] as Transform2D
	spatial.reset_physics_interpolation()
	return OK
