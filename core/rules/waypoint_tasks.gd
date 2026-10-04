class_name WaypointTasks
extends RefCounted
## Waypoint tasks (spec S11): the four task passes, and resolving colonization (S17).
##
## Built so far: transport to and from the fleet owner's own planet (load all, unload all, load n,
## unload n; minerals and colonists), colonize, colonizing empty planets, merge, scrap at a planet
## and transfer (with the S24 tech bonus at a starbase). Other tasks, transport partners,
## scrapping in deep space (salvage, S14) and Ultimate Recycling's resources wait for their specs;
## they warn.

const CARGO_COLONISTS := 3
const COLONIZER_TAG := "colonizer"
const MINERAL_RETURN := [3, 4]
## Minerals recovered by scrapping (S11 "Scrap"), by planet kind and Ultimate Recycling.
const SCRAP_RETURN := {
	"starbase": [4, 5],
	"starbase_recycling": [9, 10],
	"planet": [1, 3],
	"planet_recycling": [9, 20],
}
const TRANSFERRED_COST_DIVISOR := 4
const DESIGN_SLOTS := 16
const TROOPS_PCT_DEFAULT := 110
const ARTIFACT_FIELDS := 6
const ARTIFACT_MIN := 100
const ARTIFACT_RANGE := 301
const ARTIFACT_FULL_POPULATION := 10


class Colonization:
	extends RefCounted
	var player: int
	var planet: int
	var colonists: int

	func _init(p_player: int, p_planet: int, p_colonists: int) -> void:
		player = p_player
		planet = p_planet
		colonists = p_colonists


var _state: GameState
var _content: ContentRegistry
var _rng: StarsRandom
## Colonizations waiting for the next resolution (S11 "Colonize").
var _pending: Array[Colonization] = []


func _init(state: GameState, content: ContentRegistry, rng: StarsRandom) -> void:
	_state = state
	_content = content
	_rng = rng


## Pass 1 and 3 unload, pass 2 and 4 load (S11 "Passes"), at each fleet's current waypoint.
func run_pass(pass_number: int) -> void:
	var loading := pass_number % 2 == 0
	var fleets: Array[Fleet] = _state.fleets.duplicate()
	for fleet in fleets:
		if fleet.ship_count() == 0 or fleet.waypoints.is_empty():
			continue
		var wp := fleet.waypoints[0]
		match wp.task:
			"transport":
				_transport(fleet, wp, loading)
			"colonize":
				_colonize(fleet, wp)
			"merge":
				if loading:
					_merge(fleet, wp)
			"scrap":
				if pass_number == 1:
					_scrap(fleet)
			"transfer":
				if pass_number == 4:
					_transfer(fleet, wp)
			"none", "patrol", "route":
				pass
			_:
				push_warning("waypoint task %s is not implemented yet" % wp.task)


## S11 "Transport": the other side is the target fleet, the planet the fleet is at, or deep
## space. Unload actions run in passes 1 and 3 and are cleared once done; loads run in passes 2 and
## 4 and end the task. A refused colonist unload cancels the task.
func _transport(fleet: Fleet, wp: Waypoint, loading: bool) -> void:
	var other: Fleet = null
	var planet: Planet = null
	match wp.target:
		"fleet":
			other = _state.fleet(wp.target_owner, wp.target_id)
			if other == null or other == fleet or other.x != fleet.x or other.y != fleet.y:
				other = null
				if loading:
					_task_done(wp)
				return
		"planet":
			planet = _state.planet(fleet.planet) if fleet.planet >= 0 else null
		"none":
			pass
		_:
			push_warning("transport with %s (S14) is not implemented yet" % wp.target)
			return
	var cargo: Array = wp.task_data.get("cargo", [])
	for c in mini(cargo.size(), Fleet.CARGO_FUEL + 1):
		var action: String = cargo[c].get("action", "none")
		var amount: int = cargo[c].get("amount", 0)
		match action:
			"load_all", "load":
				if loading:
					var want := -1 if action == "load_all" else amount
					_load(fleet, other, planet, c, want)
			"unload_all", "unload":
				if not loading:
					var give := (
						fleet.cargo[c] if action == "unload_all" else mini(amount, fleet.cargo[c])
					)
					if not _unload(fleet, other, planet, c, give):
						_task_done(wp)
						return
					cargo[c] = {"action": "none", "amount": 0}
			"none":
				pass
			_:
				push_warning("transport action %s is not implemented yet" % action)
	if loading:
		_task_done(wp)


## Takes up to `want` (-1: all there is) of cargo type `c` from the fleet owner's own planet or
## fleet, limited by the fleet's free space. Anything else is skipped (fix B26/B15).
func _load(fleet: Fleet, other: Fleet, planet: Planet, c: int, want: int) -> void:
	var there := 0
	if other != null and other.owner == fleet.owner:
		there = other.cargo[c]
	elif planet != null and planet.owner == fleet.owner and c != Fleet.CARGO_FUEL:
		there = planet.population if c == CARGO_COLONISTS else planet.surface[c]
	else:
		return
	var moved := mini(there, _free_space(fleet, c))
	if want >= 0:
		moved = mini(moved, want)
	if moved <= 0:
		return
	fleet.cargo[c] += moved
	if other != null:
		other.cargo[c] -= moved
	elif c == CARGO_COLONISTS:
		planet.population -= moved
	else:
		planet.surface[c] -= moved


## Gives up to `amount` of cargo type `c` to the other side (S11 "Unloading"). Returns false when a
## colonist unload is refused, which cancels the task.
func _unload(fleet: Fleet, other: Fleet, planet: Planet, c: int, amount: int) -> bool:
	if other != null:
		var foreign := other.owner != fleet.owner
		if foreign and c == CARGO_COLONISTS:
			return false
		if foreign and c != Fleet.CARGO_FUEL:
			return true
		if foreign and _state.player(other.owner).relations[fleet.owner] == "enemy":
			return true
		var moved := mini(amount, _free_space(other, c))
		if moved > 0:
			fleet.cargo[c] -= moved
			other.cargo[c] += moved
		return true
	if planet == null:
		if c == CARGO_COLONISTS:
			return false
		if amount > 0:
			push_warning("jettisoning cargo in deep space (salvage, S14) is not implemented yet")
		return true
	if c == Fleet.CARGO_FUEL or amount <= 0:
		return true
	if c != CARGO_COLONISTS:
		fleet.cargo[c] -= amount
		planet.surface[c] += amount
		return true
	if planet.owner == fleet.owner:
		fleet.cargo[c] -= amount
		planet.population += amount
		return true
	var race := _state.player(fleet.owner).race
	if (
		planet.owner < 0
		or planet.starbase != null
		or RaceMath.trait_param(race, _content, "transport.no_invasion", 0)
	):
		return false
	_pending.append(Colonization.new(fleet.owner, planet.id, amount))
	fleet.cargo[c] -= amount
	return true


## Free cargo space for minerals and colonists, free fuel space for fuel.
func _free_space(fleet: Fleet, c: int) -> int:
	var owner := _state.player(fleet.owner)
	if c == Fleet.CARGO_FUEL:
		return maxi(Movement.fuel_capacity(fleet, owner, _content) - fleet.cargo[c], 0)
	return _cargo_space(fleet, owner)


func _cargo_space(fleet: Fleet, owner: Player) -> int:
	var capacity := 0
	for stack in fleet.stacks:
		var design := owner.ship_design(stack.design)
		if design != null:
			capacity += stack.count * PartRules.cargo_capacity(design, _content)
	var used := 0
	for c in Fleet.CARGO_FUEL:
		used += fleet.cargo[c]
	return maxi(capacity - used, 0)


## S11 "Colonize": the fleet is taken apart over an empty planet; its colonists are recorded for
## the next resolution.
func _colonize(fleet: Fleet, _wp: Waypoint) -> void:
	if fleet.planet < 0:
		return
	var planet := _state.planet(fleet.planet)
	if planet.owner != -1 or fleet.cargo[CARGO_COLONISTS] == 0:
		return
	var owner := _state.player(fleet.owner)
	var colonizer := false
	for stack in fleet.stacks:
		if stack.count <= 0:
			continue
		for slot in owner.ship_design(stack.design).parts:
			if not slot.part.is_empty() and slot.count > 0:
				if (_content.part(slot.part).get("tags", []) as Array).has(COLONIZER_TAG):
					colonizer = true
	if not colonizer:
		return
	var value := _ships_value(fleet, owner)
	for m in 3:
		planet.surface[m] += value[m] * MINERAL_RETURN[0] / MINERAL_RETURN[1] + fleet.cargo[m]
	_pending.append(Colonization.new(fleet.owner, planet.id, fleet.cargo[CARGO_COLONISTS]))
	_dismantle(fleet)


## The minerals the fleet's ships are worth when taken apart: per stack, ships x the design's
## cost, a quarter for transferred designs, and never more than what was paid (fix B14) when that
## is recorded.
func _ships_value(fleet: Fleet, owner: Player) -> Array[int]:
	var value: Array[int] = [0, 0, 0, 0]
	for stack in fleet.stacks:
		if stack.count <= 0:
			continue
		var design := owner.ship_design(stack.design)
		var each := ProductionCosts.design_cost(design, owner, _content)
		var recorded := stack.paid.any(func(v: int) -> bool: return v != 0)
		for m in value.size():
			var v := stack.count * each[m]
			if design.transferred:
				v /= TRANSFERRED_COST_DIVISOR
			if recorded:
				v = mini(v, stack.paid[m])
			value[m] += v
	return value


## The fleet's ships are gone: their designs' existing counts drop and the fleet is deleted.
func _dismantle(fleet: Fleet) -> void:
	var owner := _state.player(fleet.owner)
	for stack in fleet.stacks:
		owner.ship_design(stack.design).remaining -= stack.count
	FleetOrders.delete_fleet(_state, fleet, -1)


## S11 "Merge with fleet": the fleet's ships join the target fleet of waypoint 0, which must be the
## same player's, have ships and be at the same place; cargo, fuel and damage follow the ships.
func _merge(fleet: Fleet, wp: Waypoint) -> void:
	if wp.target != "fleet":
		return
	var target := _state.fleet(wp.target_owner, wp.target_id)
	if target == null or target == fleet or target.ship_count() == 0:
		return
	if target.owner != fleet.owner or target.x != fleet.x or target.y != fleet.y:
		return
	var ships := {}
	for stack in fleet.stacks:
		ships[stack.design] = stack.count
	FleetOrders.move_ships(_state, _content, target, fleet, ships, -1)


## S11 "Scrap": the fleet is taken apart at a planet; the planet gets part of the ships' minerals
## and all minerals in the cargo, and the colonists if it is the fleet owner's.
func _scrap(fleet: Fleet) -> void:
	if fleet.planet < 0:
		push_warning("scrapping in deep space (salvage, S14) is not implemented yet")
		return
	var planet := _state.planet(fleet.planet)
	var owner := _state.player(fleet.owner)
	var recycling := (
		planet.owner >= 0
		and RaceMath.trait_param(_state.player(planet.owner).race, _content, "scrap.recycling", 0)
	)
	var kind := "starbase" if planet.starbase != null else "planet"
	var ratio: Array = SCRAP_RETURN[kind + ("_recycling" if recycling else "")]
	var value := _ships_value(fleet, owner)
	for m in 3:
		planet.surface[m] += value[m] * ratio[0] / ratio[1] + fleet.cargo[m]
	if planet.owner == fleet.owner:
		planet.population += fleet.cargo[CARGO_COLONISTS]
	if recycling:
		push_warning("resources from Ultimate Recycling are not implemented yet")
	if planet.starbase != null and planet.owner >= 0:
		TechGain.try_bonus(
			_state.player(planet.owner),
			TechGain.tech_needed(fleet, owner, _content),
			_content,
			_rng
		)
	_dismantle(fleet)


## S11 "Transfer fleet": the fleet becomes a new fleet of the receiving player (task data word 0,
## counting players without the giver). Each design maps to an identical transferred design of the
## receiver, else to the receiver's next free slot as a transferred copy.
func _transfer(fleet: Fleet, wp: Waypoint) -> void:
	var words: Array = wp.task_data.get("raw", [])
	var to: int = words[0] if not words.is_empty() else 0
	if to >= fleet.owner:
		to += 1
	if to < 0 or to >= _state.players.size():
		return
	var receiver := _state.player(to)
	if not receiver.active or receiver.relations[fleet.owner] == "enemy":
		return
	if fleet.cargo[CARGO_COLONISTS] > 0:
		return
	var giver := _state.player(fleet.owner)
	var slots := {}
	var free := -1
	for stack in fleet.stacks:
		if stack.count <= 0:
			continue
		var slot := _identical_transferred(receiver, giver.ship_design(stack.design))
		if slot < 0:
			free += 1
			while free < DESIGN_SLOTS and receiver.ship_design(free) != null:
				free += 1
			if free >= DESIGN_SLOTS:
				return
			slot = free
		slots[stack.design] = slot
	var created := _state.add_fleet(to, _content.constant("constant.limits.fleets_per_player"))
	if created == null:
		return
	created.x = fleet.x
	created.y = fleet.y
	created.planet = fleet.planet
	var here := Waypoint.new(fleet.x, fleet.y)
	if fleet.planet >= 0:
		here.target = "planet"
		here.target_id = fleet.planet
	created.waypoints.append(here)
	created.cargo = fleet.cargo.duplicate()
	for stack in fleet.stacks:
		if stack.count <= 0:
			continue
		var slot: int = slots[stack.design]
		var design := receiver.ship_design(slot)
		if design == null:
			design = giver.ship_design(stack.design).copy() as Design
			design.slot = slot
			design.transferred = true
			design.built = 0
			design.remaining = 0
			receiver.set_design(design, false)
		var moved := created.add_ships(slot, stack.count)
		moved.damaged_percent = stack.damaged_percent
		moved.damage = stack.damage
		moved.paid = stack.paid.duplicate()
		design.built += stack.count
		design.remaining += stack.count
	_dismantle(fleet)


## The slot of a transferred design of the player with the same hull and parts, or -1.
static func _identical_transferred(player: Player, design: Design) -> int:
	for d in player.ship_designs:
		if not d.transferred or d.hull != design.hull or d.parts.size() != design.parts.size():
			continue
		var same := true
		for i in d.parts.size():
			var a := d.parts[i]
			var b := design.parts[i]
			if a.count != b.count or (a.count != 0 and a.part != b.part):
				same = false
				break
		if same:
			return d.slot
	return -1


static func _task_done(wp: Waypoint) -> void:
	wp.task = "none"
	wp.task_data = {}


## S02 5c and 16d: colonizations of empty planets (S17 for planets with an owner).
func resolve() -> void:
	var planets: Array[int] = []
	for c in _pending:
		if not planets.has(c.planet):
			planets.append(c.planet)
	for id in planets:
		var planet := _state.planet(id)
		if planet.owner != -1:
			push_warning("planet %d: ground combat is not implemented yet (S17)" % id)
			continue
		var colonists := {}
		var strength := {}
		for c in _pending:
			if c.planet != id:
				continue
			var race := _state.player(c.player).race
			var pct := RaceMath.trait_param(
				race, _content, "invasion.troops_pct", TROOPS_PCT_DEFAULT
			)
			colonists[c.player] = colonists.get(c.player, 0) + c.colonists
			strength[c.player] = strength.get(c.player, 0) + c.colonists * pct / 100
		var best := -1
		var top := -1
		var second := 0
		var tie := false
		for p in _state.players.size():
			if not colonists.has(p):
				continue
			var s: int = strength[p]
			if s >= top:
				if s == top:
					tie = true
				else:
					tie = false
					second = maxi(top, 0)
					top = s
					best = p
		if best < 0 or tie:
			continue
		var population: int = colonists[best]
		if second > 0:
			population = (top - second) * population / top
		_found_colony(planet, best, maxi(population, 1))
	_pending.clear()


func _found_colony(planet: Planet, player: int, population: int) -> void:
	var owner := _state.player(player)
	planet.owner = player
	planet.population = population
	planet.leftover_to_research = owner.default_leftover_to_research
	planet.queue.clear()
	for q in owner.default_queue:
		var effect: String = _content.get_def("production_item", q.item).get("effect", "")
		var skips := RaceMath.trait_param(owner.race, _content, "colony.skips_auto_" + effect, 0)
		if _content.get_def("production_item", q.item).get("auto", false) and skips:
			continue
		var copy := q.copy() as QueueItem
		copy.progress = 0
		planet.queue.append(copy)
	if RaceMath.trait_param(owner.race, _content, "colony.starbase", 0):
		planet.starbase = Starbase.new()
		var base := owner.starbase_design(0)
		if base != null:
			base.built += 1
			base.remaining += 1
	if planet.artifact != null:
		planet.artifact = null
		if not _state.settings.no_random_events:
			var field := _rng.random(ARTIFACT_FIELDS)
			var points := ARTIFACT_MIN + _rng.random(ARTIFACT_RANGE)
			if population < ARTIFACT_FULL_POPULATION:
				points = population * points / ARTIFACT_FULL_POPULATION
			_state.player(player).research_points[field] += points
