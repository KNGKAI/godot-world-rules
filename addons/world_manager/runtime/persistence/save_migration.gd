class_name WorldSaveMigration
extends RefCounted
## One adjacent upgrade step. A container step advances `format_version` by
## exactly one; a participant step advances one participant's `schema_version`
## by exactly one. See README D21 for ownership and placement.
##
## A migration is pure: no clock, no RNG, no world lookup, no file access, no
## live Nodes. Given the same input it must produce byte-identical canonical
## output, in this process and the next. Iterating a dictionary in a
## nondeterministic order is a defect, not a style choice, and the determinism
## test is what catches it.
##
## Container steps receive **encoded** leaves, because they run before decoding.
## Participant steps receive **decoded native** dictionaries. The helpers below
## exist for the first case only.


## Override this. The default refuses rather than silently passing the document
## through: a registered step that does nothing is indistinguishable from a
## missing one at the point where it matters.
func migrate(_document: Dictionary) -> WorldMigrationResult:
	return WorldMigrationResult.failure(
		ERR_METHOD_NOT_FOUND, {"stage": &"migrate", "reason": &"not_overridden"}
	)


# --- encoded Dictionary helpers -----------------------------------------------
#
# JSON.from_native encodes a Dictionary as {"type": "Dictionary", "args": [k1,
# v1, k2, v2, ...]} -- args is a flat, ordered, pair-wise array. sort_keys never
# reaches inside it, so pair order is part of the canonical bytes and rewriting
# args by hand is easy to get subtly wrong. These do the bookkeeping.


const DICTIONARY_TAG := "Dictionary"
const KEY_PREFIXES: PackedStringArray = ["s:", "sn:"]


static func is_dictionary_tag(value: Variant) -> bool:
	if typeof(value) != TYPE_DICTIONARY:
		return false
	var tag: Dictionary = value
	if not tag.has("type") or not tag.has("args"):
		return false
	return tag["type"] == DICTIONARY_TAG and typeof(tag["args"]) == TYPE_ARRAY


## Index of `key`'s slot in args, or -1. Matches either string prefix, so a
## StringName-keyed dictionary is found by the same plain name.
static func dictionary_tag_find(tag: Dictionary, key: String) -> int:
	if not is_dictionary_tag(tag):
		return -1
	var args: Array = tag["args"]
	var index := 0
	while index + 1 < args.size():
		var encoded: Variant = args[index]
		if typeof(encoded) == TYPE_STRING:
			for prefix: String in KEY_PREFIXES:
				if encoded == prefix + key:
					return index
		index += 2
	return -1


static func dictionary_tag_has(tag: Dictionary, key: String) -> bool:
	return dictionary_tag_find(tag, key) != -1


## The encoded value for `key`, or null when absent. Note that a genuinely null
## value encodes as null too, so pair `dictionary_tag_has` with this when the
## difference matters.
static func dictionary_tag_get(tag: Dictionary, key: String) -> Variant:
	var index := dictionary_tag_find(tag, key)
	return null if index == -1 else (tag["args"] as Array)[index + 1]


## A copy of `tag` with one key renamed **in place** in args, preserving both
## pair order and the original key's prefix. Returns an unchanged copy when the
## key is absent, so a migration can be written without a presence check.
static func dictionary_tag_renamed(
	tag: Dictionary, from_key: String, to_key: String
) -> Dictionary:
	var copy: Dictionary = tag.duplicate(true)
	var index := dictionary_tag_find(copy, from_key)
	if index == -1:
		return copy
	var args: Array = copy["args"]
	var encoded: String = args[index]
	var prefix := encoded.substr(0, encoded.length() - from_key.length())
	args[index] = prefix + to_key
	return copy
