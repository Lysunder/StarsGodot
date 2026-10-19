# ClassicPlanning

`core/ai/classic/classic_planning.gd`, extends `RefCounted`

The production every classic personality plans each turn (spec S22 "Classic production"):
the pass over its planets after the fleets have their orders (`AI_ManageProduction`), with
starbases, ships, packets, defenses and terraforming, the late-game defenses, the mines put
ahead of a waiting item (`AI_FixupMineOrders`), and the last pass that fills each queue with
factories and mines (`AI_FinishTurn`, `AI_FillPlanetQueue`).

## Constants

- `const P := preload("res://core/ai/classic/classic_production.gd")`
- `const ROBOTOIDS_MIN_POPULATION := 40`: Population (hundreds) a Robotoids planet needs before it plans production; other personalities plan below OTHERS_MIN_POPULATION only where planet_info byte INFO_DEPOT_PLAN is clear.
- `const OTHERS_MIN_POPULATION := 60`
- `const INFO_DEPOT_PLAN := 2`
- `const INFO_BOMBERS := 8`
- `const STARBASE_MIN_POPULATION := 80`: Starbases: the population a depot planet needs, and the turn before which every personality queues them.
- `const STARBASE_EARLY_TURN := 31`
- `const CYBERTRONS_SHIP_TURN := 40`
- `const UPGRADE_MIN_MINERALS := 200`: Starbase upgrades: per hundred chance 5 plus half the design's age over 10 turns (whole age from 50), and the minerals each kind a growing starbase needs on the surface.
- `const DEFENSE_MIN_POPULATION := 1600`: Defenses: population (hundreds) before a planet builds them, one per DEFENSE_POPULATION of it, at most MAX_DEFENSE_ITEMS a time.
- `const DEFENSE_POPULATION := 80`
- `const MAX_ITEMS_AT_ONCE := 4`
- `const TERRAFORM_MIN_POPULATION := 200`
- `const PACKET_MIN_LEVEL := 2`: Packets (`AI_QueuePackets`): the level needed, minerals in hand, the driver warp, and the reach squared with one or two of the best drivers (three times that with a mineral over PACKET_RICH_SURFACE).
- `const PACKET_MIN_MINERALS := 3001`
- `const PACKET_MIN_WARP := 10`
- `const PACKET_REACH2 := [7056, 50625]`
- `const PACKET_RICH_SURFACE := 12500`
- `const PACKET_WARP := 13`
- `const PACKET_FRESH_TURNS := 2`
- `const PACKET_STRONG_DEFENSE := 14`
- `const PACKET_BIG_POPULATION := 750`
- `const LATE_DEFENSE_OFFSET := 2`: Late-game defenses start at turn (universe size index + LATE_DEFENSE_OFFSET) * 10.
- `const DEFENSE_MIN_RESOURCES := 50`
- `const DEFENSE_EXTRA_RESOURCES := 150`
- `const DEFENSE_ALCHEMY_PER_EXTRA := 5`
- `const NEVER_FIRST := 600`: Mines ahead of a waiting item: years standing in for "never".
- `const NEVER_LATER := 700`
- `const ALCHEMY_TECH := 26`: Alchemy fills the queue only once every field is at this level, after ALCHEMY_TURN.
- `const ALCHEMY_TURN := 100`
- `const MACINTI_TERRAFORM_RESOURCES := 70`

## Functions

### `manage()`

```gdscript
static func manage(w: ClassicWorld, station: int) -> void
```

`AI_ManageProduction`: fleets' safe speeds, depot starbases, then each of the player's planets
(shuffled order) that has the people and, unless Macinti, the minerals for its queue
(the queue's cost within this year's output for each mineral): a starbase upgrade, else
packets, else defenses (other personalities: only where INFO_DEPOT_PLAN is clear, Cybertrons a
starbase upgrade only), else (not Robotoids) terraforming. Then the late-game defenses and the
mines ahead of waiting items.

### `queue_starbases()`

```gdscript
static func queue_starbases(w: ClassicWorld, station: int) -> void
```

`AI_QueueStarbase`: each of the player's planets without a starbase that is a freighter depot,
has STARBASE_MIN_POPULATION people and INFO_DEPOT_PLAN clear queues `station` unless a starbase
is queued there; Cybertrons instead every planet `choose_starbase` picks. Not Macinti; in a
tutorial game only before STARBASE_EARLY_TURN.

### `choose_starbase()`

```gdscript
static func choose_starbase(w: ClassicWorld, planet: Planet) -> int
```

`AI_ChooseStarbasePlanet` (Cybertrons): a planet without a starbase, at least 15% habitable,
with 500 people, gets the newer station (all concentrations 16 or more) or the newer fort;
-1 for others. The planet is selected and its production opened.

### `queue_ship()`

```gdscript
static func queue_ship(w: ClassicWorld, planet: Planet, station: int) -> bool
```

`AI_QueueShip`: the planet's starbase grows. A starbase of an older generation than the newest
station (`station`) or fort is replaced by the same size of the newest, with a chance per
hundred of 5 plus half the newest design's age past 10 turns (the whole age from 50). One of
the newest generation grows to the next size with a chance of 6 in 100 when that design exists
and the surface has UPGRADE_MIN_MINERALS of each mineral. Not when a starbase is queued, not
Cybertrons before CYBERTRONS_SHIP_TURN; Macinti's own way comes with Macinti.

### `queue_packets()`

```gdscript
static func queue_packets(w: ClassicWorld, planet: Planet, out: Array[int]) -> bool
```

`AI_QueuePackets`: from level PACKET_MIN_LEVEL, with PACKET_MIN_MINERALS of output and a
driver of PACKET_MIN_WARP or more, one turn in four (a draw) the planet aims its driver at
warp PACKET_WARP at another player's planet seen in the last PACKET_FRESH_TURNS turns within
reach that is weakly defended or lightly peopled (`packet.no_damage` races left out, and
starbases of `ai.no_packets_at_starbases` races), one drawn among them, and queues packets: 80
of germanium now and then (output over 20000 and a draw), mixed ones when rich in all three,
else each mineral over what it keeps. Not Cybertrons, and not when packets are queued.

### `queue_defenses()`

```gdscript
static func queue_defenses(w: ClassicWorld, planet: Planet) -> bool
```

`AI_QueueDefenses`: a planet of DEFENSE_MIN_POPULATION with fewer defenses than one per
DEFENSE_POPULATION queues up to MAX_ITEMS_AT_ONCE, unless defenses are queued.

### `queue_terraform()`

```gdscript
static func queue_terraform(w: ClassicWorld, planet: Planet) -> bool
```

`AI_QueueStandardItem2` (not Robotoids, not Cybertrons): a planet of TERRAFORM_MIN_POPULATION
whose environment is off the race's center on some axis queues up to MAX_ITEMS_AT_ONCE
terraforming steps, unless some are queued.

### `late_game_defenses()`

```gdscript
static func late_game_defenses(w: ClassicWorld) -> void
```

`AI_LateGameDefenses`: defenses at each planet with an enemy bomber in orbit.

### `planet_defenses()`

```gdscript
static func planet_defenses(w: ClassicWorld, planet: Planet) -> void
```

`AI_PlanetDefenses`: unless defenses are queued, a planet with DEFENSE_MIN_RESOURCES puts
defenses at the top of its queue: a twenty-fifth of its resources (less a sixth of that above
5), as far as the list allows; when a mineral (a fifth of the output, at most 100) allows fewer,
that many plus one for each DEFENSE_EXTRA_RESOURCES of nine tenths of the resources left after
alchemy for them, with DEFENSE_ALCHEMY_PER_EXTRA units of alchemy each above them.

### `fixup_mines()`

```gdscript
static func fixup_mines(w: ClassicWorld) -> void
```

`AI_FixupMineOrders`, each of the player's planets whose first queue item is not mines,
alchemy or terraforming and is not begun this year although a year's resources before it
starts would pay for one unit: as many mines as this year's resources buy (up to the mines
next year's people can work) go to the top of the queue, or auto alchemy when none, and the
queue is committed. The original then tries the queue with auto alchemy and with fewer mines
on its planet copy only, which reaches the world only when that copy is committed later.

### `finish_turn()`

```gdscript
static func finish_turn(w: ClassicWorld) -> void
```

`AI_FinishTurn`: every planet of the player (shuffled order) fills its queue.

### `fill_queue()`

```gdscript
static func fill_queue(w: ClassicWorld, planet: Planet) -> bool
```

`AI_FillPlanetQueue`, with resources to spare after the queue: Macinti terraforms what a
seventieth of them pays for; otherwise, short of a mineral (and the queue not led by alchemy),
mines at the top for what is left; with every mineral to spare, factories at the end (as many
as the germanium and resources pay for) and then mines; mines and factories only up to what the
people work, less those queued. Once every field is at ALCHEMY_TECH, after turn ALCHEMY_TURN,
alchemy for the rest (one more), at the top when short of a mineral.

---

*Generated by `tools/gen_api_docs.py` from the doc comments in `core/ai/classic/classic_planning.gd`.*
