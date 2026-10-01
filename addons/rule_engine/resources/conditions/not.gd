@tool
class_name RENotCondition
extends RECondition

@export var condition: RECondition


func evaluate(context: REMatchContext) -> REConditionResult:
	if condition == null:
		return REConditionResult.new(false, false)
	var result := condition.evaluate(context)
	if not result.valid:
		return REConditionResult.new(false, false)
	return REConditionResult.new(not result.matched, true)

