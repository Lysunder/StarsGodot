# ClassicWorld

`core/ai/classic/classic_world.gd`, extends `RefCounted`

The game as one of the original's computer players has it loaded (spec S22 "The classic
world"): a copy of the state in which the player's own planets, fleets and designs are as they
are, other players' and unowned planets are as its planet history knows them (S15), and other
players' fleets and designs are there only as far as it has seen them. The classic
personalities read only this. Their orders are applied to it as they are given (so later
choices see them, as the original's edits to its loaded game) and recorded for the turn.

Also the per-turn setup every classic personality shares (`AI_PlayTurn`): the player's
planets in shuffled order (the turn's first draws), a 16-byte record per planet
(`planet_info`), the design ratings, and each known minefield's radius squared; and the
working memory the personality keeps from turn to turn (the original keeps it in the player's
history file; we keep it in the player's knowledge, `MEMORY_KEY`, and send it back as an order,
`memory_order`).

## Constants

- `const SCANNED := 3`: Detail levels (S15).
- `const OWN := 7`
- `const UNKNOWN_ESTIMATE := 0xFFF`: The population estimate of a planet the player has never seen (the 12-bit field all set).
- `const INFO_BOMBERS := 8`: `planet_info` bytes: an enemy bomber orbits this planet of the player's (`AI_ScanFleets`).
- `const INFO_SIZE := 16`
- `const MEMORY_WORDS := 0x1000`: The original's working memory: 0x2000 bytes of 16-bit words; the first holds the bytes in use, the word itself included (2 when empty).
- `const MEMORY_FIRST := 2`
- `const MEMORY_KEY := OrderRules.AI_MEMORY_KEY`
- `const SLOT_TURNS_KEY := "classic_slot_turns"`: The shared design buffer's key and slot count, and the formula id for an empty slot's turn designed (S25 B54).
- `const SHIP_SLOTS := 16`
- `const EMPTY_SLOT_TURN := "ai.empty_slot_turn"`
- `const MINEFIELD_MARGIN := 10`: Light years the computer players add to a minefield's radius (`AI_InitScale`).
- `const BOMBER_CLASS := "ai_hull_class.bomber"`
- `const ROBOTOIDS := "ai_personality.robotoids"`
- `const TURINDRONES := "ai_personality.turindrones"`
- `const AUTOMITRONS := "ai_personality.automitrons"`
- `const ROTOTILLS := "ai_personality.rototills"`
- `const CYBERTRONS := "ai_personality.cybertrons"`
- `const MACINTI := "ai_personality.macinti"`
- `const DEPOT_COUNT := 1`: Freighter depot records in the memory (`AI_PlanFreighterDepots`): the count in word 1, then DEPOT_WORDS words each from word 2: the planet, how many fleets, and up to DEPOT_FLEETS fleets.
- `const DEPOT_FIRST := 2`
- `const DEPOT_WORDS := 10`
- `const DEPOT_FLEETS := 8`
- `const SELECT_NONE := 0`
- `const SELECT_PLANET := 1`
- `const SELECT_FLEET := 2`
- `const FLEET_ID_OWNER_SHIFT := 9`: A fleet's id word (owner << 9 | number), for the selection.

## Variables

- `var state: GameState`
- `var content: ContentRegistry`
- `var player: int = 0`
- `var personality := ""`: The content id of the original personality being played (ROBOTOIDS ...).
- `var rng: StarsRandom`
- `var detail := {}`: Planet id -> detail level as loaded (0 never seen, 1 glimpsed, 3 scanned, 7 own).
- `var loaded := {}`: Planet ids the player's turn file holds (its own and those the planet history records): the original's loaded planets, {id: true}.
- `var seen_turn := {}`: Planet id -> the turn it was last seen (this turn for the player's own; 0 never seen).
- `var own_planets: Array[Planet] = []`: The player's planets, shuffled.
- `var planet_count := 0`: The planet count of the player's record while the brain plays: its own planets (the turn file's record counts the planets it sees too, but turin1 turn 69's freighters follow the own count).
- `var planet_info := {}`: Planet id -> PackedByteArray(INFO_SIZE).
- `var ratings := {}`: "owner/slot" -> rating (`Designs_ComputeRatings`), ship designs of every player loaded.
- `var minefield_scale := {}`: Minefield -> the radius squared the computer player keeps clear of: trunc(sqrt(mines) + 10.5), squared (`AI_InitScale`: the field's radius rounded, plus MINEFIELD_MARGIN light years).
- `var memory := PackedInt32Array()`: The working memory, MEMORY_WORDS words.
- `var orders: OrderSet`
- `var rejected := PackedStringArray()`
- `var selected_kind := SELECT_NONE`: The selection the original edits through (`SetSelection`): a planet or a fleet, and the copy of a planet being edited (`g_curPlanet`): the selected planet, or the selected fleet's. Edits to the copy reach the world only when committed; selecting what is already selected keeps the copy as it is.
- `var selected_id := -1`
- `var cur_planet: Planet = null`
- `var editing: RefCounted = null`: The production being edited (ClassicProduction.Edit), or null.
- `var colony_targets_rated := false`: Colony targets were rated this turn (personalities other than Robotoids and Macinti rate once).
- `var slot_turns: Array = []`: The turn designed the original's buffer of the player's ship designs holds in each slot (shared by the computer players of one turn): a player's file sets its designs' slots, an empty slot keeps what the last computer player loaded or saved there (S25 B54).
- `var macinti_verdicts := PackedByteArray()`: Macinti's starbase verdicts this turn (ClassicMacinti.review_designs), read by the production pass's starbase step.

## Functions

### `build()`

```gdscript
static func build(host: GameState, p_content: ContentRegistry, p: int, p_rng: StarsRandom, p_personality: String = "") -> ClassicWorld
```

The world of player `p` of `host`, playing personality `p_personality` (by default the one
the player's key names).

### `me()`

```gdscript
func me() -> Player
```

### `load_slot_turns()`

```gdscript
func load_slot_turns(shared: Dictionary) -> void
```

Joins the computer players' shared design buffer (`LoadGame` of the player's file): the
player's designs set their slots' turns.

### `empty_slot_turn()`

```gdscript
func empty_slot_turn(slot: int) -> int
```

The turn designed the design buffer holds in an empty ship slot (S25 B54; fixed: 0).

### `no_empty_slot_turn()`

```gdscript
static func no_empty_slot_turn(_held: int) -> int
```

B54 fixed: an empty slot has no turn designed.

### `personality_id()`

```gdscript
func personality_id() -> String
```

The content id of the personality being played.

### `is_computer()`

```gdscript
func is_computer(index: int) -> bool
```

Whether player `index` counts as a computer player (one, or a human player marked inactive:
the original flags both alike).

### `memory_order()`

```gdscript
func memory_order() -> Dictionary
```

The order that keeps the working memory for the next turn (S11 `ai_memory`): the words in use
(none when only the count word is), or {} when the knowledge holds them already.

### `order()`

```gdscript
func order(o: Dictionary) -> String
```

Gives an order: applied to the world at once, and kept for the turn when accepted.

### `is_depot()`

```gdscript
func is_depot(planet_id: int) -> bool
```

Whether a planet is one of the freighter depots in the memory.

### `depot_of_planet()`

```gdscript
func depot_of_planet(planet_id: int) -> int
```

The depot record of a planet, or -1.

### `select_planet()`

```gdscript
func select_planet(id: int) -> void
```

Selects a planet (`SetSelection(1, id)`): the planet copy is loaded unless it is selected
already.

### `select_fleet()`

```gdscript
func select_fleet(fleet: Fleet) -> void
```

Selects one of the player's fleets (`SetSelection(2, id)`): the planet copy becomes the
fleet's planet (none in deep space) unless that planet's copy is loaded already.

### `reload_planet()`

```gdscript
func reload_planet() -> void
```

Reloads the planet copy from the world (after a commit).

### `fleet_id()`

```gdscript
static func fleet_id(fleet: Fleet) -> int
```

A fleet's id word, as the memory keeps it.

---

*Generated by `tools/gen_api_docs.py` from the doc comments in `core/ai/classic/classic_world.gd`.*
