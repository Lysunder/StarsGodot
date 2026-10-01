class_name FolderModSource
extends ModSource
## A mod in a folder (res://content/<id>, user://mods/<id>, or res://tests/... for test mods).

const TEST_ROOT := "res://tests/"

var _root: String


func _init(p_root: String) -> void:
	_root = p_root.trim_suffix("/")


## One source per sub-folder of `dir` that contains a mod.json, sorted by folder name.
static func discover(dir: String) -> Array[ModSource]:
	var result: Array[ModSource] = []
	var access := DirAccess.open(dir)
	if access == null:
		return result
	var names := access.get_directories()
	names.sort()
	for folder_name in names:
		var root := dir.trim_suffix("/") + "/" + folder_name
		if FileAccess.file_exists(root + "/mod.json"):
			result.append(FolderModSource.new(root))
	return result


func root() -> String:
	return _root


func is_test_mod() -> bool:
	return _root.begins_with(TEST_ROOT)


func has_file(path: String) -> bool:
	return FileAccess.file_exists(_root + "/" + path)


func read_text(path: String) -> String:
	return FileAccess.get_file_as_string(_root + "/" + path)


func list_files(dir: String, extension: String) -> PackedStringArray:
	var result: PackedStringArray = []
	_collect(dir.trim_suffix("/"), extension, result)
	result.sort()
	return result


func _collect(rel_dir: String, extension: String, out: PackedStringArray) -> void:
	var access := DirAccess.open(_root + "/" + rel_dir)
	if access == null:
		return
	for sub in access.get_directories():
		_collect(rel_dir + "/" + sub, extension, out)
	for file in access.get_files():
		if file.get_extension() == extension:
			out.append(rel_dir + "/" + file)
