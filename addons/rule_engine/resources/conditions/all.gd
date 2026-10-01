@tool
class_name REAllCondition
extends RECondition

@export var conditions: Array[RECondition] = []


func evaluate(context: REMatchContext) -> REConditionResult:
	for condition: RECondition in conditions:
		if condition == null:
			return REConditionResult.new(false, false)
		var result := condition.evaluate(context)
		if not result.valid:
			return REConditionResult.new(false, false)
		if not result.matched:
			return REConditionResult.new(false, true)
	return REConditionResult.new(true, true)

