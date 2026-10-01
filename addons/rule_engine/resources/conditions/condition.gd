@tool
class_name RECondition
extends Resource


func evaluate(_context: REMatchContext) -> REConditionResult:
	return REConditionResult.new(false, false)

