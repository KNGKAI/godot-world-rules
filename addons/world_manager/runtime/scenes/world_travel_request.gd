class_name WorldTravelRequest
extends RefCounted
## One validated travel_to request. Pure: no Nodes, no guard, no SceneTree, and
## no logging -- World emits the single diagnostic at the public boundary, so
## this collaborator's malformed-input paths are ordinary GdUnit4 cases.
##
## Named for the command (travel_to) rather than for "transition": a transition
## is the optional presentation adapter, and reusing the word for the request
## would collide with WorldTransition.


## Every key travel_to will ever accept. An unlisted key is ERR_INVALID_PARAMETER
## rather than ignored: a silently dropped "timeout_second" typo is a bug the
## project cannot see, and the whole point of an optional hook is that its
## absence already looks exactly like success.
const ALLOWED_KEYS: Array[StringName] = [
	&"payload",
	&"placement",
	&"timeout_seconds",
	&"transition",
]

const DEFAULT_TIMEOUT_SECONDS := 10.0
## A wall-clock watchdog, not a presentation budget. The lower bound keeps a
## timeout testable without a ten-second sleep; the upper bound keeps a typo'd
## 600 from being indistinguishable from a hang.
const MIN_TIMEOUT_SECONDS := 0.1
const MAX_TIMEOUT_SECONDS := 60.0

var world_id: StringName = &""
var entry_id: StringName = &""
var payload: Dictionary = {}
var timeout_seconds: float = DEFAULT_TIMEOUT_SECONDS
var transition: WorldTransition = null
var placement: WorldPlacement = null


## -> {error, request, field}
## `field` names the offending option so the caller's diagnostic can say which
## one, which is the difference between an actionable rejection and a bare
## code=31.
static func parse(
	world_id_in: StringName, entry_id_in: StringName, options: Dictionary
) -> Dictionary:
	if WorldId.validate(world_id_in) != OK:
		return _fail(ERR_INVALID_PARAMETER, &"world_id")
	if entry_id_in != &"" and WorldId.validate(entry_id_in) != OK:
		return _fail(ERR_INVALID_PARAMETER, &"entry_id")
	for key: Variant in options.keys():
		if typeof(key) != TYPE_STRING and typeof(key) != TYPE_STRING_NAME:
			return _fail(ERR_INVALID_PARAMETER, &"options")
		var name := StringName(key)
		if not ALLOWED_KEYS.has(name):
			return _fail(ERR_INVALID_PARAMETER, name)
	var request := WorldTravelRequest.new()
	request.world_id = world_id_in
	request.entry_id = entry_id_in
	if request._read_payload(options) != OK:
		return _fail(ERR_INVALID_PARAMETER, &"payload")
	if request._read_timeout(options) != OK:
		return _fail(ERR_INVALID_PARAMETER, &"timeout_seconds")
	var adapter_field := request._read_adapters(options)
	if adapter_field != &"":
		return _fail(ERR_INVALID_PARAMETER, adapter_field)
	return {"error": OK, "request": request, "field": &""}


## Validated at acceptance rather than mid-flight, so an out-of-range timeout is
## a rejected request and not a travel that fails halfway through.
func _read_timeout(options: Dictionary) -> Error:
	var raw: Variant = _option(options, &"timeout_seconds")
	if raw == null:
		return OK
	if typeof(raw) != TYPE_INT and typeof(raw) != TYPE_FLOAT:
		return ERR_INVALID_PARAMETER
	var seconds := float(raw)
	if is_nan(seconds) or is_inf(seconds):
		return ERR_INVALID_PARAMETER
	if seconds < MIN_TIMEOUT_SECONDS or seconds > MAX_TIMEOUT_SECONDS:
		return ERR_INVALID_PARAMETER
	timeout_seconds = seconds
	return OK


## -> the offending field name, or &"" when both adapters are acceptable.
func _read_adapters(options: Dictionary) -> StringName:
	var raw_transition: Variant = _option(options, &"transition")
	if raw_transition != null:
		if not (raw_transition is WorldTransition):
			return &"transition"
		transition = raw_transition
	var raw_placement: Variant = _option(options, &"placement")
	if raw_placement != null:
		if not (raw_placement is WorldPlacement):
			return &"placement"
		placement = raw_placement
	return &""


func _read_payload(options: Dictionary) -> Error:
	var raw: Variant = _option(options, &"payload")
	if raw == null:
		return OK
	if typeof(raw) != TYPE_DICTIONARY:
		return ERR_INVALID_PARAMETER
	# The same allowlist the state store and world metadata use. It is what
	# rejects Nodes, Callables, non-finite floats, cycles, and over-deep or
	# over-large containers, so nothing runtime-only can reach an event payload.
	if WorldValue.validate(raw) != OK:
		return ERR_INVALID_PARAMETER
	# Cloned at accept time, so a caller that mutates its own dictionary after
	# travel_to returns cannot change what listeners later see.
	var cloned: Variant = WorldValue.clone_validated(raw)
	if typeof(cloned) != TYPE_DICTIONARY:
		return ERR_INVALID_PARAMETER
	payload = cloned
	return OK


## Dictionary literals in GDScript key on String unless written &"", and a
## project may pass either, so both spellings resolve to the same option.
static func _option(options: Dictionary, name: StringName) -> Variant:
	if options.has(name):
		return options[name]
	if options.has(String(name)):
		return options[String(name)]
	return null


static func _fail(reason: Error, field: StringName) -> Dictionary:
	return {"error": reason, "request": null, "field": field}
