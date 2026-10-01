@tool
class_name RECompareCondition
extends RECondition

enum Source { FACT, PAYLOAD, BLACKBOARD }
enum Operator { EQUAL, NOT_EQUAL, GREATER, GREATER_EQUAL, LESS, LESS_EQUAL, CONTAINS, NOT_CONTAINS }

@export var source: Source = Source.FACT
@export var key: StringName
@export var operator: Operator = Operator.EQUAL
@export var value: Variant


func evaluate(context: REMatchContext) -> REConditionResult:
	var lookup := context.lookup(source, key)
	if not lookup.present:
		return REConditionResult.new(false, false)
	var comparison := compare_values(lookup.value, value, operator)
	if not comparison.valid:
		push_warning("Rule comparison uses incompatible operands for key '%s'." % key)
	return REConditionResult.new(comparison.matched, comparison.valid)


static func compare_values(left: Variant, right: Variant, p_operator: int) -> Dictionary:
	if p_operator == Operator.EQUAL or p_operator == Operator.NOT_EQUAL:
		var equality := _equal_values(left, right)
		if not equality.valid:
			return equality
		return {
			&"valid": true,
			&"matched": equality.matched if p_operator == Operator.EQUAL else not equality.matched,
		}
	if p_operator == Operator.CONTAINS or p_operator == Operator.NOT_CONTAINS:
		var containment := _contains_values(left, right)
		if not containment.valid:
			return containment
		return {
			&"valid": true,
			&"matched": containment.matched if p_operator == Operator.CONTAINS else not containment.matched,
		}
	if not _ordered_pair_is_valid(left, right):
		return {&"valid": false, &"matched": false}
	var comparison := _ordered_compare(left, right)
	match p_operator:
		Operator.GREATER:
			return {&"valid": true, &"matched": comparison > 0}
		Operator.GREATER_EQUAL:
			return {&"valid": true, &"matched": comparison >= 0}
		Operator.LESS:
			return {&"valid": true, &"matched": comparison < 0}
		Operator.LESS_EQUAL:
			return {&"valid": true, &"matched": comparison <= 0}
		_:
			return {&"valid": false, &"matched": false}


static func _equal_values(left: Variant, right: Variant) -> Dictionary:
	if typeof(left) == TYPE_INT and typeof(right) == TYPE_INT:
		return {&"valid": true, &"matched": left == right}
	if _is_number(left) and _is_number(right):
		return {&"valid": true, &"matched": float(left) == float(right)}
	if _is_text(left) and _is_text(right):
		return {&"valid": true, &"matched": str(left) == str(right)}
	if typeof(left) == typeof(right):
		return {&"valid": true, &"matched": left == right}
	return {&"valid": false, &"matched": false}


static func _contains_values(left: Variant, right: Variant) -> Dictionary:
	if _is_text(left):
		if not _is_text(right):
			return {&"valid": false, &"matched": false}
		return {&"valid": true, &"matched": str(left).contains(str(right))}
	if _is_membership_container(left):
		return {&"valid": true, &"matched": right in left}
	return {&"valid": false, &"matched": false}


static func _is_membership_container(input: Variant) -> bool:
	return typeof(input) in [
		TYPE_ARRAY,
		TYPE_DICTIONARY,
		TYPE_PACKED_BYTE_ARRAY,
		TYPE_PACKED_INT32_ARRAY,
		TYPE_PACKED_INT64_ARRAY,
		TYPE_PACKED_FLOAT32_ARRAY,
		TYPE_PACKED_FLOAT64_ARRAY,
		TYPE_PACKED_STRING_ARRAY,
		TYPE_PACKED_VECTOR2_ARRAY,
		TYPE_PACKED_VECTOR3_ARRAY,
		TYPE_PACKED_VECTOR4_ARRAY,
		TYPE_PACKED_COLOR_ARRAY,
	]


static func _ordered_pair_is_valid(left: Variant, right: Variant) -> bool:
	if _is_number(left) and _is_number(right):
		return true
	return typeof(left) == typeof(right) and _is_text(left)


static func _ordered_compare(left: Variant, right: Variant) -> int:
	if typeof(left) == TYPE_INT and typeof(right) == TYPE_INT:
		return -1 if left < right else (1 if left > right else 0)
	if _is_number(left):
		var left_number := float(left)
		var right_number := float(right)
		return -1 if left_number < right_number else (1 if left_number > right_number else 0)
	var left_text := str(left)
	var right_text := str(right)
	return -1 if left_text < right_text else (1 if left_text > right_text else 0)


static func _is_number(input: Variant) -> bool:
	return typeof(input) == TYPE_INT or typeof(input) == TYPE_FLOAT


static func _is_text(input: Variant) -> bool:
	return typeof(input) == TYPE_STRING or typeof(input) == TYPE_STRING_NAME
