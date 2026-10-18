class_name PersonalityStore
extends RefCounted
## The player's own computer player personalities (the personality editor's, S22 "The
## personality editor"), as personality files in `user://personalities`: one file a personality,
## named after it.

const DIR := "user://personalities"

## The folder used (tests point it elsewhere).
static var dir := DIR


## The personalities saved there that load, by file name.
static func personalities() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not DirAccess.dir_exists_absolute(dir):
		return out
	var sorted := Array(DirAccess.get_files_at(dir))
	sorted.sort()
	for file: String in sorted:
		if file.get_extension() != PersonalityFile.EXTENSION:
			continue
		var result := PersonalityFile.read(dir.path_join(file))
		if result.ok():
			out.append(result.personality)
	return out


static func path_for(name: String) -> String:
	var base := name.validate_filename().strip_edges()
	if base == "":
		base = "personality"
	return dir.path_join("%s.%s" % [base, PersonalityFile.EXTENSION])


## Saves the personality under its name (replacing one of the same name); returns the path, or ""
## on failure.
static func save(p: Dictionary) -> String:
	DirAccess.make_dir_recursive_absolute(dir)
	var path := path_for(str(p["name"]))
	return path if PersonalityFile.write(path, p) == OK else ""


static func delete(name: String) -> void:
	var path := path_for(name)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
