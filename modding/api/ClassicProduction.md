# ClassicProduction

`core/ai/classic/classic_production.gd`, extends `RefCounted`

How the classic personalities edit production (spec S22 "Classic production"): what the
selected planet can build (`BuildProductionList`), queue edits committed as one order
(`AI_QueueProduction`, `CommitProductionQueue`), and the estimates their choices rest on
(`AI_EstimatePlanetOutput`, `AI_EstimateQueueCost`, `Production_SimulateQueue`).

## Constants

- `const UNLIMITED := 1023`: A list count meaning "as many as you like".
- `const INSTALLATION_CAP := 1020`: The most mines or factories the list offers at once.
- `const QUEUE_LIMIT := 200`: Planets with more queue items than this take no more.
- `const ESTIMATE_YEARS := 100`: Years the completion estimate looks ahead; an item not done by then counts as this.
- `const STOPS_YEAR := Production.Status.SOME_BUILT`: Spending results that end the year's production in the estimate (Production.Status).
- `const MINES := "production_item.mines"`
- `const FACTORIES := "production_item.factories"`
- `const DEFENSES := "production_item.defenses"`
- `const ALCHEMY := "production_item.alchemy"`
- `const AUTO_ALCHEMY := "production_item.auto_alchemy"`
- `const TERRAFORM := "production_item.terraform"`
- `const GENESIS := "production_item.genesis"`
- `const SCANNER := "production_item.planetary_scanner"`
- `const PACKETS`
- `const AUTO_ITEMS`: Auto items in list order, with the trait parameter that keeps a race from them.
- `const NO_SCANNER_PARAM := "production.no_planetary_scanner"`

## Enums

- `enum Mode { TOP, APPEND, REPLACE }`: Queue edits: put the item first, last, or make it the whole queue.

## Functions

### `standard()`

```gdscript
static func standard(item: String, count: int = 0) -> QueueItem
```

### `ship()`

```gdscript
static func ship(slot: int, count: int = 0) -> QueueItem
```

### `starbase()`

```gdscript
static func starbase(slot: int, count: int = 0) -> QueueItem
```

### `same()`

```gdscript
static func same(a: QueueItem, b: QueueItem) -> bool
```

Same item, ignoring count and progress.

### `buildable()`

```gdscript
static func buildable(w: ClassicWorld, planet: Planet) -> Array[QueueItem]
```

What the planet can build, in the original's list order, each with how many more: ship designs
a dock there can hold, starbase designs but the one it has, the genesis device, packets when it
has a mass driver, factories and mines (up to INSTALLATION_CAP) and defenses up to their
maximum, alchemy, a planetary scanner when it has none, terraforming steps it still has, and the
auto items. Designs that came with transferred ships are never listed.

### `open()`

```gdscript
static func open(w: ClassicWorld) -> Edit
```

Opens the selected planet's production for editing (`BuildProductionList`): the queue is
copied, each item is held to what the list offers (and the list's count lowered by it), and an
item the list does not have becomes alchemy x0.

### `add()`

```gdscript
static func add(w: ClassicWorld, item: QueueItem, count: int, mode: Mode) -> void
```

Adds an item to the selected planet's queue (`AI_QueueProduction`). With no edit open, one is
opened, the count held to what the list offers (0 when it is not listed) and committed after;
with one open the count is taken as it is (its low 10 bits, as the original stores it). A
planet with more than QUEUE_LIMIT items takes nothing.

### `commit()`

```gdscript
static func commit(w: ClassicWorld, changed: bool) -> void
```

Ends the edit (`CommitProductionQueue`): when `changed`, the queue is given as the planet's
order and the planet copy reloaded. A design item for an empty slot is left out (the original
sends it and the year's production drops it).

### `item_cost()`

```gdscript
static func item_cost(w: ClassicWorld, planet: Planet, q: QueueItem, per_unit: bool) -> Array[int]
```

What a queue item costs at a planet: one unit (`per_unit`) or the whole count, progress not
counted; nothing for a design slot that is empty.

### `output()`

```gdscript
static func output(w: ClassicWorld, planet: Planet) -> Array[int]
```

This year's minerals and resources (`AI_EstimatePlanetOutput`): the surface plus this year's
mining (-1 each for a planet with no people), and the resources less the research share. The
share is left in when the selected planet copy (not necessarily this planet) gives only its
leftovers to research.

### `queue_cost()`

```gdscript
static func queue_cost(w: ClassicWorld, planet: Planet) -> Array[int]
```

The whole queue's cost (`AI_EstimateQueueCost`): every item at its full count, auto items
included.

### `completion()`

```gdscript
static func completion(w: ClassicWorld, planet: Planet, index: int) -> Array[int]
```

When queue item `index` of `planet`'s queue is first built and done (`FormatQueueItemETA`,
`Production_SimulateQueue`): [first year, last year], 1 being this year. Each year the planet
(a copy) mines, then spends its resources less the research share on the items in order, as
production does (S09 step 5; an auto alchemy item is passed over, its effect going to the item
after it, unless it is the last, which may then build up to INSTALLATION_CAP); what an item
carries over is spent first the next year; built mines and factories count from then on; the
people grow. An item still not done after ESTIMATE_YEARS - 1 years counts as ESTIMATE_YEARS;
an item never begun before an auto item stops is [0, 0], and an auto alchemy item that is not
the last is [-1, -1].

## Inner class `ClassicProduction.Edit`

Extends `RefCounted`.

A planet's production being edited: the queue as it will be committed, and what can still be
added (`count` of each list item: how many more, UNLIMITED for any number).

### Variables

- `var planet_id := -1`
- `var queue: Array[QueueItem] = []`
- `var buildable: Array[QueueItem] = []`

### Functions

#### `listed()`

```gdscript
func listed(q: QueueItem) -> QueueItem
```

The first list item of the same kind as `q`, or null.

#### `queued()`

```gdscript
func queued(q: QueueItem) -> bool
```

Whether the queue has an item of the same kind as `q`.

---

*Generated by `tools/gen_api_docs.py` from the doc comments in `core/ai/classic/classic_production.gd`.*
