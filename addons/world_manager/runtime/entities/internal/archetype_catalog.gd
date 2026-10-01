class_name WorldArchetypeCatalog
extends RefCounted
## Registered spawnable archetypes. Stores copies, holds no Node, and does not
## log: the facade on WorldEntityManager emits the one diagnostic, which is what
## keeps every rejection here an ordinary GdUnit4 case.
##
## Registration instantiates the scene once to check its shape, then frees it.
## That is a deliberate difference from WorldSceneDirector.register_world, which
## defers structural checks to load time: "no root identity", "two identities",
## "wrong dimension" and "unparsable components" are only observable by
## instantiating, and a project would rather learn about them at setup than
## during gameplay. The probe instance never enters the tree, so no
## PersistentEntity registers and nothing is left behind.


var _entries: Dictionary = {}


func register(definition: WorldEntityDefinition) -> Error:
	if definition == null:
		return ERR_INVALID_PARAMETER
	if WorldId.validate(definition.id) != OK:
		return ERR_INVALID_PARAMETER
	if definition.scene == null:
		return ERR_INVALID_PARAMETER
	if definition.dimension != WorldSceneValidator.Dimension.NODE_2D \
			and definition.dimension != WorldSceneValidator.Dimension.NODE_3D:
		return ERR_INVALID_PARAMETER
	# Before instantiating, so a duplicate registration costs nothing.
	if _entries.has(definition.id):
		return ERR_ALREADY_EXISTS
	var probe := definition.scene.instantiate()
	if probe == null:
		return ERR_CANT_CREATE
	var shape := _validate_shape(probe, definition.dimension)
	probe.free()
	if shape != OK:
		return shape
	var stored := WorldEntityDefinition.new()
	stored.id = definition.id
	stored.scene = definition.scene
	stored.dimension = definition.dimension
	_entries[definition.id] = stored
	return OK


func has(archetype_id: StringName) -> bool:
	return _entries.has(archetype_id)


## A copy, so a caller cannot reach into the catalog through a query result. The
## PackedScene reference is shared -- a PackedScene cannot be meaningfully deep
## copied, and register_world stores the same way. What the copy defeats is
## reassigning id/scene/dimension after registration to redirect a registered
## archetype at a different scene.
func get_definition(archetype_id: StringName) -> WorldEntityDefinition:
	if not _entries.has(archetype_id):
		return null
	var stored: WorldEntityDefinition = _entries[archetype_id]
	var copy := WorldEntityDefinition.new()
	copy.id = stored.id
	copy.scene = stored.scene
	copy.dimension = stored.dimension
	return copy


func dimension_of(archetype_id: StringName) -> WorldSceneValidator.Dimension:
	if not _entries.has(archetype_id):
		return WorldSceneValidator.Dimension.NONE
	return (_entries[archetype_id] as WorldEntityDefinition).dimension


func ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for key: Variant in _entries.keys():
		out.append(key)
	out.sort_custom(func (a: StringName, b: StringName) -> bool:
		return String(a) < String(b)
	)
	return out


func size() -> int:
	return _entries.size()


## One actor identity per archetype, and it must be reconstructable and
## capturable. Checked against the detached probe, never against a live tree.
static func _validate_shape(
	root: Node, dimension: WorldSceneValidator.Dimension
) -> Error:
	if WorldSceneValidator.dimension_of_root(root) != dimension:
		return ERR_INVALID_PARAMETER
	var entities: Array = []
	_collect(root, entities, func (node: Node) -> bool:
		return node is PersistentEntity
	)
	# One rule covering both "no root identity" and "nested independent
	# identities": exactly one, and it is the root's own direct child, which is
	# the same actor-is-the-parent shape preflight_candidate requires.
	if entities.size() != 1:
		return ERR_INVALID_PARAMETER
	var entity: PersistentEntity = entities[0]
	if entity.get_parent() != root:
		return ERR_INVALID_PARAMETER
	# An archetype is a template: instances receive a generated id, so carrying
	# an authored one would make every instance a duplicate of every other.
	if entity.persistent_id != &"":
		return ERR_INVALID_PARAMETER
	var seen_components: Dictionary = {}
	for child in entity.get_children():
		if not (child is PersistentComponent):
			continue
		var component := child as PersistentComponent
		if WorldId.validate(component.component_id) != OK:
			return ERR_INVALID_PARAMETER
		if seen_components.has(component.component_id):
			return ERR_ALREADY_EXISTS
		seen_components[component.component_id] = true
	# Attachments are validated here rather than at capture, where the failure
	# would name a world instead of the archetype that caused it.
	var attachments: Array = []
	_collect(root, attachments, func (node: Node) -> bool:
		return node is WorldAttachment
	)
	var seen_attachments: Dictionary = {}
	for item: Variant in attachments:
		var attachment := item as WorldAttachment
		if WorldId.validate(attachment.id) != OK:
			return ERR_INVALID_PARAMETER
		if seen_attachments.has(attachment.id):
			return ERR_ALREADY_EXISTS
		seen_attachments[attachment.id] = true
	return OK


static func _collect(node: Node, out: Array, matches: Callable) -> void:
	if matches.call(node):
		out.append(node)
	for child in node.get_children():
		_collect(child, out, matches)
