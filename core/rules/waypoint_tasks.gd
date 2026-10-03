class_name WaypointTasks
extends RefCounted
## Waypoint tasks (spec S11): the four task passes, and resolving colonization (S17).
##
## Built so far: transport to and from the fleet owner's own planet (load all, unload all, load n,
## unload n; minerals and colonists), colonize, and colonizing empty planets. Other tasks and
## transport partners wait for their specs; they are skipped with a warning.

const CARGO_COLONISTS := 3
const COLONIZER_TAG := "colonizer"
const MINERAL_RETURN := [3, 4]
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
			"none", "patrol", "route":
				pass
			_:
				push_warning("waypoint task %s is not implemented yet" % wp.task)


func _transport(fleet: Fleet, wp: Waypoint, loading: bool) -> void:
	var planet := _state.planet(fleet.planet) if fleet.planet >= 0 else null
	if planet == null or planet.owner != fleet.owner:
		push_warning("transport other than at the owner's own planet is not implemented yet")
		return
	var cargo: Array = wp.task_data.get("cargo", [])
	var owner := _state.player(fleet.owner)
	for c in mini(cargo.size(), Fleet.CARGO_FUEL):
		var action: String = cargo[c].get("action", "none")
		var amount: int = cargo[c].get("amount", 0)
		var have := fleet.cargo[c]
		var there := planet.population if c == CARGO_COLONISTS else planet.surface[c]
		var space := _cargo_space(fleet, owner)
		var moved := 0
		match action:
			"load_all":
				if loading:
					moved = mini(there, space)
			"load":
				if loading:
					moved = mini(amount, mini(there, space))
			"unload_all":
				if not loading:
					moved = -have
			"unload":
				if not loading:
					moved = -mini(amount, have)
			"none":
				pass
			_:
				push_warning("transport action %s is not implemented yet" % action)
		if moved == 0:
			continue
		fleet.cargo[c] += moved
		if c == CARGO_COLONISTS:
			planet.population -= moved
		else:
			planet.surface[c] -= moved
	if loading:
		_task_done(wp)


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
	var cost: Array[int] = [0, 0, 0]
	for stack in fleet.stacks:
		if stack.count <= 0:
			continue
		var design := owner.ship_design(stack.design)
		for slot in design.parts:
			if not slot.part.is_empty() and slot.count > 0:
				if (_content.part(slot.part).get("tags", []) as Array).has(COLONIZER_TAG):
					colonizer = true
		var each := ProductionCosts.design_cost(design, owner, _content)
		for m in 3:
			cost[m] += stack.count * each[m]
	if not colonizer:
		return
	for m in 3:
		planet.surface[m] += cost[m] * MINERAL_RETURN[0] / MINERAL_RETURN[1] + fleet.cargo[m]
	_pending.append(Colonization.new(fleet.owner, planet.id, fleet.cargo[CARGO_COLONISTS]))
	for stack in fleet.stacks:
		owner.ship_design(stack.design).remaining -= stack.count
	_state.remove_fleet(fleet)


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
	planet.owner = player
	planet.population = population
	if planet.artifact != null:
		planet.artifact = null
		if not _state.settings.no_random_events:
			var field := _rng.random(ARTIFACT_FIELDS)
			var points := ARTIFACT_MIN + _rng.random(ARTIFACT_RANGE)
			if population < ARTIFACT_FULL_POPULATION:
				points = population * points / ARTIFACT_FULL_POPULATION
			_state.player(player).research_points[field] += points
