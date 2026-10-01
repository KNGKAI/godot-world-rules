@tool
extends RefCounted


func filter(groups: Array, query: String) -> Array[Dictionary]:
	var normalized_query := query.strip_edges().to_lower()
	var filtered: Array[Dictionary] = []
	for group: Dictionary in groups:
		var filtered_books: Array[Dictionary] = []
		for entry: Dictionary in group.get(&"books", []):
			var book: RERuleBook = entry.get(&"book") as RERuleBook
			if book == null:
				continue
			var rules: Array[RERule] = []
			for rule: RERule in book.rules:
				if rule != null and _matches(rule, normalized_query):
					rules.append(rule)
			if rules.is_empty() and not normalized_query.is_empty():
				continue
			var filtered_entry := entry.duplicate()
			filtered_entry[&"rules"] = rules
			filtered_books.append(filtered_entry)
		if not filtered_books.is_empty():
			filtered.append({
				&"directory": group.get(&"directory", ""),
				&"books": filtered_books,
			})
	return filtered


func _matches(rule: RERule, query: String) -> bool:
	if query.is_empty():
		return true
	if String(rule.id).to_lower().contains(query) or String(rule.event).to_lower().contains(query):
		return true
	for tag: String in rule.tags:
		if tag.to_lower().contains(query):
			return true
	return false
