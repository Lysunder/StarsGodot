class_name TurnFile
extends RefCounted
## A player's turn file for play by email (spec S27 "Play by email"): the game as that player knows
## it, with an integrity checksum. It holds the player's own things in full and of everything else
## only what the player has seen (the way the classic world loads a player's game, S22): other
## planets as the player's planet history records them, other players' fleets, minefields, packets,
## wormholes and traders only when seen this year, their designs only as far as seen, and of the
## other players only what any player may know (race name, logo, standing). Nothing that would let
## a player foresee the year (the random streams) is in it.
##
## Format: {format, format_version, game_version, game_id, player, turn, ruleset_hash, mods, state,
## checksum}: the checksum is the SHA-256 of the canonical JSON of everything else, so a file
## damaged on its way is refused. It guards against accidents, not against cheating.

const FORMAT := "starsgodot-turn"
const FORMAT_VERSION := 1
const EXTENSION := "turn"
const _KEYS := [
	"format",
	"format_version",
	"game_version",
	"game_id",
	"player",
	"turn",
	"ruleset_hash",
	"mods",
	"state",
	"checksum",
]
## The player-history detail at which a planet's environment is known (S15).
const SCANNED := 3


class LoadResult:
	extends RefCounted
	var state: GameState = null
	var player: int = -1
	var game_id: String = ""
	var errors: PackedStringArray = []
	## True when the file was made with different gameplay content than the running game.
	var content_mismatch: bool = false

	func ok() -> bool:
		return errors.is_empty() and state != null


## The game as player `p` knows it this year.
static func player_state(host: GameState, p: int) -> GameState:
	var s := host.copy() as GameState
	var view: Dictionary = {}
	if p < host.views.size() and host.views[p] is Dictionary:
		view = host.views[p]
	_mask_planets(s, p, view)
	_mask_fleets(s, p, view)
	_mask_designs(s, p, view)
	_mask_objects(s, p, view)
	_mask_players(s, p)
	var messages: Array = []
	var views: Array = []
	for i in s.players.size():
		messages.append(s.messages[i] if i == p and i < s.messages.size() else [])
		views.append(view if i == p else {})
	s.messages = messages
	s.views = views
	s.battles = s.battles.filter(func(b: Dictionary) -> bool: return b.get("players", []).has(p))
	if not s.settings.public_scores:
		for entry: Dictionary in s.history:
			var records: Array = entry.get("records", [])
			for i in records.size():
				if i != p:
					records[i] = {}
	s.rng = RngStreams.new(0)
	return s


## Other planets as the player's planet history records them; this year's surface minerals only
## when seen at that detail.
static func _mask_planets(s: GameState, p: int, view: Dictionary) -> void:
	var known: Dictionary = s.player(p).knowledge.get(PlanetHistory.KEY, {})
	for planet in s.planets:
		if planet.owner == p:
			continue
		var seen_surface := int(view.get("planets", {}).get(str(planet.id), 0)) >= Scanning.MINERALS
		var surface := planet.surface.duplicate()
		ClassicWorld._blank(planet)
		var r: Dictionary = known.get(str(planet.id), {})
		if r.is_empty():
			continue
		planet.owner = int(r["owner"])
		if planet.owner == p:
			planet.owner = -1
		planet.homeworld = bool(r["homeworld"])
		if int(r["starbase_design"]) >= 0:
			planet.starbase = Starbase.new()
			planet.starbase.design = int(r["starbase_design"])
		if int(r["detail"]) >= SCANNED:
			planet.environment.assign(r["environment"])
			planet.environment_original.assign(r["environment_original"])
			planet.concentration.assign(r["concentration"])
			planet.concentration_fraction.assign(r["concentration_fraction"])
			planet.population_estimate = int(r.get("population_estimate", 0))
			planet.defense_estimate = int(r.get("defense_estimate", 0))
		if seen_surface:
			planet.surface.assign(surface)


## Other players' fleets seen this year: where they are and their ships; no cargo, name, battle
## plan or orders beyond where they are.
static func _mask_fleets(s: GameState, p: int, view: Dictionary) -> void:
	var seen: Dictionary = view.get("fleets", {})
	var kept: Array[Fleet] = []
	for fleet in s.fleets:
		if fleet.owner == p:
			kept.append(fleet)
			continue
		if not seen.has("%d/%d" % [fleet.owner, fleet.number]):
			continue
		fleet.cargo.assign([0, 0, 0, 0, 0])
		fleet.waypoints.resize(1)
		fleet.name = ""
		fleet.battle_plan = 0
		fleet.repeat = false
		kept.append(fleet)
	s.fleets = kept


## Other players' designs as far as seen: in full, or the hull alone. A starbase the player's
## planet history records counts as seen (its hull).
static func _mask_designs(s: GameState, p: int, view: Dictionary) -> void:
	var recorded := {}
	for planet in s.planets:
		if planet.owner >= 0 and planet.owner != p and planet.starbase != null:
			recorded["%d/%d" % [planet.owner, planet.starbase.design]] = true
	for other in s.players:
		if other.index == p:
			continue
		for starbase in [false, true]:
			var levels: Dictionary = view.get("starbase_designs" if starbase else "designs", {})
			var list: Array[Design] = other.starbase_designs if starbase else other.ship_designs
			var kept: Array[Design] = []
			for d in list:
				var key := "%d/%d" % [other.index, d.slot]
				var level := int(levels.get(key, 0))
				if level == 0 and starbase and recorded.has(key):
					level = SCANNED
				if level == 0:
					continue
				if level < Scanning.FULL:
					for slot in d.parts:
						slot.part = ""
						slot.count = 0
				kept.append(d)
			list.assign(kept)


## Minefields the player owns or knows; packets, wormholes and traders seen this year (its own
## packets always).
static func _mask_objects(s: GameState, p: int, view: Dictionary) -> void:
	s.minefields = s.minefields.filter(
		func(f: Minefield) -> bool: return f.owner == p or f.seen_by.has(p)
	)
	var packets: Array = view.get("packets", [])
	s.packets = s.packets.filter(
		func(k: Packet) -> bool: return k.owner == p or packets.has("%d/%d" % [k.owner, k.number])
	)
	var holes: Array = view.get("wormholes", [])
	s.wormholes = s.wormholes.filter(
		func(w: Wormhole) -> bool: return holes.has(w.number) or w.seen_by.has(p)
	)
	# a wormhole whose other end the player hasn't seen leads somewhere unknown
	for w in s.wormholes:
		if not s.wormholes.any(func(o: Wormhole) -> bool: return o.number == w.other_end):
			w.other_end = -1
	var traders: Array = view.get("traders", [])
	s.traders = s.traders.filter(func(t: Trader) -> bool: return traders.has(t.number))


## Of the other players only their race's name, plural and logo, whether they are computer
## players, and their standing (eliminated, rank; the score record only with public scores).
static func _mask_players(s: GameState, p: int) -> void:
	for other in s.players:
		if other.index == p:
			continue
		var race := Race.new()
		race.name = other.race.name
		race.plural_name = other.race.plural_name
		race.logo = other.race.logo
		other.race = race
		other.ai_personality = {}
		other.homeworld = -1
		other.tech_levels.fill(0)
		other.research_points.fill(0)
		other.research_percent = 0
		other.research_field = 0
		other.next_research_field = 0
		other.relations.fill("neutral")
		other.battle_plans = []
		other.default_queue.clear()
		other.production_templates = []
		other.message_filters.clear()
		other.trader_parts.clear()
		other.knowledge = {}
		other.mod_data = {}
		if not s.settings.public_scores:
			other.score = {}


static func encode(host: GameState, p: int, game_id: String, game_version: String) -> String:
	var s := player_state(host, p)
	var data := {
		"format": FORMAT,
		"format_version": FORMAT_VERSION,
		"game_version": game_version,
		"game_id": game_id,
		"player": p,
		"turn": s.turn,
		"ruleset_hash": s.settings.ruleset_hash,
		"mods": s.settings.mods.duplicate(true),
		"state": s.to_dict(),
	}
	data["checksum"] = checksum(data)
	return ContentRegistry.canonical(data) + "\n"


## The SHA-256 of the canonical JSON of `data` without its checksum.
static func checksum(data: Dictionary) -> String:
	var rest := data.duplicate()
	rest.erase("checksum")
	return ContentRegistry.canonical(rest).sha256_text()


static func decode(text: String, content: ContentRegistry) -> LoadResult:
	var result := LoadResult.new()
	var parsed := JsonReader.parse(text)
	if not parsed.ok:
		result.errors.append("line %d: %s" % [parsed.error_line, parsed.error])
		return result
	var data: Variant = parsed.value
	if not data is Dictionary or data.get("format") != FORMAT:
		result.errors.append("not a %s file" % FORMAT)
		return result
	for key: String in _KEYS:
		if not data.has(key):
			result.errors.append("/%s: missing" % key)
	if not result.errors.is_empty():
		return result
	if str(data["checksum"]) != checksum(data):
		result.errors.append("the file is damaged (its checksum does not match)")
		return result
	if not data["format_version"] is int or data["format_version"] > FORMAT_VERSION:
		result.errors.append("/format_version: not one this game reads")
		return result
	var errors := PackedStringArray()
	var state := ModelObject.object_from(GameState, data["state"], "/state", errors) as GameState
	if not errors.is_empty():
		result.errors = errors
		return result
	result.player = int(data["player"])
	result.game_id = str(data["game_id"])
	if result.player < 0 or result.player >= state.players.size():
		result.errors.append("/player: not a player of the game")
		return result
	result.content_mismatch = (
		state.settings.ruleset_hash != content.ruleset_hash
		or _mod_names(state.settings.mods) != content.gameplay_mods()
	)
	result.state = state
	return result


static func _mod_names(mods: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for m: Dictionary in mods:
		out.append("%s@%s" % [m.get("id", ""), m.get("version", "")])
	return out


static func write(
	path: String, host: GameState, p: int, game_id: String, game_version: String
) -> Error:
	return SaveStore.write_text(path, encode(host, p, game_id, game_version))


static func read(path: String, content: ContentRegistry) -> LoadResult:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		var r := LoadResult.new()
		r.errors.append("cannot read %s" % path)
		return r
	return decode(text, content)
