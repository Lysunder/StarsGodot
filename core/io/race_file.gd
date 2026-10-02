class_name RaceFile
extends RefCounted
## Our race file format (spec S06, "Race files and presets"): a JSON object with a header and one
## race, in canonical form. Only valid wizard races load.

const FORMAT := "starsgodot-race"
const FORMAT_VERSION := 1
const EXTENSION := "race"
const _HEADER_KEYS := ["format", "format_version", "game_version", "race"]


class LoadResult:
	extends RefCounted
	var race: Race = null
	var errors: PackedStringArray = []
	## The game version that wrote the file.
	var game_version: String = ""

	func ok() -> bool:
		return errors.is_empty() and race != null


static func encode(race: Race, game_version: String) -> String:
	var data := {
		"format": FORMAT,
		"format_version": FORMAT_VERSION,
		"game_version": game_version,
		"race": race.to_dict(),
	}
	return ContentRegistry.canonical(data) + "\n"


## Parses a race file and checks it against the running game's content. Every problem is reported.
static func decode(text: String, content: ContentRegistry) -> LoadResult:
	var result := LoadResult.new()
	var parsed := JsonReader.parse(text)
	if not parsed.ok:
		result.errors.append("line %d: %s" % [parsed.error_line, parsed.error])
		return result
	var data: Variant = parsed.value
	if not _check_header(data, result):
		return result
	var errors := PackedStringArray()
	var race := ModelObject.object_from(Race, data["race"], "/race", errors) as Race
	if not errors.is_empty():
		result.errors = errors
		return result
	for e in RaceMath.wizard_problems(race, content):
		result.errors.append(("/race" + e) if e.begins_with("/") else e)
	if result.errors.is_empty():
		result.race = race
	return result


## Writes a race file (temporary file first, then replace).
static func write(path: String, race: Race, game_version: String) -> Error:
	return SaveStore.write_text(path, encode(race, game_version))


static func read(path: String, content: ContentRegistry) -> LoadResult:
	if not FileAccess.file_exists(path):
		var missing := LoadResult.new()
		missing.errors.append("%s: no such file" % path)
		return missing
	var result := decode(FileAccess.get_file_as_string(path), content)
	var prefixed := PackedStringArray()
	for e in result.errors:
		prefixed.append("%s: %s" % [path, e])
	result.errors = prefixed
	return result


static func _check_header(data: Variant, result: LoadResult) -> bool:
	if not data is Dictionary or data.get("format") != FORMAT:
		result.errors.append("not a %s file" % FORMAT)
		return false
	for key: String in _HEADER_KEYS:
		if not data.has(key):
			result.errors.append("/%s: missing" % key)
	for key: Variant in data:
		if not _HEADER_KEYS.has(key):
			result.errors.append("/%s: unknown field" % key)
	if not result.errors.is_empty():
		return false
	var version: Variant = data["format_version"]
	if not version is int or version < 1:
		result.errors.append("/format_version: must be a positive integer")
	elif version > FORMAT_VERSION:
		result.errors.append(
			"/format_version: %d is newer than this game reads (%d)" % [version, FORMAT_VERSION]
		)
	# Older versions would be converted here, one version step at a time.
	if not data["game_version"] is String:
		result.errors.append("/game_version: must be a string")
	else:
		result.game_version = data["game_version"]
	return result.errors.is_empty()
