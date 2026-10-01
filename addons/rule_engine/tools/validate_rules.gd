extends SceneTree

const VALIDATOR_PATH := "res://addons/rule_engine/editor/validation/validator.gd"


func _init() -> void:
	var options := _parse_options(OS.get_cmdline_user_args())
	if options.books.is_empty():
		printerr("ERROR [missing_argument] Supply at least one --book=res://path.tres argument.")
		quit(2)
		return
	var books: Array = []
	var load_failed := false
	for path: String in options.books:
		var resource := ResourceLoader.load(path, "RERuleBook")
		if resource is not RERuleBook:
			printerr("ERROR [invalid_book] %s is not a loadable RERuleBook." % path)
			load_failed = true
		else:
			books.append(resource)
	var event_catalog := _load_catalog(options.event_catalog)
	var fact_catalog := _load_catalog(options.fact_catalog)
	if (not options.event_catalog.is_empty() and event_catalog == null) or (
		not options.fact_catalog.is_empty() and fact_catalog == null
	):
		load_failed = true
	var issues: Array = load(VALIDATOR_PATH).new().validate_books(
		books,
		event_catalog,
		fact_catalog,
	)
	var has_errors := load_failed
	for issue: Variant in issues:
		print(str(issue))
		if issue.severity == 0:
			has_errors = true
	print(
		"Validated %d rule book(s): %d issue(s), %s."
		% [books.size(), issues.size(), "FAILED" if has_errors else "OK"]
	)
	quit(1 if has_errors else 0)


func _parse_options(arguments: PackedStringArray) -> Dictionary:
	var result := {
		&"books": PackedStringArray(),
		&"event_catalog": "",
		&"fact_catalog": "",
	}
	for argument: String in arguments:
		if argument.begins_with("--book="):
			result.books.append(argument.trim_prefix("--book="))
		elif argument.begins_with("--event-catalog="):
			result.event_catalog = argument.trim_prefix("--event-catalog=")
		elif argument.begins_with("--fact-catalog="):
			result.fact_catalog = argument.trim_prefix("--fact-catalog=")
	return result


func _load_catalog(path: String) -> RENameCatalog:
	if path.is_empty():
		return null
	var resource := ResourceLoader.load(path, "RENameCatalog")
	if resource is RENameCatalog:
		return resource
	printerr("ERROR [invalid_catalog] %s is not a loadable RENameCatalog." % path)
	return null
