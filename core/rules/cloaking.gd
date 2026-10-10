class_name Cloaking
extends RefCounted
## Cloaking (spec S15 "Cloaking"): a fleet's and a starbase's cloak percent, and how a scanner's
## reach shrinks against them.

const PCT := 100
## Starbase cloak units above this give no cloak at all (`Design_CloakUnits`).
const STARBASE_MAX_UNITS := 25000
## K = (100 − cloak)²; K at or above this means "not cloaked".
const NO_CLOAK_FACTOR := 10000
const TACHYON_TAG := "tachyon_detector"
const TACHYON_MAX := 17
const TACHYON_CONSTANT := "constant.scanner.tachyon_cloak_pct_%d"


## Cloak units to percent (`Fleet_ComputeCloak@1078:1e02`, `Design_CloakUnits@1040:55f4`).
static func units_to_pct(units: int) -> int:
	if units <= 100:
		return units / 2
	if units <= 300:
		return (units - 100) / 8 + 50
	if units < 613:
		return (units - 300) / 24 + 75
	var v := units - 612
	if v <= 512:
		return v / 64 + 88
	if v < 1000:
		return 97 if v >= 768 else 96
	return 98


## Σ count × `cloak` over a design's parts.
static func design_units(design: Design, content: ContentRegistry) -> int:
	var total := 0
	for slot in design.parts:
		if slot.count > 0 and not slot.part.is_empty():
			total += slot.count * int(content.part(slot.part).get("stats", {}).get("cloak", 0))
	return total


## A fleet's cloak percent: the cloak units of its stacks weighted by their mass, over the fleet's
## mass (with minerals and colonists aboard, except for races whose ships cloak by themselves).
static func fleet_pct(fleet: Fleet, owner: Player, content: ContentRegistry) -> int:
	var builtin := RaceMath.trait_param(owner.race, content, "cloak.builtin_units", 0)
	var weighted := 0
	var mass := 0
	for stack in fleet.stacks:
		if stack.count <= 0:
			continue
		var design := owner.ship_design(stack.design)
		var m := PartRules.mass(design, content) * stack.count
		var units := builtin + design_units(design, content)
		if units > 0:
			weighted += units * m
		mass += m
	if weighted == 0:
		return 0
	if builtin == 0:
		for c in Fleet.CARGO_FUEL:
			mass += fleet.cargo[c]
	return units_to_pct(weighted / mass) if mass > 0 else 0


## A starbase design's cloak percent.
static func starbase_pct(design: Design, owner: Player, content: ContentRegistry) -> int:
	var units := (
		design_units(design, content)
		+ RaceMath.trait_param(owner.race, content, "cloak.starbase_units", 0)
		+ RaceMath.trait_param(owner.race, content, "cloak.builtin_units", 0)
	)
	if units <= 0 or units > STARBASE_MAX_UNITS:
		return 0
	return units_to_pct(units)


## The scanner factor K = (100 − cloak)² of the starbase at a planet; NO_CLOAK_FACTOR without one.
static func starbase_factor(state: GameState, content: ContentRegistry, planet: Planet) -> int:
	if planet.starbase == null or planet.owner < 0:
		return NO_CLOAK_FACTOR
	var owner := state.player(planet.owner)
	var design := owner.starbase_design(planet.starbase.design)
	if design == null:
		return NO_CLOAK_FACTOR
	var k := PCT - starbase_pct(design, owner, content)
	return k * k


## How much of an enemy's cloak a design's Tachyon Detectors leave, in percent (100 without any).
static func tachyon_pct(design: Design, content: ContentRegistry) -> int:
	var count := 0
	for slot in design.parts:
		if slot.count > 0 and not slot.part.is_empty():
			if content.part(slot.part).get("tags", []).has(TACHYON_TAG):
				count += slot.count
	return content.constant(TACHYON_CONSTANT % mini(count, TACHYON_MAX))


## Whether a scanner whose squared reach is `reach2` sees something cloaked `cloak` percent at
## squared distance `d2`: the reach shrinks by (100 − cloak)² / 100².
static func within(d2: int, reach2: int, cloak: int) -> bool:
	var k := PCT - cloak
	return d2 <= k * reach2 / PCT * k / PCT
