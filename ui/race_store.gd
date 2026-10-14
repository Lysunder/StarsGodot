class_name RaceStore
extends RefCounted
## The player's own races (the race wizard's results), as race files in `user://races` (S06 "Race
## files and presets"): one file a race, named after it.

const DIR := "user://races"


## The races saved there that load for the running game's content, by file name.
static func races(content: ContentRegistry) -> Array[Race]:
	var out: Array[Race] = []
	var names := (
		DirAccess.get_files_at(DIR) if DirAccess.dir_exists_absolute(DIR) else PackedStringArray()
	)
	var sorted := Array(names)
	sorted.sort()
	for file: String in sorted:
		if file.get_extension() != RaceFile.EXTENSION:
			continue
		var result := RaceFile.read(DIR.path_join(file), content)
		if result.ok():
			out.append(result.race)
	return out


## Saves the race under its name (replacing a race of the same name); returns the path, or "" on
## failure.
static func save(race: Race, game_version: String) -> String:
	DirAccess.make_dir_recursive_absolute(DIR)
	var base := race.name.validate_filename().strip_edges()
	if base == "":
		base = "race"
	var path := DIR.path_join("%s.%s" % [base, RaceFile.EXTENSION])
	return path if RaceFile.write(path, race, game_version) == OK else ""
