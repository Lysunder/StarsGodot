extends SceneTree
## Compares two save files field by field (StateDiff) and prints the differences.
##
## Usage: godot --headless --path . --script res://tools/diff_saves.gd -- A.json B.json
##        [--ignore=PATTERN ...] [--limit=N]
## Exit code 0 when the states are equal (after ignores), 1 when they differ, 2 on errors.


func _init() -> void:
	var files := PackedStringArray()
	var ignore := PackedStringArray()
	var limit := 200
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--ignore="):
			ignore.append(arg.trim_prefix("--ignore="))
		elif arg.begins_with("--limit="):
			limit = arg.trim_prefix("--limit=").to_int()
		else:
			files.append(arg)
	if files.size() != 2:
		printerr("usage: -- A.json B.json [--ignore=PATTERN ...] [--limit=N]")
		quit(2)
		return
	var states := []
	for path in files:
		var parsed := JsonReader.parse(FileAccess.get_file_as_string(path))
		if not parsed.ok or not parsed.value is Dictionary or not parsed.value.has("state"):
			printerr("%s: not a save file" % path)
			quit(2)
			return
		states.append(parsed.value["state"])
	var diffs := StateDiff.compare_dicts(states[0], states[1], ignore)
	if diffs.is_empty():
		print("equal")
		quit(0)
		return
	print(StateDiff.format(diffs, limit))
	print("%d differences" % diffs.size())
	quit(1)
