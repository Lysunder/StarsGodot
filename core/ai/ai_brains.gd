class_name AiBrains
extends RefCounted
## The brains a personality can name (spec S22 "Personalities"): built into the game, by id, each
## with the settings a personality can give it (S22 "Personality settings"). Script mods will add
## their own (M14).

const IDLE := "idle"
const BASELINE := "baseline"
## The original's personalities ported (S22), each a brain of its own.
const ROBOTOIDS := "robotoids"
const TURINDRONES := "turindrones"
const AUTOMITRONS := "automitrons"
const IDS := [IDLE, BASELINE, ROBOTOIDS, TURINDRONES, AUTOMITRONS]


static func has(id: String) -> bool:
	return IDS.has(id)


## The settings brain `id` declares: [{key, group, min, max, default}], in display order.
static func settings(id: String) -> Array:
	match id:
		BASELINE:
			return BaselineBase.SETTINGS
	return []


## A personality's settings checked against its brain's declarations: [pointer, message] per
## problem (an unknown setting, or a value out of range), for content validation.
static func problems(personality: Dictionary) -> Array:
	var out := []
	var declared := {}
	for s: Dictionary in settings(str(personality.get("brain", ""))):
		declared[s["key"]] = s
	var maps := [["/params", personality.get("params", {})]]
	var levels: Variant = personality.get("levels", [])
	if levels is Array:
		for i in levels.size():
			maps.append(["/levels/%d" % i, levels[i]])
	for entry: Array in maps:
		if not entry[1] is Dictionary:
			continue
		for key: Variant in entry[1]:
			var at := "%s/%s" % [entry[0], key]
			if not declared.has(key):
				out.append([at, "not a setting of brain %s" % personality.get("brain")])
				continue
			var value: Variant = entry[1][key]
			var s: Dictionary = declared[key]
			if value is int and (value < s["min"] or value > s["max"]):
				out.append([at, "must be %d to %d" % [s["min"], s["max"]]])
	return out


## A new brain for `id`, or null for an unknown one.
static func create(id: String) -> AiPlayer:
	match id:
		IDLE:
			return AiPlayer.new()
		BASELINE:
			return BaselineAi.new()
		ROBOTOIDS:
			return ClassicBrain.new(ClassicWorld.ROBOTOIDS)
		TURINDRONES:
			return ClassicBrain.new(ClassicWorld.TURINDRONES)
		AUTOMITRONS:
			return ClassicBrain.new(ClassicWorld.AUTOMITRONS)
	return null
