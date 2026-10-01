class_name WorldSaveV1ToV2
extends WorldSaveMigration
## Container step 1 -> 2: every version-one record is authored.
##
## That is a fact about the format, not an inference about the project. Version
## one had no way to create anything but an authored entity, so there is nothing
## to detect. The archetype is left empty deliberately: a migration cannot see
## project content, and a save must never be able to name a scene -- so no
## archetype is ever inferred from a NodePath, a scene name, or anything else.
## See README D21 and D5.
##
## A record wrapper is plain JSON; only component *values* carry
## JSON.from_native tags. So this is plain dictionary work and needs none of the
## dictionary_tag_* helpers.


func migrate(document: Dictionary) -> WorldMigrationResult:
	var out: Dictionary = document.duplicate(true)
	# int(...) + 1, never a literal 2: JSON.parse yields a float for every
	# number, and int-versus-float is visible in the canonical bytes.
	out["format_version"] = int(out["format_version"]) + 1
	var worlds_value: Variant = out.get("worlds")
	if typeof(worlds_value) != TYPE_DICTIONARY:
		return WorldMigrationResult.failure(
			ERR_INVALID_DATA, {"reason": &"worlds", "field": "worlds"}
		)
	var worlds: Dictionary = worlds_value
	for world_key: Variant in worlds.keys():
		var world_value: Variant = worlds[world_key]
		if typeof(world_value) != TYPE_DICTIONARY:
			return WorldMigrationResult.failure(
				ERR_INVALID_DATA, {"reason": &"entities", "field": str(world_key)}
			)
		var world_entry: Dictionary = world_value
		if not world_entry.has("entities") \
				or typeof(world_entry["entities"]) != TYPE_DICTIONARY:
			return WorldMigrationResult.failure(
				ERR_INVALID_DATA, {"reason": &"entities", "field": str(world_key)}
			)
		var entities: Dictionary = world_entry["entities"]
		for entity_key: Variant in entities.keys():
			var record_value: Variant = entities[entity_key]
			if typeof(record_value) != TYPE_DICTIONARY:
				return WorldMigrationResult.failure(ERR_INVALID_DATA, {
					"reason": &"record",
					"field": "%s.%s" % [str(world_key), str(entity_key)],
				})
			# Tombstones included: format two's record shape is uniform, so a
			# removed record carries the new keys like any other.
			var record: Dictionary = record_value
			record["origin"] = WorldEntityOrigin.Kind.AUTHORED
			record["archetype_id"] = ""
	return WorldMigrationResult.ok(out)
