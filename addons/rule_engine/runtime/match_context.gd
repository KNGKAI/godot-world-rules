class_name REMatchContext
extends RefCounted

enum Source { FACT, PAYLOAD, BLACKBOARD }

var payload: Dictionary
var blackboard: Dictionary
var _provider: REFactProvider
var _fact_cache: Dictionary = {}


func _init(
	p_payload: Dictionary = {},
	p_blackboard: Dictionary = {},
	p_provider: REFactProvider = null,
) -> void:
	var normalized := normalize_payload(p_payload)
	payload = normalized.value if normalized.valid else freeze_dictionary({})
	blackboard = freeze_dictionary(p_blackboard)
	_provider = p_provider if p_provider != null else REFactProvider.new()


static func normalize_payload(source: Dictionary) -> Dictionary:
	var normalized: Dictionary = {}
	var visited: Array = []
	_remember_copy(source, normalized, visited)
	for raw_key: Variant in source:
		if typeof(raw_key) != TYPE_STRING and typeof(raw_key) != TYPE_STRING_NAME:
			return {&"valid": false, &"value": {}}
		normalized[StringName(raw_key)] = _freeze_value(source[raw_key], visited)
	normalized.make_read_only()
	return {&"valid": true, &"value": normalized}


static func freeze_dictionary(source: Dictionary) -> Dictionary:
	return _freeze_dictionary(source, [])


static func freeze_value(value: Variant) -> Variant:
	return _freeze_value(value, [])


static func _freeze_value(value: Variant, visited: Array) -> Variant:
	if value is Dictionary:
		return _freeze_dictionary(value, visited)
	if value is Array:
		var existing := _find_copy(value, visited)
		if existing.found:
			return existing.value
		var frozen_array: Array = value.duplicate()
		_remember_copy(value, frozen_array, visited)
		for index: int in value.size():
			frozen_array[index] = _freeze_value(value[index], visited)
		frozen_array.make_read_only()
		return frozen_array
	if typeof(value) in [
		TYPE_PACKED_BYTE_ARRAY,
		TYPE_PACKED_INT32_ARRAY,
		TYPE_PACKED_INT64_ARRAY,
		TYPE_PACKED_FLOAT32_ARRAY,
		TYPE_PACKED_FLOAT64_ARRAY,
		TYPE_PACKED_STRING_ARRAY,
		TYPE_PACKED_VECTOR2_ARRAY,
		TYPE_PACKED_VECTOR3_ARRAY,
		TYPE_PACKED_COLOR_ARRAY,
		TYPE_PACKED_VECTOR4_ARRAY,
	]:
		return value.duplicate()
	if value is Resource and not value is Script:
		return _freeze_resource(value, visited)
	return value


static func _freeze_dictionary(source: Dictionary, visited: Array) -> Dictionary:
	var existing := _find_copy(source, visited)
	if existing.found:
		return existing.value
	var frozen: Dictionary = source.duplicate()
	frozen.clear()
	_remember_copy(source, frozen, visited)
	for key: Variant in source:
		var frozen_key: Variant = _freeze_value(key, visited)
		frozen[frozen_key] = _freeze_value(source[key], visited)
	frozen.make_read_only()
	return frozen


static func _freeze_resource(source: Resource, visited: Array) -> Resource:
	var existing := _find_copy(source, visited)
	if existing.found:
		return existing.value
	var frozen: Resource = source.duplicate(false)
	if frozen == null:
		return source
	_remember_copy(source, frozen, visited)
	_copy_resource_properties(source, frozen, visited, true)
	return frozen


static func duplicate_mutable_value(value: Variant) -> Variant:
	return _duplicate_mutable_value(value, [])


static func _duplicate_mutable_value(value: Variant, visited: Array) -> Variant:
	if value is Dictionary:
		var existing := _find_copy(value, visited)
		if existing.found:
			return existing.value
		var duplicated_dictionary: Dictionary = value.duplicate()
		duplicated_dictionary.clear()
		_remember_copy(value, duplicated_dictionary, visited)
		for key: Variant in value:
			var duplicated_key: Variant = _duplicate_mutable_value(key, visited)
			duplicated_dictionary[duplicated_key] = _duplicate_mutable_value(
				value[key], visited
			)
		return duplicated_dictionary
	if value is Array:
		var existing := _find_copy(value, visited)
		if existing.found:
			return existing.value
		var duplicated_array: Array = value.duplicate()
		_remember_copy(value, duplicated_array, visited)
		for index: int in value.size():
			duplicated_array[index] = _duplicate_mutable_value(value[index], visited)
		return duplicated_array
	if typeof(value) in [
		TYPE_PACKED_BYTE_ARRAY,
		TYPE_PACKED_INT32_ARRAY,
		TYPE_PACKED_INT64_ARRAY,
		TYPE_PACKED_FLOAT32_ARRAY,
		TYPE_PACKED_FLOAT64_ARRAY,
		TYPE_PACKED_STRING_ARRAY,
		TYPE_PACKED_VECTOR2_ARRAY,
		TYPE_PACKED_VECTOR3_ARRAY,
		TYPE_PACKED_COLOR_ARRAY,
		TYPE_PACKED_VECTOR4_ARRAY,
	]:
		return value.duplicate()
	if value is Resource and not value is Script:
		var source_resource: Resource = value
		var existing := _find_copy(source_resource, visited)
		if existing.found:
			return existing.value
		var duplicated_resource: Resource = source_resource.duplicate(false)
		if duplicated_resource == null:
			return value
		_remember_copy(source_resource, duplicated_resource, visited)
		_copy_resource_properties(source_resource, duplicated_resource, visited, false)
		return duplicated_resource
	return value


static func _copy_resource_properties(
	source: Resource,
	destination: Resource,
	visited: Array,
	freeze: bool,
) -> void:
	for property: Dictionary in source.get_property_list():
		if (int(property.usage) & PROPERTY_USAGE_STORAGE) == 0:
			continue
		var property_name := StringName(property.name)
		if property_name == &"script":
			continue
		var property_value: Variant = source.get(property_name)
		var copied_value: Variant = (
			_freeze_value(property_value, visited)
			if freeze
			else _duplicate_mutable_value(property_value, visited)
		)
		destination.set(property_name, copied_value)


static func _find_copy(value: Variant, visited: Array) -> Dictionary:
	for entry: Array in visited:
		if is_same(entry[0], value):
			return {&"found": true, &"value": entry[1]}
	return {&"found": false, &"value": null}


static func _remember_copy(source: Variant, copy: Variant, visited: Array) -> void:
	visited.append([source, copy])


func lookup(source: int, key: StringName) -> Dictionary:
	match source:
		Source.FACT:
			return _lookup_fact(key)
		Source.PAYLOAD:
			return _lookup_dictionary(payload, key)
		Source.BLACKBOARD:
			return _lookup_dictionary(blackboard, key)
		_:
			return {&"present": false, &"value": null}


func _lookup_fact(key: StringName) -> Dictionary:
	if _fact_cache.has(key):
		return _fact_cache[key]
	var present := _provider.has_fact(key)
	var result := {
		&"present": present,
		&"value": freeze_value(_provider.get_fact(key)) if present else null,
	}
	_fact_cache[key] = result
	return result


func _lookup_dictionary(values: Dictionary, key: StringName) -> Dictionary:
	var present := values.has(key)
	return {
		&"present": present,
		&"value": values.get(key) if present else null,
	}
