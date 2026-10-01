class_name WorldParticipantRegistry
extends RefCounted
## Stable-ID registry of persistence participants, plus the bulk hooks a save
## or load drives. Every pass runs in sorted ID order so behaviour does not
## depend on registration order. Does not log: callers at public boundaries do.


const MAX_PARTICIPANTS := 256

var _participants: Dictionary = {}

## id -> {from_version: WorldSaveMigration}, validated at registration. Not a
## WorldMigrationManager: that one owns container documents and enforces the D7
## metadata subset on every step, which a participant's private state has no
## reason to carry. Here the step's document *is* the state, and the version
## bookkeeping is this registry's because the table is keyed by it.
##
## Read from schema_migrations() once, at registration: a table that can change
## under a running load is a table whose failures are unreproducible.
var _migrations: Dictionary = {}


func register(id: StringName, participant: PersistenceParticipant) -> Error:
	if WorldId.validate(id) != OK:
		return ERR_INVALID_PARAMETER
	if participant == null:
		return ERR_INVALID_PARAMETER
	if _participants.has(id):
		return ERR_ALREADY_EXISTS
	if _participants.size() >= MAX_PARTICIPANTS:
		return ERR_OUT_OF_MEMORY
	var chain: Dictionary = {}
	var built := _build_chain(participant, chain)
	if built != OK:
		return built
	_participants[id] = participant
	_migrations[id] = chain
	return OK


## Validated at the boundary the project can see. A malformed table discovered
## during a load would be a surprise at the worst possible moment, and the load
## has no better answer than to refuse anyway.
static func _build_chain(participant: PersistenceParticipant, chain: Dictionary) -> Error:
	var current := participant.schema_version()
	if current < 0:
		return ERR_INVALID_PARAMETER
	var table := participant.schema_migrations()
	for key: Variant in table.keys():
		if typeof(key) != TYPE_INT:
			return ERR_INVALID_PARAMETER
		var from_version: int = key
		if from_version < 0 or from_version >= current:
			# A step at or above the declared version has nothing to produce:
			# either the table or schema_version() is wrong, and guessing which
			# is worse than refusing.
			return ERR_INVALID_PARAMETER
		var step: Variant = table[key]
		if not (step is WorldSaveMigration):
			return ERR_INVALID_PARAMETER
		chain[from_version] = step
	return OK


## Identity-checked, so a losing duplicate cannot evict the winner.
func unregister(id: StringName, participant: PersistenceParticipant) -> Error:
	if not _participants.has(id):
		return ERR_DOES_NOT_EXIST
	if _participants[id] != participant:
		return ERR_INVALID_PARAMETER
	_participants.erase(id)
	_migrations.erase(id)
	return OK


func has(id: StringName) -> bool:
	return _participants.has(id)


func get_participant(id: StringName) -> PersistenceParticipant:
	if not _participants.has(id):
		return null
	return _participants[id]


func size() -> int:
	return _participants.size()


func sorted_ids() -> Array[StringName]:
	var names: Array = []
	for id: Variant in _participants.keys():
		names.append(String(id))
	names.sort()
	var out: Array[StringName] = []
	for name: Variant in names:
		out.append(StringName(name))
	return out


func clear() -> void:
	_participants.clear()
	_migrations.clear()


## -> {error, participant_id, systems}. Each payload is self-validated and then
## detached, so a later mutation of the participant cannot change what is
## written.
func capture_all() -> Dictionary:
	var systems: Dictionary = {}
	for id: StringName in sorted_ids():
		var participant: PersistenceParticipant = _participants[id]
		var raw := participant.capture_state()
		var valid := participant.validate_state(raw)
		if valid != OK:
			return {"error": valid, "participant_id": id, "systems": {}}
		if WorldValue.validate(raw) != OK:
			return {"error": ERR_INVALID_PARAMETER, "participant_id": id, "systems": {}}
		systems[id] = {
			"schema_version": participant.schema_version(),
			"state": WorldValue.clone_validated(raw),
		}
	return {"error": OK, "participant_id": &"", "systems": systems}


## Advances every registered participant's decoded state to its current
## schema_version, in sorted ID order. Returns a NEW systems dictionary; the
## input is untouched, so a failure leaves the caller's staged data exactly as
## it was.
##
## -> {error, participant_id, systems, migrations}
##    migrations: {participant_id: {"from": int, "to": int, "steps": int}}
##
## Unknown and missing participant IDs are deliberately not this pass's
## business: it skips them and validate_all applies the unchanged strict
## policy, so that rule keeps one owner.
func migrate_all(systems: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var details: Dictionary = {}
	for key: Variant in systems.keys():
		out[String(key)] = (systems[key] as Dictionary).duplicate(true)
	for id: StringName in sorted_ids():
		if not out.has(String(id)):
			continue
		var participant: PersistenceParticipant = _participants[id]
		var entry: Dictionary = out[String(id)]
		var from_version := int(entry["schema_version"])
		var current := participant.schema_version()
		if from_version == current:
			continue
		if from_version > current:
			# State written by a newer build of the project's own system.
			# Incompatible, and never run backwards.
			return {
				"error": ERR_FILE_UNRECOGNIZED,
				"participant_id": id,
				"systems": {},
				"migrations": {},
			}
		var chain: Dictionary = _migrations[id]
		var advanced := _advance(chain, entry, from_version, current)
		if int(advanced["error"]) != OK:
			return {
				"error": advanced["error"],
				"participant_id": id,
				"systems": {},
				"migrations": {},
				"from_version": from_version,
				"to_version": advanced["to_version"],
			}
		out[String(id)] = {"schema_version": current, "state": advanced["state"]}
		details[String(id)] = {
			"from": from_version, "to": current, "steps": current - from_version,
		}
	return {"error": OK, "participant_id": &"", "systems": out, "migrations": details}


## Walks one participant's chain, one adjacent step at a time. A step receives
## the decoded state and returns the next version's decoded state; the version
## is the registry's bookkeeping, because the table is keyed by it.
##
## A missing step is ERR_UNAVAILABLE and names the gap. That is deliberately not
## the same failure as malformed state: "you have not written this migration"
## and "this payload is broken" need different fixes, and only one of them is
## the project's to make.
static func _advance(
	chain: Dictionary, entry: Dictionary, from_version: int, target: int
) -> Dictionary:
	var state: Dictionary = (entry["state"] as Dictionary).duplicate(true)
	var version := from_version
	while version < target:
		if not chain.has(version):
			return {"error": ERR_UNAVAILABLE, "state": {}, "to_version": version + 1}
		var migration: WorldSaveMigration = chain[version]
		var step := migration.migrate(state.duplicate(true))
		if step.error != OK:
			return {"error": step.error, "state": {}, "to_version": version + 1}
		# Re-checked against the allowlist before it can reach validate_state: a
		# migration is project code and must not be able to inject a Variant the
		# rest of the addon cannot handle.
		if WorldValue.validate(step.document) != OK:
			return {"error": ERR_INVALID_DATA, "state": {}, "to_version": version + 1}
		state = WorldValue.clone_validated(step.document)
		version += 1
	return {"error": OK, "state": state, "to_version": target}


## Strict both ways: an unknown participant in the slot and a registered
## participant missing from it are both failures.
##
## The schema_version equality below is deliberately exact and deliberately
## separate from migrate_all's reachability check. It is the post-condition of
## migration: if the migration pass is ever skipped, misordered, or
## short-circuited, this is what stops an unmigrated entry from reaching
## restore_state, leaving project-supplied validate_state as the only guard.
func validate_all(systems: Dictionary) -> Dictionary:
	for id: Variant in systems.keys():
		if not _participants.has(StringName(id)):
			return {"error": ERR_DOES_NOT_EXIST, "participant_id": StringName(id)}
	for id: StringName in sorted_ids():
		if not systems.has(String(id)):
			return {"error": ERR_DOES_NOT_EXIST, "participant_id": id}
		var entry: Dictionary = systems[String(id)]
		var participant: PersistenceParticipant = _participants[id]
		if int(entry["schema_version"]) != participant.schema_version():
			return {"error": ERR_INVALID_DATA, "participant_id": id}
		var checked := participant.validate_state(entry["state"])
		if checked != OK:
			return {"error": checked, "participant_id": id}
	return {"error": OK, "participant_id": &""}


## Rollback material, captured and validated before any hook runs.
func snapshot_all() -> Dictionary:
	var snapshots: Dictionary = {}
	for id: StringName in sorted_ids():
		var participant: PersistenceParticipant = _participants[id]
		var raw := participant.capture_state()
		if participant.validate_state(raw) != OK or WorldValue.validate(raw) != OK:
			return {"error": ERR_INVALID_DATA, "participant_id": id, "snapshots": {}}
		snapshots[id] = WorldValue.clone_validated(raw)
	return {"error": OK, "participant_id": &"", "snapshots": snapshots}


## Records each id in `attempted` before calling it, so the failing hook is
## included and gets rolled back too.
func restore_all(systems: Dictionary, attempted: Array[StringName]) -> Dictionary:
	for id: StringName in sorted_ids():
		var participant: PersistenceParticipant = _participants[id]
		var entry: Dictionary = systems[String(id)]
		attempted.append(id)
		var err := participant.restore_state((entry["state"] as Dictionary).duplicate(true))
		if err != OK:
			return {"error": err, "participant_id": id}
	return {"error": OK, "participant_id": &""}


## Reverse order, best effort: one failing rollback must not prevent the rest
## from being attempted. Any failure at all is unrecoverable for the caller.
func rollback(attempted: Array[StringName], snapshots: Dictionary) -> Dictionary:
	var failed: Array[StringName] = []
	var first: Error = OK
	var first_id: StringName = &""
	for index in range(attempted.size() - 1, -1, -1):
		var id := attempted[index]
		var participant: PersistenceParticipant = _participants.get(id)
		if participant == null or not snapshots.has(id):
			failed.append(id)
			if first == OK:
				first = ERR_DOES_NOT_EXIST
				first_id = id
			continue
		var err := participant.restore_state((snapshots[id] as Dictionary).duplicate(true))
		if err != OK:
			failed.append(id)
			if first == OK:
				first = err
				first_id = id
	return {"error": first, "participant_id": first_id, "failed": failed}


func reset_all() -> Dictionary:
	var first: Error = OK
	var first_id: StringName = &""
	for id: StringName in sorted_ids():
		var participant: PersistenceParticipant = _participants[id]
		var err := participant.reset_state()
		if err != OK and first == OK:
			first = err
			first_id = id
	return {"error": first, "participant_id": first_id}
