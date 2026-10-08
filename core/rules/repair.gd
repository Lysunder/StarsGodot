class_name Repair
extends RefCounted
## Repair of ships and starbases, and colonists growing in Inner-Strength fleets (spec S19).

## Damage points (of 500 per ship) repaired a year, by where the fleet is.
const MOVED := 5
const STILL_IN_SPACE := 10
const OTHERS_PLANET := 15
const OWN_PLANET := 25
const OWN_STARBASE := 40
const OWN_DOCK := 100
## Armor points a starbase repairs a year.
const STARBASE := 50
const PCT := 100
## Colonists aboard grow at half the race's growth rate; below 1 (hundred), one in three fleets
## gets 1.
const GROWTH_DIVISOR := 200
const SMALL_GROWTH_ROLL := 3


## S02 phase 18 (`RepairFleetsAndStarbases@10b0:28de`): every fleet with damaged ships repairs
## them by its rate (S19), unless it was hit by mines or went through a stargate this turn; then
## every starbase repairs. Clears those turn marks.
static func repair_all(state: GameState, content: ContentRegistry) -> void:
	for fleet in state.fleets:
		if fleet.ship_count() > 0 and not fleet.mine_hit and not fleet.gated:
			_repair_fleet(state, content, fleet)
		fleet.mine_hit = false
		fleet.gated = false
	for planet in state.planets:
		if planet.starbase == null or planet.starbase.damage == 0 or planet.owner < 0:
			continue
		var race := state.player(planet.owner).race
		var rate := STARBASE * RaceMath.trait_param(race, content, "repair.starbase_pct", PCT) / PCT
		planet.starbase.damage = (
			0 if planet.starbase.damage < rate else planet.starbase.damage - rate
		)


static func _repair_fleet(state: GameState, content: ContentRegistry, fleet: Fleet) -> void:
	var damaged := false
	var bonus := 0
	var owner := state.player(fleet.owner)
	for stack in fleet.stacks:
		if stack.damage != 0:
			damaged = true
		if stack.count > 0:
			var hull := content.hull(owner.ship_design(stack.design).hull)
			bonus = maxi(bonus, int(hull.get("stats", {}).get("repair_bonus", 0)))
	if not damaged:
		return
	var amount := rate(state, content, fleet)
	amount = amount * RaceMath.trait_param(owner.race, content, "repair.fleet_pct", PCT) / PCT
	amount += bonus
	for stack in fleet.stacks:
		if stack.damage == 0:
			continue
		if amount < stack.damage:
			stack.damage -= amount
		else:
			stack.damage = 0
			stack.damaged_percent = 0


## The fleet's repair rate by where it is (S19), before the race's factor and the repair hulls.
static func rate(state: GameState, content: ContentRegistry, fleet: Fleet) -> int:
	if not fleet.did_not_move:
		return MOVED
	if fleet.planet < 0:
		return STILL_IN_SPACE
	var planet := state.planet(fleet.planet)
	if planet.owner != fleet.owner:
		return OTHERS_PLANET
	if planet.starbase == null:
		return OWN_PLANET
	var design := state.player(planet.owner).starbase_design(planet.starbase.design)
	if design == null:
		return OWN_PLANET
	return OWN_DOCK if int(content.hull(design.hull).get("dock", 0)) != 0 else OWN_STARBASE


## S02 phase 12 (`GrowColonistsInFleets@10b0:4aa4`): colonists aboard fleets of races with the
## `fleet.colonist_growth` trait parameter (Inner-Strength) grow by growth rate x colonists div
## 200 (under 1: one chance in three of 1); what doesn't fit in the hold goes down to the fleet
## owner's planet the fleet orbits, else is lost. Nothing happens (no rolls) when no race has it.
static func grow_colonists(state: GameState, content: ContentRegistry, rng: StarsRandom) -> void:
	var any := false
	for p in state.players:
		if RaceMath.trait_param(p.race, content, "fleet.colonist_growth", 0):
			any = true
	if not any:
		return
	for fleet in state.fleets:
		var owner := state.player(fleet.owner)
		if fleet.ship_count() == 0 or fleet.cargo[Fleet.CARGO_COLONISTS] == 0:
			continue
		if not RaceMath.trait_param(owner.race, content, "fleet.colonist_growth", 0):
			continue
		var grown := owner.race.growth_rate * fleet.cargo[Fleet.CARGO_COLONISTS] / GROWTH_DIVISOR
		if grown < 1:
			if rng.random(SMALL_GROWTH_ROLL) != 0:
				continue
			grown = 1
		var moved := clampi(grown, 0, _cargo_room(fleet, owner, content))
		fleet.cargo[Fleet.CARGO_COLONISTS] += moved
		var word := fleet.owner * 512 + fleet.number
		var goto := {"fleet": fleet.number, "owner": fleet.owner}
		if moved > 0:
			TurnMessages.add(
				state, content, fleet.owner, "message.fleet.colonists_grew", goto, [word, moved]
			)
		if moved < grown and fleet.planet >= 0:
			var planet := state.planet(fleet.planet)
			if planet.owner == fleet.owner:
				planet.population += grown - moved
				TurnMessages.add(
					state,
					content,
					fleet.owner,
					"message.fleet.colonists_overflowed",
					goto,
					[word, grown - moved, planet.id]
				)


static func _cargo_room(fleet: Fleet, owner: Player, content: ContentRegistry) -> int:
	var room := 0
	for stack in fleet.stacks:
		room += stack.count * PartRules.cargo_capacity(owner.ship_design(stack.design), content)
	for c in Fleet.CARGO_FUEL:
		room -= fleet.cargo[c]
	return maxi(room, 0)
