class_name ModSource
extends RefCounted
## Read access to one mod's files. The ModLoader reads mods only through this interface, so core/
## code never touches the file system directly: FolderModSource (core/io) reads real folders, and
## MemoryModSource holds files in memory for tests.
##
## Paths are relative to the mod root and use forward slashes ("content/parts/beams.json").


## Where the mod lives, for messages (for example "res://content/core").
func root() -> String:
	return ""


## True for mods under res://tests/. The ModLoader refuses them outside test runs.
func is_test_mod() -> bool:
	return false


func has_file(_path: String) -> bool:
	return false


func read_text(_path: String) -> String:
	return ""


## Files under `dir` (recursively) with the given extension, as mod-relative paths, sorted.
func list_files(_dir: String, _extension: String) -> PackedStringArray:
	return PackedStringArray()
