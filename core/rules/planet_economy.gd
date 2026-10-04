class_name PlanetEconomy
extends RefCounted
## How a planet supports its owner (spec S08): maximum population, growth, installations,
## resources and mining.
##
## Trait parameters: `planet.max_pop_pct` (HE 50, JoaT 120), `planet.max_pop_extra_pct` (OBRM 110,
## applied last), `race.growth_rate_pct` (HE 200), `planet.revert_terraform_on_loss` (CA 1).
##
## Not yet: Alternate Reality (starbase population, square-root resources and mines).

const COLONISTS_PER_UNIT := 100
const MIN_MAX_POP := 500
const LOW_HAB := 5
const MIN_INSTALLATIONS := 10
const MIN_DEFENSES := 10
const MAX_DEFENSES := 100
const DEFENSE_POPULATION_CAP := 1000
const CROWD_DIVISOR := 562500
const STEADY_BAND := 10
const MAX_DEATH := -300
const BIG_GROWTH := 10000000
const HOMEWORLD_MIN_CONCENTRATION := 30
const WEAR_UNIT := 12500
const FRACTION_STEPS := 256


static func hab_value(planet: Planet, race: Race) -> int:
	return Habitability.value(planet.environment, race)


## Maximum population M, in units of 100 colonists (S08 step 2).
static func max_pop(planet: Planet, race: Race, content: ContentRegistry) -> int:
	var h := hab_value(planet, race)
	var m := MIN_MAX_POP if h < LOW_HAB else COLONISTS_PER_UNIT * h
	m += m * (RaceMath.trait_param(race, content, "planet.max_pop_pct", 100) - 100) / 100
	m += m * (RaceMath.trait_param(race, content, "planet.max_pop_extra_pct", 100) - 100) / 100
	return m


## The population change this year in colonists (S08 step 3); `apply` adds it to the planet.
static func grow(planet: Planet, race: Race, content: ContentRegistry, apply: bool) -> int:
	var p := planet.population
	var h := hab_value(planet, race)
	var change := 0
	if h < 0:
		change = -maxi(-h * p / 10, 1)
	else:
		var m := max_pop(planet, race, content)
		var pct := RaceMath.trait_param(race, content, "race.growth_rate_pct", 100)
		var r := race.growth_rate * pct / 100 * h
		if p > m / 4:
			var c := p * 1000 / m
			if p < m:
				r = (1000 - c) * (1000 - c) * r / CROWD_DIVISOR
			elif p < m + STEADY_BAND:
				return 0
			else:
				r = 4 * maxi(99 - c / 10, MAX_DEATH)
		change = r * p / 100
		if r / 100 * p >= BIG_GROWTH:
			change = r / 100 * p
		if change == 0:
			change = 1
	if apply:
		add_colonists(planet, change)
	return change


## Adds (or removes) colonists, keeping 0..99 single colonists beside the units.
static func add_colonists(planet: Planet, colonists: int) -> void:
	var total := planet.population * COLONISTS_PER_UNIT + planet.extra_colonists + colonists
	if total < 0:
		total = 0
	planet.population = total / COLONISTS_PER_UNIT
	planet.extra_colonists = total % COLONISTS_PER_UNIT


static func max_factories(planet: Planet, race: Race, content: ContentRegistry) -> int:
	return maxi(max_pop(planet, race, content) * race.factories_operated / 100, MIN_INSTALLATIONS)


## `population` < 0: the planet's; the production checks pass next year's (next_population).
static func operable_factories(
	planet: Planet, race: Race, content: ContentRegistry, population := -1
) -> int:
	var p := planet.population if population < 0 else population
	var n := p * race.factories_operated / 100
	return maxi(mini(n, max_factories(planet, race, content)), 1)


static func max_mines(planet: Planet, race: Race, content: ContentRegistry) -> int:
	return maxi(max_pop(planet, race, content) * race.mines_operated / 100, MIN_INSTALLATIONS)


static func operable_mines(
	planet: Planet, race: Race, content: ContentRegistry, population := -1
) -> int:
	var p := planet.population if population < 0 else population
	var n := p * race.mines_operated / 100
	return maxi(mini(n, max_mines(planet, race, content)), 1)


## Maximum defenses: habitability x 4, kept within 10..100.
static func max_defenses(planet: Planet, race: Race) -> int:
	return clampi(hab_value(planet, race) * 4, MIN_DEFENSES, MAX_DEFENSES)


static func operable_defenses(planet: Planet, race: Race, population := -1) -> int:
	var p := planet.population if population < 0 else population
	return mini(mini((p + 24) / 25, DEFENSE_POPULATION_CAP), max_defenses(planet, race))


## The population after this year's growth (S08 "next year" values), in units of 100.
static func next_population(planet: Planet, race: Race, content: ContentRegistry) -> int:
	var total := planet.population * COLONISTS_PER_UNIT + planet.extra_colonists
	total += grow(planet, race, content, false)
	return maxi(total, 0) / COLONISTS_PER_UNIT


static func effective_mines(planet: Planet, race: Race, content: ContentRegistry) -> int:
	return mini(planet.mines, operable_mines(planet, race, content))


## Resources this year (S08 step 5).
static func resources(planet: Planet, race: Race, content: ContentRegistry) -> int:
	var p := planet.population
	if p <= 0:
		return 0
	var m := max_pop(planet, race, content)
	var w := p
	if p > m:
		w = mini((p - m) / 2 + m, 2 * m)
	var used := mini(planet.factories, operable_factories(planet, race, content))
	var r := w / race.resources_per_colonist + (race.factory_output * used + 9) / 10
	return maxi(r, 1)


## The owner mines its planet (S08 step 6). `rng` rounds fractions at random during turn
## generation; null drops them (estimates).
static func mine(planet: Planet, race: Race, content: ContentRegistry, rng: StarsRandom) -> void:
	var mines := effective_mines(planet, race, content)
	for m in 3:
		var c := planet.concentration[m]
		if planet.homeworld:
			c = maxi(c, HOMEWORLD_MIN_CONCENTRATION)
		var raw := race.mine_output * (c * mines) / 10
		var amount := raw / 100
		var q := raw % 100
		if q > 0 and rng != null and rng.random(100) < q:
			amount += 1
		planet.surface[m] += amount
		_wear(planet, m, c * mines / 100)


## A remote miner mines an unowned planet at `rate` (S08 step 6, remote form; S11 "Remote
## mining"): raw output C × rate, no mine-output factor and no homeworld minimum.
static func mine_remote(planet: Planet, rate: int, rng: StarsRandom) -> void:
	for m in 3:
		var c := planet.concentration[m]
		var raw := c * rate
		var amount := raw / 100
		var q := raw % 100
		if q > 0 and rng != null and rng.random(100) < q:
			amount += 1
		planet.surface[m] += amount
		_wear(planet, m, c * rate / 100)


## Concentration wear from mining effort `effort` (S08 step 6.5).
static func _wear(planet: Planet, m: int, effort: int) -> void:
	var e := effort
	while e > 0 and planet.concentration[m] > 1:
		var c := planet.concentration[m]
		var f := planet.concentration_fraction[m]
		if f == 0:
			f = FRACTION_STEPS
		var d := 10 if c < 5 else (25 if c < 25 else mini(c, 100))
		var k := f * WEAR_UNIT / FRACTION_STEPS / d
		if e < k:
			var nf := maxi((k - e) * FRACTION_STEPS / (WEAR_UNIT / d), 1)
			if nf >= f:
				nf = f - 1
			planet.concentration_fraction[m] = nf
			if nf == 0:
				planet.concentration[m] = c - 1
			return
		planet.concentration[m] = c - 1
		planet.concentration_fraction[m] = 0
		e -= k


## A planet loses its owner and everything that needs one (S08 "Depopulation"): population,
## queue, starbase (with its mass driver), defenses and planetary scanner. Mines, factories and
## single colonists stay. `race` is the previous owner's (null for an unowned planet).
static func depopulate(planet: Planet, race: Race, content: ContentRegistry) -> void:
	if race != null and RaceMath.trait_param(race, content, "planet.revert_terraform_on_loss", 0):
		planet.environment.assign(planet.environment_original)
	planet.owner = -1
	planet.population = 0
	planet.queue.clear()
	planet.leftover_to_research = false
	planet.starbase = null
	planet.mass_driver_target = -1
	planet.mass_driver_warp = 0
	planet.defenses = 0
	planet.has_scanner = false
