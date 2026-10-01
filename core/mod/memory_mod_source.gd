class_name MemoryModSource
extends ModSource
## A mod held in memory: mod-relative path -> file text. Used by tests.

var files: Dictionary = {}
var _root: String
var _test_mod: bool


func _init(p_root: String, p_files: Dictionary = {}, p_test_mod: bool = false) -> void:
	_root = p_root
	files = p_files
	_test_mod = p_test_mod


func root() -> String:
	return _root


func is_test_mod() -> bool:
	return _test_mod


func has_file(path: String) -> bool:
	return files.has(path)


func read_text(path: String) -> String:
	return files.get(path, "")


func list_files(dir: String, extension: String) -> PackedStringArray:
	var prefix := dir.trim_suffix("/") + "/"
	var result: PackedStringArray = []
	for path: String in files:
		if path.begins_with(prefix) and path.get_extension() == extension:
			result.append(path)
	result.sort()
	return result
