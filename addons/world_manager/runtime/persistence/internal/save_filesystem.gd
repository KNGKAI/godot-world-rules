class_name WorldSaveFilesystem
extends RefCounted
## The only filesystem surface the slot store needs. Takes base names, never
## paths, and joins its own root, so an escape from the save directory is
## structurally impossible rather than merely unlikely. Does not log.


const DEFAULT_ROOT := "user://saves"

var _root: String = DEFAULT_ROOT


func get_root() -> String:
	return _root


func ensure_root() -> Error:
	if DirAccess.dir_exists_absolute(_root):
		return OK
	return DirAccess.make_dir_recursive_absolute(_root)


func exists(file_name: String) -> bool:
	if not _is_safe_name(file_name):
		return false
	return FileAccess.file_exists(_path(file_name))


## -1 when absent or unreadable, so the store can apply its size cap before
## committing to a read.
func size_of(file_name: String) -> int:
	if not exists(file_name):
		return -1
	var file := FileAccess.open(_path(file_name), FileAccess.READ)
	if file == null:
		return -1
	var length := file.get_length()
	file.close()
	return length


func list_names() -> PackedStringArray:
	if not DirAccess.dir_exists_absolute(_root):
		return PackedStringArray()
	var names := DirAccess.get_files_at(_root)
	names.sort()
	return names


func read(file_name: String) -> Dictionary:
	if not _is_safe_name(file_name):
		return {"error": ERR_INVALID_PARAMETER, "bytes": PackedByteArray()}
	if not FileAccess.file_exists(_path(file_name)):
		return {"error": ERR_FILE_NOT_FOUND, "bytes": PackedByteArray()}
	var file := FileAccess.open(_path(file_name), FileAccess.READ)
	if file == null:
		return {"error": FileAccess.get_open_error(), "bytes": PackedByteArray()}
	var bytes := file.get_buffer(file.get_length())
	var err := file.get_error()
	file.close()
	if err != OK and err != ERR_FILE_EOF:
		return {"error": err, "bytes": PackedByteArray()}
	return {"error": OK, "bytes": bytes}


## store_buffer's return value, the error after flush, and the store's later
## read-back are three separate checks because none of them alone catches a
## short write: disk-full and permission-denied share one Error code.
func write(file_name: String, bytes: PackedByteArray) -> Error:
	if not _is_safe_name(file_name):
		return ERR_INVALID_PARAMETER
	var file := FileAccess.open(_path(file_name), FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	if not file.store_buffer(bytes):
		file.close()
		return ERR_FILE_CANT_WRITE
	file.flush()
	var err := file.get_error()
	file.close()
	if err != OK:
		return err
	return OK


func remove(file_name: String) -> Error:
	if not _is_safe_name(file_name):
		return ERR_INVALID_PARAMETER
	if not FileAccess.file_exists(_path(file_name)):
		return OK
	return DirAccess.remove_absolute(_path(file_name))


## The store only ever renames onto a name it has already verified is free, so
## the Windows delete-then-move branch never fires. See README D7.
func rename(from_name: String, to_name: String) -> Error:
	if not _is_safe_name(from_name) or not _is_safe_name(to_name):
		return ERR_INVALID_PARAMETER
	if not FileAccess.file_exists(_path(from_name)):
		return ERR_FILE_NOT_FOUND
	return DirAccess.rename_absolute(_path(from_name), _path(to_name))


## Private test seam. Production always uses DEFAULT_ROOT; nothing in runtime/
## calls this, and it refuses any root outside user://.
func _configure_root(root: String) -> Error:
	if not root.begins_with("user://"):
		return ERR_INVALID_PARAMETER
	if root.contains("..") or root.contains("\\"):
		return ERR_INVALID_PARAMETER
	_root = root.trim_suffix("/")
	return OK


func _path(file_name: String) -> String:
	return "%s/%s" % [_root, file_name]


static func _is_safe_name(file_name: String) -> bool:
	if file_name.is_empty():
		return false
	if file_name.contains("/") or file_name.contains("\\") or file_name.contains(":"):
		return false
	if file_name.contains(".."):
		return false
	return true
