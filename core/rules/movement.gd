class_name Movement
extends RefCounted
## Fleet movement and fuel (spec S12): fuel use, the move toward the next waypoint, ram scoops,
## waypoints after movement, and refueling.
##
## Trait parameters: `movement.fuel_usage_pct` (Improved Fuel Efficiency 85),
## `movement.engine_failure` (Cheap Engines: 1 in 10 above warp 6).
##
## Stargates are in Stargates (S12 "Stargates"), mine hits in Minefields (S13). Not yet: warp-10
## engine damage and Alternate Reality colonists in transit.

const CANNOT_MOVE := 1 << 40
const FUEL_DIVISOR := 2000
const FUEL_ROUNDING := 10
const RANGE_PROBE := 1000
const FAILURE_WARP := 6
const FAILURE_CHANCE := 10
const SCOOP_MAX_WARP := 8
## The ram scoop message never reports more than this (S21).
const SCOOP_MESSAGE_MAX := 0x7EF4
## A partial move rounds to the nearest light year, halves away from zero (S12 step 3).
const ROUND_HALF := 0.5
## The distance to the target is rounded up (+ 0.9999, then truncated; S12 step 1).
const DISTANCE_ROUND_UP := 0.9999
## Ram scoops count the distance less this (S12 step 6).
const SCOOP_DISTANCE_CUT := 0.99999
## Movement passes in all: the first, then passes for fleets chasing fleets (S12 "Chasing").
const PASSES := 11
## A chaser's step while its target is still moving: a fifth of its budget, rounded up.
const CHASE_STEPS := 5


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
		(
			rows
			. append(
				[
					_engine_usage(engine[0], owner, warp, content),
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


## How far one empty ship of `design` gets on a full tank at `warp` (the designer's range): the
## same rule as fuel_range for a fleet of one such ship.
static func design_range(design: Design, owner: Player, warp: int, content: ContentRegistry) -> int:
	var engine := PartRules.engine(design, content)
	if not engine[1]:
		return 0
	var usage := (
		_engine_usage(engine[0], owner, warp, content)
		* RANGE_PROBE
		* PartRules.mass(design, content)
		/ FUEL_DIVISOR
	)
	var probe := (usage + FUEL_ROUNDING - 1) / FUEL_ROUNDING
	if probe == 0:
		return CANNOT_MOVE
	return PartRules.fuel_capacity(design, content) * RANGE_PROBE / probe


## An engine's fuel use per ship at `warp` from its fuel table, with the race's
## `movement.fuel_usage_pct`.
static func _engine_usage(part: String, owner: Player, warp: int, content: ContentRegistry) -> int:
	var f: int = (content.part(part)["fuel_table"] as Array)[warp]
	var pct := RaceMath.trait_param(owner.race, content, "movement.fuel_usage_pct", 100)
	return f + f * (pct - 100) / 100


static func fuel_capacity(fleet: Fleet, owner: Player, content: ContentRegistry) -> int:
	var total := 0
	for stack in fleet.stacks:
		var design := owner.ship_design(stack.design)
		if design != null:
			total += stack.count * PartRules.fuel_capacity(design, content)
	return total


## S02 phase 9: every fleet with a next waypoint moves toward it, in fleet order; fleets chasing a
## fleet wait for the first pass and then close in over later passes (S12 "Chasing a fleet").
static func move_all(state: GameState, content: ContentRegistry, rng: StarsRandom) -> void:
	for fleet in state.fleets:
		fleet.did_not_move = true
	# chaser -> {budget (left), moved, fuel (used so far this turn)}
	var chasers := {}
	# fleets lost in stargates, deleted after movement
	var lost: Array[Fleet] = []
	for fleet in state.fleets:
		if (
			fleet.ship_count() > 0
			and fleet.waypoints.size() > 1
			and fleet.waypoints[1].warp == Waypoint.WARP_STARGATE
			and fleet.waypoints[0].task != "transport"
		):
			match Stargates.jump(state, content, rng, fleet):
				"jumped":
					fleet.did_not_move = false
				"lost":
					lost.append(fleet)
			continue
		_move(state, content, rng, fleet, chasers)
	var passes := 1
	while not chasers.is_empty() and passes < PASSES:
		passes += 1
		for fleet in state.fleets:
			if chasers.has(fleet):
				_chase(state, content, rng, fleet, chasers)
	for fleet in state.fleets:
		_advance_waypoints(state, content, fleet)
	for fleet in lost:
		FleetOrders.delete_fleet(state, fleet, fleet.owner)
	# fleets destroyed by mines
	for fleet in state.fleets.duplicate():
		if fleet.stacks.is_empty():
			FleetOrders.delete_fleet(state, fleet, fleet.owner)


static func _move(
	state: GameState,
	content: ContentRegistry,
	rng: StarsRandom,
	fleet: Fleet,
	chasers: Dictionary,
) -> void:
	if fleet.ship_count() == 0 or fleet.waypoints.size() < 2:
		return
	var current := fleet.waypoints[0]
	var next := fleet.waypoints[1]
	if next.warp == 0 or current.task == "transport":
		return
	var owner := state.player(fleet.owner)
	if (
		next.warp > FAILURE_WARP
		and RaceMath.trait_param(owner.race, content, "movement.engine_failure", 0)
		and rng.random(FAILURE_CHANCE) == 0
	):
		return
	if next.target == "fleet" and state.fleet(next.target_owner, next.target_id) != null:
		chasers[fleet] = {"budget": next.warp * next.warp, "moved": 0, "fuel": 0}
		return
	_step(state, content, rng, fleet, next.warp * next.warp, {})


## A later pass for a chaser: its waypoint takes the target's position, and it moves the rest of
## its budget if the target has stopped, else a fifth of its whole budget (rounded up).
static func _chase(
	state: GameState, content: ContentRegistry, rng: StarsRandom, fleet: Fleet, chasers: Dictionary
) -> void:
	var chase: Dictionary = chasers[fleet]
	var next := fleet.waypoints[1]
	var target := state.fleet(next.target_owner, next.target_id)
	if target != null and not next.frozen:
		next.x = target.x
		next.y = target.y
	var left: int = chase["budget"]
	var step := left
	if target != null and chasers.has(target):
		step = mini(left, (left + int(chase["moved"]) + CHASE_STEPS - 1) / CHASE_STEPS)
	var going := _step(state, content, rng, fleet, step, chase)
	if going:
		chase["moved"] += step
		chase["budget"] = left - step
	if not going or chase["budget"] <= 0:
		chasers.erase(fleet)


## Moves the fleet up to `budget` light years toward its next waypoint (S12 "Moving"). `chase` is
## a chaser's state ({} otherwise): its fuel is charged for the whole distance chased so far.
## Returns true when a chaser moved without arriving and can go on.
static func _step(
	state: GameState,
	content: ContentRegistry,
	rng: StarsRandom,
	fleet: Fleet,
	budget: int,
	chase: Dictionary,
) -> bool:
	var owner := state.player(fleet.owner)
	var next := fleet.waypoints[1]
	var dx := next.x - fleet.x
	var dy := next.y - fleet.y
	var exact := sqrt(float(dx * dx + dy * dy))
	var whole := int(exact + DISTANCE_ROUND_UP)
	var warp := next.warp
	var move := mini(budget, whole)
	var moved: int = chase.get("moved", 0)
	var reach := maxi(fuel_range(fleet, owner, warp, content) - moved, 0)
	var used := 0
	if reach < move:
		fleet.cargo[Fleet.CARGO_FUEL] = 0
		move = reach
		used = 1
	else:
		# a chaser's fuel is charged for the whole distance chased so far
		fleet.cargo[Fleet.CARGO_FUEL] += int(chase.get("fuel", 0))
		used = fuel_needed(fleet, owner, warp, moved + move, content)
		if not chase.is_empty():
			chase["fuel"] = used
		fleet.cargo[Fleet.CARGO_FUEL] = maxi(fleet.cargo[Fleet.CARGO_FUEL] - used, 0)
	# out of fuel: the tank ran dry short of the target (or the fleet could not move at all)
	var out_of_fuel := (
		fleet.cargo[Fleet.CARGO_FUEL] == 0
		and used > 0
		and (move + DISTANCE_ROUND_UP <= exact or reach == 0)
	)
	if out_of_fuel:
		_lower_warp(fleet, owner, next, content)
		var word := fleet.owner * 512 + fleet.number
		var goto := {"fleet": fleet.number, "owner": fleet.owner}
		if next.warp == warp:
			TurnMessages.add(state, content, fleet.owner, "message.fleet.out_of_fuel", goto, [word])
		else:
			TurnMessages.add(
				state,
				content,
				fleet.owner,
				"message.fleet.out_of_fuel_slower",
				goto,
				[word, next.warp]
			)
	if move <= 0:
		return false
	fleet.did_not_move = false
	# minefields on the way (S13): a hit stops the fleet where it happened
	var hit := Minefields.check_path(state, content, rng, fleet, mini(move, int(exact)))
	if hit >= 0:
		if fleet.stacks.is_empty():
			return false
		if hit < int(exact):
			move = hit
	var arrived := move >= int(exact)
	# the move reaches the target when it covers the distance rounded down (fuel counts it rounded up)
	if arrived:
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
		arrived = landed
	if arrived and next.target == "wormhole":
		_through_wormhole(state, fleet, next)
	# scoops make fuel over min(move, trunc(distance - 0.99999)); not after running out of fuel or a
	# mine hit
	if not out_of_fuel and hit < 0:
		var scooped := mini(move, int(exact - SCOOP_DISTANCE_CUT))
		if scooped > 0:
			var room := fuel_capacity(fleet, owner, content) > fleet.cargo[Fleet.CARGO_FUEL]
			var made := _ram_scoops(fleet, owner, warp, scooped, content)
			if made > 0 and room:
				TurnMessages.add(
					state,
					content,
					fleet.owner,
					"message.fleet.ram_scoop",
					{"fleet": fleet.number, "owner": fleet.owner},
					[fleet.owner * 512 + fleet.number, mini(made, SCOOP_MESSAGE_MAX)]
				)
	return not chase.is_empty() and not arrived and not out_of_fuel and hit < 0


## A fleet arriving on a wormhole its waypoint targets comes out at the other end (S12 step 8): both
## ends are seen by its owner, who also knows where the far end is; other players' waypoints that
## target the fleet stay at the near end.
static func _through_wormhole(state: GameState, fleet: Fleet, next: Waypoint) -> void:
	var near := state.wormhole(next.target_id)
	if near == null:
		return
	var far := state.wormhole(near.other_end)
	if far == null:
		return
	FleetTargets.freeze_followers(state, fleet)
	for w: Wormhole in [near, far]:
		if not w.seen_by.has(fleet.owner):
			w.seen_by.append(fleet.owner)
			w.seen_by.sort()
	if not far.tracked_by.has(fleet.owner):
		far.tracked_by.append(fleet.owner)
		far.tracked_by.sort()
	fleet.x = far.x
	fleet.y = far.y
	fleet.planet = -1
	for pl in state.planets:
		if pl.x == far.x and pl.y == far.y:
			fleet.planet = pl.id
			break
	next.x = far.x
	next.y = far.y


## Out of fuel: the next waypoint's warp drops to the highest warp that uses no fuel.
static func _lower_warp(
	fleet: Fleet, owner: Player, next: Waypoint, content: ContentRegistry
) -> void:
	var w := 1
	while w <= 10 and fuel_needed(fleet, owner, w, RANGE_PROBE, content) == 0:
		w += 1
	if w >= 2:
		next.warp = w - 1


## Engines that use no fuel at this warp make fuel (S12 step 6); returns the fuel made.
static func _ram_scoops(
	fleet: Fleet, owner: Player, warp: int, distance: int, content: ContentRegistry
) -> int:
	if warp > SCOOP_MAX_WARP:
		return 0
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
	return made


static func _engine_count(design: Design, part: String) -> int:
	var n := 0
	for slot in design.parts:
		if slot.part == part:
			n += slot.count
	return n


## S12 "Waypoints after movement": waypoints targeting fleets take their positions; a fleet that
## reached its next waypoint makes it its current one; a fleet that moved part of the way is in deep
## space; a following fleet drops the waypoint it copied (S12 "Following a fleet").
static func _advance_waypoints(state: GameState, content: ContentRegistry, fleet: Fleet) -> void:
	if fleet.waypoints.size() < 2:
		return
	if fleet.following:
		if not fleet.did_not_move:
			_settle_here(fleet)
		fleet.waypoints.resize(1)
		TurnMessages.add(
			state,
			content,
			fleet.owner,
			"message.fleet.follow_done",
			{"fleet": fleet.number, "owner": fleet.owner},
			[fleet.owner * 512 + fleet.number]
		)
		return
	for i in range(1, fleet.waypoints.size()):
		var wp := fleet.waypoints[i]
		if wp.target != "fleet":
			continue
		var target := state.fleet(wp.target_owner, wp.target_id)
		if target == null:
			wp.target = "none"
			wp.target_owner = -1
			wp.target_id = -1
		elif not wp.frozen:
			wp.x = target.x
			wp.y = target.y
	if fleet.did_not_move:
		return
	var next := fleet.waypoints[1]
	if fleet.x == next.x and fleet.y == next.y:
		var last := fleet.waypoints[-1]
		var loop := (
			fleet.repeat and fleet.waypoints.size() != 2 and (last.x != next.x or last.y != next.y)
		)
		fleet.waypoints.remove_at(1)
		fleet.waypoints[0] = next
		# a reached fleet becomes the place it was, unless a transport or merge is to be done with it
		if next.target == "fleet" and next.task != "transport" and next.task != "merge":
			next = next.copy() as Waypoint
			fleet.waypoints[0] = next
			_settle_here(fleet)
		if loop:
			fleet.waypoints.append(next.copy() as Waypoint)
		if fleet.waypoints.size() == 1 and _orders_done(state, fleet, next):
			TurnMessages.add(
				state,
				content,
				fleet.owner,
				"message.fleet.completed",
				{"fleet": fleet.number, "owner": fleet.owner},
				[fleet.owner * 512 + fleet.number]
			)
		return
	_settle_here(fleet)


## Waypoint 0 becomes where the fleet is: its planet, or deep space.
static func _settle_here(fleet: Fleet) -> void:
	var here := fleet.waypoints[0]
	here.x = fleet.x
	here.y = fleet.y
	here.target = "planet" if fleet.planet >= 0 else "none"
	here.target_owner = -1
	here.target_id = fleet.planet


## S21: a fleet that reached its last waypoint has completed its orders unless that waypoint's
## task is still to do there (transport, colonize, remote mining, scrap, lay mines, patrol, or a
## route from one of its owner's planets that has a route).
static func _orders_done(state: GameState, fleet: Fleet, wp: Waypoint) -> bool:
	if wp.task in ["transport", "colonize", "remote_mine", "scrap", "lay_mines", "patrol"]:
		return false
	if wp.task == "route" and wp.target == "planet":
		var planet := state.planet(wp.target_id)
		if planet != null and planet.owner == fleet.owner and planet.route >= 0:
			return false
	return true


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
