class_name WorldSaveDocument
extends RefCounted
## Version-one save schema: limits, field sets, and structural validation.
## Holds no JSON and no file access. Does not log.


const ENVELOPE_VERSION := 1
const FORMAT_VERSION := 2

## Slot files are capped before reading. Nesting of the *encoded* JSON is bounded
## only to keep recursion safe: the encoded tree is deeper than the native one
## because every tagged value adds an object plus an args array. The semantic
## limit stays WorldValue.MAX_DEPTH and is enforced after native decoding.
const MAX_FILE_BYTES := 16 * 1024 * 1024
const MAX_ENCODED_DEPTH := 192
const MAX_VISITS := 100000

## Plain structural integers stay inside JSON's exactly representable range.
## Gameplay int64 values live inside encoded leaves and use the "i:" string tag,
## which is exact at every magnitude.
const MAX_EXACT_INT := 9007199254740991
const CHECKSUM_LENGTH := 64

const ENVELOPE_KEYS: PackedStringArray = ["checksum", "envelope_version", "payload_json"]
const PAYLOAD_KEYS: PackedStringArray = [
	"active_world",
	"created_at",
	"format_version",
	"generation",
	"systems",
	"updated_at",
	"world_state",
	"worlds",
]
const SNAPSHOT_KEYS: PackedStringArray = [
	"active_world",
	"created_at",
	"generation",
	"systems",
	"updated_at",
	"world_state",
	"worlds",
]
## Exact, and deliberately not version-aware: both consumers are already
## guaranteed to be at the current version -- the decoder's check runs under a
## structural pass that refuses any other version first, and the encoder's runs
## under a function that stamps the version itself -- so a version-aware key set
## would be a branch no input could take. Tombstones carry every key too, so a
## removed dynamic record stays recognisable as dynamic.
const RECORD_KEYS: PackedStringArray = [
	"archetype_id", "components", "origin", "parent_id", "parent_kind", "policy",
	"removed",
]
const SYSTEM_KEYS: PackedStringArray = ["schema_version", "state"]

## The subset that is present, and identically typed, at every container
## version. See README D7: an older payload cannot be checked against
## PAYLOAD_KEYS -- that is the current format's key set -- but it can always be
## described, which is what makes an outdated slot listable and what preserves
## generation continuity when a save is written over it. Phase 9's bump may not
## rename or retype any of these.
const METADATA_KEYS: PackedStringArray = [
	"active_world", "created_at", "format_version", "generation", "updated_at",
]


static func has_exact_keys(value: Dictionary, expected: PackedStringArray) -> bool:
	if value.size() != expected.size():
		return false
	for key: String in expected:
		if not value.has(key):
			return false
	return true


## JSON parsing yields TYPE_FLOAT for every number, so a structural integer read
## back from a file we just wrote is not TYPE_INT. Accept either, and require an
## exactly representable integral value.
static func as_exact_int(value: Variant, out: Array) -> Error:
	var kind := typeof(value)
	if kind == TYPE_INT:
		var as_int: int = value
		if absi(as_int) > MAX_EXACT_INT:
			return ERR_INVALID_DATA
		out.append(as_int)
		return OK
	if kind != TYPE_FLOAT:
		return ERR_INVALID_DATA
	var as_float: float = value
	if not is_finite(as_float):
		return ERR_INVALID_DATA
	if floorf(as_float) != as_float:
		return ERR_INVALID_DATA
	if absf(as_float) > float(MAX_EXACT_INT):
		return ERR_INVALID_DATA
	out.append(int(as_float))
	return OK


## Version-independent metadata check, used before a payload's container version
## is known. Deliberately not has_exact_keys: an older or newer payload is
## allowed to carry other fields, and rejecting it for that would report a
## version difference as corruption.
static func validate_metadata(payload: Dictionary, out: Dictionary) -> Error:
	for field: String in METADATA_KEYS:
		if not payload.has(field):
			return ERR_INVALID_DATA
	for field: String in ["created_at", "updated_at", "generation"]:
		var parsed: Array = []
		if as_exact_int(payload[field], parsed) != OK:
			return ERR_INVALID_DATA
		out[field] = int(parsed[0])
	var active: Variant = payload["active_world"]
	if active != null:
		if typeof(active) != TYPE_STRING or WorldId.validate(StringName(active)) != OK:
			return ERR_INVALID_DATA
	out["active_world"] = null if active == null else StringName(active)
	return OK


static func is_checksum_text(value: Variant) -> bool:
	if typeof(value) != TYPE_STRING:
		return false
	var text: String = value
	if text.length() != CHECKSUM_LENGTH:
		return false
	for index in text.length():
		var code := text.unicode_at(index)
		var is_digit := code >= 48 and code <= 57
		var is_lower_hex := code >= 97 and code <= 102
		if not is_digit and not is_lower_hex:
			return false
	return true


## Reject a record whose required persistent parent is absent from the same
## world's saved set, or is present only as a tombstone. Such a record cannot be
## reconstructed, so it must never reach a slot file.
static func validate_parent_closure(entities: Dictionary) -> Dictionary:
	for entity_id: Variant in entities.keys():
		var record: Dictionary = entities[entity_id]
		var parent_kind: int = record["parent_kind"]
		if parent_kind != WorldEntityParent.Kind.PERSISTENT_ENTITY:
			continue
		var parent_id: String = record["parent_id"]
		if not entities.has(parent_id):
			return {"error": ERR_INVALID_PARAMETER, "field": "%s.parent_id" % str(entity_id)}
		var parent: Dictionary = entities[parent_id]
		if bool(parent["removed"]):
			return {"error": ERR_INVALID_PARAMETER, "field": "%s.parent_id" % str(entity_id)}
	return {"error": OK, "field": ""}


## Walk parent chains and reject a cycle. Mirrors the in-memory check in
## WorldPersistenceManager so a cyclic set cannot be written or read.
static func validate_parent_cycles(entities: Dictionary) -> Dictionary:
	for entity_id: Variant in entities.keys():
		var seen: Dictionary = {}
		var current: String = str(entity_id)
		while true:
			if seen.has(current):
				return {"error": ERR_INVALID_PARAMETER, "field": "%s.parent_id" % str(entity_id)}
			seen[current] = true
			if not entities.has(current):
				break
			var record: Dictionary = entities[current]
			if int(record["parent_kind"]) != WorldEntityParent.Kind.PERSISTENT_ENTITY:
				break
			var parent_id: String = record["parent_id"]
			if parent_id == "":
				break
			current = parent_id
	return {"error": OK, "field": ""}
