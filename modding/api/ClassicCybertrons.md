# ClassicCybertrons

`core/ai/classic/classic_cybertrons.gd`, extends `RefCounted`

The original's Cybertrons (spec S22 "Cybertrons", `AI_Cybertrons`): research by plan, designs
drawn from template pools (`AI_Cybertrons_Designs`), warship groups gathering and invading
(`AI_Cybertrons_Invade`), colonist transports filling small colonies
(`AI_Cybertrons_ColonistTransport`), mine-laying scouts, production by planet
(`AI_Cybertrons_Economy`) and mineral packets thrown at their own planets and at others'
(`AI_Cybertrons_PlanPackets`). Per-planet state lives in the working memory: a lasting word A
per planet from word 1, and a word B per planet after them, cleared every turn.

## Constants

- `const F := preload("res://core/ai/classic/classic_fleets.gd")`
- `const P := preload("res://core/ai/classic/classic_production.gd")`
- `const RESEARCH_PLAN := "ai_research_plan.cybertrons"`
- `const RESEARCH_PCT := 17`
- `const TEMPLATE := "ai_design_template.cybertrons_"`
- `const MARKS_BASE := "ai.cybertrons_marks_base"`: Formula ids (S25 B44, B45, B46): where the fleet passes keep their marks, whose record a packet target's timer goes to, and how far a sector target must be.
- `const PACKET_RECORD := "ai.cybertrons_packet_record"`
- `const SECTOR_REACH := "ai.cybertrons_sector_reach"`
- `const LONG_TARGET := "ai.cybertrons_long_target"`
- `const SCOUT_SLOT := 0`: Design slots.
- `const COLONY_SLOT := 1`
- `const GROUP_FIRST := [6, 10]`
- `const MERGES := [[0], [4, 5], [14, 15], [6, 7, 8, 9], [10, 11, 12, 13]]`: Slots merged into one fleet each turn (`AI_MergeFleetsByHull`), in this order.
- `const SPLIT_TURN := 80`
- `const RETIRE_TURNS := [120, 200, 400]`: Retirement ages: before turn RETIRE_TURNS[i], RETIRE_AGES[i] turns; later the last.
- `const RETIRE_AGES := [50, 70, 100, 300]`
- `const ESCORT_START := 3`
- `const ESCORT_MAX := 50`
- `const TROOPS_START := 6`
- `const TROOPS_MAX := 12`
- `const INFO_OTHERS := 9`: planet_info bytes.
- `const INFO_TARGET := 10`
- `const INFO_COLONY := 15`
- `const HEADED := 0x80`
- `const A_SECTOR := 0x07`: Memory word A (lasting): bits 0-2 the packet sector, 0x08 a colony ship queued, 0x10 a sector packet thrown, 0x60 a packet timer (counts down each turn), 0x80 a packet still on its way.
- `const A_COLONY := 0x08`
- `const A_SECTOR_SENT := 0x10`
- `const A_TIMER := 0x60`
- `const A_TIMER_STEP := 0x20`
- `const A_LONG_THROW := 0x80`
- `const B_NO_TARGET := 0x01`: Memory word B (this turn): 0x01 no colony target, 0x06 people unloaded (counts to 3), 0x18 transports heading there (counts to 3), 0x20 its guards are few, 0x40 guarded; high byte bits 1, 2, 4 short of ironium, boranium, germanium.
- `const B_UNLOADED := 0x06`
- `const B_UNLOADED_STEP := 0x02`
- `const B_TRANSPORTS := 0x18`
- `const B_TRANSPORT_STEP := 0x08`
- `const B_FEW_GUARDS := 0x20`
- `const B_GUARDED := 0x40`
- `const B_SHORT := [0x100, 0x200, 0x400]`
- `const FORT_SLOTS := [1, 3, 6, 8]`: Starbase designs in these slots are forts (S22 "Starbase designs").
- `const SHORT_FORT := 10`
- `const SHORT_STATION := 1000`
- `const PACKET_RICH := 700`
- `const PACKET_KG := 70`
- `const PACKET_FEED_MAX := 7`
- `const PACKET_FEED_MIN := 7`
- `const PACKET_SPARE := 210`
- `const PACKET_ATTACK_SPARE := 151`
- `const PACKET_SECTOR_SPARE := 170`
- `const SECTOR_JITTER_PCT := [30, 15]`
- `const MAP_ORIGIN := 1000`
- `const FEED_REACH := [7, 2]`: A packet goes at most this many light years per warp squared (feed reach), and an attack target within PACKET_ATTACK_REACH per warp squared.
- `const ATTACK_REACH := [5, 2]`
- `const DECAY_PAIR := [8, 7]`: Packet decay over a throw: per year of flight, 8/7 with a matched pair of drivers, else 4/3.
- `const DECAY_SINGLE := [4, 3]`
- `const COLONY_TOO_MANY := 40`
- `const COLONY_GROWTH := 5500`
- `const COLONY_SECOND_GROWTH := 15000`
- `const COLONY_SECOND_TURN := 100`
- `const TRANSPORT_POPULATION := 2000`
- `const TRANSPORT_SHIPS := 50`
- `const SCOUT_SHIPS_MAX := 10000`
- `const ENEMY_NEAR2 := 90000`
- `const SCOUT_SCRAP_TURN := 6`
- `const SCOUT_LAY_TURN := 40`
- `const LAY_FOREVER := 5`
- `const SCOUT_JOIN := [72, 108]`
- `const SCOUT_REACH := 105`
- `const GROUP_JOIN := [100, 200]`
- `const FLEETS_IDLE_MAX := 120`
- `const FLEETS_GROUP_MAX := 250`
- `const FLEETS_GUARD_MAX := 40`
- `const COLONISTS_LOADED := 250`
- `const TRANSPORT_LOAD := 1000`
- `const TRANSPORT_HOME_POPULATION := 2200`
- `const SMALL_COLONY := 200`
- `const COLONY_FULL := 1000`
- `const COLONY_LEVEL := 210`
- `const NEAR_COLONY2 := 160001`
- `const SEEK_REACH := 450`
- `const FLEET_KEEP2 := 62501`
- `const WARP := 4`
- `const GROWTH_PCT := "race.growth_rate_pct"`
- `const SPACE_DOCK := "hull.space_dock"`
- `const HIT_SCALE := 16000`: The original's packet damage scale, 6.25e-5 as a double: a hair over 1/HIT_SCALE.

## Variables

- `var w: ClassicWorld`
- `var turn := 0`
- `var level := 0`
- `var escort := 0`
- `var troops := 0`
- `var wanted := 0`: Warship strength the planets build toward (`local_36`).
- `var age := 0`
- `var obsolete := []`
- `var destroyer := -1`: Newest designs: destroyers (slots 4-5), heavies (14-15), transports (2-3); -1 none.
- `var heavy := -1`
- `var transport := -1`
- `var transport_ships := 0`
- `var group := -1`: The newest warship group (0 for slots 6-9, 1 for 10-13), -1 none.
- `var counter := 0`: The retirement loop's counter, as the warship count reads it (`local_1e`).
- `var colony_ships := 0`
- `var own_warships: Array[Fleet] = []`
- `var enemies: Array[Fleet] = []`
- `var scout_fleets := 0`: Fleet counts of the first pass (`local_38`, `local_44`, `local_42`, `local_40`, `local_3e`).
- `var scout_ships := 0`
- `var idle_warships := 0`
- `var busy_warships := 0`
- `var guard_fleets := 0`
- `var planet_count := 0`

## Functions

### `play()`

```gdscript
static func play(world: ClassicWorld) -> void
```

One turn of Cybertrons on world `w`.

### `a_word()`

```gdscript
func a_word(id: int) -> int
```

### `set_a_word()`

```gdscript
func set_a_word(id: int, value: int) -> void
```

### `b_word()`

```gdscript
func b_word(id: int) -> int
```

### `set_b_word()`

```gdscript
func set_b_word(id: int, value: int) -> void
```

### `designs()`

```gdscript
static func designs(world: ClassicWorld) -> void
```

`AI_Cybertrons_Designs`: designs by turn, drawn from template pools (spec S22 "Cybertrons",
step 2).

### `fort()`

```gdscript
static func fort(p: Planet) -> bool
```

### `colonist_transport()`

```gdscript
func colonist_transport(fleet: Fleet) -> void
```

`AI_Cybertrons_ColonistTransport`: at one of the player's planets a transport loads people
from a big one (else unloads); at another player's planet without a starbase whose owner takes
drops it drops them and turns home; then it heads, with people, for a small or underfilled
colony near by (none: it unloads here), or, empty, for a big starbase planet. In deep space it
heads for the nearest planet.

### `nearest_planet_to()`

```gdscript
func nearest_planet_to(x: int, y: int) -> Planet
```

### `invade()`

```gdscript
func invade(fleet: Fleet) -> void
```

`AI_Cybertrons_Invade`: a warship group gathers at the player's planets until it has the
escort and the flagships, then sets out for the best target (as Robotoids, without troops or
drops); a weakened group goes back to a starbase planet.

### `economy()`

```gdscript
func economy(planet: Planet, dest: int, grp: int, guard: int) -> int
```

`AI_Cybertrons_Economy`: with mines and factories mostly in use (else seldom), the newest
warship group, a guard, or a destroyer. Returns 1, 2, 3 for what it added, 0 for nothing.

### `marks_base()`

```gdscript
static func marks_base(planets: int, _last_loaded: int) -> int
```

B44 fixed: the fleet passes mark the planets' own B words.

### `packet_record()`

```gdscript
static func packet_record(target: int) -> int
```

B45 fixed: the target's own record (none: no record, -2).

### `sector_reach()`

```gdscript
static func sector_reach(s2: int) -> int
```

B46 fixed: the reach squared in full.

### `long_target()`

```gdscript
static func long_target(driver_target: int, _last_chosen: int) -> int
```

B48 fixed: a planet whose long throw is under way times its driver's target.

---

*Generated by `tools/gen_api_docs.py` from the doc comments in `core/ai/classic/classic_cybertrons.gd`.*
