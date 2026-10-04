# S03 Data model

Status: draft (2026-10-01). Entities, numbering and iteration order read from the original's records and the
functions that create and search them; field lists collected from the rule specs written so far. Fields owned by
later specs (S09, S14–S18, S21) are listed with their owner and filled in when that spec is written.
References: `CreateFleet@1030:1f2e`, `GetFleetById@1030:14a8`, `GetPlanetById@1030:01e4`,
`CreateSpaceObject@1100:0000`, `DeleteSpaceObject@1100:015a`, `FindObject18ById@1030:01a0`,
`MoveSpaceObjects@10a8:0f6e`, `Token_RemainingArmor@10e0:046a`, `DecodePlanetBlock@1068:1f0c`,
`DecodeFleetBlock@1068:235e`, `DecodePlayerBlock@1068:0370`, `DecodeDesignBlock@1068:0000`; the record layouts of
the player, planet, fleet, waypoint and design structures; starsapi block notes as a second reference.

## Summary

The game state is one value that holds everything a turn reads and writes: settings, players and their races,
planets, fleets, designs, the objects in space, the random streams, and each player's messages and knowledge. The
turn engine is a function from (state, orders) to a new state, so the state must be complete, comparable and
saveable.

This spec fixes three things the rules depend on:

1. **Identity:** how every object is numbered, including the original's "lowest free number" rule.
2. **Order:** the order in which collections are iterated. Rule specs say "in fleet order" or "for each planet";
   this spec defines what that means. The order decides who draws which random number, so it must match the
   original exactly.
3. **Units and widths:** what each number means and how large it can get.

It is not a file format. Our save format (end of this spec) is a plain rendering of the model; the original's
files are read only by the dev harness (S23).

## General rules

- **Integers only.** Every gameplay number is an integer (64-bit in GDScript). Ranges below are the valid values;
  the original's narrower storage (bytes, 16-bit words) is a limit, not behaviour, except where a rule spec says a
  value wraps or truncates.
- **Content by id.** Parts, hulls, traits and other definitions are referenced by their string content id
  (`part.engine.quick_jump_5`). Original numeric ids appear only in `content/core/legacy_ids.json` and the harness.
- **Players by index.** A player is referenced by its index, 0 to (player count − 1). "No owner" is −1.
- **Collections are lists in a defined order,** never dictionaries iterated in insertion or hash order. Where a list
  is keyed, it is kept sorted by that key.
- **Mod data.** Every entity (game, player, planet, fleet, design, space object) has a `mod_data` map from mod id to
  that mod's own JSON-style value (integers, strings, booleans, lists, maps; no floats). The engine saves, copies and
  compares it, and never interprets it.
- **Turn-only marks.** A few flags exist only during turn generation (for example "didn't move this turn"). They are
  reset at the start of the phase that uses them, are not saved, and are not part of equality.
- **Derived values are not stored.** A design's mass, cost, armor, fuel capacity, and so on are computed from content
  and the owner's tech level (S04) when needed, so a content change or a mod patch can never leave stale copies.
  (Stored counters such as "ships built" are not derived values.)

## Game

| Field | Meaning |
|---|---|
| `turn` | 0 in the first year; the year shown to players is 2400 + turn |
| `settings` | universe and rule options, below |
| `players` | list, by index |
| `planets` | list, by planet id |
| `fleets` | list, sorted by (owner, number) |
| `minefields`, `packets`, `wormholes`, `traders` | space objects, below |
| `rng` | the random streams (S01): game seed and each stream's state |
| `messages` | per player, this turn's messages (S21) |
| `battles` | this turn's battle records (S16) |
| `history` | per player, score history (S20) |
| `mod_data` | per mod |

### Settings

| Field | Meaning |
|---|---|
| `universe_width` | light years; the universe spans 1000 … 1000 + width on both axes (positions are absolute) |
| `density`, `player_positions` | universe generation inputs (S07) |
| `options` | the game options as named booleans: `max_minerals`, `slow_tech`, `accelerated_start`, `no_random_events`, `computer_alliances`, `public_scores`, `galaxy_clumping`, plus the "techs start at 3" option that lives on the race (S06) |
| `victory` | victory conditions (S20) |
| `tutorial` | the tutorial game (reseeds the classic stream each turn, S01) |
| `content_hash`, `mods` | the ruleset hash and the list of enabled mods with versions, from the mod loader (M2) |

## Player

| Field | Meaning |
|---|---|
| `index` | 0 … 15 by default (limit `limits.players`) |
| `race` | the race definition (S06): names, logo, primary and lesser traits, habitability, growth rate, economy settings, research costs, leftover-points choice, options |
| `ai` | none (human) or a personality and level (S22) |
| `active` | still in the game |
| `homeworld` | planet id |
| `tech_levels` | six integers 0 … 26, in tech field order (energy, weapons, propulsion, construction, electronics, biotech) |
| `research_points` | six integers, progress toward each field's next level (S05) |
| `research_percent` | 0 … 100 (default 15) |
| `research_field`, `next_research_field` | S05 |
| `relations` | one per player index: neutral, friend or enemy |
| `battle_plans` | list of battle plans (S16) |
| `ship_designs` | 16 slots (limit `limits.ship_designs`), each empty or a design |
| `starbase_designs` | 10 slots (limit `limits.starbase_designs`), each empty or a design |
| `default_queue` | the production queue a newly colonized planet starts with: standard items only, at most 12, progress 0 (S09, S11) |
| `default_leftover_to_research` | a new colony's "contribute only leftover resources to research" setting |
| `trader_parts` | Mystery Trader parts obtained (S18) |
| `knowledge` | what this player knows of other objects (S15), below |
| `mod_data` | per mod |

A design is referenced as (owner, kind, slot), where kind is ship or starbase. Slot numbers are stable: deleting a
design empties its slot and never renumbers the others.

### Design

| Field | Meaning |
|---|---|
| `name` | text |
| `hull` | hull content id |
| `slots` | one entry per hull slot, in the hull's slot order: part content id (or none) and count |
| `turn_designed` | turn |
| `built`, `remaining` | ships of this design ever built, and still existing (score and reports) |
| `picture` | cosmetic picture index |
| `transferred` | the design came with ships another player transferred (S11); such ships count at a quarter of their cost when scrapped or colonizing |

## Planet

Planets are numbered 0 … (count − 1) when the universe is created (S07), in that order, and keep their id for the
whole game. "Each planet" means in id order.

| Field | Meaning |
|---|---|
| `id`, `name`, `x`, `y` | fixed at creation |
| `owner` | player index or −1 |
| `environment` | gravity, temperature, radiation, each 0 … 100 (current values) |
| `environment_original` | the values before any terraforming |
| `concentration` | mineral concentration per mineral (ironium, boranium, germanium), 0 … 255 |
| `concentration_fraction` | per mineral, the 0 … 255 fraction byte mining uses (S08) |
| `surface` | kT per mineral |
| `population` | units of 100 colonists |
| `extra_colonists` | 0 … 99 single colonists (S08) |
| `mines`, `factories` | 0 … 4095 |
| `defenses` | 0 … 4095 (the planet's maximum is lower, S08) |
| `homeworld` | flag |
| `has_scanner` | a planetary scanner has been built (S15) |
| `starbase` | none, or the design slot of the owner's starbase design plus its damage in armor points (0 … 4095) |
| `mass_driver_target`, `mass_driver_warp` | packet destination planet (−1 = none) and the driver's warp setting (S09, S14) |
| `route` | route destination for new fleets (planet id or none) (S11) |
| `queue` | production queue (S09): items with `item` (content id of a `production_item`, or "" for a design), `design` (slot, −1 for a standard item), `starbase`, `count` (0–1023), `progress` (0–100% of one unit) |
| `leftover_to_research` | only resources left after the queue go to research (S09) |
| `artifact` | random-event artifact (S18) |
| `mod_data` | per mod |

## Fleet

| Field | Meaning |
|---|---|
| `owner`, `number` | identity; see "Numbering" |
| `name` | none (the default name is built by the UI from the first design and the number) or a custom name |
| `x`, `y` | position |
| `planet` | planet id when in orbit, else −1 |
| `stacks` | list of ship stacks, sorted by design slot (one stack per design at most) |
| `cargo` | ironium, boranium, germanium (kT), colonists (kT; 1 kT = 100 colonists), fuel (mg) |
| `battle_plan` | index into the owner's battle plans |
| `waypoints` | list; the first is where the fleet is now, the second its next destination (limit `limits.waypoints`, 87 by default) |
| `repeat` | repeat orders (S12) |
| `mod_data` | per mod |

### Stack

| Field | Meaning |
|---|---|
| `design` | ship design slot of the owner |
| `count` | ships, 1 … `limits.ships_per_stack` |
| `damaged_percent` | 0 … 100: percentage of the stack's ships that are damaged |
| `damage` | 0 … 499: damage of each damaged ship, in 1/500 of the design's armor (the original caps it at 499 when loading) |
| `paid` | resources and minerals actually paid for these ships (B14 fix, S11) |

The damage pair is the original's representation, and the battle, mine and gate rules (S12, S13, S16) are written
against it. The number of damaged ships is count × damaged_percent div 100 (at least 1 when damaged_percent > 0, as
those rules state). Whether the B09 fix needs a finer field is decided in S16.

### Waypoint

| Field | Meaning |
|---|---|
| `x`, `y` | position |
| `target` | none (deep space), or a planet id, fleet (owner, number) or space object (kind, owner, number) |
| `warp` | 0 … 10, or 11 for stargate travel |
| `task` | none, transport, colonize, remote mine, merge, scrap, lay mines, patrol, route, transfer |
| `task_data` | depends on the task (S11): per cargo type an action and an amount for transport; the target fleet, player, years or range for the others |

The original's "task slot in use" bit is UI state and is not modelled. Its "frozen position" bit is a turn-only
mark (S12).

## Space objects

Four kinds of objects live in space. In the original they are one list, sorted by an id that puts the kind first,
then the owner, then a number. We keep one list per kind, each sorted by (owner, number). **The original's combined
order is therefore: all minefields, then packets and salvage, then wormholes, then the Mystery Trader,** each in
(owner, number) order. A rule that loops over "all space objects" (for example `MoveSpaceObjects`) uses exactly
that order.

| Kind (order) | Collection | Fields | Spec |
|---|---|---|---|
| 0 Minefield | `minefields` | owner, number, x, y, mines, type (standard, heavy, speed bump), detonate order, players who have seen it | S13 |
| 1 Packet or salvage | `packets` | owner, number, x, y, minerals per type; packets: destination planet, warp; salvage: no destination, warp 0 | S14 |
| 2 Wormhole | `wormholes` | number, x, y, other end, stability, age (years since it last moved), players who have seen it | S12, S18 |
| 3 Mystery Trader | `traders` | number, x, y, destination, warp, item, players met | S18 |

Packets and salvage share one kind and one numbering, so they are one collection with a `salvage` flag.
Wormholes and the Mystery Trader have no owner (the original stores owner 0 for them; we use −1 and sort them by
number, which gives the same order since all share one owner value).

"Players who have seen it" is a sorted list of player indices.

## Numbering

- **Fleets:** a new fleet of player p gets the lowest number not used by any of p's fleets, starting from 0 (the
  original scans p's fleets in number order for the first gap). It is inserted in (owner, number) order.
  Numbers are never reused while the fleet exists and never renumbered.
- **Space objects:** the same rule within one (kind, owner): the lowest unused number.
- **Limits:** a player has at most `limits.fleets_per_player` fleets (512); a (kind, owner) has at most
  `limits.space_object_numbers` numbers; the game has at most `limits.space_objects` space objects in total (the
  original refuses to create one beyond 4050). When a limit is reached, creation fails and the rule that tried it
  says what happens (usually nothing is created).
- The original's fleet id (owner × 512 + number) is used only by the harness.

## Iteration order

Unless a rule spec says otherwise:

| Phrase in a spec | Order |
|---|---|
| each player | index ascending |
| each planet | id ascending |
| each fleet / fleet order | owner ascending, then number ascending |
| each stack of a fleet | design slot ascending |
| each minefield, packet, wormhole | owner ascending, then number ascending, within the kind |
| all space objects | the combined order above |
| each design of a player | ship designs by slot, then starbase designs by slot |

A rule that creates or deletes objects while iterating states how the loop continues; by default it visits the
list as it was at the start of the loop, skipping objects deleted since.

## Player knowledge (S15)

Each player keeps what it has learnt of things it does not own, because reports and the map show the last seen
values:

- per planet: the year last seen, how much is known (from position only up to full detail), and the values seen;
- the designs of other players it has seen (hull and visible parts);
- fleets seen this turn (position, heading, warp, mass), rebuilt each turn;
- minefields and wormholes seen (the "seen by" lists above).

S15 fills in the details; the model only reserves the place.

## Equality, copies and hashing

- Two states are **equal** when their saved forms (below) are equal. Turn-only marks are not compared.
- A **copy** is a deep copy; changing it never changes the original (used by AI lookahead and tests).
- The **state hash** is SHA-256 of the canonical saved form: keys sorted, no whitespace, integers in decimal. It is
  used by tests, PBEM consistency checks and the harness.

## Saved form

Our own JSON format, written by `core/io` only:

```json
{
  "format": "starsgodot-save",
  "format_version": 1,
  "game_version": "0.1.0",
  "ruleset_hash": "<sha-256 from the content registry>",
  "mods": [{ "id": "core", "version": "0.1.0" }],
  "state": { "...": "the fields above, by name" }
}
```

- Objects are written with their field names; lists keep the model order.
- All numbers are integers. JSON readers may return them as floats; the loader converts and rejects any value with
  a fraction. Every value the model holds fits in 53 bits, so the conversion is exact. The game seed is limited to
  0 … 2^53 − 1 for this reason.
- Loading validates ranges, references (planet ids, design slots, content ids) and ordering, and reports every
  problem with its path, like the content loader does. A game only loads when there are none.
- A save whose `ruleset_hash` or mod list differs from the running game's loads only after the player confirms
  (and never in PBEM hosting).
- `format_version` increases whenever the saved form changes; older versions are converted on load.

## Randomness

None. The order rules above decide which object receives which draw in every other spec.

## Known bugs

- **B24 32k ships per fleet:** ship counts are wide integers; `limits.ships_per_stack` (default 32767) is a rule
  constant, and a merge that would exceed it is refused instead of losing ships.
- **B25 crash with the 10th starbase design:** our design slots are a list indexed from 0 with bounds checks; the
  turn engine never reads past the end. The root cause in the original is still to be found (S16 or S09).
- **L01 limits:** `limits.players` 16, `limits.fleets_per_player` 512, `limits.ship_designs` 16,
  `limits.starbase_designs` 10, `limits.waypoints` 87, `limits.space_objects` 4050, plus the battle limit in S16.
  They are content constants, so mods can raise them.

## Worked examples

- Player 2 has fleets numbered 0, 1 and 3. A new fleet of player 2 gets number 2 and is placed between them. The
  original's fleet id would be 2 × 512 + 2 = 1026.
- Minefields of players 1 and 0, a packet of player 0, and one wormhole: the combined order is player 0's
  minefield, player 1's minefield, player 0's packet, the wormhole.
- A stack of 10 ships of a design with 100 armor, damaged_percent 50, damage 20: 5 ships are damaged, each by
  20 × 100 ÷ 500 = 4 armor; the stack has lost 20 armor of its 1000.

## Mod hooks

- Content constants (ids `constant.limits.<name>`): `limits.players`, `limits.fleets_per_player`,
  `limits.ship_designs`, `limits.starbase_designs`, `limits.waypoints`, `limits.ships_per_stack`,
  `limits.space_objects`, `limits.space_object_numbers`.
- `mod_data` on every entity.
- Mods cannot add new entity kinds in this version; they attach data to existing ones.

## Open questions

1. The exact highest number a (kind, owner) can use for space objects (the original's check allows 511 or 512).
2. The production queue item's progress fields (S09).
3. The meaning of installation byte 5 (S23) (S08, S15).
4. Wormhole and Mystery Trader fields beyond position (S12, S18).
