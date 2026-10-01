class_name WorldValue
extends RefCounted
## Validates and isolates serializable values. Does not log.


const MAX_DEPTH := 64
const MAX_VISITS := 100000


static func validate(value: Variant) -> Error:
	return _walk(value, [], 0, [0])


static func clone_validated(value: Variant) -> Variant:
	if validate(value) != OK:
		return null
	return _clone(value)


static func _walk(value: Variant, ancestors: Array, depth: int, visits: Array) -> Error:
	visits[0] = int(visits[0]) + 1
	if int(visits[0]) > MAX_VISITS:
		return ERR_INVALID_PARAMETER
	var value_type := typeof(value)
	match value_type:
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING, TYPE_STRING_NAME:
			return OK
		TYPE_FLOAT:
			return OK if is_finite(value) else ERR_INVALID_PARAMETER
		TYPE_VECTOR2, TYPE_VECTOR2I, TYPE_RECT2, TYPE_RECT2I, TYPE_VECTOR3, TYPE_VECTOR3I, \
		TYPE_TRANSFORM2D, TYPE_VECTOR4, TYPE_VECTOR4I, TYPE_PLANE, TYPE_QUATERNION, TYPE_AABB, \
		TYPE_BASIS, TYPE_TRANSFORM3D, TYPE_PROJECTION, TYPE_COLOR:
			return OK if _math_is_finite(value) else ERR_INVALID_PARAMETER
		TYPE_PACKED_BYTE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, \
		TYPE_PACKED_STRING_ARRAY:
			return _count_packed(value, visits)
		TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_VECTOR2_ARRAY, \
		TYPE_PACKED_VECTOR3_ARRAY, TYPE_PACKED_VECTOR4_ARRAY, TYPE_PACKED_COLOR_ARRAY:
			var packed_err := _count_packed(value, visits)
			if packed_err != OK:
				return packed_err
			return OK if _packed_is_finite(value) else ERR_INVALID_PARAMETER
		TYPE_ARRAY:
			return _walk_array(value, ancestors, depth, visits)
		TYPE_DICTIONARY:
			return _walk_dictionary(value, ancestors, depth, visits)
		_:
			return ERR_INVALID_PARAMETER


static func _walk_array(value: Array, ancestors: Array, depth: int, visits: Array) -> Error:
	var next_depth := depth + 1
	if next_depth > MAX_DEPTH:
		return ERR_INVALID_PARAMETER
	if _is_ancestor(value, ancestors):
		return ERR_INVALID_PARAMETER
	ancestors.append(value)
	for item: Variant in value:
		var err := _walk(item, ancestors, next_depth, visits)
		if err != OK:
			ancestors.pop_back()
			return err
	ancestors.pop_back()
	return OK


static func _walk_dictionary(value: Dictionary, ancestors: Array, depth: int, visits: Array) -> Error:
	var next_depth := depth + 1
	if next_depth > MAX_DEPTH:
		return ERR_INVALID_PARAMETER
	if _is_ancestor(value, ancestors):
		return ERR_INVALID_PARAMETER
	ancestors.append(value)
	for key: Variant in value.keys():
		var key_type := typeof(key)
		if key_type != TYPE_STRING and key_type != TYPE_STRING_NAME:
			ancestors.pop_back()
			return ERR_INVALID_PARAMETER
		var err := _walk(value[key], ancestors, next_depth, visits)
		if err != OK:
			ancestors.pop_back()
			return err
	ancestors.pop_back()
	return OK


static func _is_ancestor(value: Variant, ancestors: Array) -> bool:
	for item: Variant in ancestors:
		if is_same(item, value):
			return true
	return false


static func _count_packed(value: Variant, visits: Array) -> Error:
	var extra := 0
	if value is PackedByteArray:
		extra = (value as PackedByteArray).size()
	elif value is PackedInt32Array:
		extra = (value as PackedInt32Array).size()
	elif value is PackedInt64Array:
		extra = (value as PackedInt64Array).size()
	elif value is PackedFloat32Array:
		extra = (value as PackedFloat32Array).size()
	elif value is PackedFloat64Array:
		extra = (value as PackedFloat64Array).size()
	elif value is PackedStringArray:
		extra = (value as PackedStringArray).size()
	elif value is PackedVector2Array:
		extra = (value as PackedVector2Array).size()
	elif value is PackedVector3Array:
		extra = (value as PackedVector3Array).size()
	elif value is PackedVector4Array:
		extra = (value as PackedVector4Array).size()
	elif value is PackedColorArray:
		extra = (value as PackedColorArray).size()
	visits[0] = int(visits[0]) + extra
	if int(visits[0]) > MAX_VISITS:
		return ERR_INVALID_PARAMETER
	return OK


static func _math_is_finite(value: Variant) -> bool:
	match typeof(value):
		TYPE_VECTOR2:
			var v2: Vector2 = value
			return v2.is_finite()
		TYPE_VECTOR2I:
			return true
		TYPE_VECTOR3:
			var v3: Vector3 = value
			return v3.is_finite()
		TYPE_VECTOR3I:
			return true
		TYPE_VECTOR4:
			var v4: Vector4 = value
			return v4.is_finite()
		TYPE_VECTOR4I:
			return true
		TYPE_RECT2:
			var r2: Rect2 = value
			return r2.position.is_finite() and r2.size.is_finite()
		TYPE_RECT2I:
			return true
		TYPE_TRANSFORM2D:
			var t2: Transform2D = value
			return t2.x.is_finite() and t2.y.is_finite() and t2.origin.is_finite()
		TYPE_TRANSFORM3D:
			var t3: Transform3D = value
			return t3.origin.is_finite() and t3.basis.x.is_finite() and t3.basis.y.is_finite() \
				and t3.basis.z.is_finite()
		TYPE_BASIS:
			var b: Basis = value
			return b.x.is_finite() and b.y.is_finite() and b.z.is_finite()
		TYPE_QUATERNION:
			var q: Quaternion = value
			return is_finite(q.x) and is_finite(q.y) and is_finite(q.z) and is_finite(q.w)
		TYPE_PLANE:
			var p: Plane = value
			return p.normal.is_finite() and is_finite(p.d)
		TYPE_AABB:
			var aabb: AABB = value
			return aabb.position.is_finite() and aabb.size.is_finite()
		TYPE_PROJECTION:
			var proj: Projection = value
			return proj[0].is_finite() and proj[1].is_finite() and proj[2].is_finite() \
				and proj[3].is_finite()
		TYPE_COLOR:
			var c: Color = value
			return is_finite(c.r) and is_finite(c.g) and is_finite(c.b) and is_finite(c.a)
		_:
			return false


static func _packed_is_finite(value: Variant) -> bool:
	match typeof(value):
		TYPE_PACKED_FLOAT32_ARRAY:
			for n: float in value as PackedFloat32Array:
				if not is_finite(n):
					return false
			return true
		TYPE_PACKED_FLOAT64_ARRAY:
			for n: float in value as PackedFloat64Array:
				if not is_finite(n):
					return false
			return true
		TYPE_PACKED_VECTOR2_ARRAY:
			for item: Vector2 in value as PackedVector2Array:
				if not item.is_finite():
					return false
			return true
		TYPE_PACKED_VECTOR3_ARRAY:
			for item: Vector3 in value as PackedVector3Array:
				if not item.is_finite():
					return false
			return true
		TYPE_PACKED_VECTOR4_ARRAY:
			for item: Vector4 in value as PackedVector4Array:
				if not item.is_finite():
					return false
			return true
		TYPE_PACKED_COLOR_ARRAY:
			for item: Color in value as PackedColorArray:
				if not (is_finite(item.r) and is_finite(item.g) and is_finite(item.b) \
						and is_finite(item.a)):
					return false
			return true
		_:
			return false


static func _clone(value: Variant) -> Variant:
	match typeof(value):
		TYPE_ARRAY:
			var out: Array = []
			for item: Variant in value:
				out.append(_clone(item))
			return out
		TYPE_DICTIONARY:
			var out: Dictionary = {}
			for key: Variant in value.keys():
				out[String(key)] = _clone(value[key])
			return out
		TYPE_PACKED_BYTE_ARRAY:
			return (value as PackedByteArray).duplicate()
		TYPE_PACKED_INT32_ARRAY:
			return (value as PackedInt32Array).duplicate()
		TYPE_PACKED_INT64_ARRAY:
			return (value as PackedInt64Array).duplicate()
		TYPE_PACKED_FLOAT32_ARRAY:
			return (value as PackedFloat32Array).duplicate()
		TYPE_PACKED_FLOAT64_ARRAY:
			return (value as PackedFloat64Array).duplicate()
		TYPE_PACKED_STRING_ARRAY:
			return (value as PackedStringArray).duplicate()
		TYPE_PACKED_VECTOR2_ARRAY:
			return (value as PackedVector2Array).duplicate()
		TYPE_PACKED_VECTOR3_ARRAY:
			return (value as PackedVector3Array).duplicate()
		TYPE_PACKED_VECTOR4_ARRAY:
			return (value as PackedVector4Array).duplicate()
		TYPE_PACKED_COLOR_ARRAY:
			return (value as PackedColorArray).duplicate()
		_:
			return value
