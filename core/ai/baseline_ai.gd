class_name BaselineAi
extends AiPlayer
## Our own computer player (spec S22 "The baseline brain"), first part: it grows an economy and
## spreads out. Each turn, in this order: research settings, the default queue for new colonies,
## colony ships and scouts already built (orders to the fleets), then each planet's queue. It
## reads only its view (its own things, and other planets as it knows them) and draws nothing.
##
## Parameters (personality `params`, per level in `levels`), with their defaults:
## research_pct 15, scouts 3, colony_ships 2, colony_min_population 150 (units of 100 colonists a
## planet needs before it builds ships), colonists_share_pct 25 (of the planet's people a colony
## ship takes, up to its room), min_value 5 (lowest habitability worth settling).

const AUTO_FACTORIES := "production_item.auto_factories"
const AUTO_MINES := "production_item.auto_mines"
const AUTO_COUNT := 200
const COLONIZER_TAG := "colonizer"
## One more colony ship allowed per this many planets owned, one more scout per PLANETS_PER_SCOUT.
const COLONIES_PER_SHIP := 3
const PLANETS_PER_SCOUT := 5
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
var _owned_planets := 0
## Planets the player has never scanned.
var _unknown_planets := 0
## Planet details from the view, by id, read once per turn.
var _infos := {}


func play(ctx: AiContext) -> void:
	_ctx = ctx
	_state = ctx.view.state
	_me = ctx.me()
	_designs = BaselineDesigns.new(ctx.view, ctx.content)
	_count_planets()
	_research()
	if _state.turn == 0:
		_defaults()
	_update_designs()
	_note_destinations()
	for fleet in _state.fleets_of(_me.index):
		if _is_colony_fleet(fleet):
			_send_colony_ship(fleet)
		elif _is_scout(fleet):
			_send_scout(fleet)
	for planet in _state.planets:
		if planet.owner == _me.index:
			_plan_queue(planet)


func _info(id: int) -> Dictionary:
	if not _infos.has(id):
		_infos[id] = _ctx.view.planet_info(id)
	return _infos[id]


func _count_planets() -> void:
	for planet in _state.planets:
		if planet.owner == _me.index:
			_owned_planets += 1
		elif not _info(planet.id)["known"]:
			_unknown_planets += 1


# --- Research -------------------------------------------------------------------------------


## The research budget, and the field: the lowest level, ties by FIELD_PRIORITY.
func _research() -> void:
	var order := PartRules.tech_order(_ctx.content)
	var best := -1
	for field: String in FIELD_PRIORITY:
		var i: int = order[field]
		if best < 0 or _me.tech_levels[i] < _me.tech_levels[best]:
			best = i
	var percent := _ctx.param("research_pct", 15)
	if (
		_me.research_percent == percent
		and _me.research_field == best
		and _me.next_research_field == Player.NEXT_FIELD_LOWEST
	):
		return
	_ctx.order(
		{"type": "research", "percent": percent, "field": best, "next": Player.NEXT_FIELD_LOWEST}
	)


## New colonies build factories and mines.
func _defaults() -> void:
	(
		_ctx
		. order(
			{
				"type": "player_defaults",
				"leftover_to_research": false,
				"queue": [_item(AUTO_FACTORIES, AUTO_COUNT), _item(AUTO_MINES, AUTO_COUNT)],
			}
		)
	)


static func _item(id: String, count: int) -> Dictionary:
	return {"item": id, "design": -1, "starbase": false, "count": count, "progress": 0}


static func _design_item(slot: int, count: int) -> Dictionary:
	return {"item": "", "design": slot, "starbase": false, "count": count, "progress": 0}


# --- Fleets ---------------------------------------------------------------------------------


## Where the player's fleets are already going.
func _note_destinations() -> void:
	_colony_targets.clear()
	_scout_targets.clear()
	for fleet in _state.fleets_of(_me.index):
		if fleet.waypoints.size() < 2 or fleet.waypoints[-1].target != "planet":
			continue
		var target := fleet.waypoints[-1].target_id
		if _is_colony_fleet(fleet):
			_colony_targets[target] = true
		elif _is_scout(fleet):
			_scout_targets[target] = true


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


## A colony ship: load colonists where it is (the player's populated planet), then go to the best
## planet it can reach and colonize it; at its target, colonize.
func _send_colony_ship(fleet: Fleet) -> void:
	if _busy(fleet):
		return
	var here := _state.planet(fleet.planet) if fleet.planet >= 0 else null
	if here != null and here.owner < 0 and fleet.cargo[Fleet.CARGO_COLONISTS] > 0:
		_order_waypoint0_colonize(fleet, here)
		return
	if fleet.cargo[Fleet.CARGO_COLONISTS] == 0:
		if here == null or here.owner != _me.index:
			# empty away from home (its target was taken): back to the nearest planet with people
			var home := _nearest_populated(fleet)
			if home >= 0:
				_go(fleet, home, "none")
			return
		var share := here.population * _ctx.param("colonists_share_pct", 25) / 100
		var load := mini(_cargo_room(fleet), share)
		if load <= 0:
			return
		(
			_ctx
			. order(
				{
					"type": "cargo_transfer",
					"fleet": fleet.number,
					"other": {"planet": here.id},
					"amounts": [0, 0, 0, load, 0],
				}
			)
		)
	var target := _best_colony_target(fleet)
	if target < 0:
		return
	_colony_targets[target] = true
	_go(fleet, target, "colonize")


## Colonize the unowned planet the fleet is already at (waypoint 0's task).
func _order_waypoint0_colonize(fleet: Fleet, planet: Planet) -> void:
	var wp := _waypoint_to(planet, "colonize", fleet.waypoints[0].warp)
	_ctx.order({"type": "waypoint_change", "fleet": fleet.number, "index": 0, "waypoint": wp})


func _cargo_room(fleet: Fleet) -> int:
	var room := 0
	for stack in fleet.stacks:
		room += PartRules.cargo_capacity(_design_of(fleet, stack), _ctx.content) * stack.count
	for c in Fleet.CARGO_COLONISTS + 1:
		room -= fleet.cargo[c]
	return maxi(room, 0)


## The unowned planet with the best value for the player within reach, nearest first on ties;
## -1 when none is worth it.
func _best_colony_target(fleet: Fleet) -> int:
	var best := -1
	var best_value := _ctx.param("min_value", 5) - 1
	var best_d2 := 0
	for planet in _state.planets:
		if _colony_targets.has(planet.id) or planet.owner == _me.index:
			continue
		var info := _info(planet.id)
		if not info["known"] or info["owner"] >= 0:
			continue
		var value: int = info["habitability"]
		var d2 := _d2(fleet.x, fleet.y, planet.x, planet.y)
		if value < best_value or (value == best_value and best >= 0 and d2 >= best_d2):
			continue
		if _warp_for(fleet, planet) == 0:
			continue
		best = planet.id
		best_value = value
		best_d2 = d2
	return best


## A scout goes to the nearest planet the player has not scanned and no other scout is heading
## for, if it can get there and back to a dock of its own on its fuel; otherwise it goes to the
## nearest such dock to refuel.
func _send_scout(fleet: Fleet) -> void:
	if _busy(fleet):
		return
	var best := -1
	var best_d2 := 0
	var best_warp := 0
	for planet in _state.planets:
		if _scout_targets.has(planet.id) or planet.owner == _me.index:
			continue
		if _info(planet.id)["known"]:
			continue
		var d2 := _d2(fleet.x, fleet.y, planet.x, planet.y)
		if best >= 0 and d2 >= best_d2:
			continue
		var dock := _nearest_dock(planet.x, planet.y)
		if dock == null:
			continue
		var there_and_back := (
			_distance(fleet.x, fleet.y, planet.x, planet.y)
			+ _distance(planet.x, planet.y, dock.x, dock.y)
		)
		var warp := _warp_covering(fleet, there_and_back)
		if warp == 0:
			continue
		best = planet.id
		best_d2 = d2
		best_warp = warp
	if best < 0:
		var dock := _nearest_dock(fleet.x, fleet.y)
		if dock == null or dock.id == fleet.planet:
			return
		best = dock.id
		best_warp = 0
	_scout_targets[best] = true
	_go(fleet, best, "none", best_warp)


## The player's planet nearest the fleet with people to spare, -1 for none.
func _nearest_populated(fleet: Fleet) -> int:
	var best := -1
	var best_d2 := 0
	for planet in _state.planets:
		if (
			planet.owner != _me.index
			or planet.population < _ctx.param("colony_min_population", 150)
		):
			continue
		var d2 := _d2(fleet.x, fleet.y, planet.x, planet.y)
		if best < 0 or d2 < best_d2:
			best = planet.id
			best_d2 = d2
	return best


## The player's planet nearest a point with a starbase that refuels (a dock), or null.
func _nearest_dock(x: int, y: int) -> Planet:
	var best: Planet = null
	var best_d2 := 0
	for planet in _state.planets:
		if planet.owner != _me.index or planet.starbase == null:
			continue
		var base := _me.starbase_design(planet.starbase.design)
		if base == null or int(_ctx.content.hull(base.hull).get("dock", 0)) == 0:
			continue
		var d2 := _d2(x, y, planet.x, planet.y)
		if best == null or d2 < best_d2:
			best = planet
			best_d2 = d2
	return best


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


# --- Designs ------------------------------------------------------------------------------


## A scout and a colony ship of the best parts the player has: saved in a free slot when the
## player has none of that kind, or when it is better than the best one it has (faster, or as
## fast and going BaselineDesigns.BETTER_PCT as far).
func _update_designs() -> void:
	var taken := {}
	for kind in [BaselineDesigns.SCOUT, BaselineDesigns.COLONY]:
		var made := _designs.build(kind)
		if made == null:
			continue
		var have := _best_design(kind)
		if have != null and not _designs.better(made, have):
			continue
		var slot := _free_slot(taken)
		if slot < 0:
			continue
		taken[slot] = true
		made.slot = slot
		made.turn_designed = _state.turn
		_new_designs[kind] = slot
		_made[slot] = made
		_ctx.order(
			{"type": "design_change", "starbase": false, "slot": slot, "design": made.to_dict()}
		)


func _free_slot(taken: Dictionary) -> int:
	var limit := _ctx.content.constant("constant.limits.ship_designs")
	for slot in limit:
		if _me.ship_design(slot) == null and not taken.has(slot):
			return slot
	return -1


func _test(kind: String) -> Callable:
	return _is_scout_design if kind == BaselineDesigns.SCOUT else _is_colony_design


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
	var d := _best_design(kind)
	return d.slot if d != null else -1


# --- Production -----------------------------------------------------------------------------


## A planet's queue, on planets with people to spare (`colony_min_population`): a colony ship
## while the player has fewer than `colony_ships` + one per COLONIES_PER_SHIP planets and there
## are places to settle, a scout while it has fewer than `scouts` + one per PLANETS_PER_SCOUT
## planets and planets it has never scanned; then factories and mines. Sent only when it
## differs from the planet's queue.
func _plan_queue(planet: Planet) -> void:
	var items: Array = []
	var spare := planet.population >= _ctx.param("colony_min_population", 150)
	var colony_slot := _design_slot(BaselineDesigns.COLONY)
	if (
		spare
		and colony_slot >= 0
		and _affords(planet, colony_slot)
		and _ships(BaselineDesigns.COLONY, planet) < _colony_quota()
		and _has_colony_targets()
	):
		items.append(_design_item(colony_slot, 1))
		_planned[BaselineDesigns.COLONY] = _planned.get(BaselineDesigns.COLONY, 0) + 1
	var scout_slot := _design_slot(BaselineDesigns.SCOUT)
	if (
		spare
		and scout_slot >= 0
		and _affords(planet, scout_slot)
		and _ships(BaselineDesigns.SCOUT, planet) < _scout_quota()
		and _unknown_planets > 0
	):
		items.append(_design_item(scout_slot, 1))
		_planned[BaselineDesigns.SCOUT] = _planned.get(BaselineDesigns.SCOUT, 0) + 1
	items.append(_item(AUTO_FACTORIES, AUTO_COUNT))
	items.append(_item(AUTO_MINES, AUTO_COUNT))
	if _same_queue(planet, items):
		return
	_ctx.order({"type": "production_queue", "planet": planet.id, "items": items})


## Whether the planet has the minerals for one ship of the design on its surface now (a ship
## waiting for minerals would hold up the player's quota).
func _affords(planet: Planet, slot: int) -> bool:
	var d: Design = _made.get(slot, _me.ship_design(slot))
	var cost := ProductionCosts.design_cost(d, _me, _ctx.content)
	for m in 3:
		if planet.surface[m] < cost[m]:
			return false
	return true


func _colony_quota() -> int:
	return _ctx.param("colony_ships", 2) + _owned_planets / COLONIES_PER_SHIP


func _scout_quota() -> int:
	return _ctx.param("scouts", 3) + _owned_planets / PLANETS_PER_SCOUT


## Same items and counts in the same order (progress aside).
func _same_queue(planet: Planet, items: Array) -> bool:
	if planet.queue.size() != items.size():
		return false
	for i in items.size():
		var q := planet.queue[i]
		var want: Dictionary = items[i]
		if q.item != want["item"] or q.design != want["design"] or q.count != want["count"]:
			return false
	return true


## Ships of a kind the player has or is building: its fleets of that kind, the ones queued on its
## other planets, and the ones planned this turn (`planet`'s own queue is being replanned).
func _ships(kind: String, planet: Planet) -> int:
	var fleet_test := _is_scout if kind == BaselineDesigns.SCOUT else _is_colony_fleet
	var design_test := _test(kind)
	var n := 0
	for fleet in _state.fleets_of(_me.index):
		if fleet_test.call(fleet):
			n += 1
	for other in _state.planets:
		if other.owner != _me.index or other == planet:
			continue
		for q in other.queue:
			if q.is_design() and not q.starbase and design_test.call(_me.ship_design(q.design)):
				n += q.count
	return n + int(_planned.get(kind, 0))


## Whether any known unowned planet is worth settling and not already a colony ship's target.
func _has_colony_targets() -> bool:
	for planet in _state.planets:
		if planet.owner == _me.index or _colony_targets.has(planet.id):
			continue
		var info := _info(planet.id)
		if (
			info["known"]
			and info["owner"] < 0
			and info["habitability"] >= _ctx.param("min_value", 5)
		):
			return true
	return false
