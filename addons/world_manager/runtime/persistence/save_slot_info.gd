class_name WorldSaveSlotInfo
extends RefCounted
## Detached slot metadata. Holds no FileAccess and no live handle, so a listing
## can outlive the scan that produced it.


## Appended, never reordered: the values are a public surface.
##
## VALID is the strongest claim the store can make on its own -- verified intact
## and structurally valid at the current format version. It has never meant
## "this will load": an unknown or missing participant still fails the load.
##
## OUTDATED is deliberately weaker. The envelope and checksum verified and the
## container version is older than current, but structural validity at that
## older version can only be established after migration, and migration depends
## on a registry the store does not know about.
##
## Across the three generations the precedence is
## INCOMPATIBLE > OUTDATED > RECOVERABLE > VALID, and `source` is authoritative
## for which generation the status came from.
enum Status {
	VALID = 0,
	RECOVERABLE = 1,
	CORRUPT = 2,
	INCOMPATIBLE = 3,
	OUTDATED = 4,
}

## Which generation on disk the status came from: primary, backup, temporary,
## or empty when nothing readable was found.
var slot_id: StringName = &""
var status: Status = Status.CORRUPT
var source: StringName = &""
var generation: int = 0
var created_at: int = 0
var updated_at: int = 0
var format_version: int = 0
var size_bytes: int = 0

## An absent active world is distinguishable from a world named "", without
## giving up the static type.
var has_active_world: bool = false
var active_world: StringName = &""


func duplicate_info() -> WorldSaveSlotInfo:
	var copy := WorldSaveSlotInfo.new()
	copy.slot_id = slot_id
	copy.status = status
	copy.source = source
	copy.generation = generation
	copy.created_at = created_at
	copy.updated_at = updated_at
	copy.format_version = format_version
	copy.size_bytes = size_bytes
	copy.has_active_world = has_active_world
	copy.active_world = active_world
	return copy
