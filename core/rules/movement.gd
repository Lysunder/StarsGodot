class_name Movement
extends RefCounted
## Fleet movement and fuel (spec S12): fuel use, the move toward the next waypoint, ram scoops,
## waypoints after movement, and refueling.
##
## Trait parameters: `movement.fuel_usage_pct` (Improved Fuel Efficiency 85),
## `movement.engine_failure` (Cheap Engines: 1 in 10 above warp 6).
##
## Not yet: fleets following fleets, stargates (warp 11), wormhole jumps on arrival, minefield
## hits (S13), warp-10 engine damage and Alternate Reality colonists in transit.

const CANNOT_MOVE := 1 << 40
const FUEL_DIVISOR := 2000
const FUEL_ROUNDING := 10
const RANGE_PROBE := 1000
const FAILURE_WARP := 6
const FAILURE_CHANCE := 10
const SCOOP_MAX_WARP := 8
## A partial move rounds to the nearest light year, halves away from zero (S12 step 3).
const ROUND_HALF := 0.5
## The distance to the target is rounded up (+ 0.9999, then truncated; S12 step 1).
const DISTANCE_ROUND_UP := 0.9999


## Fuel (mg) the fleet needs to move `distance` light years at `warp` (S12 "Fuel use"); a huge value
## when a design can't move.
static func fuel_needed(
	fleet: Fleet, owner: Player, warp: int, distance: int, content: ContentRegistry
) -> int:
	var usage := _usage(fleet, owner, warp, distance, content)
	if usage >= CANNOT_MOVE:
		return CANNOT_MOVE
	return (usage + FUEL_ROUNDING - 1) / FUEL_ROUNDING


static func _usage(
	fleet: Fleet, owner: Player, warp: int, distance: int, content: ContentRegistry
) -> int:
	var rows := []
	for stack in fleet.stacks:
		if stack.count <= 0:
			continue
		var design := owner.ship_design(stack.design)
		var engine := PartRules.engine(design, content)
		if not engine[1]:
			return CANNOT_MOVE
		var f: int = (content.part(engine[0])["fuel_table"] as Array)[warp]
		var pct := RaceMath.trait_param(owner.race, content, "movement.fuel_usage_pct", 100)
		f += f * (pct - 100) / 100
		(
			rows
			. append(
				[
					f,
					stack.design,
					PartRules.mass(design, content) * stack.count,
					PartRules.cargo_capacity(design, content) * stack.count,
				]
			)
		)
	rows.sort()
	var cargo := 0
	for c in Fleet.CARGO_FUEL:
		cargo += fleet.cargo[c]
	var usage := 0
	for row: Array in rows:
		var carried := mini(cargo, row[3])
		cargo -= carried
		if row[0] > 0:
			usage += row[0] * distance * (row[2] + carried) / FUEL_DIVISOR
	return usage


## How far the fleet gets on its fuel at `warp` (S12): (fuel x 1000) div (fuel for 1000 ly).
static func fuel_range(fleet: Fleet, owner: Player, warp: int, content: ContentRegistry) -> int:
	var probe := fuel_needed(fleet, owner, warp, RANGE_PROBE, content)
	if probe == 0:
		return CANNOT_MOVE
	if probe >= CANNOT_MOVE:
		return 0
	return fleet.cargo[Fleet.CARGO_FUEL] * RANGE_PROBE / probe


static func fuel_capacity(fleet: Fleet, owner: Player, content: ContentRegistry) -> int:
	var total := 0
	for stack in fleet.stacks:
		var design := owner.ship_design(stack.design)
		if design != null:
			total += stack.count * PartRules.fuel_capacity(design, content)
	return total


## S02 phase 9: every fleet with a next waypoint moves toward it, in fleet order.
static func move_all(state: GameState, content: ContentRegistry, rng: StarsRandom) -> void:
	for fleet in state.fleets:
		fleet.did_not_move = true
	for fleet in state.fleets:
		_move(state, content, rng, fleet)
	for fleet in state.fleets:
		_advance_waypoints(fleet)


static func _move(
	state: GameState, content: ContentRegistry, rng: StarsRandom, fleet: Fleet
) -> void:
	if fleet.ship_count() == 0 or fleet.waypoints.size() < 2:
		return
	var current := fleet.waypoints[0]
	var next := fleet.waypoints[1]
	if next.warp == 0 or current.task == "transport":
		return
	if next.warp == Waypoint.WARP_STARGATE:
		push_warning(
			"fleet %d/%d: stargate travel is not implemented yet" % [fleet.owner, fleet.number]
		)
		return
	var owner := state.player(fleet.owner)
	if (
		next.warp > FAILURE_WARP
		and RaceMath.trait_param(owner.race, content, "movement.engine_failure", 0)
		and rng.random(FAILURE_CHANCE) == 0
	):
		return
	var dx := next.x - fleet.x
	var dy := next.y - fleet.y
	var exact := sqrt(float(dx * dx + dy * dy))
	var whole := int(exact + DISTANCE_ROUND_UP)
	var warp := next.warp
	var budget := warp * warp
	var move := mini(budget, whole)
	var reach := fuel_range(fleet, owner, warp, content)
	var out_of_fuel := false
	if reach < move:
		fleet.cargo[Fleet.CARGO_FUEL] = 0
		move = reach
		out_of_fuel = true
	else:
		var need := fuel_needed(fleet, owner, warp, move, content)
		fleet.cargo[Fleet.CARGO_FUEL] = maxi(fleet.cargo[Fleet.CARGO_FUEL] - need, 0)
	if out_of_fuel:
		_lower_warp(fleet, owner, next, content)
	if move <= 0:
		return
	fleet.did_not_move = false
	if move >= whole:
		fleet.x = next.x
		fleet.y = next.y
		fleet.planet = next.target_id if next.target == "planet" else -1
	else:
		var ratio := float(move) / exact
		fleet.x += int(dx * ratio + (ROUND_HALF if dx > 0 else -ROUND_HALF))
		fleet.y += int(dy * ratio + (ROUND_HALF if dy > 0 else -ROUND_HALF))
		# rounding can land the fleet on its target: then it has arrived
		var landed := fleet.x == next.x and fleet.y == next.y
		fleet.planet = next.target_id if landed and next.target == "planet" else -1
	_ram_scoops(fleet, owner, warp, move, content)


## Out of fuel: the next waypoint's warp drops to the highest warp that uses no fuel.
static func _lower_warp(
	fleet: Fleet, owner: Player, next: Waypoint, content: ContentRegistry
) -> void:
	var w := 1
	while w <= 10 and fuel_needed(fleet, owner, w, RANGE_PROBE, content) == 0:
		w += 1
	if w >= 2:
		next.warp = w - 1


## Engines that use no fuel at this warp make fuel (S12 step 6).
static func _ram_scoops(
	fleet: Fleet, owner: Player, warp: int, distance: int, content: ContentRegistry
) -> void:
	if warp > SCOOP_MAX_WARP:
		return
	var made := 0
	for stack in fleet.stacks:
		var design := owner.ship_design(stack.design)
		var engine := PartRules.engine(design, content)
		if not engine[1]:
			continue
		var table: Array = content.part(engine[0])["fuel_table"]
		if table[warp] != 0:
			continue
		var engines := _engine_count(design, engine[0])
		var k := engines
		if warp + 1 <= 10 and table[warp + 1] == 0:
			k = 3 * engines
			if warp + 2 <= 10 and table[warp + 2] == 0:
				k = 6 * engines
				if warp <= 7 and table[warp + 3] == 0:
					k = 10 * engines
		made += stack.count * k * distance
	if made > 0:
		var space := fuel_capacity(fleet, owner, content) - fleet.cargo[Fleet.CARGO_FUEL]
		fleet.cargo[Fleet.CARGO_FUEL] += clampi(made, 0, maxi(space, 0))


static func _engine_count(design: Design, part: String) -> int:
	var n := 0
	for slot in design.parts:
		if slot.part == part:
			n += slot.count
	return n


## S12 "Waypoints after movement": a fleet that reached its next waypoint makes it its current one;
## a fleet that moved part of the way is in deep space.
static func _advance_waypoints(fleet: Fleet) -> void:
	if fleet.waypoints.size() < 2 or fleet.did_not_move:
		return
	var next := fleet.waypoints[1]
	if fleet.x == next.x and fleet.y == next.y:
		var last := fleet.waypoints[-1]
		var loop := (
			fleet.repeat and fleet.waypoints.size() != 2 and (last.x != next.x or last.y != next.y)
		)
		fleet.waypoints.remove_at(1)
		fleet.waypoints[0] = next
		if loop:
			fleet.waypoints.append(next.copy() as Waypoint)
		return
	var here := fleet.waypoints[0]
	here.x = fleet.x
	here.y = fleet.y
	here.target = "none"
	here.target_owner = -1
	here.target_id = -1


## S02 phase 15: a fleet at a starbase with a dock that belongs to its owner or a friend is
## refueled; otherwise fuel-making parts and hulls add `fuel_generation` per ship (S12).
static func refuel_all(state: GameState, content: ContentRegistry) -> void:
	for fleet in state.fleets:
		if fleet.ship_count() == 0:
			continue
		var owner := state.player(fleet.owner)
		var capacity := fuel_capacity(fleet, owner, content)
		if _at_friendly_dock(state, content, fleet, owner):
			fleet.cargo[Fleet.CARGO_FUEL] = capacity
			continue
		var made := 0
		for stack in fleet.stacks:
			var design := owner.ship_design(stack.design)
			if design == null:
				continue
			var per_ship: int = content.hull(design.hull).get("stats", {}).get("fuel_generation", 0)
			for slot in design.parts:
				if not slot.part.is_empty():
					per_ship += (
						slot.count
						* int(content.part(slot.part).get("stats", {}).get("fuel_generation", 0))
					)
			made += stack.count * per_ship
		if made > 0:
			fleet.cargo[Fleet.CARGO_FUEL] = mini(fleet.cargo[Fleet.CARGO_FUEL] + made, capacity)


static func _at_friendly_dock(
	state: GameState, content: ContentRegistry, fleet: Fleet, owner: Player
) -> bool:
	if fleet.planet < 0:
		return false
	var planet := state.planet(fleet.planet)
	if planet == null or planet.starbase == null or planet.owner < 0:
		return false
	if planet.owner != fleet.owner:
		if planet.owner >= owner.relations.size() or owner.relations[planet.owner] != "friend":
			return false
	var base := state.player(planet.owner).starbase_design(planet.starbase.design)
	return base != null and content.hull(base.hull).get("dock", 0) != 0
