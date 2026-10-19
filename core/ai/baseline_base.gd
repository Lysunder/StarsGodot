class_name BaselineBase
extends AiPlayer
## What the baseline brain (BaselineAi, spec S22 "The baseline brain") works with: its
## constants, the turn's working state, and the helpers its decisions share (recognising its
## ships, distances and warps, planets with docks and people, design choices and quotas).

## The settings personalities give this brain (spec S22 "Personality settings"): key, group,
## range and default; names and descriptions are in the language files (`ai_setting.<key>`).
const SETTINGS := [
	{"key": "research_pct", "group": "research", "min": 0, "max": 100, "default": 15},
	{"key": "scouts", "group": "expansion", "min": 0, "max": 20, "default": 3},
	{"key": "colony_ships", "group": "expansion", "min": 0, "max": 20, "default": 2},
	{"key": "colony_min_population", "group": "expansion", "min": 0, "max": 10000, "default": 150},
	{"key": "colonists_share_pct", "group": "expansion", "min": 1, "max": 100, "default": 25},
	{"key": "min_value", "group": "expansion", "min": 1, "max": 100, "default": 5},
	{"key": "dock_min_population", "group": "economy", "min": 0, "max": 10000, "default": 300},
	{"key": "dock_spacing", "group": "economy", "min": 0, "max": 2000, "default": 200},
	{"key": "defense_min_population", "group": "economy", "min": 0, "max": 10000, "default": 50},
	{"key": "haul_turn", "group": "economy", "min": 0, "max": 1000, "default": 30},
	{"key": "haulers", "group": "economy", "min": 0, "max": 20, "default": 1},
	{"key": "war_turn", "group": "military", "min": 0, "max": 1000, "default": 40},
	{"key": "warships", "group": "military", "min": 0, "max": 50, "default": 3},
	{"key": "bombers", "group": "military", "min": 0, "max": 50, "default": 2},
	{"key": "transports", "group": "military", "min": 0, "max": 20, "default": 1},
	{"key": "warship_min_population", "group": "military", "min": 0, "max": 10000, "default": 300},
	{"key": "attack_ships", "group": "military", "min": 1, "max": 100, "default": 5},
	{"key": "defense_range", "group": "military", "min": 0, "max": 1000, "default": 60},
	{"key": "attack_margin_pct", "group": "military", "min": 0, "max": 1000, "default": 150},
	{"key": "invasion_report_age", "group": "military", "min": 0, "max": 100, "default": 1},
	{"key": "invasion_max_years", "group": "military", "min": 1, "max": 100, "default": 10},
]
const AUTO_FACTORIES := "production_item.auto_factories"
const AUTO_MINES := "production_item.auto_mines"
const AUTO_DEFENSES := "production_item.auto_defenses"
const AUTO_TERRAFORM := "production_item.auto_max_terraform"
## Habitability (percent) at which a planet needs no terraforming.
const FULL_VALUE := 100
const AUTO_COUNT := 200
const COLONIZER_TAG := "colonizer"
## One more colony ship allowed per this many planets owned, one more scout per PLANETS_PER_SCOUT.
const COLONIES_PER_SHIP := 3
const PLANETS_PER_SCOUT := 5
const WARSHIPS_PER_PLANETS := 2
const BOMBERS_PER_PLANETS := 3
const TRANSPORTS_PER_PLANETS := 8
const HAULERS_PER_PLANETS := 6
## Hulls that make another player's fleet a threat.
const THREAT_HULLS := [
	"hull.frigate",
	"hull.destroyer",
	"hull.cruiser",
	"hull.battle_cruiser",
	"hull.battleship",
	"hull.dreadnought",
	"hull.privateer",
	"hull.rogue",
	"hull.galleon",
	"hull.mini_bomber",
	"hull.b_17_bomber",
	"hull.stealth_bomber",
	"hull.b_52_bomber",
]
## Troops sent: enough for the estimate's upper end (+1/8) times this margin, in percent.
const TROOP_MARGIN_PCT := 130
## Troops added per year the transport needs to get there, compounded, in percent (the planet
## grows meanwhile).
const GROWTH_PER_YEAR_PCT := 12
## A new warship design is saved when it is this many percent as strong as the best one.
const WARSHIP_BETTER_PCT := 130
## The working memory (S11 `ai_memory`): word 0 the bytes in use (itself included), word 1 the
## players met in battle, one bit each.
const MEMORY_BYTES := 4
const HOSTILE_WORD := 1
const FRIEND := "friend"
const ENEMY := "enemy"
## Research fields in the order the brain raises them when levels are equal.
const FIELD_PRIORITY := [
	"tech_field.propulsion",
	"tech_field.construction",
	"tech_field.biotech",
	"tech_field.energy",
	"tech_field.electronics",
	"tech_field.weapons",
]

var _ctx: AiContext
var _state: GameState
var _me: Player
## Planet ids the player's colony ships are already heading for, and the scouts' destinations.
var _colony_targets := {}
var _scout_targets := {}
var _designs: BaselineDesigns
## This turn's new design slots by kind, and ships of each kind added to queues this turn.
var _new_designs := {}
## This turn's new designs by slot (not in the state until the orders apply).
var _made := {}
var _planned := {}
## Planets given a dock this turn.
var _planned_docks: Array[Planet] = []
## Fleets merged into another this turn.
var _merged := {}
## The player's planets with another player's war fleet within `defense_range`, nearest home first.
var _threatened: Array[Planet] = []
## Planets troop transports are heading for.
var _invasion_targets := {}
## This turn's new dock design, or null.
var _new_dock: Design = null
var _owned_planets := 0
## Planets the player has never scanned.
var _unknown_planets := 0
## The relations the player keeps this turn (after `_update_relations`), one per player.
var _relations: Array[String] = []
## Planet details from the view, by id, read once per turn.
var _infos := {}


func _info(id: int) -> Dictionary:
	if not _infos.has(id):
		_infos[id] = _ctx.view.planet_info(id)
	return _infos[id]


static func _item(id: String, count: int) -> Dictionary:
	return {"item": id, "design": -1, "starbase": false, "count": count, "progress": 0}


static func _design_item(slot: int, count: int) -> Dictionary:
	return {"item": "", "design": slot, "starbase": false, "count": count, "progress": 0}


func _design_of(fleet: Fleet, stack: ShipStack) -> Design:
	return _state.player(fleet.owner).ship_design(stack.design)


func _is_colony_fleet(fleet: Fleet) -> bool:
	for stack in fleet.stacks:
		if _is_colony_design(_design_of(fleet, stack)):
			return true
	return false


func _is_colony_design(d: Design) -> bool:
	if d == null:
		return false
	for slot in d.parts:
		if (
			not slot.part.is_empty()
			and _ctx.content.part(slot.part).get("tags", []).has(COLONIZER_TAG)
		):
			return true
	return false


## A scout: scout hulls only, without weapons.
func _is_scout(fleet: Fleet) -> bool:
	for stack in fleet.stacks:
		if not _is_scout_design(_design_of(fleet, stack)):
			return false
	return not fleet.stacks.is_empty()


func _is_scout_design(d: Design) -> bool:
	if d == null or d.hull != "hull.scout":
		return false
	for slot in d.parts:
		if slot.part.is_empty():
			continue
		var category: String = _ctx.content.part(slot.part)["category"]
		if category in ["beam", "torpedo", "bomb"]:
			return false
	return true


func _busy(fleet: Fleet) -> bool:
	return fleet.waypoints.size() > 1


func _cargo_room(fleet: Fleet) -> int:
	var room := 0
	for stack in fleet.stacks:
		room += PartRules.cargo_capacity(_design_of(fleet, stack), _ctx.content) * stack.count
	for c in Fleet.CARGO_COLONISTS + 1:
		room -= fleet.cargo[c]
	return maxi(room, 0)


## A fleet of warships and bombers only.
func _is_war_fleet(fleet: Fleet) -> bool:
	for stack in fleet.stacks:
		var d := _design_of(fleet, stack)
		if not _is_warship_design(d) and not _is_bomber_design(d):
			return false
	return not fleet.stacks.is_empty()


## Another player's fleet with ships on a combat or bomber hull (the hull is what a sighting shows).
func _looks_armed(fleet: Fleet) -> bool:
	var owner := _state.player(fleet.owner)
	for stack in fleet.stacks:
		var d := owner.ship_design(stack.design)
		if d != null and THREAT_HULLS.has(d.hull):
			return true
	return false


## The player's relation to player `q` this turn ("neutral" when it has none).
func _relation(q: int) -> String:
	if q < _relations.size():
		return _relations[q]
	return _me.relations[q] if q < _me.relations.size() else "neutral"


## Whether the player treats player `q` as an enemy (attacks its planets, invades them).
func _is_enemy(q: int) -> bool:
	return q >= 0 and q != _me.index and _relation(q) == ENEMY


## What the player's view holds of another player's design: FULL when it knows it in full.
func _design_level(owner: int, slot: int, starbase: bool) -> int:
	if _me.index >= _state.views.size() or not _state.views[_me.index] is Dictionary:
		return 0
	var key := "starbase_designs" if starbase else "designs"
	return int(_state.views[_me.index].get(key, {}).get("%d/%d" % [owner, slot], 0))


## A fleet's strength: its ships' design strengths (the player's own designs in full).
func _fleet_strength(fleet: Fleet) -> int:
	var total := 0
	for stack in fleet.stacks:
		var d := _design_of(fleet, stack)
		if d != null:
			total += _designs.strength(d) * stack.count
	return total


## What the player can tell of the strength at a planet of another player: its starbase (as the
## planet history knows it) and the owner's armed fleets seen this turn within `defense_range`,
## each design estimated (`BaselineDesigns.estimate`).
func _enemy_strength(planet: Planet) -> int:
	var info := _info(planet.id)
	var owner: int = info["owner"]
	if owner < 0:
		return 0
	var total := 0
	var base := int(info.get("starbase_design", -1))
	if base >= 0:
		var d := _state.player(owner).starbase_design(base)
		total += _designs.estimate(d, _design_level(owner, base, true) >= Scanning.FULL)
	if _me.index >= _state.views.size() or not _state.views[_me.index] is Dictionary:
		return total
	var reach := _ctx.param("defense_range")
	for key: String in _state.views[_me.index].get("fleets", {}):
		var parts := key.split("/")
		var fleet := _state.fleet(int(parts[0]), int(parts[1]))
		if fleet == null or fleet.owner != owner:
			continue
		if _d2(fleet.x, fleet.y, planet.x, planet.y) > reach * reach:
			continue
		for stack in fleet.stacks:
			var d := _design_of(fleet, stack)
			if d == null:
				continue
			var full := _design_level(owner, d.slot, false) >= Scanning.FULL
			if full or THREAT_HULLS.has(d.hull):
				total += _designs.estimate(d, full) * stack.count
	return total


## Whether a fleet of strength `ours` may attack where the enemy has `theirs`: by the margin.
func _strong_enough(ours: int, theirs: int) -> bool:
	return ours * 100 >= theirs * _ctx.param("attack_margin_pct")


func _is_threatened(planet_id: int) -> bool:
	for planet in _threatened:
		if planet.id == planet_id:
			return true
	return false


func _is_transport(fleet: Fleet) -> bool:
	for stack in fleet.stacks:
		if not _is_transport_design(_design_of(fleet, stack)):
			return false
	return not fleet.stacks.is_empty()


## Colonists (kT) moved by hand between the fleet and the planet: positive loads, negative lands.
func _transfer(fleet: Fleet, planet: Planet, colonists: int) -> void:
	(
		_ctx
		. order(
			{
				"type": "cargo_transfer",
				"fleet": fleet.number,
				"other": {"planet": planet.id},
				"amounts": [0, 0, 0, colonists, 0],
			}
		)
	)


## The player's planet nearest the fleet with people to spare, -1 for none.
func _nearest_populated(fleet: Fleet) -> int:
	var best := -1
	var best_d2 := 0
	for planet in _state.planets:
		if planet.owner != _me.index or planet.population < _ctx.param("colony_min_population"):
			continue
		var d2 := _d2(fleet.x, fleet.y, planet.x, planet.y)
		if best < 0 or d2 < best_d2:
			best = planet.id
			best_d2 = d2
	return best


## The player's planet nearest a point with a starbase that refuels (a dock), or null; with
## `planned`, the docks queued this turn count too.
func _nearest_dock(x: int, y: int, planned: bool = false) -> Planet:
	var best: Planet = null
	var best_d2 := 0
	for planet in _state.planets:
		if not _has_dock(planet) and not (planned and _planned_docks.has(planet)):
			continue
		var d2 := _d2(x, y, planet.x, planet.y)
		if best == null or d2 < best_d2:
			best = planet
			best_d2 = d2
	return best


func _has_dock(planet: Planet) -> bool:
	if planet.owner != _me.index or planet.starbase == null:
		return false
	var base := _me.starbase_design(planet.starbase.design)
	return base != null and int(_ctx.content.hull(base.hull).get("dock", 0)) != 0


## Sends the fleet to a planet (its only waypoint after where it is) with a task, at `warp`, or
## (0) the fastest its fuel allows for the way there (at least 1).
func _go(fleet: Fleet, planet_id: int, task: String, warp: int = 0) -> void:
	var planet := _state.planet(planet_id)
	if warp <= 0:
		warp = maxi(_warp_for(fleet, planet), 1)
	var wp := _waypoint_to(planet, task, warp)
	_ctx.order({"type": "waypoint_add", "fleet": fleet.number, "index": 1, "waypoint": wp})


static func _waypoint_to(planet: Planet, task: String, warp: int) -> Dictionary:
	return {
		"x": planet.x,
		"y": planet.y,
		"target": "planet",
		"target_owner": -1,
		"target_id": planet.id,
		"warp": warp,
		"task": task,
		"task_data": {},
	}


## The fastest warp, from the fleet's default down, whose fuel range covers the way to the
## planet; 0 when it can't get there at all.
func _warp_for(fleet: Fleet, planet: Planet) -> int:
	return _warp_covering(fleet, _distance(fleet.x, fleet.y, planet.x, planet.y))


func _warp_covering(fleet: Fleet, distance: int) -> int:
	var top := Retargeting.default_warp(fleet, _me, _ctx.content)
	for warp in range(top, 0, -1):
		if Movement.fuel_range(fleet, _me, warp, _ctx.content) >= distance:
			return warp
	return 0


## Light-years between two points, rounded up.
static func _distance(x1: int, y1: int, x2: int, y2: int) -> int:
	return ceili(sqrt(float(_d2(x1, y1, x2, y2))))


static func _d2(x1: int, y1: int, x2: int, y2: int) -> int:
	return (x1 - x2) * (x1 - x2) + (y1 - y2) * (y1 - y2)


func _best_transport() -> Design:
	var best: Design = null
	for d in _me.ship_designs:
		if not _is_transport_design(d):
			continue
		if best == null or _designs.cargo(d) >= _designs.cargo(best):
			best = d
	return best


## Our troop transports: the design name marks them (other freighters are left alone).
func _is_transport_design(d: Design) -> bool:
	return _is_freighter_named(d, BaselineDesigns.TRANSPORT)


func _is_hauler_design(d: Design) -> bool:
	return _is_freighter_named(d, BaselineDesigns.HAULER)


func _is_freighter_named(d: Design, kind: String) -> bool:
	return (
		d != null
		and d.name == BaselineDesigns.NAMES[kind]
		and BaselineDesigns.FREIGHTER_HULLS.has(d.hull)
	)


func _is_hauler(fleet: Fleet) -> bool:
	for stack in fleet.stacks:
		if not _is_hauler_design(_design_of(fleet, stack)):
			return false
	return not fleet.stacks.is_empty()


## The best design passing `test` by cargo room (the newest on ties), or null.
func _best_freighter(test: Callable) -> Design:
	var best: Design = null
	for d in _me.ship_designs:
		if test.call(d) and (best == null or _designs.cargo(d) >= _designs.cargo(best)):
			best = d
	return best


func _best_bomber() -> Design:
	var best: Design = null
	for d in _me.ship_designs:
		if not _is_bomber_design(d):
			continue
		if best == null or _designs.bomb_power(d) >= _designs.bomb_power(best):
			best = d
	return best


func _is_bomber_design(d: Design) -> bool:
	return d != null and _designs.bomb_power(d) > 0 and not _designs.is_armed(d)


## The player's strongest armed ship design that is not a scout (the newest on ties), or null.
func _best_warship() -> Design:
	var best: Design = null
	for d in _me.ship_designs:
		if not _is_warship_design(d):
			continue
		if best == null or _designs.strength(d) >= _designs.strength(best):
			best = d
	return best


func _is_warship_design(d: Design) -> bool:
	return _designs.is_armed(d) and not _is_scout_design(d) and not _is_colony_design(d)


## The player's dock design (this turn's new one first), the cheapest if several, or null.
func _dock_design() -> Design:
	if _new_dock != null:
		return _new_dock
	var best: Design = null
	for d in _me.starbase_designs:
		if not _designs.is_dock(d):
			continue
		var cost := int(_ctx.content.hull(d.hull).get("cost", {}).get("resources", 0))
		if (
			best == null
			or cost < int(_ctx.content.hull(best.hull).get("cost", {}).get("resources", 0))
		):
			best = d
	return best


func _free_slot(taken: Dictionary) -> int:
	var limit := _ctx.content.constant("constant.limits.ship_designs")
	for slot in limit:
		if _me.ship_design(slot) == null and not taken.has(slot):
			return slot
	return -1


func _test(kind: String) -> Callable:
	match kind:
		BaselineDesigns.SCOUT:
			return _is_scout_design
		BaselineDesigns.WARSHIP:
			return _is_warship_design
		BaselineDesigns.BOMBER:
			return _is_bomber_design
		BaselineDesigns.TRANSPORT:
			return _is_transport_design
		BaselineDesigns.HAULER:
			return _is_hauler_design
	return _is_colony_design


## The player's best design of `kind` (the newest on ties), or null.
func _best_design(kind: String) -> Design:
	var best: Design = null
	for d in _me.ship_designs:
		if _test(kind).call(d) and (best == null or not _designs.better(best, d, false)):
			best = d
	return best


## The slot production uses for `kind`: this turn's new design, else the best one; -1 for none.
func _design_slot(kind: String) -> int:
	if _new_designs.has(kind):
		return _new_designs[kind]
	var d: Design = null
	match kind:
		BaselineDesigns.WARSHIP:
			d = _best_warship()
		BaselineDesigns.BOMBER:
			d = _best_bomber()
		BaselineDesigns.TRANSPORT:
			d = _best_transport()
		BaselineDesigns.HAULER:
			d = _best_freighter(_is_hauler_design)
		_:
			d = _best_design(kind)
	return d.slot if d != null else -1


## Whether the planet has the minerals for one ship of the design on its surface now (a ship
## waiting for minerals would hold up the player's quota).
func _affords(planet: Planet, slot: int) -> bool:
	return _affords_design(planet, _made.get(slot, _me.ship_design(slot)))


func _affords_design(planet: Planet, d: Design) -> bool:
	var cost := ProductionCosts.design_cost(d, _me, _ctx.content)
	for m in 3:
		if planet.surface[m] < cost[m]:
			return false
	return true


func _hauler_quota() -> int:
	return _ctx.param("haulers") + _owned_planets / HAULERS_PER_PLANETS


func _transport_quota() -> int:
	return _ctx.param("transports") + _owned_planets / TRANSPORTS_PER_PLANETS


func _bomber_quota() -> int:
	return _ctx.param("bombers") + _owned_planets / BOMBERS_PER_PLANETS


func _warship_quota() -> int:
	return _ctx.param("warships") + _owned_planets / WARSHIPS_PER_PLANETS


func _colony_quota() -> int:
	return _ctx.param("colony_ships") + _owned_planets / COLONIES_PER_SHIP


func _scout_quota() -> int:
	return _ctx.param("scouts") + _owned_planets / PLANETS_PER_SCOUT


## Same items and counts in the same order (progress aside).
func _same_queue(planet: Planet, items: Array) -> bool:
	if planet.queue.size() != items.size():
		return false
	for i in items.size():
		var q := planet.queue[i]
		var want: Dictionary = items[i]
		if q.item != want["item"] or q.design != want["design"] or q.count != want["count"]:
			return false
		if q.starbase != want["starbase"]:
			return false
	return true


## Ships of a kind the player has or is building: its fleets of that kind, the ones queued on its
## other planets, and the ones planned this turn (`planet`'s own queue is being replanned).
func _ships(kind: String, planet: Planet) -> int:
	var fleet_test := _is_colony_fleet
	if kind == BaselineDesigns.SCOUT:
		fleet_test = _is_scout
	elif kind == BaselineDesigns.WARSHIP or kind == BaselineDesigns.BOMBER:
		fleet_test = _is_war_fleet
	elif kind == BaselineDesigns.TRANSPORT:
		fleet_test = _is_transport
	elif kind == BaselineDesigns.HAULER:
		fleet_test = _is_hauler
	var design_test := _test(kind)
	var n := 0
	for fleet in _state.fleets_of(_me.index):
		if not fleet_test.call(fleet):
			continue
		if kind == BaselineDesigns.WARSHIP or kind == BaselineDesigns.BOMBER:
			for stack in fleet.stacks:
				if design_test.call(_design_of(fleet, stack)):
					n += stack.count
		else:
			n += 1
	for other in _state.planets:
		if other.owner != _me.index or other == planet:
			continue
		for q in other.queue:
			if q.is_design() and not q.starbase and design_test.call(_me.ship_design(q.design)):
				n += q.count
	return n + int(_planned.get(kind, 0))
