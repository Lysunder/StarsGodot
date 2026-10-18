class_name Routes
extends RefCounted
## Routes and default orders (spec S11 "Route"): a fleet idle at a planet with a route, or newly
## built there (S09), gets a waypoint at the route's destination; other idle fleets with mining
## robots get the remote mining or merge task.

## With a dock at the destination the warp is chosen from this one down by fuel range.
const DOCK_WARP := 9
## The lowest warp the ease-off step comes down to.
const EASE_MIN := 2
## The route distance is rounded up by this, then truncated.
const DISTANCE_ROUND_UP := 0.999
const DEFAULT_PLAN := 0


## `Fleet_FollowRoute@1078:13f8`: the fleet gets a second waypoint at `planet`'s route destination
## with the route task; returns the warp chosen (0: not enough fuel to go).
static func follow(state: GameState, content: ContentRegistry, fleet: Fleet, planet: Planet) -> int:
	var destination := state.planet(planet.route)
	var owner := state.player(fleet.owner)
	var wp := Waypoint.new(destination.x, destination.y)
	wp.target = "planet"
	wp.target_id = destination.id
	wp.task = "route"
	# no task data (S11; the original's five data words are zero for a fresh waypoint)
	wp.task_data = {"raw": [0, 0, 0, 0, 0]}
	fleet.waypoints.resize(1)
	fleet.waypoints.append(wp)
	var warp := Retargeting.default_warp(fleet, owner, content)
	var d := int(Vector2(fleet.x, fleet.y).distance_to(Vector2(wp.x, wp.y)) + DISTANCE_ROUND_UP)
	if (
		destination.owner == planet.owner
		and planet.starbase != null
		and destination.starbase != null
	):
		if _can_gate(state, content, fleet, owner, planet, destination, d):
			warp = Waypoint.WARP_STARGATE
		if warp < DOCK_WARP and _has_dock(state, content, destination):
			warp = DOCK_WARP
			while warp > 0 and Movement.fuel_range(fleet, owner, warp, content) < d:
				warp -= 1
	if warp > 0 and warp < Waypoint.WARP_STARGATE:
		var q := d / warp / warp
		while warp > EASE_MIN and d / (warp - 1) / (warp - 1) <= q:
			warp -= 1
		var fuel := fleet.cargo[Fleet.CARGO_FUEL]
		while warp > 0 and Movement.fuel_needed(fleet, owner, warp, d, content) > fuel:
			warp -= 1
	wp.warp = warp
	return warp


## An empty fleet jumps between the two starbases' gates when the jump would lose 0% of the
## heaviest design (S12 "Stargates").
static func _can_gate(
	state: GameState,
	content: ContentRegistry,
	fleet: Fleet,
	owner: Player,
	source: Planet,
	destination: Planet,
	d: int
) -> bool:
	for c in Fleet.CARGO_FUEL:
		if fleet.cargo[c] != 0:
			return false
	var from := Stargates.gate(state, content, source)
	var to := Stargates.gate(state, content, destination)
	if from.is_empty() or to.is_empty():
		return false
	var heaviest := 0
	for stack in fleet.stacks:
		if stack.count != 0:
			heaviest = maxi(heaviest, PartRules.mass(owner.ship_design(stack.design), content))
	return Stargates.damage_percent(from, to, d, heaviest) == 0


static func _has_dock(state: GameState, content: ContentRegistry, planet: Planet) -> bool:
	var base := state.player(planet.owner).starbase_design(planet.starbase.design)
	return base != null and int(content.hull(base.hull).get("dock", 0)) != 0


## `Fleet_SetDefaultOrders@1078:17c2`: a fleet with mining robots at an unowned planet merges into
## a miner fleet already there, or remote-mines (also at an Alternate Reality race's own planet);
## the battle plan becomes the default. Returns the merge target, or null.
static func default_orders(
	state: GameState, content: ContentRegistry, fleet: Fleet, planet: Planet
) -> Fleet:
	fleet.battle_plan = DEFAULT_PLAN
	var owner := state.player(fleet.owner)
	var lives_in_space := RaceMath.trait_param(owner.race, content, "colony.starbase", 0) != 0
	if planet.owner >= 0 and not (lives_in_space and planet.owner == fleet.owner):
		return null
	if WaypointTasks.mining_rate(fleet, owner, content) <= 0:
		return null
	var wp := fleet.waypoints[0]
	if planet.owner < 0:
		for other in state.fleets_of(fleet.owner):
			if other == fleet or other.ship_count() == 0:
				continue
			if other.x != fleet.x or other.y != fleet.y:
				continue
			var rate := WaypointTasks.mining_rate(other, owner, content)
			if rate > 0 and rate < WaypointTasks.MINING_RATE_MAX:
				wp.task = "merge"
				wp.target = "fleet"
				wp.target_owner = other.owner
				wp.target_id = other.number
				return other
	wp.task = "remote_mine"
	# the original stores the task's five data words, all zero
	if not wp.task_data.has("raw"):
		wp.task_data = {"raw": [0, 0, 0, 0, 0]}
	return null
