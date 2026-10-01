@tool
class_name REAnyCondition
extends RECondition

@export var conditions: Array[RECondition] = []


func evaluate(context: REMatchContext) -> REConditionResult:
	var saw_invalid := false
	for condition: RECondition in conditions:
		if condition == null:
			saw_invalid = true
			continue
		var result := condition.evaluate(context)
		if result.valid and result.matched:
			return REConditionResult.new(true, true)
		if not result.valid:
			saw_invalid = true
	return REConditionResult.new(false, not saw_invalid)

