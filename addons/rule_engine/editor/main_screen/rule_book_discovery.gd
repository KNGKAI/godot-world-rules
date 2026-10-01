@tool
extends RefCounted

signal changed

var _filesystem: Variant
var _resource_loader: Callable
var _groups: Array[Dictionary] = []


func _init(filesystem: Variant, resource_loader: Callable = Callable()) -> void:
	_filesystem = filesystem
	_resource_loader = resource_loader


func start() -> void:
	if _filesystem != null:
		var filesystem_changed: Signal = _filesystem.filesystem_changed
		if not filesystem_changed.is_connected(_on_filesystem_changed):
			filesystem_changed.connect(_on_filesystem_changed)
	refresh()


func stop() -> void:
	if _filesystem == null:
		return
	var filesystem_changed: Signal = _filesystem.filesystem_changed
	if filesystem_changed.is_connected(_on_filesystem_changed):
		filesystem_changed.disconnect(_on_filesystem_changed)


func refresh() -> void:
	var entries: Array[Dictionary] = []
	if _filesystem != null:
		_scan_directory(_filesystem.get_filesystem(), entries)
	entries.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return left.path < right.path
	)
	_groups = _group_entries(entries)
	changed.emit()


func get_groups() -> Array[Dictionary]:
	return _groups.duplicate(true)


func get_books() -> Array[RERuleBook]:
	var books: Array[RERuleBook] = []
	for group: Dictionary in _groups:
		for entry: Dictionary in group.books:
			books.append(entry.book)
	return books


func _on_filesystem_changed() -> void:
	refresh()


func _scan_directory(directory: Variant, entries: Array[Dictionary]) -> void:
	if directory == null:
		return
	for file_index: int in directory.get_file_count():
		var path: String = directory.get_file_path(file_index)
		if (
			not _is_rule_book_type(directory.get_file_type(file_index))
			or path.get_extension().to_lower() not in ["tres", "res"]
		):
			continue
		var loaded: Resource = (
			_resource_loader.call(path) as Resource
			if _resource_loader.is_valid()
			else ResourceLoader.load(path) as Resource
		)
		if loaded is RERuleBook:
			entries.append({&"path": path, &"book": loaded})
	for directory_index: int in directory.get_subdir_count():
		_scan_directory(directory.get_subdir(directory_index), entries)


func _is_rule_book_type(file_type: String) -> bool:
	return file_type == "RERuleBook" or file_type.ends_with("/RERuleBook")


func _group_entries(entries: Array[Dictionary]) -> Array[Dictionary]:
	var by_directory: Dictionary = {}
	for entry: Dictionary in entries:
		var directory: String = entry.path.get_base_dir()
		if not by_directory.has(directory):
			by_directory[directory] = []
		by_directory[directory].append(entry)
	var directories: Array = by_directory.keys()
	directories.sort()
	var groups: Array[Dictionary] = []
	for directory: String in directories:
		groups.append({&"directory": directory, &"books": by_directory[directory]})
	return groups
