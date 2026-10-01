extends SceneTree
## Loads save files with the core content and reports every problem (SaveFile + StateValidator).
## Used to check files written by the harness importer (tools/harness/stars_import.py).
##
## Usage: godot --headless --path . --script res://tools/check_save.gd -- FILE.json [...]
## Exit code 0 when every file loads cleanly.


func _init() -> void:
	var loaded := ModLoader.new().load_mods(FolderModSource.discover("res://content"), [])
	if not loaded.ok():
		printerr(loaded.error_text())
		quit(2)
		return
	var failed := 0
	for path in OS.get_cmdline_user_args():
		var result := SaveFile.decode(FileAccess.get_file_as_string(path), loaded.registry)
		if result.ok():
			print(
				(
					"%s: ok (turn %d, %d planets, %d fleets, hash %s)"
					% [
						path,
						result.state.turn,
						result.state.planets.size(),
						result.state.fleets.size(),
						result.state.state_hash().substr(0, 12),
					]
				)
			)
		else:
			failed += 1
			print("%s: %d problems" % [path, result.errors.size()])
			for e in result.errors.slice(0, 40):
				print("  " + e)
	quit(1 if failed > 0 else 0)
