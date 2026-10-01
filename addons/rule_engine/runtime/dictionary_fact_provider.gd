class_name REDictionaryFactProvider
extends REFactProvider

var facts: Dictionary


func _init(p_facts: Dictionary = {}) -> void:
	facts = p_facts


func has_fact(key: StringName) -> bool:
	return facts.has(key)


func get_fact(key: StringName) -> Variant:
	return facts.get(key)

