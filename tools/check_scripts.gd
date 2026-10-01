extends SceneTree
## Compiles every project script (outside addons/) and fails if any has a parse or compile error.
## Tests only load the scripts they use; this catches errors in scripts nothing tests yet.
##
## Usage: godot --headless --path . -s res://tools/check_scripts.gd

const ROOTS: PackedStringArray = [
	"res://core", "res://content", "res://ui", "res://tests", "res://tools"
]


func _initialize() -> void:
	var checked := 0
	var failed: PackedStringArray = []
	for root in ROOTS:
		for path in _list_scripts(root):
			checked += 1
			var script := load(path) as GDScript
			if script == null or not script.can_instantiate():
				failed.append(path)
	for path in failed:
		printerr("Script error: ", path)
	print("check_scripts: %d scripts, %d with errors" % [checked, failed.size()])
	quit(1 if failed.size() > 0 else 0)


func _list_scripts(dir_path: String) -> PackedStringArray:
	var result: PackedStringArray = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return result
	for sub in dir.get_directories():
		result.append_array(_list_scripts(dir_path.path_join(sub)))
	for file in dir.get_files():
		if file.get_extension() == "gd":
			result.append(dir_path.path_join(file))
	return result
