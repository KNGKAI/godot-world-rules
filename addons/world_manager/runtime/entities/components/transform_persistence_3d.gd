class_name TransformPersistence3D
extends PersistentComponent
## Local Transform3D + top_level. RigidBody3D is not supported.


func _init() -> void:
	if component_id == &"":
		component_id = &"transform"


func capture_state() -> Dictionary:
	var node := actor()
	if not (node is Node3D):
		return {}
	var spatial := node as Node3D
	return {
		"transform": spatial.transform,
		"top_level": spatial.top_level,
	}


func validate_state(state: Dictionary) -> Error:
	var node := actor()
	if node is RigidBody3D:
		return ERR_UNAVAILABLE
	if not (node is Node3D):
		return ERR_INVALID_PARAMETER
	if not state.has("transform") or not state.has("top_level"):
		return ERR_INVALID_PARAMETER
	if typeof(state["transform"]) != TYPE_TRANSFORM3D:
		return ERR_INVALID_PARAMETER
	if typeof(state["top_level"]) != TYPE_BOOL:
		return ERR_INVALID_PARAMETER
	return WorldValue.validate(state)


func restore_state(state: Dictionary) -> Error:
	var err := validate_state(state)
	if err != OK:
		return err
	var spatial := actor() as Node3D
	spatial.top_level = bool(state["top_level"])
	spatial.transform = state["transform"] as Transform3D
	spatial.reset_physics_interpolation()
	return OK
