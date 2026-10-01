class_name WorldSerializationResult
extends RefCounted
## Outcome of one encode or decode. Only the fields that operation produces are
## filled; a failure exposes neither bytes nor a partially decoded document.


var error: Error = OK
var bytes: PackedByteArray = PackedByteArray()
var document: Dictionary = {}

## The raw parsed payload: checksum-verified, but NOT validated against the
## current format and with every value leaf still in JSON.from_native tag form.
## Never set together with `document`, which means the opposite -- validated,
## native-decoded, identifiers normalised to StringName. The two are duck-
## compatible and confusing them is silent: `created_at` is a float here, and
## `world_state` is a perfectly usable Dictionary that decodes to garbage.
var payload: Dictionary = {}
var context: Dictionary = {}


static func ok_bytes(
	produced: PackedByteArray, produced_context: Dictionary
) -> WorldSerializationResult:
	var result := WorldSerializationResult.new()
	result.error = OK
	result.bytes = produced
	result.context = produced_context
	return result


static func ok_document(
	decoded: Dictionary, decoded_context: Dictionary
) -> WorldSerializationResult:
	var result := WorldSerializationResult.new()
	result.error = OK
	result.document = decoded
	result.context = decoded_context
	return result


static func ok_payload(
	parsed: Dictionary, parsed_context: Dictionary
) -> WorldSerializationResult:
	var result := WorldSerializationResult.new()
	result.error = OK
	result.payload = parsed
	result.context = parsed_context
	return result


static func failure(reason: Error, failure_context: Dictionary) -> WorldSerializationResult:
	var result := WorldSerializationResult.new()
	result.error = reason
	result.context = failure_context
	return result


func is_ok() -> bool:
	return error == OK
