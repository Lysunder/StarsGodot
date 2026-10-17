class_name WaypointWarp
extends RefCounted
## The warp a waypoint gets by default (spec S12 "Default warp", `Waypoint_DefaultWarp@1050:5650`)
## and the fuel a fleet needs to reach a waypoint (`Waypoint_FuelNeeded@1048:6948`). The classic
## computer players set their fleets' speeds with it (S22).

## Distances to a waypoint are rounded up this way before years are counted.
const DISTANCE_ROUND_UP := 0.99999
const YEARS_ROUND_UP := 0.9999
const COLONIZE := "colonize"
const SCRAP := "scrap"
const COLONIZER_TAG := "colonizer"
## The safe speed below which a fleet is sped up to WARP_FAST where it is welcome.
const WARP_FAST := 9
const WARP_STARGATE := 11
const STARBASE_FORT := "hull.orbital_fort"


## The most fuel the fleet holds on the way to waypoint `index`: leg by leg from waypoint 0, each
## leg at its waypoint's warp (none at warp 0 or above 10), refilled at the player's own planets
## with a dock. A leg of more than one year takes the larger of its fuel at once and year by year;
## engines that make fuel and fuel transports (`fuel_generation` per ship and year) can bring it
## down to one year's fuel, or to that year's fuel plus what the makers fall short by each further
## year.
static func fuel_needed(
	state: GameState, content: ContentRegistry, fleet: Fleet, index: int
) -> int:
	var owner := state.player(fleet.owner)
	var most := 0
	var running := 0
	for k in mini(index, fleet.waypoints.size() - 1):
		var from := fleet.waypoints[k]
		var to := fleet.waypoints[k + 1]
		var w := to.warp
		var years := 1
		var use := 0
		var dist := 0
		if w > 0 and w <= 10:
			var d := Vector2(to.x - from.x, to.y - from.y).length()
			dist = int(d + DISTANCE_ROUND_UP)
			years = int((d + DISTANCE_ROUND_UP) * (1.0 / float(w * w)) + YEARS_ROUND_UP)
			# the whole leg, its distance rounded up (`Fleet_CalcFuelUsage` with no distance given)
			use = Movement.fuel_needed(fleet, owner, w, int(d + YEARS_ROUND_UP), content)
		if years > 1:
			var yearly := Movement.fuel_needed(fleet, owner, w, w * w, content)
			var last := Movement.fuel_needed(fleet, owner, w, (1 - years) * w * w + dist, content)
			use = maxi(use, (years - 1) * yearly + last)
			var made := Movement.scoop_fuel(fleet, owner, w, w * w, content)
			for stack in fleet.stacks:
				var hull := content.hull(owner.ship_design(stack.design).hull)
				made += stack.count * int(hull.get("stats", {}).get("fuel_generation", 0))
			if made > 0:
				if yearly <= made:
					use = yearly
				else:
					var stretched := yearly + (yearly - made) * (years - 1)
					if stretched < use:
						use = stretched
		running += use
		most = maxi(most, running)
		if to.target == "planet" and _dock(state, content, state.planet(to.target_id), fleet.owner):
			running = 0
	return most


## A planet of `player` with a starbase that docks ships.
static func _dock(state: GameState, content: ContentRegistry, planet: Planet, player: int) -> bool:
	if planet == null or planet.owner != player or planet.starbase == null:
		return false
	var d := state.player(player).starbase_design(planet.starbase.design)
	return d != null and int(content.hull(d.hull).get("dock", 0)) != 0


## The planet at a position, or null.
static func planet_at(state: GameState, x: int, y: int) -> Planet:
	for p in state.planets:
		if p.x == x and p.y == y:
			return p
	return null


## The default warp of waypoint `index` (1 or later) of the fleet; for waypoint 0, the fleet's
## default warp (Retargeting.default_warp). Below WARP_FAST, a fleet heading for its own or an
## unowned planet, or carrying colonizers or told to colonize or scrap there, starts from
## WARP_FAST; other fleets (going to someone else's planet or into space) from one above the
## default (or the previous waypoint's warp when faster, up to 10) when they have a tenth of
## their fuel capacity to spare over the trip and seven tenths in the tank. From there the warp
## comes down to the default until the trip takes no more than the fuel aboard and either half of
## it, or the destination is the player's own dock, or the fleet is a colonizer. For a computer
## player (`ai`) every fleet counts as a colonizer here, and one that was not keeps within the
## fleet's top warp (no easing) unless going to its own planet with a starbase that is not a fort.
## Then the warp drops to the slowest taking as many years (not below 2; not for a fleet target),
## and becomes WARP_STARGATE when its own gates at both ends take the fleet with no damage and no
## cargo to unload.
static func default_warp(
	state: GameState, content: ContentRegistry, fleet: Fleet, index: int, ai: bool
) -> int:
	var owner := state.player(fleet.owner)
	var warp := Retargeting.default_warp(fleet, owner, content)
	var top := Retargeting.default_warp(fleet, owner, content, false) if ai else warp
	if index <= 0 or index >= fleet.waypoints.size():
		return warp
	var wp := fleet.waypoints[index]
	var saved := wp.warp
	var colonizer := (
		wp.task == COLONIZE or wp.task == SCRAP or _carries_colonizer(fleet, owner, content)
	)
	var capped := false
	if not colonizer and ai:
		capped = true
		colonizer = true
	var lowest := warp
	if warp < WARP_FAST:
		var planet := planet_at(state, wp.x, wp.y)
		var welcome := planet != null and (planet.owner == -1 or planet.owner == fleet.owner)
		var climb := false
		if colonizer or welcome:
			if capped and planet != null and planet.owner == fleet.owner:
				var d := (
					owner.starbase_design(planet.starbase.design)
					if planet.starbase != null
					else null
				)
				if d == null or d.hull != STARBASE_FORT:
					capped = false
			warp = WARP_FAST
			climb = true
		else:
			if index > 1:
				var before := fleet.waypoints[index - 1].warp
				if before > warp and before <= 10:
					warp = before
			var capacity := Movement.fuel_capacity(fleet, owner, content)
			if (
				capacity / 10 > fuel_needed(state, content, fleet, index)
				and (capacity * 7 / 10 <= fleet.cargo[Fleet.CARGO_FUEL])
			):
				warp += 1
				climb = true
		if climb:
			while warp > lowest:
				wp.warp = warp
				var need := fuel_needed(state, content, fleet, index)
				if need <= fleet.cargo[Fleet.CARGO_FUEL]:
					if _dock(state, content, planet, fleet.owner):
						break
					if need <= fleet.cargo[Fleet.CARGO_FUEL] / 2 or colonizer:
						break
				warp -= 1
			wp.warp = saved
	if capped and warp > top:
		warp = top
	var years := 2
	if warp > 1 and wp.target != "fleet":
		var prev := fleet.waypoints[index - 1]
		var dist := int(Vector2(wp.x - prev.x, wp.y - prev.y).length())
		years = (warp * warp + dist - 1) / (warp * warp)
		var w := warp - 1
		while w > 1 and (w * w + dist - 1) / (w * w) == years:
			w -= 1
		warp = w + 1
	if years > 1 and _clean_gate(state, content, fleet, owner, fleet.waypoints[index - 1], wp):
		warp = WARP_STARGATE
	if warp > WARP_STARGATE:
		warp = WARP_FAST
	return warp


static func _carries_colonizer(fleet: Fleet, owner: Player, content: ContentRegistry) -> bool:
	for stack in fleet.stacks:
		if stack.count <= 0:
			continue
		for slot in owner.ship_design(stack.design).parts:
			if slot.count > 0 and not slot.part.is_empty():
				if (content.part(slot.part).get("tags", []) as Array).has(COLONIZER_TAG):
					return true
	return false


## The player's own stargates at both ends (or Jump Gates on every ship to a gate of its own) take
## every ship of the fleet with no damage, and it has no cargo to leave behind
## (`Waypoint_StargateCheck` answering 1).
static func _clean_gate(
	state: GameState,
	content: ContentRegistry,
	fleet: Fleet,
	owner: Player,
	from: Waypoint,
	to: Waypoint
) -> bool:
	var there := planet_at(state, to.x, to.y)
	if there == null or there.owner != fleet.owner:
		return false
	var there_gate := Stargates.gate(state, content, there)
	if there_gate.is_empty():
		return false
	var here := planet_at(state, from.x, from.y)
	var here_gate := {}
	if here != null and here.owner == fleet.owner:
		here_gate = Stargates.gate(state, content, here)
	if here_gate.is_empty():
		if not Stargates.all_have_jump_gate(fleet, owner, content):
			return false
		here_gate = there_gate
	if not RaceMath.trait_param(owner.race, content, "movement.gate_cargo", 0):
		for c in Fleet.CARGO_FUEL:
			if fleet.cargo[c] > 0:
				return false
	var dist := int(Vector2(to.x - from.x, to.y - from.y).length())
	for stack in fleet.stacks:
		if stack.count <= 0:
			continue
		var mass := PartRules.mass(owner.ship_design(stack.design), content)
		if Stargates.damage_percent(here_gate, there_gate, dist, mass) != 0:
			return false
	return true
