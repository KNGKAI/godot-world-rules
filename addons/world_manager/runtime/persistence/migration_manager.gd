class_name WorldMigrationManager
extends RefCounted
## Ordered registry of adjacent container migrations. Pure: it transforms copies
## of serialized payloads and touches no file, no clock, and no live object.
## Does not log -- every failure is a returned Error, so a broken chain is
## testable without an engine diagnostic. See README D21.
##
## The target version is a parameter rather than a property. Production callers
## pass WorldSaveDocument.FORMAT_VERSION; tests drive a longer chain by passing
## a larger number, which is why no private "configure the current version" seam
## exists. Nothing here decides what "current" means.


## A chain longer than this is a registry mistake, not a save from a very old
## build. Bounded so a cycle introduced by a future refactor cannot spin.
const MAX_STEPS := 256

var _migrations: Dictionary = {}


## Registers the step that reads `from_version` and produces `from_version + 1`.
func register_migration(from_version: int, migration: WorldSaveMigration) -> Error:
	if migration == null or from_version < 0:
		return ERR_INVALID_PARAMETER
	if _migrations.has(from_version):
		return ERR_ALREADY_EXISTS
	if _migrations.size() >= MAX_STEPS:
		return ERR_OUT_OF_MEMORY
	_migrations[from_version] = migration
	return OK


func has_migration(from_version: int) -> bool:
	return _migrations.has(from_version)


func size() -> int:
	return _migrations.size()


## Advances `document` to `target_version`, one registered step at a time.
##
## The input is never mutated and never escapes into the result: the first thing
## this does is take a deep copy, and every step's output is deep-copied again
## before the next step sees it. On any failure the result carries no document
## at all.
func migrate(document: Dictionary, target_version: int) -> WorldMigrationResult:
	if target_version < 0:
		return WorldMigrationResult.failure(
			ERR_INVALID_PARAMETER, {"stage": &"target", "target_version": target_version}
		)
	var source: Array = []
	if not document.has("format_version") \
			or WorldSaveDocument.as_exact_int(document["format_version"], source) != OK:
		return WorldMigrationResult.failure(
			ERR_INVALID_DATA, {"stage": &"version", "field": "format_version"}
		)
	var version := int(source[0])
	if version < 0:
		return WorldMigrationResult.failure(
			ERR_INVALID_DATA, {"stage": &"version", "format_version": version}
		)
	if version > target_version:
		# Newer than anything this build understands. Incompatible, not corrupt,
		# and never silently downgraded by running steps backwards.
		return WorldMigrationResult.failure(ERR_FILE_UNRECOGNIZED, {
			"stage": &"version",
			"source_format_version": version,
			"target_format_version": target_version,
		})
	var working: Dictionary = document.duplicate(true)
	var applied := 0
	while version < target_version:
		if applied >= MAX_STEPS:
			return WorldMigrationResult.failure(
				ERR_INVALID_DATA, {"stage": &"chain", "format_version": version}
			)
		if not _migrations.has(version):
			# Named distinctly from malformed state: "you have not written this
			# migration" and "this payload is broken" are different problems and
			# a project can only act on one of them.
			return WorldMigrationResult.failure(ERR_UNAVAILABLE, {
				"stage": &"missing_step",
				"from_version": version,
				"to_version": version + 1,
				"target_format_version": target_version,
			})
		var migration: WorldSaveMigration = _migrations[version]
		var step := migration.migrate(working.duplicate(true))
		if step.error != OK:
			var failed: Dictionary = step.context.duplicate(true)
			failed["stage"] = &"step"
			failed["from_version"] = version
			return WorldMigrationResult.failure(step.error, failed)
		var validated := _validate_step(step.document, version)
		if validated != OK:
			return WorldMigrationResult.failure(validated, {
				"stage": &"step_output",
				"from_version": version,
				"to_version": version + 1,
			})
		working = step.document.duplicate(true)
		version += 1
		applied += 1
	return WorldMigrationResult.ok(working, {
		"source_format_version": int(source[0]),
		"format_version": version,
		"steps": applied,
	})


## Checked after every step, not only at the end. A step that advances two
## versions, forgets to stamp the new one, or drops a metadata field is a defect
## in that step, and saying so at the step is the difference between a fixable
## report and "the chain produced something wrong".
static func _validate_step(produced: Dictionary, from_version: int) -> Error:
	var stamped: Array = []
	if not produced.has("format_version") \
			or WorldSaveDocument.as_exact_int(produced["format_version"], stamped) != OK:
		return ERR_INVALID_DATA
	if int(stamped[0]) != from_version + 1:
		return ERR_INVALID_DATA
	# The D7 metadata subset holds at every container version. A step is free to
	# reshape anything else; these five it may not drop or retype, because the
	# slot listing reads them without knowing the version.
	var metadata: Dictionary = {}
	return WorldSaveDocument.validate_metadata(produced, metadata)
