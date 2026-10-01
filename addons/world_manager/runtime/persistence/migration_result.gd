class_name WorldMigrationResult
extends RefCounted
## Outcome of one migration step, or of a whole chain. A failure exposes no
## document at all: a half-migrated payload is the one thing a caller must never
## be handed, because it looks exactly like a whole one.


var error: Error = OK
var document: Dictionary = {}
var context: Dictionary = {}


static func ok(produced: Dictionary, produced_context: Dictionary = {}) -> WorldMigrationResult:
	var result := WorldMigrationResult.new()
	result.error = OK
	result.document = produced
	result.context = produced_context
	return result


static func failure(reason: Error, failure_context: Dictionary) -> WorldMigrationResult:
	var result := WorldMigrationResult.new()
	result.error = reason
	result.context = failure_context
	return result


func is_ok() -> bool:
	return error == OK
