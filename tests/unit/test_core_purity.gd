extends GdUnitTestSuite
## Enforces the core/ rules from CONTRIBUTING.md: no scene types, no globals, and no randomness,
## clock or OS access outside the engine's own streams. A plain text scan; comments are ignored.

const CORE_DIR := "res://core"

## [regex, message, folders exempt from the rule]
const RULES: Array = [
	[
		(
			"^\\s*extends\\s+"
			+ "(Node|Node2D|Node3D|Control|CanvasItem|CanvasLayer|Window|Viewport|SceneTree)\\b"
		),
		"core/ scripts must not be scene types",
		[],
	],
	["\\bget_tree\\s*\\(", "core/ must not use the SceneTree", []],
	["\\bstatic\\s+var\\b", "core/ must not keep static (global) state", []],
	[
		"\\b(randi|randf|randi_range|randf_range|randfn|randomize|seed)\\s*\\(",
		"use the engine's RNG streams",
		[]
	],
	["\\bRandomNumberGenerator\\b", "use the engine's RNG streams", []],
	[
		"\\b(Time|OS|Engine|Performance)\\s*\\.",
		"core/ must not read clocks, OS or engine state",
		[]
	],
	["\\b(FileAccess|DirAccess)\\b", "only core/io may touch files", ["res://core/io/"]],
]


func test_core_scripts_follow_rules() -> void:
	var problems: PackedStringArray = []
	for path in _list_scripts(CORE_DIR):
		problems.append_array(violations(FileAccess.get_file_as_string(path), path))
	assert_array(Array(problems)).is_empty()


func test_scanner_catches_violations() -> void:
	var src := "extends Node\n\nfunc f() -> int:\n\treturn randi()  # bad\n"
	assert_int(violations(src, "res://core/x.gd").size()).is_equal(2)


func test_scanner_ignores_comments_and_exempt_folders() -> void:
	var src := "extends RefCounted\n## Time.get_ticks_msec() is banned\nvar f := FileAccess\n"
	assert_int(violations(src, "res://core/io/save.gd").size()).is_equal(0)
	assert_int(violations(src, "res://core/model/x.gd").size()).is_equal(1)


static func violations(source: String, path: String) -> PackedStringArray:
	var found: PackedStringArray = []
	var lines := source.split("\n")
	for rule: Array in RULES:
		var re := RegEx.create_from_string(rule[0])
		if _is_exempt(path, rule[2]):
			continue
		for i in lines.size():
			if re.search(_strip_comment(lines[i])) != null:
				found.append("%s:%d: %s" % [path, i + 1, rule[1]])
	return found


static func _is_exempt(path: String, exempt_dirs: Array) -> bool:
	for dir: String in exempt_dirs:
		if path.begins_with(dir):
			return true
	return false


static func _strip_comment(line: String) -> String:
	var hash_pos := line.find("#")
	return line if hash_pos < 0 else line.substr(0, hash_pos)


static func _list_scripts(dir_path: String) -> PackedStringArray:
	var result: PackedStringArray = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return result
	var subdirs := dir.get_directories()
	subdirs.sort()
	for sub in subdirs:
		result.append_array(_list_scripts(dir_path.path_join(sub)))
	var files := dir.get_files()
	files.sort()
	for file in files:
		if file.get_extension() == "gd":
			result.append(dir_path.path_join(file))
	return result
