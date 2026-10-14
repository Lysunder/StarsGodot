class_name PlanetEstimates
extends RefCounted
## What other players see of a planet's population and defenses (spec S15 "Estimates";
## `UpdatePlanetEstimates@10b0:31da`, S02 phase 22): each populated planet's population give or
## take an eighth, in units of 400 colonists, and a 1-15 class for how much of a bombing its
## defenses stop. A race with `estimate.hides_population` shows no population.

## The largest population estimate (in units of 400 colonists).
const POPULATION_MAX := 0xFFA
## An accelerated start's estimate is the plain one (these bits) times four (S07).
const ACCELERATED_MASK := 0x3FF
## Defense class: (DEFENSE_BASE - percent let through, rounded) div DEFENSE_STEP, 1..DEFENSE_MAX.
const DEFENSE_BASE := 104
const DEFENSE_STEP := 6
const DEFENSE_MAX := 15
const ESTIMATE_BITS := 0xFFF


## The plain estimate of a population (units of 100 colonists): a quarter, in 12 bits.
static func of_population(population: int) -> int:
	return (population >> 2) & ESTIMATE_BITS


## Phase 22: every planet, in planet order; one draw per populated planet of a race that shows
## its population.
static func update(state: GameState, content: ContentRegistry, rng: StarsRandom) -> void:
	for planet in state.planets:
		if planet.population == 0:
			planet.population_estimate = 0
			planet.defense_estimate = 0
			continue
		var race := state.player(planet.owner).race
		if RaceMath.trait_param(race, content, "estimate.hides_population", 0):
			planet.population_estimate = 0
		else:
			planet.population_estimate = _population(planet.population, rng)
		planet.defense_estimate = defense_class(state, content, planet)


## The population give or take: (P + random(P div 4) - P div 8) div 4, at least 1. The bound is
## a 16-bit signed value, as in the original (a negative one draws but gives 0).
static func _population(population: int, rng: StarsRandom) -> int:
	var bound := population >> 2
	bound = ((bound & 0xFFFF) ^ 0x8000) - 0x8000
	var v := (population + rng.random(bound) - (population >> 3)) >> 2
	return clampi(v, 1, POPULATION_MAX)


## How well a planet's defenses cover it, 1..15; 0 without defenses.
static func defense_class(state: GameState, content: ContentRegistry, planet: Planet) -> int:
	if planet.defenses == 0:
		return 0
	var through := DefenseCoverage.scale_round(
		100, DefenseCoverage.uncovered(state, content, planet)
	)
	return clampi((DEFENSE_BASE - through) / DEFENSE_STEP, 1, DEFENSE_MAX)
