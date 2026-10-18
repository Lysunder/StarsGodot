class_name PersonalityFile
extends RefCounted
## A computer player's personality as the player keeps it (spec S22 "The personality editor"):
## a name, the brain that plays it, the brain's settings, and per difficulty level the settings
## that level changes, in the same shape a game keeps (`Player.ai_personality`). Files are JSON:
## {format, format_version, name, brain, params, levels}.

const FORMAT := "stars_personality"
const FORMAT_VERSION := 1
const EXTENSION := "json"
const NAME_MAX := 32


class Result:
	extends RefCounted
	var personality: Dictionary = {}
	var errors := PackedStringArray()

	func ok() -> bool:
		return errors.is_empty()


## A new personality for `brain` with no settings of its own (every setting at its default) and
## one empty map per difficulty level.
static func make(name: String, brain: String) -> Dictionary:
	var levels: Array = []
	for i in ComputerPlayers.LEVELS.size():
		levels.append({})
	return {"name": name, "brain": brain, "params": {}, "levels": levels}


## The content personality `id` as a personality of the player's (its display name, a deep copy
## of its settings, a map for every level).
static func from_content(content: ContentRegistry, id: String) -> Dictionary:
	var def := content.get_def(ComputerPlayers.PERSONALITY, id)
	var out := make(content.display_name(id), str(def.get("brain", "")))
	out["params"] = (def.get("params", {}) as Dictionary).duplicate(true)
	var levels: Array = def.get("levels", [])
	for i in mini(levels.size(), ComputerPlayers.LEVELS.size()):
		out["levels"][i] = (levels[i] as Dictionary).duplicate(true)
	return out


## The brains a personality of the player's can name (not the idle one, which plays inactive
## humans).
static func brains() -> Array:
	return AiBrains.IDS.filter(func(id: String) -> bool: return id != AiBrains.IDLE)


## What is wrong with a personality: its name, its brain, and its settings against the brain's
## declarations (AiBrains.problems).
static func check(p: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var name: Variant = p.get("name")
	if not name is String or str(name).strip_edges().is_empty():
		out.append("the personality needs a name")
	elif str(name).length() > NAME_MAX:
		out.append("the name is longer than %d characters" % NAME_MAX)
	if not brains().has(p.get("brain")):
		out.append("unknown brain %s" % str(p.get("brain")))
		return out
	if not p.get("params") is Dictionary:
		out.append("params must be a map")
	var levels: Variant = p.get("levels")
	if not levels is Array or (levels as Array).size() > ComputerPlayers.LEVELS.size():
		out.append("levels must be a list of up to %d maps" % ComputerPlayers.LEVELS.size())
	else:
		for m: Variant in levels:
			if not m is Dictionary:
				out.append("levels must be a list of maps")
				break
	if not out.is_empty():
		return out
	for problem: Array in AiBrains.problems(p):
		out.append("%s: %s" % problem)
	return out


## The value setting `key` has at difficulty `level` (-1: the personality's own, no level): the
## level's value when it sets one, else the personality's, else the brain's default.
static func value(p: Dictionary, level: int, key: String) -> int:
	var levels: Array = p.get("levels", [])
	if level >= 0 and level < levels.size() and (levels[level] as Dictionary).has(key):
		return int(levels[level][key])
	var params: Dictionary = p.get("params", {})
	if params.has(key):
		return int(params[key])
	for s: Dictionary in AiBrains.settings(str(p.get("brain", ""))):
		if s["key"] == key:
			return int(s["default"])
	return 0


## Settings stored as JSON numbers come back as floats: whole numbers become ints again.
static func _ints(m: Dictionary) -> Dictionary:
	var out := {}
	for k: Variant in m:
		var v: Variant = m[k]
		out[str(k)] = int(v) if (v is float and v == floor(v)) else v
	return out


static func read(path: String) -> Result:
	var r := Result.new()
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		r.errors.append("cannot read %s" % path)
		return r
	var data: Variant = JSON.parse_string(text)
	if not data is Dictionary or data.get("format") != FORMAT:
		r.errors.append("%s is not a personality file" % path)
		return r
	if int(data.get("format_version", 0)) > FORMAT_VERSION:
		r.errors.append("%s comes from a newer version" % path)
		return r
	var p := {
		"name": data.get("name"),
		"brain": data.get("brain"),
		"params": _ints(data.get("params", {})) if data.get("params", {}) is Dictionary else null,
		"levels": [],
	}
	var levels: Variant = data.get("levels", [])
	if levels is Array:
		for m: Variant in levels:
			p["levels"].append(_ints(m) if m is Dictionary else m)
	else:
		p["levels"] = levels
	r.errors = check(p)
	if r.ok():
		r.personality = p
	return r


static func write(path: String, p: Dictionary) -> Error:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	var data := {
		"format": FORMAT,
		"format_version": FORMAT_VERSION,
		"name": p["name"],
		"brain": p["brain"],
		"params": p.get("params", {}),
		"levels": p.get("levels", []),
	}
	f.store_string(JSON.stringify(data, "  ", false) + "\n")
	return OK
