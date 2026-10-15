class_name ClassicWorld
extends RefCounted
## The game as one of the original's computer players has it loaded (spec S22 "The classic
## world"): a copy of the state in which the player's own planets, fleets and designs are as they
## are, other players' and unowned planets are as its planet history knows them (S15), and other
## players' fleets and designs are there only as far as it has seen them. The classic
## personalities read only this. Their orders are applied to it as they are given (so later
## choices see them, as the original's edits to its loaded game) and recorded for the turn.
##
## Also the per-turn setup every classic personality shares (`AI_PlayTurn`): the player's
## planets in shuffled order (the turn's first draws), a 16-byte record per planet
## (`planet_info`), the design ratings, and each known minefield's radius squared.

## Detail levels (S15).
const SCANNED := 3
const OWN := 7
## `planet_info` bytes: an enemy bomber orbits this planet of the player's (`AI_ScanFleets`).
const INFO_BOMBERS := 8
const INFO_SIZE := 16
## The original's working memory per AI turn: 0x2000 bytes of 16-bit words, the first one 2.
const MEMORY_WORDS := 0x1000
const MEMORY_FIRST := 2
const BOMBER_CLASS := "ai_hull_class.bomber"

var state: GameState
var content: ContentRegistry
var player: int = 0
var rng: StarsRandom
## Planet id -> detail level as loaded (0 never seen, 1 glimpsed, 3 scanned, 7 own).
var detail := {}
## The player's planets, shuffled.
var own_planets: Array[Planet] = []
## Planet id -> PackedByteArray(INFO_SIZE).
var planet_info := {}
## "owner/slot" -> rating (`Designs_ComputeRatings`), ship designs of every player loaded.
var ratings := {}
## Minefield -> its radius squared, trunc(sqrt(mines))^2 (`AI_InitScale`).
var minefield_scale := {}
var memory := PackedInt32Array()
var orders: OrderSet
var rejected := PackedStringArray()


static func build(
	host: GameState, p_content: ContentRegistry, p: int, p_rng: StarsRandom
) -> ClassicWorld:
	var w := ClassicWorld.new()
	w.content = p_content
	w.player = p
	w.rng = p_rng
	w.state = host.copy() as GameState
	w.orders = OrderSet.new(p, host.turn)
	w._mask_planets()
	w._mask_fleets(host)
	w._mask_designs(host)
	w._mask_minefields()
	w.memory.resize(MEMORY_WORDS)
	w.memory[0] = MEMORY_FIRST
	w._setup()
	return w


func me() -> Player:
	return state.player(player)


## Gives an order: applied to the world at once, and kept for the turn when accepted.
func order(o: Dictionary) -> String:
	var reason := OrderRules.apply(state, content, player, o)
	if reason.is_empty():
		orders.add(o)
	else:
		rejected.append(reason)
	return reason


# --- Masking --------------------------------------------------------------------------------


## Other planets as the planet history records them (scanned values only when it has them).
func _mask_planets() -> void:
	var known: Dictionary = me().knowledge.get(PlanetHistory.KEY, {})
	for planet in state.planets:
		if planet.owner == player:
			detail[planet.id] = OWN
			continue
		var r: Dictionary = known.get(str(planet.id), {})
		detail[planet.id] = int(r.get("detail", 0))
		var seen_surface := _seen_level(planet.id) >= Scanning.MINERALS
		var surface := planet.surface.duplicate()
		_blank(planet)
		if r.is_empty():
			continue
		planet.owner = int(r["owner"])
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


## A planet as loaded with nothing known: no owner, values zero.
static func _blank(planet: Planet) -> void:
	planet.owner = -1
	planet.homeworld = false
	planet.starbase = null
	planet.environment.assign([0, 0, 0])
	planet.environment_original.assign([0, 0, 0])
	planet.concentration.assign([0, 0, 0])
	planet.concentration_fraction.assign([0, 0, 0])
	planet.surface.assign([0, 0, 0])
	planet.population = 0
	planet.extra_colonists = 0
	planet.mines = 0
	planet.factories = 0
	planet.defenses = 0
	planet.population_estimate = 0
	planet.defense_estimate = 0
	planet.has_scanner = false
	planet.queue.clear()
	planet.route = -1
	planet.mass_driver_target = -1
	planet.artifact = null


func _seen_level(planet_id: int) -> int:
	if player >= state.views.size() or not state.views[player] is Dictionary:
		return 0
	return int(state.views[player].get("planets", {}).get(str(planet_id), 0))


## Other players' fleets only when seen this turn: where they are and their ships, no cargo, no
## orders beyond where they are.
func _mask_fleets(host: GameState) -> void:
	var seen: Dictionary = {}
	if player < host.views.size() and host.views[player] is Dictionary:
		seen = host.views[player].get("fleets", {})
	var kept: Array[Fleet] = []
	for fleet in state.fleets:
		if fleet.owner == player:
			kept.append(fleet)
			continue
		if not seen.has("%d/%d" % [fleet.owner, fleet.number]):
			continue
		fleet.cargo.assign([0, 0, 0, 0, 0])
		fleet.waypoints.resize(1)
		fleet.name = ""
		kept.append(fleet)
	state.fleets = kept


## Other players' designs only when seen: in full at level 7, the hull alone below.
func _mask_designs(host: GameState) -> void:
	var views: Dictionary = {}
	if player < host.views.size() and host.views[player] is Dictionary:
		views = host.views[player]
	for other in state.players:
		if other.index == player:
			continue
		for starbase in [false, true]:
			var levels: Dictionary = views.get("starbase_designs" if starbase else "designs", {})
			var list: Array[Design] = other.starbase_designs if starbase else other.ship_designs
			var kept: Array[Design] = []
			for d in list:
				var level := int(levels.get("%d/%d" % [other.index, d.slot], 0))
				if level == 0:
					continue
				if level < OWN:
					for slot in d.parts:
						slot.part = ""
						slot.count = 0
				kept.append(d)
			list.assign(kept)


func _mask_minefields() -> void:
	var kept: Array[Minefield] = []
	for field in state.minefields:
		if field.owner == player or field.known_by.has(player):
			kept.append(field)
	state.minefields = kept


# --- The per-turn setup ---------------------------------------------------------------------


func _setup() -> void:
	_rate_designs()
	_scan_fleets()
	_scale_minefields()
	_list_own_planets()


## `Designs_ComputeRatings`: every loaded ship design's rating (S20 `Design_Evaluate`).
func _rate_designs() -> void:
	for other in state.players:
		for d in other.ship_designs:
			ratings["%d/%d" % [other.index, d.slot]] = Score.ship_rating(d, content)


## `AI_ScanFleets`: the player's planets with another player's fleet in orbit that has ships on a
## bomber hull.
func _scan_fleets() -> void:
	for planet in state.planets:
		var info := PackedByteArray()
		info.resize(INFO_SIZE)
		planet_info[planet.id] = info
	var bombers: Array = content.get_def("ai_hull_class", BOMBER_CLASS)["hulls"]
	for fleet in state.fleets:
		if fleet.owner == player or fleet.planet < 0:
			continue
		var owner := state.player(fleet.owner)
		var has_bomber := false
		for stack in fleet.stacks:
			var d := owner.ship_design(stack.design)
			if stack.count > 0 and d != null and bombers.has(d.hull):
				has_bomber = true
		var at := state.planet(fleet.planet)
		if has_bomber and at != null and at.owner == player:
			var info: PackedByteArray = planet_info[at.id]
			info[INFO_BOMBERS] = 1
			planet_info[at.id] = info


## `AI_InitScale`.
func _scale_minefields() -> void:
	for field in state.minefields:
		var r := int(sqrt(float(field.mines)))
		minefield_scale[field] = r * r


## `AI_BuildOwnPlanetList`: the player's planets in planet order, then shuffled: for each place i
## but the last, swap it with place i + random(n - i).
func _list_own_planets() -> void:
	for planet in state.planets:
		if planet.owner == player:
			own_planets.append(planet)
	var n := own_planets.size()
	for i in n - 1:
		var j := i + rng.random(n - i)
		var swap := own_planets[i]
		own_planets[i] = own_planets[j]
		own_planets[j] = swap
