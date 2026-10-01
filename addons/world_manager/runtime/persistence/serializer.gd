class_name WorldSaveSerializer
extends RefCounted
## Version-one save encoding and decoding. Object support is never enabled and
## the flag is never exposed. Does not log: every failure is a returned Error, so
## a malformed save is testable without an engine diagnostic.


## JSON.from_native formats a bare float itself, as a "f:" string of about
## fourteen significant digits, so stringify's full_precision never reaches it.
## Floats inside math types and packed float arrays ride in args as raw JSON
## numbers and are already exact. Bare and container-nested floats are therefore
## wrapped in a one-key dictionary carrying a one-element PackedFloat64Array,
## which is bit-exact and stays inside to_native's own vocabulary. The key is
## reserved: encode rejects a snapshot that uses it, so the wrapper can never be
## confused with authored data. See README D7.
const FLOAT_WRAP_KEY := "__wm_float__"

const SCALAR_INT_PREFIX := "i:"
const SCALAR_FLOAT_PREFIX := "f:"
const SCALAR_STRING_PREFIX := "s:"
const SCALAR_STRING_NAME_PREFIX := "sn:"

## Measured on Godot 4.7.1. args is a flat list of components, so a packed array
## carries element_count * stride numbers. See README D7 for the dump.
const FIXED_ARITY_TAGS: Dictionary = {
	"Vector2": 2,
	"Vector2i": 2,
	"Vector3": 3,
	"Vector3i": 3,
	"Vector4": 4,
	"Vector4i": 4,
	"Rect2": 4,
	"Rect2i": 4,
	"Plane": 4,
	"Quaternion": 4,
	"Color": 4,
	"Transform2D": 6,
	"AABB": 6,
	"Basis": 9,
	"Transform3D": 12,
	"Projection": 16,
}
const NUMERIC_STRIDE_TAGS: Dictionary = {
	"PackedByteArray": 1,
	"PackedInt32Array": 1,
	"PackedInt64Array": 1,
	"PackedFloat32Array": 1,
	"PackedFloat64Array": 1,
	"PackedVector2Array": 2,
	"PackedVector3Array": 3,
	"PackedVector4Array": 4,
	"PackedColorArray": 4,
}
const STRING_ARRAY_TAG := "PackedStringArray"
const DICTIONARY_TAG := "Dictionary"
const TAG_KEYS: PackedStringArray = ["args", "type"]


# --- encoding -----------------------------------------------------------------


static func encode(snapshot: Dictionary) -> WorldSerializationResult:
	var checked := _validate_snapshot(snapshot)
	var snapshot_error: Error = checked["error"]
	if snapshot_error != OK:
		return WorldSerializationResult.failure(
			snapshot_error, {"stage": &"snapshot", "field": checked["field"]}
		)
	var payload: Dictionary = {}
	payload["format_version"] = WorldSaveDocument.FORMAT_VERSION
	payload["created_at"] = int(snapshot["created_at"])
	payload["updated_at"] = int(snapshot["updated_at"])
	payload["generation"] = int(snapshot["generation"])
	var active: Variant = snapshot["active_world"]
	payload["active_world"] = null if active == null else String(active)
	payload["world_state"] = _encode_leaf(snapshot["world_state"])
	var worlds: Dictionary = {}
	var source_worlds: Dictionary = snapshot["worlds"]
	for world_id: Variant in source_worlds.keys():
		var entities: Dictionary = {}
		var source_entities: Dictionary = source_worlds[world_id]
		for entity_id: Variant in source_entities.keys():
			var source_record: Dictionary = source_entities[entity_id]
			var components: Dictionary = {}
			var source_components: Dictionary = source_record["components"]
			for component_id: Variant in source_components.keys():
				components[String(component_id)] = _encode_leaf(source_components[component_id])
			entities[String(entity_id)] = {
				"archetype_id": String(source_record["archetype_id"]),
				"components": components,
				"origin": int(source_record["origin"]),
				"parent_id": String(source_record["parent_id"]),
				"parent_kind": int(source_record["parent_kind"]),
				"policy": int(source_record["policy"]),
				"removed": bool(source_record["removed"]),
			}
		worlds[String(world_id)] = {"entities": entities}
	payload["worlds"] = worlds
	var systems: Dictionary = {}
	var source_systems: Dictionary = snapshot["systems"]
	for participant_id: Variant in source_systems.keys():
		var entry: Dictionary = source_systems[participant_id]
		systems[String(participant_id)] = {
			"schema_version": int(entry["schema_version"]),
			"state": _encode_leaf(entry["state"]),
		}
	payload["systems"] = systems
	var payload_json := JSON.stringify(payload, "", true, true)
	var checksum := _sha256_hex(payload_json.to_utf8_buffer())
	var envelope: Dictionary = {
		"checksum": checksum,
		"envelope_version": WorldSaveDocument.ENVELOPE_VERSION,
		"payload_json": payload_json,
	}
	var bytes := JSON.stringify(envelope, "\t", true, true).to_utf8_buffer()
	if bytes.size() > WorldSaveDocument.MAX_FILE_BYTES:
		return WorldSerializationResult.failure(
			ERR_INVALID_DATA, {"stage": &"limit", "limit": &"size", "size": bytes.size()}
		)
	return WorldSerializationResult.ok_bytes(bytes, {
		"checksum": checksum,
		"byte_size": bytes.size(),
		"generation": int(snapshot["generation"]),
	})


static func _encode_leaf(value: Variant) -> Variant:
	return JSON.from_native(_wrap_floats(WorldValue.clone_validated(value)), false)


static func _wrap_floats(value: Variant) -> Variant:
	match typeof(value):
		TYPE_FLOAT:
			return {FLOAT_WRAP_KEY: PackedFloat64Array([value])}
		TYPE_ARRAY:
			var items: Array = []
			for item: Variant in value:
				items.append(_wrap_floats(item))
			return items
		TYPE_DICTIONARY:
			var mapped: Dictionary = {}
			for key: Variant in value.keys():
				mapped[key] = _wrap_floats(value[key])
			return mapped
		_:
			return value


static func _unwrap_floats(value: Variant, out: Array) -> Error:
	match typeof(value):
		TYPE_ARRAY:
			var items: Array = []
			for item: Variant in value:
				var unwrapped: Array = []
				var err := _unwrap_floats(item, unwrapped)
				if err != OK:
					return err
				items.append(unwrapped[0])
			out.append(items)
			return OK
		TYPE_DICTIONARY:
			var source: Dictionary = value
			if source.size() == 1 and source.has(FLOAT_WRAP_KEY):
				var inner: Variant = source[FLOAT_WRAP_KEY]
				if typeof(inner) != TYPE_PACKED_FLOAT64_ARRAY:
					return ERR_INVALID_DATA
				var packed: PackedFloat64Array = inner
				if packed.size() != 1:
					return ERR_INVALID_DATA
				out.append(packed[0])
				return OK
			var mapped: Dictionary = {}
			for key: Variant in source.keys():
				var unwrapped: Array = []
				var err := _unwrap_floats(source[key], unwrapped)
				if err != OK:
					return err
				mapped[key] = unwrapped[0]
			out.append(mapped)
			return OK
		_:
			out.append(value)
			return OK


static func _sha256_hex(data: PackedByteArray) -> String:
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(data)
	return hashing.finish().hex_encode()


# --- decoding -----------------------------------------------------------------


## Full decode: envelope, then the current format's structure. Behaviour is
## identical to the single pass this replaced, for every current-version input.
static func decode(bytes: PackedByteArray) -> WorldSerializationResult:
	var opened := read_payload(bytes)
	if opened.error != OK:
		return opened
	return decode_payload(opened.payload, int(opened.context["byte_size"]))


## Checksum-verified, JSON-parsed payload with its value leaves still in
## JSON.from_native tag form. Enforces only what holds at *every* container
## version -- the envelope, the checksum, and the D7 metadata subset -- so an
## older payload survives to the migration pipeline instead of being reported as
## corrupt. A future version is rejected here, which is the pipeline's third
## step. The current format's key set is decode_payload's business, not this
## function's; checking it here is what used to make a version difference look
## like corruption.
static func read_payload(bytes: PackedByteArray) -> WorldSerializationResult:
	if bytes.is_empty():
		return WorldSerializationResult.failure(
			ERR_FILE_CORRUPT, {"stage": &"limit", "limit": &"empty"}
		)
	if bytes.size() > WorldSaveDocument.MAX_FILE_BYTES:
		return WorldSerializationResult.failure(
			ERR_INVALID_DATA, {"stage": &"limit", "limit": &"size", "size": bytes.size()}
		)
	if not _is_well_formed_utf8(bytes):
		return WorldSerializationResult.failure(ERR_FILE_CORRUPT, {"stage": &"utf8"})
	var envelope_parsed: Array = []
	var envelope_error := _parse_json(bytes.get_string_from_utf8(), envelope_parsed)
	if envelope_error != OK:
		return WorldSerializationResult.failure(
			ERR_FILE_CORRUPT, {"stage": &"envelope_parse"}
		)
	var envelope_value: Variant = envelope_parsed[0]
	if typeof(envelope_value) != TYPE_DICTIONARY:
		return WorldSerializationResult.failure(
			ERR_INVALID_DATA, {"stage": &"envelope_fields"}
		)
	var envelope: Dictionary = envelope_value
	if not WorldSaveDocument.has_exact_keys(envelope, WorldSaveDocument.ENVELOPE_KEYS):
		return WorldSerializationResult.failure(
			ERR_INVALID_DATA, {"stage": &"envelope_fields"}
		)
	var envelope_version: Array = []
	if WorldSaveDocument.as_exact_int(envelope["envelope_version"], envelope_version) != OK:
		return WorldSerializationResult.failure(
			ERR_INVALID_DATA, {"stage": &"envelope_fields"}
		)
	if int(envelope_version[0]) != WorldSaveDocument.ENVELOPE_VERSION:
		return WorldSerializationResult.failure(
			ERR_FILE_UNRECOGNIZED,
			{"stage": &"envelope_version", "envelope_version": envelope_version[0]},
		)
	if not WorldSaveDocument.is_checksum_text(envelope["checksum"]):
		return WorldSerializationResult.failure(
			ERR_INVALID_DATA, {"stage": &"envelope_fields"}
		)
	if typeof(envelope["payload_json"]) != TYPE_STRING:
		return WorldSerializationResult.failure(
			ERR_INVALID_DATA, {"stage": &"envelope_fields"}
		)
	var payload_json: String = envelope["payload_json"]
	if _sha256_hex(payload_json.to_utf8_buffer()) != String(envelope["checksum"]):
		return WorldSerializationResult.failure(ERR_FILE_CORRUPT, {"stage": &"checksum"})
	var payload_parsed: Array = []
	if _parse_json(payload_json, payload_parsed) != OK:
		return WorldSerializationResult.failure(
			ERR_FILE_CORRUPT, {"stage": &"payload_parse"}
		)
	var payload_value: Variant = payload_parsed[0]
	if typeof(payload_value) != TYPE_DICTIONARY:
		return WorldSerializationResult.failure(ERR_INVALID_DATA, {"stage": &"fields"})
	var payload: Dictionary = payload_value
	if not payload.has("format_version"):
		return WorldSerializationResult.failure(
			ERR_INVALID_DATA, {"stage": &"fields", "field": "format_version"}
		)
	var format_version: Array = []
	if WorldSaveDocument.as_exact_int(payload["format_version"], format_version) != OK:
		return WorldSerializationResult.failure(
			ERR_FILE_CORRUPT, {"stage": &"version", "field": "format_version"}
		)
	var version := int(format_version[0])
	if version > WorldSaveDocument.FORMAT_VERSION:
		return WorldSerializationResult.failure(
			ERR_FILE_UNRECOGNIZED, {"stage": &"version", "format_version": version}
		)
	var metadata: Dictionary = {}
	if WorldSaveDocument.validate_metadata(payload, metadata) != OK:
		return WorldSerializationResult.failure(
			ERR_INVALID_DATA, {"stage": &"fields", "field": "metadata"}
		)
	return WorldSerializationResult.ok_payload(payload, {
		"format_version": version,
		"envelope_version": WorldSaveDocument.ENVELOPE_VERSION,
		"checksum": String(envelope["checksum"]),
		"created_at": metadata["created_at"],
		"updated_at": metadata["updated_at"],
		"generation": metadata["generation"],
		"active_world": metadata["active_world"],
		"byte_size": bytes.size(),
	})


## Structural validation against the *current* format, plus native leaf
## decoding. Input must already be checksum-verified by read_payload and already
## be at FORMAT_VERSION -- migration is what gets an older payload here. A
## checksum-valid file is not a structurally valid one, so these failures report
## the shape problem rather than corruption.
static func decode_payload(payload: Dictionary, byte_size: int) -> WorldSerializationResult:
	if not WorldSaveDocument.has_exact_keys(payload, WorldSaveDocument.PAYLOAD_KEYS):
		return WorldSerializationResult.failure(ERR_INVALID_DATA, {"stage": &"fields"})
	var format_version: Array = []
	if WorldSaveDocument.as_exact_int(payload["format_version"], format_version) != OK:
		return WorldSerializationResult.failure(
			ERR_FILE_CORRUPT, {"stage": &"version", "field": "format_version"}
		)
	var version := int(format_version[0])
	if version != WorldSaveDocument.FORMAT_VERSION:
		return WorldSerializationResult.failure(
			ERR_FILE_UNRECOGNIZED, {"stage": &"version", "format_version": version}
		)
	var metadata: Dictionary = {}
	if WorldSaveDocument.validate_metadata(payload, metadata) != OK:
		return WorldSerializationResult.failure(
			ERR_INVALID_DATA, {"stage": &"fields", "field": "metadata"}
		)
	var active: Variant = metadata["active_world"]
	var budget: Array = [0]
	var document: Dictionary = {}
	document["format_version"] = version
	document["created_at"] = metadata["created_at"]
	document["updated_at"] = metadata["updated_at"]
	document["generation"] = metadata["generation"]
	document["active_world"] = active
	var state_out: Array = []
	var state_error := _decode_leaf(payload["world_state"], budget, state_out)
	if state_error["error"] != OK:
		return WorldSerializationResult.failure(state_error["error"], {
			"stage": state_error["stage"], "field": "world_state",
		})
	if typeof(state_out[0]) != TYPE_DICTIONARY:
		return WorldSerializationResult.failure(
			ERR_INVALID_DATA, {"stage": &"fields", "field": "world_state"}
		)
	document["world_state"] = state_out[0]
	var worlds_result := _decode_worlds(payload["worlds"], budget)
	if worlds_result["error"] != OK:
		return WorldSerializationResult.failure(worlds_result["error"], {
			"stage": worlds_result["stage"], "field": worlds_result["field"],
		})
	document["worlds"] = worlds_result["worlds"]
	var systems_result := _decode_systems(payload["systems"], budget)
	if systems_result["error"] != OK:
		return WorldSerializationResult.failure(systems_result["error"], {
			"stage": systems_result["stage"], "field": systems_result["field"],
		})
	document["systems"] = systems_result["systems"]
	return WorldSerializationResult.ok_document(document, {
		"format_version": version,
		"envelope_version": WorldSaveDocument.ENVELOPE_VERSION,
		"created_at": metadata["created_at"],
		"updated_at": metadata["updated_at"],
		"generation": metadata["generation"],
		"active_world": document["active_world"],
		"byte_size": byte_size,
	})


static func _decode_worlds(value: Variant, budget: Array) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {"error": ERR_INVALID_DATA, "stage": &"fields", "field": "worlds"}
	var worlds: Dictionary = {}
	var source: Dictionary = value
	for world_key: Variant in source.keys():
		if typeof(world_key) != TYPE_STRING or WorldId.validate(StringName(world_key)) != OK:
			return {"error": ERR_INVALID_DATA, "stage": &"fields", "field": "worlds"}
		var world_value: Variant = source[world_key]
		if typeof(world_value) != TYPE_DICTIONARY:
			return {"error": ERR_INVALID_DATA, "stage": &"fields", "field": str(world_key)}
		var world_entry: Dictionary = world_value
		if not WorldSaveDocument.has_exact_keys(world_entry, ["entities"]):
			return {"error": ERR_INVALID_DATA, "stage": &"fields", "field": str(world_key)}
		var entities_value: Variant = world_entry["entities"]
		if typeof(entities_value) != TYPE_DICTIONARY:
			return {"error": ERR_INVALID_DATA, "stage": &"fields", "field": str(world_key)}
		var entities: Dictionary = {}
		var source_entities: Dictionary = entities_value
		for entity_key: Variant in source_entities.keys():
			if typeof(entity_key) != TYPE_STRING \
					or WorldId.validate(StringName(entity_key)) != OK:
				return {"error": ERR_INVALID_DATA, "stage": &"fields", "field": str(entity_key)}
			var record_result := _decode_record(source_entities[entity_key], budget)
			if record_result["error"] != OK:
				return {
					"error": record_result["error"],
					"stage": record_result["stage"],
					"field": "%s.%s" % [str(world_key), str(entity_key)],
				}
			entities[str(entity_key)] = record_result["record"]
		var closure := WorldSaveDocument.validate_parent_closure(entities)
		if closure["error"] != OK:
			return {"error": closure["error"], "stage": &"fields", "field": closure["field"]}
		var cycles := WorldSaveDocument.validate_parent_cycles(entities)
		if cycles["error"] != OK:
			return {"error": cycles["error"], "stage": &"fields", "field": cycles["field"]}
		worlds[str(world_key)] = entities
	return {"error": OK, "stage": &"", "field": "", "worlds": worlds}


static func _decode_record(value: Variant, budget: Array) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {"error": ERR_INVALID_DATA, "stage": &"fields"}
	var source: Dictionary = value
	if not WorldSaveDocument.has_exact_keys(source, WorldSaveDocument.RECORD_KEYS):
		return {"error": ERR_INVALID_DATA, "stage": &"fields"}
	var policy: Array = []
	if WorldSaveDocument.as_exact_int(source["policy"], policy) != OK:
		return {"error": ERR_INVALID_DATA, "stage": &"fields"}
	if int(policy[0]) != WorldPersistencePolicy.Kind.SAVE_GAME:
		return {"error": ERR_INVALID_DATA, "stage": &"fields"}
	var parent_kind: Array = []
	if WorldSaveDocument.as_exact_int(source["parent_kind"], parent_kind) != OK:
		return {"error": ERR_INVALID_DATA, "stage": &"fields"}
	var kind := int(parent_kind[0])
	if kind != WorldEntityParent.Kind.WORLD_ROOT \
			and kind != WorldEntityParent.Kind.PERSISTENT_ENTITY \
			and kind != WorldEntityParent.Kind.ATTACHMENT:
		return {"error": ERR_INVALID_DATA, "stage": &"fields"}
	if typeof(source["parent_id"]) != TYPE_STRING:
		return {"error": ERR_INVALID_DATA, "stage": &"fields"}
	var parent_id: String = source["parent_id"]
	if kind == WorldEntityParent.Kind.WORLD_ROOT:
		if parent_id != "":
			return {"error": ERR_INVALID_DATA, "stage": &"fields"}
	elif WorldId.validate(StringName(parent_id)) != OK:
		return {"error": ERR_INVALID_DATA, "stage": &"fields"}
	var origin: Array = []
	if WorldSaveDocument.as_exact_int(source["origin"], origin) != OK:
		return {"error": ERR_INVALID_DATA, "stage": &"fields"}
	if WorldEntityOrigin.validate(int(origin[0])) != OK:
		return {"error": ERR_INVALID_DATA, "stage": &"fields"}
	if typeof(source["archetype_id"]) != TYPE_STRING:
		return {"error": ERR_INVALID_DATA, "stage": &"fields"}
	var archetype_id: String = source["archetype_id"]
	# An authored record has no archetype and a dynamic one has a valid archetype.
	# Validating the id here is also what stops a save naming a resource path: a
	# string containing "/" fails the grammar before any catalog is consulted.
	if int(origin[0]) == WorldEntityOrigin.Kind.DYNAMIC:
		if WorldId.validate(StringName(archetype_id)) != OK:
			return {"error": ERR_INVALID_DATA, "stage": &"fields"}
	elif archetype_id != "":
		return {"error": ERR_INVALID_DATA, "stage": &"fields"}
	if typeof(source["removed"]) != TYPE_BOOL:
		return {"error": ERR_INVALID_DATA, "stage": &"fields"}
	if typeof(source["components"]) != TYPE_DICTIONARY:
		return {"error": ERR_INVALID_DATA, "stage": &"fields"}
	var components: Dictionary = {}
	var source_components: Dictionary = source["components"]
	for component_key: Variant in source_components.keys():
		if typeof(component_key) != TYPE_STRING \
				or WorldId.validate(StringName(component_key)) != OK:
			return {"error": ERR_INVALID_DATA, "stage": &"fields"}
		var decoded: Array = []
		var leaf_error := _decode_leaf(source_components[component_key], budget, decoded)
		if leaf_error["error"] != OK:
			return {"error": leaf_error["error"], "stage": leaf_error["stage"]}
		if typeof(decoded[0]) != TYPE_DICTIONARY:
			return {"error": ERR_INVALID_DATA, "stage": &"fields"}
		components[str(component_key)] = decoded[0]
	return {"error": OK, "stage": &"", "record": {
		"archetype_id": archetype_id,
		"components": components,
		"origin": int(origin[0]),
		"parent_id": parent_id,
		"parent_kind": kind,
		"policy": int(policy[0]),
		"removed": bool(source["removed"]),
	}}


static func _decode_systems(value: Variant, budget: Array) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {"error": ERR_INVALID_DATA, "stage": &"fields", "field": "systems"}
	var systems: Dictionary = {}
	var source: Dictionary = value
	for participant_key: Variant in source.keys():
		if typeof(participant_key) != TYPE_STRING \
				or WorldId.validate(StringName(participant_key)) != OK:
			return {"error": ERR_INVALID_DATA, "stage": &"fields", "field": "systems"}
		var entry_value: Variant = source[participant_key]
		if typeof(entry_value) != TYPE_DICTIONARY:
			return {"error": ERR_INVALID_DATA, "stage": &"fields", "field": str(participant_key)}
		var entry: Dictionary = entry_value
		if not WorldSaveDocument.has_exact_keys(entry, WorldSaveDocument.SYSTEM_KEYS):
			return {"error": ERR_INVALID_DATA, "stage": &"fields", "field": str(participant_key)}
		var schema_version: Array = []
		if WorldSaveDocument.as_exact_int(entry["schema_version"], schema_version) != OK:
			return {"error": ERR_INVALID_DATA, "stage": &"fields", "field": str(participant_key)}
		if int(schema_version[0]) < 0:
			return {"error": ERR_INVALID_DATA, "stage": &"fields", "field": str(participant_key)}
		var decoded: Array = []
		var leaf_error := _decode_leaf(entry["state"], budget, decoded)
		if leaf_error["error"] != OK:
			return {
				"error": leaf_error["error"],
				"stage": leaf_error["stage"],
				"field": str(participant_key),
			}
		if typeof(decoded[0]) != TYPE_DICTIONARY:
			return {"error": ERR_INVALID_DATA, "stage": &"fields", "field": str(participant_key)}
		systems[str(participant_key)] = {
			"schema_version": int(schema_version[0]),
			"state": decoded[0],
		}
	return {"error": OK, "stage": &"", "field": "", "systems": systems}


## Validate the encoded tag tree completely before any native conversion. Godot
## reports an unknown tag, a bad arity, or an object tag by pushing an engine
## error and returning null, so to_native must only ever see input it cannot
## fail on.
static func _decode_leaf(encoded: Variant, budget: Array, out: Array) -> Dictionary:
	var tag_error := _validate_encoded(encoded, 0, budget)
	if tag_error != OK:
		return {"error": tag_error, "stage": &"tag"}
	var native: Variant = JSON.to_native(encoded, false)
	var unwrapped: Array = []
	if _unwrap_floats(native, unwrapped) != OK:
		return {"error": ERR_INVALID_DATA, "stage": &"tag"}
	if WorldValue.validate(unwrapped[0]) != OK:
		return {"error": ERR_INVALID_DATA, "stage": &"value"}
	out.append(WorldValue.clone_validated(unwrapped[0]))
	return {"error": OK, "stage": &""}


static func _validate_encoded(value: Variant, depth: int, budget: Array) -> Error:
	budget[0] = int(budget[0]) + 1
	if int(budget[0]) > WorldSaveDocument.MAX_VISITS:
		return ERR_INVALID_DATA
	if depth > WorldSaveDocument.MAX_ENCODED_DEPTH:
		return ERR_INVALID_DATA
	match typeof(value):
		TYPE_NIL, TYPE_BOOL:
			return OK
		TYPE_STRING:
			return _validate_scalar_text(value)
		TYPE_ARRAY:
			for item: Variant in value as Array:
				var err := _validate_encoded(item, depth + 1, budget)
				if err != OK:
					return err
			return OK
		TYPE_DICTIONARY:
			return _validate_tag(value, depth, budget)
		_:
			return ERR_INVALID_DATA


## "i:notanint" decodes silently to zero, so the scalar payload is checked here
## rather than trusted to to_native.
static func _validate_scalar_text(value: String) -> Error:
	if value.begins_with(SCALAR_INT_PREFIX):
		var body := value.substr(SCALAR_INT_PREFIX.length())
		return OK if body.is_valid_int() else ERR_INVALID_DATA
	if value.begins_with(SCALAR_FLOAT_PREFIX):
		var body := value.substr(SCALAR_FLOAT_PREFIX.length())
		if not body.is_valid_float():
			return ERR_INVALID_DATA
		return OK if is_finite(body.to_float()) else ERR_INVALID_DATA
	if value.begins_with(SCALAR_STRING_NAME_PREFIX) or value.begins_with(SCALAR_STRING_PREFIX):
		return OK
	return ERR_INVALID_DATA


static func _validate_tag(value: Dictionary, depth: int, budget: Array) -> Error:
	if not WorldSaveDocument.has_exact_keys(value, TAG_KEYS):
		return ERR_INVALID_DATA
	if typeof(value["type"]) != TYPE_STRING:
		return ERR_INVALID_DATA
	if typeof(value["args"]) != TYPE_ARRAY:
		return ERR_INVALID_DATA
	var tag: String = value["type"]
	var args: Array = value["args"]
	budget[0] = int(budget[0]) + args.size()
	if int(budget[0]) > WorldSaveDocument.MAX_VISITS:
		return ERR_INVALID_DATA
	if FIXED_ARITY_TAGS.has(tag):
		if args.size() != int(FIXED_ARITY_TAGS[tag]):
			return ERR_INVALID_DATA
		return _validate_numbers(args)
	if NUMERIC_STRIDE_TAGS.has(tag):
		var stride := int(NUMERIC_STRIDE_TAGS[tag])
		if args.size() % stride != 0:
			return ERR_INVALID_DATA
		return _validate_numbers(args)
	if tag == STRING_ARRAY_TAG:
		for item: Variant in args:
			if typeof(item) != TYPE_STRING:
				return ERR_INVALID_DATA
		return OK
	if tag == DICTIONARY_TAG:
		if args.size() % 2 != 0:
			return ERR_INVALID_DATA
		for item: Variant in args:
			var err := _validate_encoded(item, depth + 1, budget)
			if err != OK:
				return err
		return OK
	return ERR_INVALID_DATA


static func _validate_numbers(args: Array) -> Error:
	for item: Variant in args:
		var kind := typeof(item)
		if kind == TYPE_INT:
			continue
		if kind != TYPE_FLOAT:
			return ERR_INVALID_DATA
		if not is_finite(item as float):
			return ERR_INVALID_DATA
	return OK


## JSON.parse_string pushes an engine error on malformed input; the instance form
## reports through a return value, which keeps a corrupt save testable.
static func _parse_json(text: String, out: Array) -> Error:
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		return err
	out.append(json.data)
	return OK


## PackedByteArray.get_string_from_utf8 silently repairs invalid sequences and
## logs while doing it. Both are fatal here: a repaired string is not the string
## the checksum covers, and the log would fail the runner's no-error gate.
static func _is_well_formed_utf8(bytes: PackedByteArray) -> bool:
	if bytes.size() >= 3 and bytes[0] == 0xEF and bytes[1] == 0xBB and bytes[2] == 0xBF:
		return false
	var index := 0
	var size := bytes.size()
	while index < size:
		var lead := bytes[index]
		var following := 0
		var code := 0
		if lead < 0x80:
			index += 1
			continue
		elif lead >= 0xC2 and lead <= 0xDF:
			following = 1
			code = lead & 0x1F
		elif lead >= 0xE0 and lead <= 0xEF:
			following = 2
			code = lead & 0x0F
		elif lead >= 0xF0 and lead <= 0xF4:
			following = 3
			code = lead & 0x07
		else:
			return false
		if index + following >= size:
			return false
		for offset in range(1, following + 1):
			var continuation := bytes[index + offset]
			if continuation < 0x80 or continuation > 0xBF:
				return false
			code = (code << 6) | (continuation & 0x3F)
		if following == 2 and code < 0x800:
			return false
		if following == 3 and code < 0x10000:
			return false
		if code > 0x10FFFF:
			return false
		if code >= 0xD800 and code <= 0xDFFF:
			return false
		index += following + 1
	return true


# --- encode-side validation ---------------------------------------------------


static func _validate_snapshot(snapshot: Dictionary) -> Dictionary:
	if not WorldSaveDocument.has_exact_keys(snapshot, WorldSaveDocument.SNAPSHOT_KEYS):
		return {"error": ERR_INVALID_PARAMETER, "field": ""}
	for field: String in ["created_at", "updated_at", "generation"]:
		var parsed: Array = []
		if WorldSaveDocument.as_exact_int(snapshot[field], parsed) != OK:
			return {"error": ERR_INVALID_PARAMETER, "field": field}
		if int(parsed[0]) < 0:
			return {"error": ERR_INVALID_PARAMETER, "field": field}
	var active: Variant = snapshot["active_world"]
	if active != null:
		var active_kind := typeof(active)
		if active_kind != TYPE_STRING and active_kind != TYPE_STRING_NAME:
			return {"error": ERR_INVALID_PARAMETER, "field": "active_world"}
		if WorldId.validate(StringName(active)) != OK:
			return {"error": ERR_INVALID_PARAMETER, "field": "active_world"}
	var state_check := _validate_leaf(snapshot["world_state"], "world_state")
	if state_check["error"] != OK:
		return state_check
	if typeof(snapshot["worlds"]) != TYPE_DICTIONARY:
		return {"error": ERR_INVALID_PARAMETER, "field": "worlds"}
	var worlds: Dictionary = snapshot["worlds"]
	for world_id: Variant in worlds.keys():
		var world_check := _validate_identifier(world_id, "worlds")
		if world_check["error"] != OK:
			return world_check
		if typeof(worlds[world_id]) != TYPE_DICTIONARY:
			return {"error": ERR_INVALID_PARAMETER, "field": String(world_id)}
		var entities: Dictionary = worlds[world_id]
		var normalized: Dictionary = {}
		for entity_id: Variant in entities.keys():
			var entity_check := _validate_identifier(entity_id, String(world_id))
			if entity_check["error"] != OK:
				return entity_check
			var record_check := _validate_record(entities[entity_id], String(entity_id))
			if record_check["error"] != OK:
				return record_check
			normalized[String(entity_id)] = {
				"parent_kind": int((entities[entity_id] as Dictionary)["parent_kind"]),
				"parent_id": String((entities[entity_id] as Dictionary)["parent_id"]),
				"removed": bool((entities[entity_id] as Dictionary)["removed"]),
			}
		var closure := WorldSaveDocument.validate_parent_closure(normalized)
		if closure["error"] != OK:
			return {"error": ERR_INVALID_PARAMETER, "field": closure["field"]}
		var cycles := WorldSaveDocument.validate_parent_cycles(normalized)
		if cycles["error"] != OK:
			return {"error": ERR_INVALID_PARAMETER, "field": cycles["field"]}
	if typeof(snapshot["systems"]) != TYPE_DICTIONARY:
		return {"error": ERR_INVALID_PARAMETER, "field": "systems"}
	var systems: Dictionary = snapshot["systems"]
	for participant_id: Variant in systems.keys():
		var participant_check := _validate_identifier(participant_id, "systems")
		if participant_check["error"] != OK:
			return participant_check
		if typeof(systems[participant_id]) != TYPE_DICTIONARY:
			return {"error": ERR_INVALID_PARAMETER, "field": String(participant_id)}
		var entry: Dictionary = systems[participant_id]
		if not WorldSaveDocument.has_exact_keys(entry, WorldSaveDocument.SYSTEM_KEYS):
			return {"error": ERR_INVALID_PARAMETER, "field": String(participant_id)}
		var schema_version: Array = []
		if WorldSaveDocument.as_exact_int(entry["schema_version"], schema_version) != OK:
			return {"error": ERR_INVALID_PARAMETER, "field": String(participant_id)}
		if int(schema_version[0]) < 0:
			return {"error": ERR_INVALID_PARAMETER, "field": String(participant_id)}
		var entry_check := _validate_leaf(entry["state"], String(participant_id))
		if entry_check["error"] != OK:
			return entry_check
	return {"error": OK, "field": ""}


static func _validate_record(value: Variant, field: String) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {"error": ERR_INVALID_PARAMETER, "field": field}
	var record: Dictionary = value
	if not WorldSaveDocument.has_exact_keys(record, WorldSaveDocument.RECORD_KEYS):
		return {"error": ERR_INVALID_PARAMETER, "field": field}
	if WorldPersistencePolicy.validate(int(record["policy"])) != OK:
		return {"error": ERR_INVALID_PARAMETER, "field": field}
	if int(record["policy"]) != WorldPersistencePolicy.Kind.SAVE_GAME:
		return {"error": ERR_INVALID_PARAMETER, "field": field}
	var kind := int(record["parent_kind"])
	if kind != WorldEntityParent.Kind.WORLD_ROOT \
			and kind != WorldEntityParent.Kind.PERSISTENT_ENTITY \
			and kind != WorldEntityParent.Kind.ATTACHMENT:
		return {"error": ERR_INVALID_PARAMETER, "field": field}
	var parent_kind_type := typeof(record["parent_id"])
	if parent_kind_type != TYPE_STRING and parent_kind_type != TYPE_STRING_NAME:
		return {"error": ERR_INVALID_PARAMETER, "field": field}
	var parent_id := String(record["parent_id"])
	if kind == WorldEntityParent.Kind.WORLD_ROOT:
		if parent_id != "":
			return {"error": ERR_INVALID_PARAMETER, "field": field}
	elif WorldId.validate(StringName(parent_id)) != OK:
		return {"error": ERR_INVALID_PARAMETER, "field": field}
	if WorldEntityOrigin.validate(int(record["origin"])) != OK:
		return {"error": ERR_INVALID_PARAMETER, "field": field}
	var archetype_type := typeof(record["archetype_id"])
	if archetype_type != TYPE_STRING and archetype_type != TYPE_STRING_NAME:
		return {"error": ERR_INVALID_PARAMETER, "field": field}
	var archetype_id := String(record["archetype_id"])
	if int(record["origin"]) == WorldEntityOrigin.Kind.DYNAMIC:
		if WorldId.validate(StringName(archetype_id)) != OK:
			return {"error": ERR_INVALID_PARAMETER, "field": field}
	elif archetype_id != "":
		return {"error": ERR_INVALID_PARAMETER, "field": field}
	if typeof(record["removed"]) != TYPE_BOOL:
		return {"error": ERR_INVALID_PARAMETER, "field": field}
	if typeof(record["components"]) != TYPE_DICTIONARY:
		return {"error": ERR_INVALID_PARAMETER, "field": field}
	var components: Dictionary = record["components"]
	for component_id: Variant in components.keys():
		var component_check := _validate_identifier(component_id, field)
		if component_check["error"] != OK:
			return component_check
		var leaf_check := _validate_leaf(components[component_id], String(component_id))
		if leaf_check["error"] != OK:
			return leaf_check
	return {"error": OK, "field": ""}


static func _validate_identifier(value: Variant, field: String) -> Dictionary:
	var kind := typeof(value)
	if kind != TYPE_STRING and kind != TYPE_STRING_NAME:
		return {"error": ERR_INVALID_PARAMETER, "field": field}
	if WorldId.validate(StringName(value)) != OK:
		return {"error": ERR_INVALID_PARAMETER, "field": field}
	return {"error": OK, "field": ""}


static func _validate_leaf(value: Variant, field: String) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {"error": ERR_INVALID_PARAMETER, "field": field}
	if WorldValue.validate(value) != OK:
		return {"error": ERR_INVALID_PARAMETER, "field": field}
	if _uses_reserved_key(value):
		return {"error": ERR_INVALID_PARAMETER, "field": field}
	return {"error": OK, "field": ""}


## The float wrapper key is reserved so the wrapper can never be mistaken for
## authored data on the way back in.
static func _uses_reserved_key(value: Variant) -> bool:
	match typeof(value):
		TYPE_DICTIONARY:
			for key: Variant in value.keys():
				if String(key) == FLOAT_WRAP_KEY:
					return true
				if _uses_reserved_key(value[key]):
					return true
			return false
		TYPE_ARRAY:
			for item: Variant in value:
				if _uses_reserved_key(item):
					return true
			return false
		_:
			return false
