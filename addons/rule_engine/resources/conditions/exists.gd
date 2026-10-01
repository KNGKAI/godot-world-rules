@tool
class_name REExistsCondition
extends RECondition

enum Source { FACT, PAYLOAD, BLACKBOARD }

@export var source: Source = Source.FACT
@export var key: StringName


func evaluate(context: REMatchContext) -> REConditionResult:
	var lookup := context.lookup(source, key)
	return REConditionResult.new(lookup.present, true)

