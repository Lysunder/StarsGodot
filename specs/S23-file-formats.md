# S23 File formats (harness import only)

Status: draft (2026-10-01), second pass. Covers the container (framing, cipher, header, footer), the packed text
encoding, and every block the importer needs for the host state: settings with planet positions (7), players (6),
planets (13, 14) with production queues (28), fleets (16, 17) with waypoints (19, 20) and names (21), designs (26),
space objects (43) and battle plans (30). Checked by decoding real files from the harness: two small games and an
80-turn game with five computer players (`runs/big1`). Scores, events, messages and battle records are listed but
not imported; order files (`.x`) are a later pass (see "Order files").
References: `ReadBlock@1068:305a`, `WriteBlock@1068:579a`, `WriteFileHeader@1068:53f8`,
`ReadGameFileHeader@1068:54ea`, `InitFileCipher`, `CipherNext`, `CipherBlock` (1038:89aa..8ae6), `LoadGame@1068:0508`,
`DecodePlayerBlock@1068:0370`, `DecodePlanetBlock@1068:1f0c`, `DecodeFleetBlock@1068:235e`,
`DecodeDesignBlock@1068:0000`, `DecodeStarsString@1038:a666`, `DecodeStarsChar@1038:a842`,
`NewGameFromDefFile@1070:39d4`, `CreateSpaceObject@1100:0000`, `DropSalvage@10e8:183a`. starsapi
(github.com/stars-4x/starsapi) as the second reference; where it disagrees with the code, the code wins (noted).

## Summary

The game itself never reads or writes the original's files (decision: new save format). Only the dev harness does:
`tools/harness/` (Python, M4) reads the original's files and writes our JSON save format (S03), so golden-turn tests
can compare our engine with the original. This spec describes just enough of the original's formats for that.

**Out of scope, by rule:** the serial-number and registration data. The importer skips block type 9 entirely and
never interprets the parts of headers or player records that relate to registration; this spec does not describe
them. Passwords are not imported either.

## File kinds

All files of one game share a base name and a game id.

| Extension | Written by | Holds |
|---|---|---|
| `.xy` | game creation | universe settings and planet positions/names |
| `.hst` | host | the full game state (the importer's main source) |
| `.m1` … `.m16` | host | one player's view of this turn (embedded turns accumulate when the host runs several turns in one process) |
| `.h1` … `.h16` | player client | that player's accumulated history |
| `.x1` … `.x16` | player client | that player's orders for the turn (second pass) |

## Container

A file is a sequence of **blocks**. Each block is a 16-bit little-endian header, `type << 10 | size` (type 0–63, size
0–1023 bytes), followed by `size` bytes of data. All multi-byte numbers are little-endian; signed values are two's
complement.

1. The first block is the **file header** (type 8, 16 bytes), never encrypted.
2. Every later block's data is encrypted, except the footer (type 0), whose data is plain.
3. The last block is the **footer** (type 0): 2 bytes in `.hst` and `.m` files (a checksum the importer does not
   need), 0 bytes in `.h` files. A `.m` file written for several turns repeats header … footer once per turn.
4. Exception: in `.xy` files, the settings block (7) is followed by raw, **unframed** planet data (4 bytes per
   planet, not encrypted), then the footer.

### File header (type 8)

| Offset | Size | Meaning |
|---|---|---|
| 0 | 4 | magic `J3J3` |
| 4 | 4 | game id (random, chosen at creation; the same in every file of the game) |
| 8 | 2 | version: major in bits 12–15, minor in bits 5–11, increment in bits 0–4 (2.6i files: 0x2A2A) |
| 10 | 2 | turn (year − 2400) |
| 12 | 2 | bits 0–4: player index (31 in host and `.xy` files); bits 5–15: the cipher salt |
| 14 | 1 | file kind: 0 `.xy`, 1 `.x`, 2 `.hst`, 3 `.m`, 4 `.h` |
| 15 | 1 | status flags; bit 4 enters the cipher setup (below); the importer needs no other bit |

The salt is drawn when the file is written: one `random(2000)` from the game's generator plus the clock tick count
(S01, "Draws outside the rules"). It is why two otherwise identical files differ.

### Cipher

The data of each encrypted block is XORed with a keystream made from the two S01 component generators, seeded from
the header. Each keystream value is (s1 − s2) mod 2^32 after both components advance: the plain 32-bit difference,
**without** the correction `random()` applies when the difference is below 1.

1. salt = header word at 12 shifted right by 5 (11 bits). i = salt & 31, j = (salt >> 5) & 31. If bit 10 of the salt
   is set, i += 32; otherwise j += 32.
2. The generator starts from (s1, s2) = (P[i], P[j]), with P the S01 seed table (including entry 55 = 279).
3. Discard ((game id & 3) + 1) × ((turn & 3) + 1) × ((player & 3) + 1) + f values, where f is bit 4 of header
   byte 15 (0 or 1).
4. For each encrypted block in file order, continuing the same stream: XOR each whole 4-byte group of the data with
   one keystream value (little-endian); if 1–3 bytes remain, take one more value and XOR them with its low bytes in
   order.

A new file header (in a multi-turn `.m` file) restarts the cipher from its own salt.

### Packed text

Names in blocks are stored as a length byte followed by that many bytes of packed text. A length of 0 is followed by
a plain zero-terminated string instead (player names only). Packed text is a sequence of 4-bit codes, high nibble
of each byte first:

| Codes | Character |
|---|---|
| 0–10 | one nibble: space, `a e h i l n o r s t` |
| 11–14, then n | two nibbles: k = (first − 11) × 16 + n. k 0–25 `A`–`Z`; 26–35 `0`–`9`; 36–51 `b c d f g j k m p q u v w x y z`; 52–63 `+ - , ! . ? : ; ' * % $` |
| 15, then a, b | three nibbles: the byte b × 16 + a (any character) |

A final 0xF nibble in the last byte is padding and is ignored.

## Blocks in the game-state files

Block types this spec decodes (first pass) or lists for the second pass:

| Type | Name | In | Pass |
|---|---|---|---|
| 0 | footer | all | 1 (not decoded) |
| 6 | player | `.hst`, `.m`, `.h` | 1 |
| 7 | settings and planet positions | `.xy` | 1 |
| 8 | file header | all | 1 |
| 9 | (registration data) | where present | never decoded |
| 12 | events (turn messages) | `.m` | not imported |
| 13 | planet (full) | `.hst`, `.m` | 1 |
| 14 | planet (partial view) | `.m`, `.h` | 1 |
| 16 | fleet (full) | `.hst`, `.m` | 1 |
| 17 | fleet (partial view) | `.m`, `.h` | 1 |
| 19, 20 | waypoint (follows its fleet) | `.hst`, `.m` | 1 |
| 21 | fleet name (follows its fleet's waypoints) | `.hst`, `.m` | 1 |
| 26 | design | `.hst`, `.m`, `.h` | 1 |
| 28 | production queue (follows its planet) | `.hst`, `.m` | 2 |
| 30 | battle plan | `.hst`, `.m` | 2 |
| 31, 39 | battle record and continuation | `.m` | not imported |
| 32, 33 | counters, message filter | `.h` | not imported |
| 40 | player-to-player message | `.m` | not imported |
| 41 | computer player memory | not seen yet | not imported |
| 43 | space object, preceded by a 2-byte count block of the same type | `.hst`, `.m` (to confirm) | 1 |
| 45 | player scores (24 bytes; fields belong to S20) | `.m`, `.h` | not imported |
| 1–5, 10, 23–25, 27, 29, 34–38, 42, 44, 46 | orders | `.x` | later pass |

Order in a `.hst`:

1. header;
2. players, by index;
3. planets, by id, each followed by its production queue block when the queue is not empty;
4. ship designs: for each player in order, as many design blocks as the player record's ship design count;
5. fleets in (owner, number) order, each followed by its waypoints and, if named, its name block;
6. starbase designs: for each player in order, as many as the player record's starbase design count;
7. the space object count block, then the objects in id order;
8. battle plans;
9. footer.

Design blocks carry no owner: the importer assigns them by these counts.

### Settings (type 7, 64 bytes, `.xy`)

| Offset | Size | Meaning | Our model (S03) |
|---|---|---|---|
| 0 | 4 | game id | (checked against headers) |
| 4 | 2 | universe size 0–4 | `universe_width` = (size + 1) × 400 |
| 6 | 2 | density 0–3 | `density`: sparse, normal, dense, packed |
| 8 | 2 | number of players | |
| 10 | 2 | number of planets | |
| 12 | 2 | player positions 0–3 | `player_positions`: close, moderate, farther, distant |
| 14 | 2 | (not used by the loader) | |
| 16 | 2 | options, below | the option booleans |
| 18 | 2 | turn (0 in `.xy`) | |
| 20 | 12 | victory conditions (second pass, S20) | `victory` |
| 32 | 32 | game name, zero-padded plain text | |

Options word, with the order the definition file uses (line 3) in brackets: 0x01 maximum minerals [1], 0x02 slower
tech advances [2], 0x20 accelerated start [3], 0x80 no random events [4], 0x10 computer players form alliances [5],
0x40 public player scores [6], 0x100 galaxy clumping [7]. Set by the game itself: 0x04 when there is at most one
human player (every player then starts as every other's enemy, S07), 0x08 for the tutorial (S07).

**Planet data** (after the block, 4 bytes per planet in planet id order), as a 32-bit value v:

- x = previous planet's x + (v & 1023), starting from 1000 before planet 0 (planets are sorted by x);
- y = (v >> 10) & 4095;
- name id = v >> 22 (0–999), an index into the original's list of planet names.

The name list is part of the original program, so the importer never copies it into the repository: it writes a
neutral name (`Planet <id>`) unless the developer points it at their own copy of the original (as in D13).

### Player (type 6)

Bytes 0–7 are always present. When bits 0–2 of byte 6 are all set, the full record follows: bytes 0–0x6F are the
player record, byte 0x70 is the number n of relation bytes, then n relation bytes; then the race name and plural
name (packed text each). Otherwise the names follow byte 7 directly (another player's view).

| Offset | Size | Meaning | Our model |
|---|---|---|---|
| 0 | 1 | player index | `index` |
| 1 | 1 | number of ship designs | (check) |
| 2 | 2 | number of planets (low 10 bits) | (check) |
| 4 | 2 | number of fleets (low 12 bits); starbase designs (high 4 bits) | (check) |
| 6 | 1 | bits 3–7: logo; bits 0–2: 7 when the full record follows | `race.logo` |
| 7 | 1 | bit 1: computer player; bits 2–4: AI level; bits 5–7: AI personality (7 = inactive human) | `ai`, `ai_level` |
| 8 | 2 | homeworld planet id | `homeworld` |
| 0x0A | 6 | not imported | |
| 0x10 | 3 × 1 | habitability centers: gravity, temperature, radiation (signed; −1 immune) | `race.hab_center` |
| 0x13 | 3 × 1 | habitability low ends | `race.hab_low` |
| 0x16 | 3 × 1 | habitability high ends | `race.hab_high` |
| 0x19 | 1 | growth rate (%) | `race.growth_rate` |
| 0x1A | 6 × 1 | tech levels, field order | `tech_levels` |
| 0x20 | 6 × 4 | research points, field order | `research_points` |
| 0x38 | 1 | research percentage | `research_percent` |
| 0x39 | 1 | low nibble: field being researched; high nibble: next-field setting (0–5 a field, 6 same field, 7 lowest field) | `research_field`, `next_research_field` |
| 0x3A | 4 | grows every year; probably resources spent on research (to confirm, S05/S09) | |
| 0x3E | 1 | resources per colonist (in units of 100 colonists) | `race.resources_per_colonist` |
| 0x3F … 0x44 | 6 × 1 | factory output, factory cost, factories operated, mine output, mine cost, mines operated | race economy settings |
| 0x45 | 1 | leftover-points choice | `race.leftover_points` |
| 0x46 | 6 × 1 | research cost per field: 0 expensive, 1 normal, 2 cheap | `race.research_costs` |
| 0x4C | 1 | primary trait index (S06 order) | `race.primary_trait` (via the trait ids) |
| 0x4E | 4 | bits 0–13: lesser traits (S06 order); bit 29: techs start at 3; bit 31: cheap factories | `race.lesser_traits`, options |
| 0x52 | 2 | Mystery Trader items (second pass, S18) | `trader_parts` |
| 0x54 … 0x6F | | not imported | |
| 0x70 | 1 + n | relations, one byte per player: 0 neutral, 1 friend, 2 enemy; n can be smaller than the number of players (trailing neutral entries are left out) | `relations` |

### Planet (type 13 full, 14 partial)

| Offset | Size | Meaning |
|---|---|---|
| 0 | 2 | bits 0–10: planet id; bits 11–15: owner (31 = none → −1) |
| 2 | 2 | flags (below) |
| 4 | … | sections, each present or not as the flags say, in this order |

Flags: bits 0–6 are the **detail level** (how much the file's viewer knows; 7 = everything); 0x80 homeworld;
0x200 has a starbase; 0x400 terraformed; 0x800 installations present; 0x1000 artifact; 0x2000 surface minerals
present; 0x4000 route present. (starsapi reads bits 0–6 as separate flags; the code reads them as one level.)

Sections:

1. **Environment** (detail level above 2):
   - 1 byte: two bits per mineral (ironium in bits 0–1), 0 = no fraction byte, 1 = one fraction byte follows;
   - those fraction bytes (`concentration_fraction`, 0 when absent);
   - 3 bytes concentration (`concentration`); 3 bytes environment (`environment`);
   - if terraformed, 3 bytes original environment (`environment_original`; otherwise equal to `environment`);
   - if owned, 2 bytes of estimates for other players' views (not imported).
2. **Surface** (flag 0x2000): 1 byte of two-bit length codes for ironium, boranium, germanium, population (bits
   0–1, 2–3, 4–5, 6–7; code 0/1/2/3 = 0/1/2/4 bytes), then the four values (`surface`, `population` in units of 100
   colonists).
3. **Installations** (flag 0x800, 8 bytes): byte 0 extra colonists (`extra_colonists`); bytes 1–3 mines (12 bits)
   and factories (12 bits); byte 4 and the low nibble of byte 5 defenses (12 bits); the high nibble of byte 5
   unknown; byte 6 bit 7 "contribute only leftover resources to
   research" (S09; `leftover_to_research`), bit 0 set when the planet has **no** planetary scanner (`has_scanner`);
   byte 7 zero.
4. **Starbase** (flag 0x200), full planets 4 bytes as two words:
   - word 0: bits 0–3 starbase design slot (`starbase.design`); bits 4–15 damage in armor points
     (`starbase.damage`);
   - word 1: bits 0–9 mass driver destination planet id + 1, 0 = none (`mass_driver_target`); bits 10–13 driver
     warp − 4 (`mass_driver_warp`; new colonies start at 1, warp 5); bit 14 "fought this turn", cleared on load
     (not imported); bit 15 unknown.

   Partial planets: 1 byte, the design slot.
5. **Route** (flag 0x4000, full planets only): 2 bytes, bits 0–9 route destination planet id + 1 (`route`).
6. Partial planets in `.m` and `.h` files end with 2 bytes: the turn the data was seen (player knowledge, S15).

### Fleet (type 16 full, 17 partial)

| Offset | Size | Meaning |
|---|---|---|
| 0 | 2 | bits 0–8: fleet number; bits 9–12: owner |
| 2 | 2 | owner again (16-bit) |
| 4 | 1 | kind: 7 full, 4 full except damage and orders, 3 partial |
| 5 | 1 | flags: 8 = ship counts are 1 byte each (else 2) |
| 6 | 2 | planet id in orbit, 0xFFFF = none (`planet` −1) |
| 8, 10 | 2 + 2 | x, y |
| 12 | 2 | design mask: bit d set = the fleet has ships of design slot d |
| 14 | … | one ship count per set bit, in slot order (`stacks`) |

Then, for kinds 4 and 7:

- 2 bytes of two-bit length codes (ironium, boranium, germanium, colonists, fuel in bits 0–9, codes as for planet
  surface), then the five values (`cargo`; colonists in kT = 100 colonists, fuel in mg).

Then, for kind 7 (always in `.hst`):

- 2 bytes damage mask, then one 16-bit damage word per set bit, in slot order: bits 0–6 percent of ships damaged
  (`damaged_percent`), bits 7–15 damage per damaged ship in 1/500 of armor (`damage`). On loading the original caps
  the damage part at 499;
- 1 byte battle plan (`battle_plan`); 1 byte number of waypoints n;
- then n waypoint blocks (type 19 or 20) and, if the fleet has a custom name, a name block (21, packed text).

Kinds 3 and 4 instead end with 1 byte dx, 1 byte dy (heading), 1 byte warp (low nibble), 1 zero byte, and 4
bytes total mass (player knowledge, S15).

### Production queue (type 28)

Follows its planet. 4 bytes per item, in queue order:

| Bits | Meaning |
|---|---|
| word 0, bits 0–9 | count |
| word 0, bits 10–15 | item: a standard item number (S09) or a design slot |
| word 1, bits 0–3 | kind: 2 standard item, 4 design |
| word 1, bits 4–15 | progress on the first unit (units in S09) |

The importer maps them to S03 queue items: kind 2 items through `legacy_ids.json` (`production_item` numbers),
kind 4 items below 16 to ship design slots and from 16 to starbase slots (number − 16).

### Battle plan (type 30)

4 bytes, then the plan name (packed text; length 0 means a plain zero-terminated string follows):

| Byte | Meaning |
|---|---|
| 0 | low nibble owner, high nibble plan number |
| 1 | low nibble tactic (S16) |
| 2 | low nibble primary target, high nibble secondary target (S16) |
| 3 | whom to attack: 0 nobody, 1 enemies, 2 enemies and neutrals, 3 everyone, 4 + n player n |

Value meanings are defined in S16; the importer copies them into `battle_plans`.

### Waypoint (type 19 with task data, 20 without)

| Offset | Size | Meaning | Our model |
|---|---|---|---|
| 0, 2 | 2 + 2 | x, y | `x`, `y` |
| 4 | 2 | target id: planet id, fleet id (owner × 512 + number) or space object id | `target_owner`, `target_id` |
| 6 | 1 | low nibble task (0 none, 1 transport, 2 colonize, 3 remote mine, 4 merge, 5 scrap, 6 lay mines, 7 patrol, 8 route, 9 transfer); high nibble warp | `task`, `warp` |
| 7 | 1 | low nibble target kind: 1 planet, 2 fleet, 4 deep space, 8 space object; 0x10 UI bit; 0x20 frozen (cleared on load) | `target` |
| 8 | 10 | task data (S11), type 19 only; transport: one 16-bit word per cargo type, action in bits 12–15, amount in bits 0–11 | `task_data` |

Type 20 blocks are 8 bytes (no task data); type 19 blocks are 18. The first waypoint is the fleet's current
position.

### Design (type 26)

| Offset | Size | Meaning |
|---|---|---|
| 0 | 1 | bits 0–1 always set; bit 2: full design |
| 1 | 1 | bit 0 always set; bits 2–5 design slot; bit 6 starbase; bit 7 a second flag (to identify) |
| 2 | 1 | hull number (0–31 ship hulls, 32–36 starbase hulls; content id via `legacy_ids.json`) |
| 3 | 1 | picture |

Full designs then have: 2 bytes armor (derived; checked, not imported), 1 byte number of slots k, 2 bytes turn
designed, 4 bytes ships built, 4 bytes ships remaining, then k slots of 4 bytes (category mask word, item number,
count; content ids via `legacy_ids.json`), then the name (packed text). Partial designs have 2 bytes mass and then
the name.

Ship design slots are 0–15 and starbase design slots 0–9; the owner comes from the block order (see "Blocks in the
game-state files").

### Space objects (type 43)

The objects are preceded by a 2-byte block of the same type holding their count. Each object block is 18 bytes,
the original's in-memory record; bytes 16–17 hold the last turn the object was updated (0 for objects created
this turn):

| Offset | Size | Meaning |
|---|---|---|
| 0 | 2 | bits 0–8 number; bits 9–12 owner; bits 13–15 kind (0 minefield, 1 packet or salvage, 2 wormhole, 3 Mystery Trader) |
| 2, 4 | 2 + 2 | x, y |

| Kind | Offsets 6–17 |
|---|---|
| Minefield | 6: mines (4 bytes); 12: type (0 standard, 1 heavy, 2 speed bump); 13: 1 = detonating; 14: players who have seen it (16-bit mask) |
| Packet / salvage | 6: word, bits 0–9 destination planet (1023 = none: salvage), bits 10–13 warp (0 for salvage), bits 14–15 status bits (S14); 8, 10, 12: ironium, boranium, germanium (16-bit each); 14: bits 0–13 mass in units of 10 kT (each mineral rounded up when created; S14) |
| Wormhole | 6: word, bits 0–1 stability (`stability`), bits 2–11 years since it last moved (`age`), bits 12–15 not imported (bit 13 is set in every file seen; meaning open); 8: players who have been through (mask); 10: players who can see it (mask); 12: the other end's full object id |
| Mystery Trader | 6, 8: destination x, y; 10: warp (low nibble); 12: players met (mask); 14: items carried (mask); 16: turn counter |

Wormholes and the Mystery Trader are stored with owner 0; the importer maps them to "no owner" (S03).

## Order files

`.x` files carry one player's orders as blocks (waypoint changes, cargo transfers, production queue changes,
research, relations, battle plans, fleet splits and merges), after the header (file kind 1; the player index in the
header). The harness does not write them: order fixtures are made by playing turns in the original client. It
converts them to our order files (`tools/harness/stars_orders.py`, S11); block types not yet converted stop the
conversion.

| Block | Layout |
|---|---|
| 3 waypoint delete | 2 bytes fleet id (number, owner × 512); 2 bytes index, bit 15 set: delete two |
| 4 waypoint add | fleet id; 2 bytes index; the waypoint as in type 19/20 (8 bytes, or with 2 to 10 bytes of task data; missing words are zero) |
| 5 waypoint change | as 4; replaces the waypoint at index |
| 29 production queue change | 2 bytes planet id (11 bits), then the whole queue as 4-byte items (as type 28) |
| 34 research change | 1 byte research percent; 1 byte: current field in the low nibble, next field setting in the high nibble |
| 35 planet change | 2 bytes planet id; 4 bytes v: bit 0 only leftover to research, bits 1–10 mass driver destination + 1 (0 none), bits 11–14 mass driver warp − 4, bits 15–24 route destination + 1 (0 none) |

## Mapping to our save format

- Planet ids, fleet (owner, number) and space object (kind, owner, number) carry over unchanged, so the S03 order
  rules give the original's order.
- Content: hull and part numbers, trait indices and planet name ids map through `content/core/legacy_ids.json`.
- Values the original derives (design mass and armor, estimates) are checked, not imported.
- The importer writes one save per `.hst` (the host state) and keeps each `.m` file's view for player knowledge.
- The classic random stream's state at the start of the turn comes from the harness (S01, "Verification notes"),
  not from the files.
- Names: by default the importer writes neutral names (`Race 0`, `Design 3`, `Plan 1`, `Planet 17`) and drops
  fleet names, so converted files hold no text from the original and can serve as fixtures. A `--keep-names`
  option keeps race, design, plan and fleet names for local use.
- Relations shorter than the player count are padded with neutral entries.
- Values the importer cannot know yet are written as defaults and marked here: `paid` on stacks (0), `repeat` on
  fleets (false; the flag is not located yet), `trader_parts` and the trader's `item` (S18), and task data in
  raw form (S11).
- Implementation: `tools/harness/starsfile.py` (container, cipher, packed text) and `stars_import.py` (mapping);
  `tools/check_save.gd` loads converted files with `SaveFile` and `StateValidator`.

## Randomness

None in reading. Writing a file draws one `random(2000)` from the game's generator for the salt (S01).

## Edge cases

- Ship counts are 1 or 2 bytes each depending on the fleet flag; cargo and surface values 0, 1, 2 or 4 bytes.
- A planet section missing from the file means the viewer doesn't know it, not that the value is 0; the importer
  reads only `.hst` files for the state, where every section is present for owned planets.
- Block sizes never exceed 1023 bytes.

## Worked examples

- Header of a 2.6i host file: magic `J3J3`, version 0x2A2A, player field 31, file kind 2.
- Settings of the spike games: size 0 (tiny, width 400), density 1 (normal), 3 players, 32 planets, positions 1
  (moderate); options 0x80 in the game created with "no random events".
- Planet data value v with v & 1023 = 16, (v >> 10) & 4095 = 1370, v >> 22 = 932: the first planet is at
  (1016, 1370) with name id 932.
- Packed text: the nibbles 0x1 0x2 0x3 give "aeh"; the nibbles 0xB 0x0 give "A"; 0xD 0xA gives k = 42, "k".

## Mod hooks

None: the harness is a dev tool.

## Open questions

1. Header byte 15.
2. Player record dword 0x3A (probably research spending) and the remaining record bytes.
3. Starbase word 1 bit 15, installation byte 5, and the packet status bits (S14).
4. Design byte 1 bit 7.
5. Wormhole word bits 12–15 (S18); the minefield layout has no fixture yet (the computer players laid no mines
   in 80 turns).
6. Production queue progress units and the standard item numbers (S09).
