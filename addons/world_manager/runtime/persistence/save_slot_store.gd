class_name WorldSaveSlotStore
extends RefCounted
## Rotate-then-publish slot storage with read-only recovery.
##
## Every rename targets a name already verified free, which is what keeps the
## sequence safe on Windows, where renaming onto an existing file deletes the
## destination first and briefly leaves no valid save. The guarantee is
## preservation and recovery across tested process and I/O failures -- not
## power-loss durability and not native atomic replacement. One process owns
## writes; two application instances sharing a save root are unsupported and
## there is no in-process guard for that. Does not log.


const PUBLISH_ATTEMPTS := 3
const MAX_QUARANTINE := 64
const MAX_SLOT_LENGTH := 64

const SUFFIX_PRIMARY := ".sav"
const SUFFIX_BACKUP := ".sav.bak"
const SUFFIX_TEMP := ".sav.tmp"
const SUFFIX_QUARANTINE := ".sav.bad"

const SOURCE_PRIMARY := &"primary"
const SOURCE_BACKUP := &"backup"
const SOURCE_TEMPORARY := &"temporary"

## Windows resolves these basenames to devices regardless of extension. The
## grammar already excludes uppercase, so a lowercase comparison is complete.
const RESERVED_DEVICE_NAMES: PackedStringArray = [
	"con", "prn", "aux", "nul",
	"com1", "com2", "com3", "com4", "com5", "com6", "com7", "com8", "com9",
	"lpt1", "lpt2", "lpt3", "lpt4", "lpt5", "lpt6", "lpt7", "lpt8", "lpt9",
]

var _filesystem: WorldSaveFilesystem


func _init(filesystem: WorldSaveFilesystem = null) -> void:
	_filesystem = filesystem if filesystem != null else WorldSaveFilesystem.new()


## Grammar [a-z0-9][a-z0-9_-]{0,63}, scanned rather than matched with RegEx:
## PCRE2's "$" also matches before a trailing newline, so an anchored pattern
## would accept "slot\n".
static func validate_slot_id(slot_id: StringName) -> Error:
	var text := String(slot_id)
	if text.is_empty() or text.length() > MAX_SLOT_LENGTH:
		return ERR_INVALID_PARAMETER
	for index in text.length():
		var code := text.unicode_at(index)
		var is_digit := code >= 48 and code <= 57
		var is_lower := code >= 97 and code <= 122
		var is_extra := code == 45 or code == 95
		if is_digit or is_lower:
			continue
		if index > 0 and is_extra:
			continue
		return ERR_INVALID_PARAMETER
	if RESERVED_DEVICE_NAMES.has(text):
		return ERR_INVALID_PARAMETER
	return OK


# --- reading ------------------------------------------------------------------


## The envelope pass over the best available generation: checksum verified,
## payload parsed, value leaves still encoded. This is what the migration
## pipeline consumes, and it is the only read that can succeed for an outdated
## slot. Migration lives above the store, so the store reports the version and
## never guesses. Never deletes, promotes, repairs, or rewrites anything.
func open_slot(slot_id: StringName) -> WorldSerializationResult:
	var scan := _select(slot_id)
	if int(scan["error"]) != OK:
		return scan["result"]
	var opened: WorldSerializationResult = (scan["probe"] as Dictionary)["opened"]
	opened.context["slot_id"] = slot_id
	opened.context["source"] = scan["source"]
	opened.context["recovered"] = scan["source"] != SOURCE_PRIMARY
	return opened


## Prefers a verified primary, then a verified backup, then a verified
## temporary. Never deletes, promotes, repairs, or rewrites anything. An
## outdated generation is reported rather than decoded: only migration can make
## it current, and that is the load pipeline's job, not the store's.
func read_slot(slot_id: StringName) -> WorldSerializationResult:
	var scan := _select(slot_id)
	if int(scan["error"]) != OK:
		return scan["result"]
	var probe: Dictionary = scan["probe"]
	if probe["status"] == &"outdated":
		return WorldSerializationResult.failure(ERR_FILE_UNRECOGNIZED, {
			"stage": &"version",
			"slot_id": slot_id,
			"source": scan["source"],
			"format_version": probe["format_version"],
		})
	var result: WorldSerializationResult = probe["result"]
	result.context["slot_id"] = slot_id
	result.context["source"] = scan["source"]
	result.context["recovered"] = scan["source"] != SOURCE_PRIMARY
	return result


## Primary, then backup, then temporary; the first publishable generation wins.
## Shared by open_slot and read_slot so recovery selection has one owner.
func _select(slot_id: StringName) -> Dictionary:
	var id_error := validate_slot_id(slot_id)
	if id_error != OK:
		return {"error": id_error, "result": WorldSerializationResult.failure(
			id_error, {"stage": &"slot_id", "slot_id": slot_id}
		)}
	var any_present := false
	for source: StringName in [SOURCE_PRIMARY, SOURCE_BACKUP, SOURCE_TEMPORARY]:
		var probe := _probe(slot_id, source)
		if not bool(probe["present"]):
			continue
		any_present = true
		var status: StringName = probe["status"]
		if status == &"incompatible":
			# A valid newer schema is incompatible, not corrupt. Falling through
			# to an older generation here would be a silent downgrade.
			return {"error": ERR_FILE_UNRECOGNIZED, "result":
				WorldSerializationResult.failure(ERR_FILE_UNRECOGNIZED, {
					"stage": &"version",
					"slot_id": slot_id,
					"source": source,
					"format_version": probe["format_version"],
				})}
		if not _is_publishable(status):
			continue
		return {"error": OK, "probe": probe, "source": source}
	if not any_present:
		return {"error": ERR_FILE_NOT_FOUND, "result": WorldSerializationResult.failure(
			ERR_FILE_NOT_FOUND, {"stage": &"read", "slot_id": slot_id}
		)}
	return {"error": ERR_FILE_CORRUPT, "result": WorldSerializationResult.failure(
		ERR_FILE_CORRUPT, {"stage": &"read", "slot_id": slot_id}
	)}


func list_slots() -> Array[WorldSaveSlotInfo]:
	var seen: Dictionary = {}
	for name: String in _filesystem.list_names():
		if not name.ends_with(SUFFIX_PRIMARY) and not name.ends_with(SUFFIX_BACKUP) \
				and not name.ends_with(SUFFIX_TEMP):
			continue
		var stem := name.substr(0, name.find(SUFFIX_PRIMARY))
		if validate_slot_id(StringName(stem)) != OK:
			continue
		seen[stem] = true
	var ids: Array = seen.keys()
	ids.sort()
	var out: Array[WorldSaveSlotInfo] = []
	for stem: Variant in ids:
		var info := _describe(StringName(stem))
		if info != null:
			out.append(info)
	return out


func _describe(slot_id: StringName) -> WorldSaveSlotInfo:
	var info := WorldSaveSlotInfo.new()
	info.slot_id = slot_id
	var any_present := false
	for source: StringName in [SOURCE_PRIMARY, SOURCE_BACKUP, SOURCE_TEMPORARY]:
		var probe := _probe(slot_id, source)
		if not bool(probe["present"]):
			continue
		any_present = true
		var status: StringName = probe["status"]
		if status == &"incompatible":
			info.status = WorldSaveSlotInfo.Status.INCOMPATIBLE
			info.source = source
			info.format_version = int(probe["format_version"])
			info.size_bytes = int(probe["size"])
			return info
		if not _is_publishable(status):
			continue
		# Metadata is readable at every container version (README D7), which is
		# what lets an outdated generation be described rather than merely
		# counted. The status is the weaker claim, not the metadata.
		var opened: WorldSerializationResult = probe["opened"]
		if status == &"outdated":
			info.status = WorldSaveSlotInfo.Status.OUTDATED
		else:
			info.status = WorldSaveSlotInfo.Status.VALID if source == SOURCE_PRIMARY \
				else WorldSaveSlotInfo.Status.RECOVERABLE
		info.source = source
		info.size_bytes = int(probe["size"])
		info.generation = int(opened.context["generation"])
		info.created_at = int(opened.context["created_at"])
		info.updated_at = int(opened.context["updated_at"])
		info.format_version = int(opened.context["format_version"])
		var active: Variant = opened.context["active_world"]
		info.has_active_world = active != null
		info.active_world = StringName(active) if active != null else &""
		return info
	if not any_present:
		return null
	info.status = WorldSaveSlotInfo.Status.CORRUPT
	return info


func _probe(slot_id: StringName, source: StringName) -> Dictionary:
	var name := _file_name(slot_id, source)
	var absent := {"present": false, "status": &"absent", "size": 0, "format_version": 0}
	if not _filesystem.exists(name):
		return absent
	var size := _filesystem.size_of(name)
	if size < 0:
		return {"present": true, "status": &"corrupt", "size": 0, "format_version": 0}
	if size > WorldSaveDocument.MAX_FILE_BYTES:
		return {"present": true, "status": &"corrupt", "size": size, "format_version": 0}
	var read := _filesystem.read(name)
	if int(read["error"]) != OK:
		return {"present": true, "status": &"corrupt", "size": size, "format_version": 0}
	# Two passes, and the split matters: the envelope pass establishes the
	# version, so the classification below states what is actually known rather
	# than inferring intent from whichever Error code a single decode returned.
	var opened := WorldSaveSerializer.read_payload(read["bytes"])
	if opened.error == ERR_FILE_UNRECOGNIZED:
		return {
			"present": true,
			"status": &"incompatible",
			"size": size,
			"format_version": int(opened.context.get("format_version", 0)),
			"opened": opened,
		}
	if opened.error != OK:
		return {"present": true, "status": &"corrupt", "size": size, "format_version": 0}
	var version := int(opened.context["format_version"])
	if version < WorldSaveDocument.FORMAT_VERSION:
		# Intact, but only migration can say whether it is structurally valid at
		# its own version, and migration is not the store's business.
		return {
			"present": true,
			"status": &"outdated",
			"size": size,
			"format_version": version,
			"opened": opened,
			"bytes": read["bytes"],
		}
	var decoded := WorldSaveSerializer.decode_payload(opened.payload, size)
	if decoded.error != OK:
		return {"present": true, "status": &"corrupt", "size": size, "format_version": 0}
	return {
		"present": true,
		"status": &"valid",
		"size": size,
		"format_version": version,
		"opened": opened,
		"result": decoded,
		"bytes": read["bytes"],
	}


## Generations the write sequence may rotate and publish over. An outdated save
## belongs here: quarantine is for bytes that failed verification, and renaming
## an intact older save to <slot>.sav.bad hides it from every public surface.
static func _is_publishable(status: StringName) -> bool:
	return status == &"valid" or status == &"outdated"


# --- writing ------------------------------------------------------------------


## Coroutine: publication retries are spaced one process frame apart, so every
## caller must await. Returns OK only when the new generation is published.
func write_slot(slot_id: StringName, bytes: PackedByteArray) -> Error:
	var id_error := validate_slot_id(slot_id)
	if id_error != OK:
		return id_error
	if bytes.is_empty() or bytes.size() > WorldSaveDocument.MAX_FILE_BYTES:
		return ERR_INVALID_PARAMETER
	var root_error := _filesystem.ensure_root()
	if root_error != OK:
		return ERR_FILE_CANT_WRITE
	for source: StringName in [SOURCE_PRIMARY, SOURCE_BACKUP, SOURCE_TEMPORARY]:
		if _probe(slot_id, source)["status"] == &"incompatible":
			return ERR_FILE_UNRECOGNIZED
	var normalized := _normalize(slot_id)
	if normalized != OK:
		return normalized
	var temp_name := _file_name(slot_id, SOURCE_TEMPORARY)
	var verified := _write_verified(temp_name, bytes)
	if verified != OK:
		# The live generations were never touched.
		_filesystem.remove(temp_name)
		return verified
	var primary_name := _file_name(slot_id, SOURCE_PRIMARY)
	var backup_name := _file_name(slot_id, SOURCE_BACKUP)
	if _is_publishable(_probe(slot_id, SOURCE_PRIMARY)["status"]):
		if _filesystem.exists(backup_name):
			if _filesystem.remove(backup_name) != OK:
				return ERR_FILE_CANT_WRITE
		if _filesystem.rename(primary_name, backup_name) != OK:
			return ERR_FILE_CANT_WRITE
	for attempt in PUBLISH_ATTEMPTS:
		if _filesystem.rename(temp_name, primary_name) == OK:
			return OK
		if attempt < PUBLISH_ATTEMPTS - 1:
			await _wait_one_frame()
	# Both the previous generation and the verified new one remain recoverable.
	return ERR_FILE_CANT_WRITE


## Bring a recovery-only slot into a shape the write sequence can publish into,
## without ever destroying its only valid generation.
func _normalize(slot_id: StringName) -> Error:
	var primary_name := _file_name(slot_id, SOURCE_PRIMARY)
	var temp_name := _file_name(slot_id, SOURCE_TEMPORARY)
	var primary := _probe(slot_id, SOURCE_PRIMARY)
	if bool(primary["present"]) and not _is_publishable(primary["status"]):
		var quarantine := _free_quarantine_name(slot_id)
		if quarantine.is_empty():
			return ERR_FILE_CANT_WRITE
		if _filesystem.rename(primary_name, quarantine) != OK:
			return ERR_FILE_CANT_WRITE
		primary = _probe(slot_id, SOURCE_PRIMARY)
	var temporary := _probe(slot_id, SOURCE_TEMPORARY)
	if not bool(primary["present"]) and _is_publishable(temporary["status"]):
		# A sole verified temporary is the newest generation; promote it to the
		# now-free primary name so .tmp can be reused.
		if _filesystem.rename(temp_name, primary_name) != OK:
			return ERR_FILE_CANT_WRITE
		return OK
	if bool(temporary["present"]) and _is_publishable(primary["status"]):
		if _filesystem.remove(temp_name) != OK:
			return ERR_FILE_CANT_WRITE
	return OK


## Write, then read back and compare the intended bytes exactly. A checksum
## alone would accept a valid but stale temporary as the new save, and no Error
## code distinguishes a short write from success.
func _write_verified(temp_name: String, bytes: PackedByteArray) -> Error:
	var write_error := _filesystem.write(temp_name, bytes)
	if write_error != OK:
		return ERR_FILE_CANT_WRITE
	var read := _filesystem.read(temp_name)
	if int(read["error"]) != OK:
		return ERR_FILE_CANT_WRITE
	var written: PackedByteArray = read["bytes"]
	if written != bytes:
		return ERR_FILE_CANT_WRITE
	if WorldSaveSerializer.decode(written).error != OK:
		return ERR_FILE_CANT_WRITE
	return OK


func _free_quarantine_name(slot_id: StringName) -> String:
	for index in MAX_QUARANTINE:
		var candidate := "%s%s%d" % [String(slot_id), SUFFIX_QUARANTINE, index]
		if not _filesystem.exists(candidate):
			return candidate
	return ""


func _file_name(slot_id: StringName, source: StringName) -> String:
	match source:
		SOURCE_BACKUP:
			return "%s%s" % [String(slot_id), SUFFIX_BACKUP]
		SOURCE_TEMPORARY:
			return "%s%s" % [String(slot_id), SUFFIX_TEMP]
		_:
			return "%s%s" % [String(slot_id), SUFFIX_PRIMARY]


func _wait_one_frame() -> void:
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		await (loop as SceneTree).process_frame
