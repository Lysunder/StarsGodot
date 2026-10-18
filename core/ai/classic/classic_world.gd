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
## (`planet_info`), the design ratings, and each known minefield's radius squared; and the
## working memory the personality keeps from turn to turn (the original keeps it in the player's
## history file; we keep it in the player's knowledge, `MEMORY_KEY`, and send it back as an order,
## `memory_order`).

## Detail levels (S15).
const SCANNED := 3
const OWN := 7
## The population estimate of a planet the player has never seen (the 12-bit field all set).
const UNKNOWN_ESTIMATE := 0xFFF
## `planet_info` bytes: an enemy bomber orbits this planet of the player's (`AI_ScanFleets`).
const INFO_BOMBERS := 8
const INFO_SIZE := 16
## The original's working memory: 0x2000 bytes of 16-bit words; the first holds the bytes in
## use, the word itself included (2 when empty).
const MEMORY_WORDS := 0x1000
const MEMORY_FIRST := 2
const MEMORY_KEY := OrderRules.AI_MEMORY_KEY
## The shared design buffer's key and slot count, and the formula id for an empty slot's turn
## designed (S25 B54).
const SLOT_TURNS_KEY := "classic_slot_turns"
const SHIP_SLOTS := 16
const EMPTY_SLOT_TURN := "ai.empty_slot_turn"
## Light years the computer players add to a minefield's radius (`AI_InitScale`).
const MINEFIELD_MARGIN := 10
const BOMBER_CLASS := "ai_hull_class.bomber"
const ROBOTOIDS := "ai_personality.robotoids"
const TURINDRONES := "ai_personality.turindrones"
const AUTOMITRONS := "ai_personality.automitrons"
const ROTOTILLS := "ai_personality.rototills"
const CYBERTRONS := "ai_personality.cybertrons"
const MACINTI := "ai_personality.macinti"
## Freighter depot records in the memory (`AI_PlanFreighterDepots`): the count in word 1, then
## DEPOT_WORDS words each from word 2: the planet, how many fleets, and up to DEPOT_FLEETS fleets.
const DEPOT_COUNT := 1
const DEPOT_FIRST := 2
const DEPOT_WORDS := 10
const DEPOT_FLEETS := 8
const SELECT_NONE := 0
const SELECT_PLANET := 1
const SELECT_FLEET := 2
## A fleet's id word (owner << 9 | number), for the selection.
const FLEET_ID_OWNER_SHIFT := 9

var state: GameState
var content: ContentRegistry
var player: int = 0
## The content id of the original personality being played (ROBOTOIDS ...).
var personality := ""
var rng: StarsRandom
## Planet id -> detail level as loaded (0 never seen, 1 glimpsed, 3 scanned, 7 own).
var detail := {}
## Planet ids the player's turn file holds (its own and those the planet history records): the
## original's loaded planets, {id: true}.
var loaded := {}
## Planet id -> the turn it was last seen (this turn for the player's own; 0 never seen).
var seen_turn := {}
## The player's planets, shuffled.
var own_planets: Array[Planet] = []
## The planet count of the player's record while the brain plays: its own planets (the turn
## file's record counts the planets it sees too, but turin1 turn 69's freighters follow the own
## count).
var planet_count := 0
## Planet id -> PackedByteArray(INFO_SIZE).
var planet_info := {}
## "owner/slot" -> rating (`Designs_ComputeRatings`), ship designs of every player loaded.
var ratings := {}
## Minefield -> the radius squared the computer player keeps clear of: trunc(sqrt(mines) + 10.5),
## squared (`AI_InitScale`: the field's radius rounded, plus MINEFIELD_MARGIN light years).
var minefield_scale := {}
## The working memory, MEMORY_WORDS words.
var memory := PackedInt32Array()
var orders: OrderSet
var rejected := PackedStringArray()

## The selection the original edits through (`SetSelection`): a planet or a fleet, and the copy
## of a planet being edited (`g_curPlanet`): the selected planet, or the selected fleet's. Edits
## to the copy reach the world only when committed; selecting what is already selected keeps the
## copy as it is.
var selected_kind := SELECT_NONE
var selected_id := -1
var cur_planet: Planet = null
## The production being edited (ClassicProduction.Edit), or null.
var editing: RefCounted = null
## Colony targets were rated this turn (personalities other than Robotoids and Macinti rate once).
var colony_targets_rated := false
## The turn designed the original's buffer of the player's ship designs holds in each slot
## (shared by the computer players of one turn): a player's file sets its designs' slots, an
## empty slot keeps what the last computer player loaded or saved there (S25 B54).
var slot_turns: Array = []
## Macinti's starbase verdicts this turn (ClassicMacinti.review_designs), read by the production
## pass's starbase step.
var macinti_verdicts := PackedByteArray()


## The world of player `p` of `host`, playing personality `p_personality` (by default the one
## the player's key names).
static func build(
	host: GameState,
	p_content: ContentRegistry,
	p: int,
	p_rng: StarsRandom,
	p_personality: String = "",
) -> ClassicWorld:
	var w := ClassicWorld.new()
	w.content = p_content
	w.player = p
	w.rng = p_rng
	w.state = host.copy() as GameState
	w.personality = p_personality
	if w.personality.is_empty():
		w.personality = ComputerPlayers.personality_id(ComputerPlayers.personality_of(w.me()))
	w.orders = OrderSet.new(p, host.turn)
	w._count_planets(host)
	w._mask_planets()
	w._mask_fleets(host)
	w._mask_designs(host)
	w._mask_minefields()
	w._mask_objects(host)
	w._load_memory()
	w._setup()
	return w


func me() -> Player:
	return state.player(player)


## Joins the computer players' shared design buffer (`LoadGame` of the player's file): the
## player's designs set their slots' turns.
func load_slot_turns(shared: Dictionary) -> void:
	if not shared.has(SLOT_TURNS_KEY):
		var turns: Array = []
		turns.resize(SHIP_SLOTS)
		turns.fill(0)
		shared[SLOT_TURNS_KEY] = turns
	slot_turns = shared[SLOT_TURNS_KEY]
	for d in me().ship_designs:
		slot_turns[d.slot] = d.turn_designed


## The turn designed the design buffer holds in an empty ship slot (S25 B54; fixed: 0).
func empty_slot_turn(slot: int) -> int:
	var held: int = slot_turns[slot] if slot < slot_turns.size() else 0
	return content.ruleset.formula(EMPTY_SLOT_TURN).call(held)


## B54 fixed: an empty slot has no turn designed.
static func no_empty_slot_turn(_held: int) -> int:
	return 0


## The content id of the personality being played.
func personality_id() -> String:
	return personality


## Whether player `index` counts as a computer player (one, or a human player marked inactive:
## the original flags both alike).
func is_computer(index: int) -> bool:
	var p := state.player(index)
	return not p.is_human() or not p.active


func _load_memory() -> void:
	memory.resize(MEMORY_WORDS)
	memory.fill(0)
	memory[0] = MEMORY_FIRST
	var saved: Array = me().knowledge.get(MEMORY_KEY, [])
	for i in mini(saved.size(), MEMORY_WORDS):
		memory[i] = int(saved[i])


## The order that keeps the working memory for the next turn (S11 `ai_memory`): the words in use
## (none when only the count word is), or {} when the knowledge holds them already.
func memory_order() -> Dictionary:
	var words := clampi(memory[0] / 2, 1, MEMORY_WORDS)
	var out: Array = []
	if words > 1:
		for i in words:
			out.append(memory[i] & 0xFFFF)
	var saved: Array = me().knowledge.get(MEMORY_KEY, [])
	if saved == out:
		return {}
	return {"type": "ai_memory", "words": out}


## Gives an order: applied to the world at once, and kept for the turn when accepted.
func order(o: Dictionary) -> String:
	var reason := OrderRules.apply(state, content, player, o)
	if reason.is_empty():
		orders.add(o)
	else:
		rejected.append(reason)
	return reason


## Whether a planet is one of the freighter depots in the memory.
func is_depot(planet_id: int) -> bool:
	return depot_of_planet(planet_id) >= 0


## The depot record of a planet, or -1.
func depot_of_planet(planet_id: int) -> int:
	for i in memory[DEPOT_COUNT]:
		if memory[DEPOT_FIRST + i * DEPOT_WORDS] == planet_id:
			return i
	return -1


# --- Selection ------------------------------------------------------------------------------


## Selects a planet (`SetSelection(1, id)`): the planet copy is loaded unless it is selected
## already.
func select_planet(id: int) -> void:
	if selected_kind == SELECT_PLANET and selected_id == id:
		return
	var planet := state.planet(id)
	if planet == null:
		return
	cur_planet = planet.copy() as Planet
	selected_kind = SELECT_PLANET
	selected_id = id


## Selects one of the player's fleets (`SetSelection(2, id)`): the planet copy becomes the
## fleet's planet (none in deep space) unless that planet's copy is loaded already.
func select_fleet(fleet: Fleet) -> void:
	var id := fleet.owner << FLEET_ID_OWNER_SHIFT | fleet.number
	if selected_kind == SELECT_FLEET and selected_id == id:
		return
	if fleet.planet < 0:
		cur_planet = null
	elif cur_planet == null or cur_planet.id != fleet.planet:
		cur_planet = state.planet(fleet.planet).copy() as Planet
	selected_kind = SELECT_FLEET
	selected_id = id


## Reloads the planet copy from the world (after a commit).
func reload_planet() -> void:
	if cur_planet != null:
		cur_planet = state.planet(cur_planet.id).copy() as Planet


## A fleet's id word, as the memory keeps it.
static func fleet_id(fleet: Fleet) -> int:
	return fleet.owner << FLEET_ID_OWNER_SHIFT | fleet.number


# --- Masking --------------------------------------------------------------------------------


func _count_planets(host: GameState) -> void:
	for planet in host.planets:
		if planet.owner == player:
			planet_count += 1


## Other planets as the planet history records them (scanned values only when it has them).
func _mask_planets() -> void:
	var known: Dictionary = me().knowledge.get(PlanetHistory.KEY, {})
	for planet in state.planets:
		if planet.owner == player:
			detail[planet.id] = OWN
			seen_turn[planet.id] = state.turn
			loaded[planet.id] = true
			continue
		var r: Dictionary = known.get(str(planet.id), {})
		if not r.is_empty():
			loaded[planet.id] = true
		detail[planet.id] = int(r.get("detail", 0))
		seen_turn[planet.id] = int(r.get("turn", 0))
		var seen_surface := _seen_level(planet.id) >= Scanning.MINERALS
		var surface := planet.surface.duplicate()
		_blank(planet)
		if r.is_empty():
			planet.population_estimate = UNKNOWN_ESTIMATE
			continue
		planet.owner = int(r["owner"])
		if planet.owner == player:
			# a planet the history says is the player's but the turn file doesn't: loading
			# makes it unowned, scanned (the player lost it)
			planet.owner = -1
			detail[planet.id] = SCANNED
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
		if field.owner == player or field.seen_by.has(player):
			kept.append(field)
	state.minefields = kept


## Packets and salvage seen this turn (the player's own too only when seen; all of its own when
## there is no view yet), and the wormholes its turn file holds (those it has seen when there is
## no view yet).
func _mask_objects(host: GameState) -> void:
	var view: Dictionary = {}
	if player < host.views.size() and host.views[player] is Dictionary:
		view = host.views[player]
	var seen_packets: Array = view.get("packets", [])
	var packets: Array[Packet] = []
	for packet in state.packets:
		var mine := view.is_empty() and packet.owner == player
		if mine or seen_packets.has("%d/%d" % [packet.owner, packet.number]):
			packets.append(packet)
	state.packets = packets
	var seen_holes: Array = view.get("wormholes", [])
	var holes: Array[Wormhole] = []
	for hole in state.wormholes:
		var known := hole.seen_by.has(player) if view.is_empty() else seen_holes.has(hole.number)
		if known:
			holes.append(hole)
	state.wormholes = holes


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
		var root := int(sqrt(float(field.mines)))
		while root * root > field.mines:
			root -= 1
		while (root + 1) * (root + 1) <= field.mines:
			root += 1
		# + 10.5, truncated: one more when the root's fraction is a half or more
		var r := root + MINEFIELD_MARGIN + (1 if field.mines > root * root + root else 0)
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
