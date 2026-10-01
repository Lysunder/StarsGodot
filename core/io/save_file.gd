class_name SaveFile
extends RefCounted
## Our save format (spec S03, "Saved form"): a JSON object with a header and the game state.
##
## encode() and decode() work on text; SaveStore reads and writes the files. The text is the
## canonical form (keys sorted, no whitespace), so the same state always gives the same bytes.
##
## A save made with different content (ruleset hash or gameplay mod list) still loads, but
## needs_confirmation() is true: the player must agree before playing it, and a PBEM host must
## refuse it.

const FORMAT := "starsgodot-save"
const FORMAT_VERSION := 1
const _HEADER_KEYS := ["format", "format_version", "game_version", "ruleset_hash", "mods", "state"]


class LoadResult:
	extends RefCounted
	var state: GameState = null
	var errors: PackedStringArray = []
	## The game version that wrote the file.
	var game_version: String = ""
	## True when the file was made with different gameplay content than the running game.
	var content_mismatch: bool = false
	## The gameplay mods recorded in the file, "id@version".
	var saved_mods: PackedStringArray = []

	func ok() -> bool:
		return errors.is_empty() and state != null

	func needs_confirmation() -> bool:
		return content_mismatch


## Records the content a game is played with (call when a game is created).
static func stamp(state: GameState, content: ContentRegistry) -> void:
	state.settings.ruleset_hash = content.ruleset_hash
	var mods := []
	for entry in content.gameplay_mods():
		var at := entry.rfind("@")
		mods.append({"id": entry.substr(0, at), "version": entry.substr(at + 1)})
	state.settings.mods = mods


static func encode(state: GameState, game_version: String) -> String:
	var data := {
		"format": FORMAT,
		"format_version": FORMAT_VERSION,
		"game_version": game_version,
		"ruleset_hash": state.settings.ruleset_hash,
		"mods": state.settings.mods.duplicate(true),
		"state": state.to_dict(),
	}
	return ContentRegistry.canonical(data) + "\n"


## Parses and checks a save against the running game's content. Every problem is reported.
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
	var state := ModelObject.object_from(GameState, data["state"], "/state", errors) as GameState
	if not errors.is_empty():
		result.errors = errors
		return result
	if state.settings.ruleset_hash != data["ruleset_hash"]:
		result.errors.append("/ruleset_hash: does not match /state/settings/ruleset_hash")
	if ContentRegistry.canonical(state.settings.mods) != ContentRegistry.canonical(data["mods"]):
		result.errors.append("/mods: does not match /state/settings/mods")
	for e in StateValidator.validate(state, content):
		result.errors.append("/state" + e)
	result.saved_mods = _mod_names(state.settings.mods)
	result.content_mismatch = (
		state.settings.ruleset_hash != content.ruleset_hash
		or result.saved_mods != content.gameplay_mods()
	)
	if result.errors.is_empty():
		result.state = state
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
	if not data["ruleset_hash"] is String:
		result.errors.append("/ruleset_hash: must be a string")
	if not data["mods"] is Array:
		result.errors.append("/mods: must be a list")
	return result.errors.is_empty()


static func _mod_names(mods: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for m: Variant in mods:
		if m is Dictionary:
			out.append("%s@%s" % [m.get("id", ""), m.get("version", "")])
	return out
