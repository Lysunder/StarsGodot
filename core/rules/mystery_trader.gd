class_name MysteryTrader
extends RefCounted
## The Mystery Trader (spec S18): its arrival (a random event, `RandomEvent_MysteryTrader`), its
## movement in phase 8 (`MoveSpaceObjects`) and its meetings with fleets and planets in the
## waypoint 1 step (`DoMysteryTrader@1100:0784`).

const RESEARCH := "research"
const SHIPS := "ships"
const SHIPS_BIT := 12
const ITEM_BITS := 13
const OBJECT_KIND := 8192
const TRADER_KIND := 3
const EDGE_LOW := 1020
const EDGE_SPAN := 361
const EDGE_HIGH := 1380
const WARP_MAX_STARTLED := 12
const WARP_MIN_TURNED := 6
const MINERALS_NEEDED := 5000
const MINERALS_PER_LEVEL := 1200
const LEVELS_BASE := 6
const LEVELS_MAX := 10
const PART_TRIES := 25
const PLANET_TRIES := 50
const PLANET_REACH := 100
const PLANET_TECH_LIMIT := 150
const PLANET_LEVELS := 6
const AI_LEVEL_TRADING := 2
const AI_MINERALS := [3500, 5000]
const SHIP_DESIGNS := [
	"starting_design.trader_nubian",
	"starting_design.trader_morph_shield",
	"starting_design.trader_morph_armor",
]
const SHIPS_MAX := 5

# --- Items -----------------------------------------------------------------------------------


## The content id of item bit `bit` (S18 "The Trader's items"); bit 12 is ships.
static func item_of(content: ContentRegistry, bit: int) -> String:
	if bit == SHIPS_BIT:
		return SHIPS
	for type in ["part", "hull"]:
		for id in content.ids(type):
			if int(content.get_def(type, id).get("trader_bit", -1)) == bit:
				return id
	return RESEARCH


static func _has(player: Player, item: String) -> bool:
	return player.trader_parts.has(item)


static func _add(player: Player, item: String) -> void:
	if not player.trader_parts.has(item):
		player.trader_parts.append(item)
		player.trader_parts.sort()


static func object_word(trader: Trader) -> int:
	return TRADER_KIND * OBJECT_KIND + trader.number


# --- Arrival ---------------------------------------------------------------------------------


## S18 "A Mystery Trader arrives".
static func arrive(state: GameState, content: ContentRegistry, rng: StarsRandom) -> void:
	var t := state.turn
	if t <= 39:
		return
	var n := 7
	if t % 100 == 71:
		n = 2
	elif t % 100 == 33:
		n = 3
	elif t % 128 == 49:
		n = 4
	elif t & 1:
		return
	if rng.random(n) != 0:
		return
	if state.space_object_count() >= content.constant("constant.limits.space_objects"):
		return
	var trader := state.add_trader(content.constant("constant.limits.space_object_numbers"))
	if trader == null:
		return
	trader.warp = 8 + rng.random(5)
	var s := RandomEvents.universe_size(state)
	var c0 := rng.random(s * 400 + EDGE_SPAN) + EDGE_LOW
	var c1 := rng.random(s * 400 + EDGE_SPAN) + EDGE_LOW
	var e0 := EDGE_LOW
	var e1 := s * 400 + EDGE_HIGH
	if rng.random(2) != 0:
		e0 = e1
		e1 = EDGE_LOW
	var ends := [c0, e0, c1, e1]
	var r := rng.random(2)
	trader.x = ends[r]
	trader.y = ends[1 - r]
	trader.destination_x = ends[r + 2]
	trader.destination_y = ends[3 - r]
	trader.item = _arrival_item(content, rng, t, trader.warp)
	for p in state.players.size():
		_announce(state, content, p, "message.trader.arrived", trader)


static func _arrival_item(content: ContentRegistry, rng: StarsRandom, t: int, warp: int) -> String:
	var b := 5 if t < 100 else (3 if t < 250 else 2)
	if warp < 10:
		b += 1
	elif warp > 10:
		b -= 1
	if rng.random(10) < b:
		return SHIPS if rng.random(6) == 0 else RESEARCH
	var bit := rng.random(ITEM_BITS)
	if bit in [6, 7, 10, 11]:
		bit = rng.random(ITEM_BITS)
		var early := (t < 120 and bit == 7) or (t < 150 and bit == 10) or (t < 180 and bit == 11)
		if early and rng.random(2) != 0:
			return RESEARCH
	return item_of(content, bit)


# --- Movement --------------------------------------------------------------------------------


## S18 "The Trader moves": phase 8, after the packets. Waypoints follow afterwards (the caller).
static func move_all(state: GameState, content: ContentRegistry, rng: StarsRandom) -> void:
	for trader in state.traders:
		if trader.warp <= WARP_MAX_STARTLED and rng.random(25) == 0:
			if rng.random(3) == 0:
				_new_destination(state, rng, trader)
			trader.warp += 1
			for p in state.players.size():
				_announce(state, content, p, "message.trader.course_changed", trader)
		var v := trader.warp * trader.warp
		var dx := trader.destination_x - trader.x
		var dy := trader.destination_y - trader.y
		var d := sqrt(float(dx * dx + dy * dy))
		if int(d) > v:
			var f := float(v) / d
			var x := trader.x + int(dx * f + (0.5 if dx > 0 else -0.5))
			var y := trader.y + int(dy * f + (0.5 if dy > 0 else -0.5))
			if x != trader.destination_x or y != trader.destination_y:
				trader.x = x
				trader.y = y
				continue
		trader.x = trader.destination_x
		trader.y = trader.destination_y
		trader.warp = maxi(trader.warp - 2, WARP_MIN_TURNED) + 1
		_new_destination(state, rng, trader)
		for p in state.players.size():
			_announce(state, content, p, "message.trader.turned_back", trader)


static func _new_destination(state: GameState, rng: StarsRandom, trader: Trader) -> void:
	var s := RandomEvents.universe_size(state)
	var e := s * 400 + EDGE_HIGH if rng.random(2) == 0 else EDGE_LOW
	var c := rng.random(s * 400 + EDGE_SPAN) + EDGE_LOW
	if rng.random(2) == 0:
		trader.destination_x = e
		trader.destination_y = c
	else:
		trader.destination_x = c
		trader.destination_y = e


# --- Meetings --------------------------------------------------------------------------------


## S18 "Meeting the Trader": phase 16b, after battles and bombing.
static func meet_all(state: GameState, content: ContentRegistry, rng: StarsRandom) -> void:
	var absorbed: Array[Fleet] = []
	for trader in state.traders:
		var i := 0
		while i < state.fleets.size():
			var fleet := state.fleets[i]
			i += 1
			if fleet.ship_count() == 0 or fleet.x != trader.x or fleet.y != trader.y:
				continue
			var gift := _meet_fleet(state, content, rng, trader, fleet, absorbed)
			if gift != null and state.fleets.find(gift) < i:
				i += 1
		_meet_planets(state, content, rng, trader)
	for fleet in absorbed:
		FleetOrders.delete_fleet(state, fleet, fleet.owner)


## One fleet on the trader's position. Returns a fleet of ships the trader gave, or null.
static func _meet_fleet(
	state: GameState,
	content: ContentRegistry,
	rng: StarsRandom,
	trader: Trader,
	fleet: Fleet,
	absorbed: Array[Fleet]
) -> Fleet:
	var owner := state.player(fleet.owner)
	var minerals := fleet.cargo[0] + fleet.cargo[1] + fleet.cargo[2]
	var word := fleet.owner * 512 + fleet.number
	var goto := {"fleet": fleet.number, "owner": fleet.owner}
	if minerals < MINERALS_NEEDED:
		if not fleet.did_not_move:
			TurnMessages.add(state, content, fleet.owner, "message.trader.refused", goto, [word])
		return null
	if trader.met.has(fleet.owner):
		TurnMessages.add(state, content, fleet.owner, "message.trader.recovering", goto, [word])
		return null
	_mark_met(trader, fleet.owner)
	_remove_completed(state, fleet)
	fleet.stacks.clear()
	absorbed.append(fleet)
	var top := content.constant("constant.research.max_level")
	var maxed := true
	for level in owner.tech_levels:
		if level < top:
			maxed = false
	if trader.item == RESEARCH or _has(owner, trader.item):
		if maxed:
			if rng.random(5) == 0:
				TurnMessages.add(
					state, content, fleet.owner, "message.trader.nothing_to_teach", {}, [word]
				)
				return null
		else:
			_research(state, content, rng, owner, minerals, word)
			return null
	var item := trader.item
	if item == RESEARCH:
		item = item_of(content, rng.random(ITEM_BITS))
	# (the original gives up on its last roll even when that one finds an item)
	var rolls := 0
	while _has(owner, item) and rolls < PART_TRIES:
		rolls += 1
		item = item_of(content, rng.random(ITEM_BITS))
	if rolls == PART_TRIES or item == SHIPS:
		return _ships(state, content, rng, fleet, word)
	_add(owner, item)
	var kind := "message.trader.part"
	if content.has_def(item) and content.type_of(item) == "hull":
		kind = "message.trader.hull"
	elif content.part(item).get("category", "") == "planetary":
		kind = "message.trader.planetary"
	TurnMessages.add(state, content, fleet.owner, kind, {"item": item}, [word])
	return null


static func _research(
	state: GameState,
	content: ContentRegistry,
	rng: StarsRandom,
	owner: Player,
	minerals: int,
	word: int
) -> void:
	var levels := mini((minerals - MINERALS_NEEDED) / MINERALS_PER_LEVEL + LEVELS_BASE, LEVELS_MAX)
	var total := 0
	for level in owner.tech_levels:
		total += level
	if total >= 108:
		levels = 1
	elif total >= 96:
		levels = 2
	elif total >= 84:
		levels -= 3
	elif total >= 72:
		levels -= 2
	elif total >= 60:
		levels -= 1
	var kind := "message.trader.research"
	if owner.trader_parts.size() == ITEM_BITS:
		kind = "message.trader.research_all_parts"
	TurnMessages.add(state, content, owner.index, kind, {}, [word, levels])
	var top := content.constant("constant.research.max_level")
	var slow := state.settings.slow_tech
	for i in levels:
		var field := -1
		if rng.random(4) < 3:
			field = rng.random(6)
			if owner.tech_levels[field] >= top:
				field = -1
		if field < 0:
			field = ResearchRules.lowest_field(owner)
			if owner.tech_levels[field] >= top:
				break
		var stored := owner.research_points[field] * (2 if slow else 1)
		var needed := ResearchRules.level_cost(owner, field, content, slow) - stored
		owner.research_points[field] *= 2
		if needed > 0:
			owner.research_points[field] += needed
		ResearchRules.update(state, content, [])


static func _ships(
	state: GameState, content: ContentRegistry, rng: StarsRandom, fleet: Fleet, word: int
) -> Fleet:
	var owner := state.player(fleet.owner)
	if not owner.is_human():
		return null
	var t := state.turn
	var kind := rng.random(3 if t > 100 else 4)
	if kind > 0:
		kind = 1 + rng.random(2)
	var template := StartingSetup.design_from(content, SHIP_DESIGNS[kind], -1)
	var slot := -1
	for d in owner.ship_designs:
		if _same_design(d, template):
			slot = d.slot
	if slot < 0:
		for s in content.constant("constant.limits.ship_designs"):
			if owner.ship_design(s) == null:
				slot = s
				break
	var fleets := 0
	for f in state.fleets:
		if f.owner == fleet.owner and f.ship_count() > 0:
			fleets += 1
	var limit := content.constant("constant.limits.fleets_per_player")
	if slot < 0 or fleets >= limit:
		TurnMessages.add(state, content, fleet.owner, "message.trader.ships_no_room", {}, [word])
		return null
	var n := 2 if rng.random(3) == 0 else 1
	if t > 100:
		n += rng.random(t / 100 + 1)
	n = mini(n, SHIPS_MAX)
	if kind > 0:
		n += rng.random(n + 1)
	var gift := state.add_fleet(fleet.owner, limit)
	if gift == null:
		TurnMessages.add(state, content, fleet.owner, "message.trader.ships_no_room", {}, [word])
		return null
	var design := owner.ship_design(slot)
	if design == null:
		design = template
		design.slot = slot
		owner.set_design(design, false)
	design.built += n
	design.remaining += n
	gift.x = fleet.x
	gift.y = fleet.y
	gift.planet = fleet.planet
	var here := Waypoint.new(fleet.x, fleet.y)
	if fleet.planet >= 0:
		here.target = "planet"
		here.target_id = fleet.planet
	gift.waypoints.append(here)
	gift.add_ships(slot, n)
	gift.did_not_move = true
	gift.cargo[Fleet.CARGO_FUEL] = Movement.fuel_capacity(gift, owner, content)
	TurnMessages.add(
		state,
		content,
		fleet.owner,
		"message.trader.ships",
		{"fleet": gift.number, "owner": gift.owner},
		[word, n]
	)
	return gift


static func _same_design(a: Design, b: Design) -> bool:
	if a.hull != b.hull or a.parts.size() != b.parts.size():
		return false
	for i in a.parts.size():
		if a.parts[i].part != b.parts[i].part or a.parts[i].count != b.parts[i].count:
			return false
	return true


## S18 "Planets trading": computer players of level 2 and up trade from starbase planets.
static func _meet_planets(
	state: GameState, content: ContentRegistry, rng: StarsRandom, trader: Trader
) -> void:
	for planet in state.planets:
		if planet.owner < 0 or planet.starbase == null or trader.met.has(planet.owner):
			continue
		var owner := state.player(planet.owner)
		if owner.is_human() or owner.ai_level < AI_LEVEL_TRADING:
			continue
		var dx := planet.x - trader.x
		if dx > PLANET_REACH:
			break
		var dy := planet.y - trader.y
		if dx * dx + dy * dy > PLANET_REACH * PLANET_REACH:
			continue
		var minerals := planet.surface[0] + planet.surface[1] + planet.surface[2]
		var price: int = AI_MINERALS[0 if owner.ai_level == AI_LEVEL_TRADING else 1]
		if minerals < price:
			continue
		var item := trader.item
		var found := false
		if item != RESEARCH:
			var rolls := 0
			while _has(owner, item) and rolls < PLANET_TRIES:
				rolls += 1
				item = item_of(content, rng.random(ITEM_BITS))
			found = rolls < PLANET_TRIES
		if found:
			_add(owner, item)
			_mark_met(trader, planet.owner)
			_take(planet, minerals)
			continue
		var total := 0
		for level in owner.tech_levels:
			total += level
		if total >= PLANET_TECH_LIMIT:
			continue
		for i in PLANET_LEVELS:
			owner.tech_levels[ResearchRules.lowest_field(owner)] += 1
		_mark_met(trader, planet.owner)
		_take(planet, price)


## Takes `amount` kT of surface minerals, germanium first.
static func _take(planet: Planet, amount: int) -> void:
	for m in [2, 1, 0]:
		var take := mini(planet.surface[m], amount)
		planet.surface[m] -= take
		amount -= take
		if amount <= 0:
			return


static func _mark_met(trader: Trader, player: int) -> void:
	if not trader.met.has(player):
		trader.met.append(player)
		trader.met.sort()


## The absorbed fleet's "completed its orders" message goes (`RemoveMessages`).
static func _remove_completed(state: GameState, fleet: Fleet) -> void:
	if fleet.owner >= state.messages.size():
		return
	var kept := []
	for m: Dictionary in state.messages[fleet.owner]:
		var g: Dictionary = m.goto
		var same: bool = g.get("fleet", -1) == fleet.number and g.get("owner", -1) == fleet.owner
		if m.type == "message.fleet.completed" and same:
			continue
		kept.append(m)
	state.messages[fleet.owner] = kept


static func _announce(
	state: GameState, content: ContentRegistry, p: int, type: String, t: Trader
) -> void:
	TurnMessages.add(state, content, p, type, {"trader": t.number}, [object_word(t)])
