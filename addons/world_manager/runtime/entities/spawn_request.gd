class_name WorldSpawnRequest
extends Resource
## One dynamic spawn, validated by value. Holds no Node and no manager, so
## validate() is pure and every rejection here is an ordinary GdUnit4 case.
##
## The transform is deliberately not a record field. It reaches a save through
## the archetype's TransformPersistence component on the normal capture path;
## this only sets the node.


## No enum value is a safe default for a policy, so there is a sentinel instead.
## NONE would make a forgotten policy a silently non-persistent spawn -- in a
## persistence addon, the worst available failure, because it looks fine until
## the player reloads. SAVE_GAME would silently write every transient effect into
## the save file. And NONE has to stay a legal explicit choice, so the sentinel
## cannot be NONE. WorldPersistencePolicy.validate already rejects -1.
const POLICY_UNSET := -1

@export var archetype_id: StringName = &""
@export var persistence_policy: int = POLICY_UNSET
@export var parent_kind: WorldEntityParent.Kind = WorldEntityParent.Kind.WORLD_ROOT
@export var parent_id: StringName = &""
@export var transform_2d: Transform2D = Transform2D.IDENTITY
@export var transform_3d: Transform3D = Transform3D.IDENTITY
@export var initial_components: Dictionary = {}


func validate() -> Error:
	if WorldId.validate(archetype_id) != OK:
		return ERR_INVALID_PARAMETER
	if WorldPersistencePolicy.validate(persistence_policy) != OK:
		return ERR_INVALID_PARAMETER
	if parent_kind != WorldEntityParent.Kind.WORLD_ROOT \
			and parent_kind != WorldEntityParent.Kind.PERSISTENT_ENTITY \
			and parent_kind != WorldEntityParent.Kind.ATTACHMENT:
		return ERR_INVALID_PARAMETER
	# The same pairing rule a record obeys: a request that could not be recorded
	# must not be accepted.
	if parent_kind == WorldEntityParent.Kind.WORLD_ROOT:
		if parent_id != &"":
			return ERR_INVALID_PARAMETER
	elif WorldId.validate(parent_id) != OK:
		return ERR_INVALID_PARAMETER
	return _validate_components()


## Detached copies, so the caller's dictionary is never aliased into a live
## actor -- the isolation _collect_live_records applies on the capture side.
func copied_components() -> Dictionary:
	var out: Dictionary = {}
	for key: Variant in initial_components.keys():
		out[StringName(key)] = WorldValue.clone_validated(initial_components[key])
	return out


func _validate_components() -> Error:
	for key: Variant in initial_components.keys():
		if typeof(key) != TYPE_STRING and typeof(key) != TYPE_STRING_NAME:
			return ERR_INVALID_PARAMETER
		if WorldId.validate(StringName(key)) != OK:
			return ERR_INVALID_PARAMETER
		var payload: Variant = initial_components[key]
		if typeof(payload) != TYPE_DICTIONARY:
			return ERR_INVALID_PARAMETER
		# The same allowlist component state goes through everywhere else: it is
		# what rejects Nodes, Callables, non-finite floats and cycles.
		if WorldValue.validate(payload) != OK:
			return ERR_INVALID_PARAMETER
	return OK
