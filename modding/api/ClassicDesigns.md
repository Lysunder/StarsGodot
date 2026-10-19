# ClassicDesigns

`core/ai/classic/classic_designs.gd`, extends `RefCounted`

How the classic personalities make and retire designs (spec S22 "Classic designs"): a design
from a template (a hull and a part class per slot, each slot filled with the best part of its
class the player can use, as many as the slot holds), a picture and a name drawn from the
hull's name list, and the starbase designs every classic personality keeps up to date.

## Constants

- `const NAME_TRIES := 20`
- `const NAME_NUMBERS := 100`
- `const PICTURES := 4`
- `const STARBASE_NAMES := "ai_design_names.starbase"`
- `const OTHER_NAMES := "ai_design_names.utility"`
- `const STATION := "ai_design_template.space_station"`
- `const FORT := "ai_design_template.orbital_fort"`
- `const FORT_SLOTS := [1, 3, 6, 8]`: Starbase slots that hold forts; the others hold stations (`AI_CreateDesign`).
- `const STATION_SLOTS := [0, 2, 4, 5, 7, 9]`: The two generations of stations and forts (`AI_UpdateStarbaseDesigns`), and how old the newest one gets before the other generation is designed.
- `const FORT_GENERATION_SLOTS := [1, 3, 6, 8]`
- `const GENERATION_TURNS := 40`
- `const STARBASE_REVIEW_TURN := 50`
- `const FULL := 3`: Starbase design sizes: 1 small, 2 medium, 3 full.
- `const ORBITAL := "orbital"`: Part category whose slots a small starbase leaves empty.
- `const KEEPS_SMALL_SLOTS := ["ai_personality.cybertrons"]`: Personalities whose small starbases keep their single-part slots.

## Functions

### `best_part()`

```gdscript
static func best_part(w: ClassicWorld, class_id: String) -> String
```

The best part of an `ai_part_class` the player can use, or "" (`AI_BestPartOfClass`): the
candidate groups in order, each best part first.

### `from_template()`

```gdscript
static func from_template(w: ClassicWorld, template_id: String) -> Design
```

A design from template `template_id`, or null when the player cannot use the hull or a slot's
class has no part it can use (`AI_OutfitDesign`): every slot holds as many parts as the hull
allows.

### `outfit()`

```gdscript
static func outfit(w: ClassicWorld, slot: int, template_id: String) -> bool
```

Designs ship slot `slot` from a template, named from the hull's list, and gives the order;
false when a part is missing or the order is refused.

### `create_starbase()`

```gdscript
static func create_starbase(w: ClassicWorld, slot: int, size: int, template_id: String = "") -> bool
```

A starbase design (`AI_CreateDesign`) of `size` 1 (small) to 3 (full) in starbase slot `slot`:
a fort in FORT_SLOTS (where a medium fort is a full one), a station elsewhere, unless
`template_id` names another. Smaller sizes hold fewer parts: slots of 4 or more a quarter (size
1) or half (size 2); for size 1 smaller slots one part less, and orbital slots none.

### `save()`

```gdscript
static func save(w: ClassicWorld, design: Design, starbase: bool) -> bool
```

Stores a design in its slot (`AI_SaveDesign`); the turn is stamped. A design already there is
deleted first in the turn's orders, so the host takes it out of the queues and fleets, but in
this world it is only overwritten: queue items, ships and starbases of the slot stay and now
refer to the new design. False when the order is refused.

### `delete()`

```gdscript
static func delete(w: ClassicWorld, slot: int, starbase: bool) -> void
```

Empties a design slot. The turn's orders delete it, so the host takes it out of the queues and
fleets; in this world, as in the original's (which only marks the slot empty), queue items and
ships of the slot stay.

### `names_for()`

```gdscript
static func names_for(content: ContentRegistry, hull: String, starbase: bool) -> Array
```

The names for a hull's designs: the first `ai_design_names` listing the hull, else the list
for other hulls.

### `newest_in_slots()`

```gdscript
static func newest_in_slots(w: ClassicWorld, low: int, high: int, max_age: int, obsolete: Array) -> Dictionary
```

The newest design among ship slots `low`..`high` (`AI_FindDesignForHulls`): the first of the
latest turn designed. Designs older than `max_age` turns are deleted when no ships of them are
left (even the one returned), else marked in `obsolete` (by slot). Returns {slot (-1 none),
remaining: ships of the slots left, at most 32000}.

### `update_starbase_designs()`

```gdscript
static func update_starbase_designs(w: ClassicWorld) -> void
```

Keeps the starbase designs (`AI_UpdateStarbaseDesigns`): a medium station in slot 2 and a full
one in 4 when 2 is empty, a small fort in 1 when empty, a full fort in 3 when empty. From turn
STARBASE_REVIEW_TURN, when the newest station (slots 0, 2, 4, 5, 7, 9) is GENERATION_TURNS old,
the other generation (0, 2, 4 or 5, 7, 9) is designed small, medium, full, unless one of its
designs still has starbases; likewise forts (1, 3 or 6, 8: small, full) when neither has any.

### `newer_starbase()`

```gdscript
static func newer_starbase(w: ClassicWorld, older: int, newer: int) -> int
```

`newer` when its starbase design is newer than `older`'s, else `older`
(`AI_NewerStarbaseDesign05`, `AI_NewerStarbaseDesign16`).

---

*Generated by `tools/gen_api_docs.py` from the doc comments in `core/ai/classic/classic_designs.gd`.*
