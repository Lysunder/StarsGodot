# ClassicFreight

`core/ai/classic/classic_freight.gd`, extends `RefCounted`

The classic personalities' cargo (spec S22 "Classic freight"): moving cargo, how many colony
ships to keep (`AI_CountColonyShips`), freighter runs (`AI_PlanTransport`,
`AI_PickUpSalvage`) and the freighter depots kept in the memory (`AI_PlanFreighterDepots`).

## Constants

- `const TURINDRONES_PEOPLE_FROM := 1200`: Turindrones' freighters leaving home with more than TURINDRONES_PEOPLE_FROM people (hundreds) for a smaller owned planet take TURINDRONES_PEOPLE along.
- `const TURINDRONES_PEOPLE := 1000`
- `const F := preload("res://core/ai/classic/classic_fleets.gd")`
- `const COLONY_COUNT_TURN := 30`: Colony ships are counted from this turn; easy computer players count on even turns only.
- `const RUN_SPEED := 25`: Freighter runs: the speed and the years a leg takes (distance div RUN_SPEED, rounded up).
- `const RUN_WARP := 4`
- `const SALVAGE_REACH := 200`: Freighters look at salvage this far (each axis, toward smaller coordinates any distance).
- `const MIN_LOAD := 10`
- `const FULL_HOME_SCORE := 25000`
- `const DEPOT_TURN := 20`: Depots (`AI_PlanFreighterDepots`).
- `const DEPOTS_MAX := 64`
- `const DEPOT_MIN_POPULATION := 80`
- `const DEPOT_MIN_VALUE := 7000`
- `const DEPOT_MIN_INSTALLATIONS := 20`
- `const DEPOT_SPACING2 := 2500`
- `const DEPOT_SHARE_BELOW := 4`

## Functions

### `move_cargo()`

```gdscript
static func move_cargo(w: ClassicWorld, fleet: Fleet, other: Dictionary, c: int, amount: int) -> int
```

Moves up to `amount` of cargo `c` between the fleet and `other` (a planet, fleet or salvage
partner as in a cargo_transfer order): positive loads the fleet, negative unloads it; held to
what the giver has and the taker can hold before the order is given, so the order asks for what
moves (`AI_MoveCargo`, `AI_DropColonists`); nothing is given when nothing would move. Another
player's planet or fleet gives nothing. Returns the amount moved.

### `colony_ships()`

```gdscript
static func colony_ships(w: ClassicWorld) -> Dictionary
```

`AI_CountColonyShips`: {build: whether to build another colony ship, count: the player's fleets
with ships of colony designs}. Before COLONY_COUNT_TURN always (on easy only on even turns);
later while there are few (at most universe size index x 20 + 10, and with the player's planets
at most four fifths of all planets) and the colony designs built do not exceed planets plus
colony fleets by 26 or more, or on a draw with fewer than 5.

### `plan_transport()`

```gdscript
static func plan_transport(w: ClassicWorld, fleet: Fleet, home: Planet) -> int
```

`AI_PlanTransport`: a freighter's next run, from its depot `home`. Each planet is scored by
what it offers per year of travel (RUN_SPEED a year): a full freighter scores
FULL_HOME_SCORE at home (20 per percent full, per year, from 35% full); another of the player's
planets without a starbase (or one queued) by the share of the freighter its minerals fill
(all three, or mostly the scarcest at home when that is under half of the next, only it when
under a quarter); Robotoids also carry people from home (with 1101 people or 301) to thinly
peopled planets (65). Planets other freighters of its kind head for are passed over. Salvage
nearby may score better. The freighter loads at the target (unloads at home), at RUN_WARP;
Robotoids leaving home with people for a planet take some along; Turindrones' freighters take
people from a well-peopled home to a smaller owned planet and unload people at any owned
planet but home. Returns the target planet or salvage, or -1.

### `cargo_capacity()`

```gdscript
static func cargo_capacity(fleet: Fleet, owner: Player, content: ContentRegistry) -> int
```

The fleet's cargo room (`Fleet_GetCapacity(fleet, 2)`).

### `pick_up_salvage()`

```gdscript
static func pick_up_salvage(w: ClassicWorld, fleet: Fleet, mode: int, scarce: int, full: int, cap: int, best: int, target: int) -> Dictionary
```

`AI_PickUpSalvage`: salvage where the freighter is is loaded (the scarce mineral first when
`mode` is set, then everything unless `mode` is 2); salvage within SALVAGE_REACH scores like a
planet and may become the target. Returns {picked, salvage (or null), target}.

### `plan_depots()`

```gdscript
static func plan_depots(w: ClassicWorld) -> void
```

`AI_PlanFreighterDepots` (not Cybertrons or Macinti), from turn DEPOT_TURN: depots on planets
the player lost are dropped; the player's planets with a starbase (shuffled order) become
depots, then rich planets (population DEPOT_MIN_POPULATION, concentration squared x 4 plus
surface over the three minerals DEPOT_MIN_VALUE, DEPOT_MIN_INSTALLATIONS mines and factories;
Robotoids not within 50 light years of another depot), up to DEPOTS_MAX. Each freighter
not yet at a depot joins the nearest depot with room (DEPOT_FLEETS); a depot with fewer than
DEPOT_SHARE_BELOW freighters takes one from the first depot with two more.

### `depot_of_fleet()`

```gdscript
static func depot_of_fleet(w: ClassicWorld, id: int) -> int
```

The depot record a freighter (fleet id word) belongs to, or -1.

---

*Generated by `tools/gen_api_docs.py` from the doc comments in `core/ai/classic/classic_freight.gd`.*
