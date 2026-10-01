class_name WorldEntityIdGenerator
extends RefCounted
## Generated dynamic entity IDs and their reservations. Holds no registry and no
## records -- it takes a predicate -- and does not log, so exhaustion is a
## returned Error and therefore testable without a diagnostic. See README D5.
##
## Crypto rather than randi(): RandomNumberGenerator is a PCG seeded from 64
## bits, so two processes started in the same tick can produce the same stream,
## and a 128-bit ID drawn from a 64-bit seed has 64-bit collision properties
## whatever its length. A test pins the API at runtime so a build without the
## module fails a check rather than a player's save.


const PREFIX := "dyn:"
const ID_BYTES := 16
const MAX_ATTEMPTS := 8

var _reserved: Dictionary = {}
var _crypto: Crypto = Crypto.new()
var _source: Callable = Callable()


func _init() -> void:
	_source = _crypto_bytes


## Private test seam: substitute the byte source to force a collision or an
## exhaustion. Nothing in runtime/ calls this.
func _configure_source(source: Callable) -> void:
	_source = source


## `taken` is Callable(StringName) -> bool, supplied by the owner so this class
## needs to know nothing about the registry or the record tables.
## -> {error, id}
func reserve(taken: Callable) -> Dictionary:
	for _attempt in MAX_ATTEMPTS:
		var bytes: Variant = _source.call(ID_BYTES)
		if typeof(bytes) != TYPE_PACKED_BYTE_ARRAY:
			return {"error": ERR_UNAVAILABLE, "id": &""}
		var raw: PackedByteArray = bytes
		if raw.size() != ID_BYTES:
			return {"error": ERR_UNAVAILABLE, "id": &""}
		var candidate := StringName(PREFIX + raw.hex_encode())
		if _reserved.has(candidate):
			continue
		if taken.call(candidate):
			continue
		_reserved[candidate] = true
		return {"error": OK, "id": candidate}
	# Nothing was added to _reserved, so exhaustion has no cleanup path that
	# could be forgotten. ERR_CANT_CREATE rather than ERR_UNAVAILABLE, which
	# already means "you have not written this migration step" in this codebase.
	return {"error": ERR_CANT_CREATE, "id": &""}


## Every reserve is paired with exactly one release. On a successful commit the
## reservation is converted rather than kept -- the registry and the record
## table cover the ID from then on -- so _reserved is empty at rest, which is
## directly assertable.
func release(id: StringName) -> void:
	_reserved.erase(id)


func clear() -> void:
	_reserved.clear()


func reservation_count() -> int:
	return _reserved.size()


func _crypto_bytes(count: int) -> PackedByteArray:
	return _crypto.generate_random_bytes(count)
