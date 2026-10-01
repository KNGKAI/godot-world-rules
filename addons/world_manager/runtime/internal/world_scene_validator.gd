class_name WorldSceneValidator
extends RefCounted
## Detached candidate checks. Does not read global transforms or log.


enum Dimension {
	NONE,
	NODE_2D,
	NODE_3D,
}


static func dimension_of_root(root: Node) -> Dimension:
	if root == null:
		return Dimension.NONE
	if root is Node3D:
		return Dimension.NODE_3D
	if root is Node2D:
		return Dimension.NODE_2D
	return Dimension.NONE


static func validate_candidate(root: Node, required_entry: StringName) -> Error:
	if root == null or not is_instance_valid(root):
		return ERR_CANT_CREATE
	var dim := dimension_of_root(root)
	if dim == Dimension.NONE:
		return ERR_INVALID_DATA
	var seen: Dictionary = {}
	var walk_err := _walk(root, dim, seen)
	if walk_err != OK:
		return walk_err
	if required_entry != &"":
		if WorldId.validate(required_entry) != OK:
			return ERR_INVALID_PARAMETER
		if not seen.has(required_entry):
			return ERR_DOES_NOT_EXIST
	return OK


static func find_marker(root: Node, entry_id: StringName) -> Node:
	if root == null or not is_instance_valid(root):
		return null
	if _is_entry_marker(root) and _marker_id(root) == entry_id:
		return root
	for child in root.get_children():
		var found := find_marker(child, entry_id)
		if found != null:
			return found
	return null


static func _walk(node: Node, dim: Dimension, seen: Dictionary) -> Error:
	if _is_entry_marker(node):
		var marker_dim := Dimension.NODE_2D if node is WorldEntryPoint2D else Dimension.NODE_3D
		if marker_dim != dim:
			return ERR_INVALID_PARAMETER
		var entry_id := _marker_id(node)
		if WorldId.validate(entry_id) != OK:
			return ERR_INVALID_PARAMETER
		if seen.has(entry_id):
			return ERR_ALREADY_EXISTS
		seen[entry_id] = node
	for child in node.get_children():
		var err := _walk(child, dim, seen)
		if err != OK:
			return err
	return OK


static func _is_entry_marker(node: Node) -> bool:
	return node is WorldEntryPoint2D or node is WorldEntryPoint3D


static func _marker_id(node: Node) -> StringName:
	return node.get("id") as StringName
