# PlanetEconomy

`core/rules/planet_economy.gd`, extends `RefCounted`

How a planet supports its owner (spec S08): maximum population, growth, installations,
resources and mining.

Trait parameters: `planet.max_pop_pct` (HE 50, JoaT 120), `planet.max_pop_extra_pct` (OBRM 110,
applied last), `race.growth_rate_pct` (HE 200), `planet.revert_terraform_on_loss` (CA 1),
and Alternate Reality's `planet.starbase_population`, `planet.no_installations`,
`planet.root_mines` and `planet.root_resources` (AR 1): the maximum population by the
starbase's hull (constants `constant.planet.starbase_population.<hull>`), no factories, mines
or defenses, effective mines the square root of the people, and resources
sqrt(W / pe x energy) x max(h, 25) / 10, rounded up from 0.999.

## Constants

- `const POP_GROWTH := "economy.pop_growth"`: The growth formula's id (Ruleset).
- `const COLONISTS_PER_UNIT := 100`
- `const MIN_MAX_POP := 500`
- `const LOW_HAB := 5`
- `const MIN_INSTALLATIONS := 10`
- `const MIN_DEFENSES := 10`
- `const MAX_DEFENSES := 100`
- `const DEFENSE_POPULATION_CAP := 1000`
- `const CROWD_DIVISOR := 562500`
- `const STEADY_BAND := 10`
- `const MAX_DEATH := -300`
- `const BIG_GROWTH := 10000000`
- `const HOMEWORLD_MIN_CONCENTRATION := 30`
- `const AR_MIN_HAB := 25`: Alternate Reality's resources count habitability as at least this.
- `const WEAR_UNIT := 12500`
- `const FRACTION_STEPS := 256`

## Functions

### `hab_value()`

```gdscript
static func hab_value(planet: Planet, race: Race) -> int
```

### `max_pop()`

```gdscript
static func max_pop(planet: Planet, race: Race, content: ContentRegistry) -> int
```

Maximum population M, in units of 100 colonists (S08 step 2).

### `grow()`

```gdscript
static func grow(planet: Planet, race: Race, content: ContentRegistry, apply: bool) -> int
```

The population change this year in colonists (S08 step 3); `apply` adds it to the planet.

### `standard_growth()`

```gdscript
static func standard_growth(planet: Planet, race: Race, content: ContentRegistry) -> int
```

The Standard growth (S08 step 4): the colonists a year adds to (or takes from) the planet.
Formula `economy.pop_growth` (Ruleset), which mods may replace.

### `add_colonists()`

```gdscript
static func add_colonists(planet: Planet, colonists: int) -> void
```

Adds (or removes) colonists, keeping 0..99 single colonists beside the units.

### `max_factories()`

```gdscript
static func max_factories(planet: Planet, race: Race, content: ContentRegistry) -> int
```

### `operable_factories()`

```gdscript
static func operable_factories(planet: Planet, race: Race, content: ContentRegistry, population := -1) -> int
```

`population` < 0: the planet's; the production checks pass next year's (next_population).

### `max_mines()`

```gdscript
static func max_mines(planet: Planet, race: Race, content: ContentRegistry) -> int
```

### `operable_mines()`

```gdscript
static func operable_mines(planet: Planet, race: Race, content: ContentRegistry, population := -1) -> int
```

### `max_defenses()`

```gdscript
static func max_defenses(planet: Planet, race: Race, content: ContentRegistry = null) -> int
```

Maximum defenses: habitability x 4, kept within 10..100.

### `operable_defenses()`

```gdscript
static func operable_defenses(planet: Planet, race: Race, population := -1, content: ContentRegistry = null) -> int
```

### `next_population()`

```gdscript
static func next_population(planet: Planet, race: Race, content: ContentRegistry) -> int
```

The population after this year's growth (S08 "next year" values), in units of 100.

### `effective_mines()`

```gdscript
static func effective_mines(planet: Planet, race: Race, content: ContentRegistry) -> int
```

### `resources()`

```gdscript
static func resources(planet: Planet, race: Race, content: ContentRegistry) -> int
```

Resources this year (S08 step 5).

### `mine()`

```gdscript
static func mine(planet: Planet, race: Race, content: ContentRegistry, rng: StarsRandom) -> void
```

The owner mines its planet (S08 step 6). `rng` rounds fractions at random during turn
generation; null drops them (estimates).

### `mine_remote()`

```gdscript
static func mine_remote(planet: Planet, rate: int, rng: StarsRandom, homeworld_min := false) -> void
```

A remote miner mines an unowned planet at `rate` (S08 step 6, remote form; S11 "Remote
mining"): raw output C × rate, no mine-output factor and no homeworld minimum (with
`homeworld_min`, as for an Alternate Reality owner's miners in orbit, the minimum applies).

### `mine_orbit()`

```gdscript
static func mine_orbit(state: GameState, planet: Planet, content: ContentRegistry, rng: StarsRandom, mark: bool) -> void
```

`planet.orbit_miners` (Alternate Reality), after the planet's own mining: the owner's fleets
in orbit with no waypoint beyond and the remote-mining task mine the planet at their rate, in
fleet order, as remote miners do but with the homeworld minimum (`Planet_Mine@1020:3a72`).
With `mark` they count as having moved, so the task pass leaves them be.

### `depopulate()`

```gdscript
static func depopulate(planet: Planet, race: Race, content: ContentRegistry) -> void
```

A planet loses its owner and everything that needs one (S08 "Depopulation"): population,
queue, starbase (with its mass driver), defenses and planetary scanner. Mines, factories and
single colonists stay. `race` is the previous owner's (null for an unowned planet).

---

*Generated by `tools/gen_api_docs.py` from the doc comments in `core/rules/planet_economy.gd`.*
