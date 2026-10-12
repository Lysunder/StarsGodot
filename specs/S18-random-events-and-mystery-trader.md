# S18 Random events and the Mystery Trader

Status: draft (2026-10-12). Read from the code (the Trader's movement from the disassembly); built
(`core/rules/random_events.gd`, `core/rules/mystery_trader.gd`) and unit-tested; not yet seen in a harness game
(every fixture so far has random events off).
References: `DoProduction@10b0:0000` (calls the events), `DoRandomEvents@10b0:1c1a`,
`RandomEvent_CometStrike@10b0:33aa`, `RandomEvent_EnvironmentChange@10b0:3784`,
`RandomEvent_MineralDeposit@10b0:3898`, `RandomEvent_MysteryTrader@10b0:3932`, `Planet_FreeQueue@10b0:36d6`,
`MoveSpaceObjects@10a8:0f6e` (Trader movement), `DoMysteryTrader@1100:0784`, `GrantMysteryTraderPart@1100:1194`,
`Part_NeedsMysteryTraderItem@10d0:4af6`, `GetDesignTemplates@1008:50be`, `Tech_CostForItem@10d0:49ee`.

## Summary

Unless the game has random events off, four events may happen each year right after the tech update of the
production step (S02 13e), in this order: a comet strike, an environment change, a mineral deposit, and the arrival
of a Mystery Trader. A Trader crosses known space from one edge to the far edge and turns back, speeding up now and
then. A fleet that waits on the Trader's position carrying at least 5,000 kT of minerals is absorbed (S02 16b): in
return its owner gets tech levels, a part or hull the Trader carries, or ships of the Trader's own designs. Expert
computer players can also trade from starbase planets near the Trader.

## Data used

- Settings: `no_random_events`, the universe size s (0 tiny … 4 huge; the universe spans 1000 … 1000 + 400 (s + 1)
  in both axes), an option bit 0x04 of the original's option word (unidentified, see "Open questions").
- Turn number t (the year's, before it advances).
- Planets (population in hundreds, environment and its original values, mineral concentrations and surface
  minerals, queue, owner, starbase), players (PRT, tech levels and research points, `trader_parts`, computer player
  and level, designs, fleet count), fleets (position, cargo, ships), traders (S03: number, position, destination,
  warp, item, players met).
- Content: the Trader's items in bit order (below), its three ship designs, constant `research.max_level` (26).

Written: as each step says; new traders, fleets and designs; messages (S21).

### The Trader's items

The original keeps a Trader's item, and a player's items, as bits; we use these content ids, by bit:

| Bit | Item | Bit | Item |
|---|---|---|---|
| 0 | `part.mechanical.multi_cargo_pod` | 6 | `part.torpedo.anti_matter_torpedo` |
| 1 | `part.electrical.multi_function_pod` | 7 | `part.beam.multi_contained_munition` |
| 2 | `part.shield.langston_shell` | 8 | `hull.mini_morph` |
| 3 | `part.armor.mega_poly_shell` | 9 | `part.engine.enigma_pulsar` |
| 4 | `part.mining_robot.alien_miner` | 10 | `part.planetary.genesis_device` |
| 5 | `part.bomb.hush_a_boom` | 11 | `part.mechanical.jump_gate` |

Bit 12 means ships, and no bit means research. A trader's `item` is the content id, `"ships"` or `"research"`. A
player's `trader_parts` holds the ids (and possibly `"ships"`, see "Planets trading") the player has; a part or hull
marked `mystery_trader` can be used only when it is there (S04, S11).

### The Trader's ships

Three designs (the original's design templates 7 to 9, `GetDesignTemplates`), kept as content:

| Kind | Hull | Parts (slot by slot, count) |
|---|---|---|
| 0 | Nubian | Enigma Pulsar 3, Mega Poly Shell 3, Mega Poly Shell 3, Anti-Matter Torpedo 3, Anti-Matter Torpedo 3, Langston Shell 3, Langston Shell 3, Multi Function Pod 3, Multi Function Pod 3, Multi Cargo Pod 3, Multi Contained Munition 3 × 3 slots |
| 1 | Mini Morph | Enigma Pulsar 2, Langston Shell 3, Multi Function Pod 1, Multi Cargo Pod 1, Jump Gate 1, Anti-Matter Torpedo 2, Anti-Matter Torpedo 2 |
| 2 | Mini Morph | Enigma Pulsar 2, Mega Poly Shell 3, Multi Function Pod 1, Multi Cargo Pod 1, Jump Gate 1, Anti-Matter Torpedo 2, Anti-Matter Torpedo 2 |

## Algorithm

All draws are `random(n)` from the classic stream, in the order written. "A planet at random" is `random(number of
planets)` in planet order.

### Comet strike (`RandomEvent_CometStrike`)

1. `random(20)`: nothing unless 0. Then a planet at random. Nothing more unless t > 9, and the planet has no owner,
   fewer than 51 hundred colonists, or t > 19 (young colonies are spared for the first 20 years).
2. Size k = `random(4)` (0 small, 1 medium, 2 large, 3 huge).
3. **Axes named:** the list (0, 1, 2) is shuffled: for i = 0, 1, 2, swap item i with item `random(3)`.
4. **Minerals:** amounts a[m] = `random(250)` + 50 for m = 0, 1, 2 (ironium, boranium, germanium). The list (0, 1, 2)
   is shuffled again: for i = 0, 1, swap item i with item i + `random(3 − i)`; call it the minerals order.
5. **Messages** to every player: a player who owns the planet and is not Alternate Reality gets
   **`event.comet_hit_yours_<size>`** `[planet, axis, …]` (with the first k + 1 named axes, at most 3); everyone else
   **`event.comet_hit_<size>`** `[planet]`. Sizes: `small`, `medium`, `large`, `huge`. All goto the planet.
6. **Colonists:** an owner that is not Alternate Reality loses trunc(population × (25 + 20k) / 100): 25%, 45%, 65% or
   85%.
7. **Concentrations:** for i = 0 … min(k, 2), mineral m = the i-th of the minerals order: a[m] += `random(17000)` +
   3000; its concentration becomes min(concentration + `random(50)` + 50, plus `random(15)` + 15 for a huge comet,
   200).
8. **Surface minerals:** each mineral gets a[m] div 16.
9. **Environment:** for each changed axis (fix B38 below: the named axes, i = 0 … min(k, 2)): d = `random(3)` + 3,
   plus `random(3)` + 3 for a huge comet; negative when `random(2)` is not 0. The value and its original value each
   move by d, kept within 1 … 99.
10. The planet's queue keeps only its auto items (`Planet_FreeQueue`, S09: the standard items numbered 0 to 6).

### Environment change (`RandomEvent_EnvironmentChange`)

1. `random(20)`: nothing unless 0. Then a planet at random. Nothing more unless it has no owner, fewer than 51
   hundred colonists, or t > 19.
2. Axis a = `random(3)`. An owned planet's owner gets **`event.environment_changed`** `[planet, axis]` (goto the
   planet).
3. d = `random(3)` + 3; when that is 3, d = `random(3)` + 6 instead; negative when `random(2)` is not 0. The axis's
   value and original value each move by d, kept within 1 … 99.
4. The queue keeps only its auto items, as for comets.

### Mineral deposit (`RandomEvent_MineralDeposit`)

1. `random(15 − s)`: nothing unless 0. Then a planet at random. Nothing more unless t > 9.
2. Mineral m = `random(3)`. An owned planet's owner gets **`event.mineral_deposit`** `[planet, mineral]` (goto the
   planet).
3. When the concentration is below 180, it grows by `random(15)` + 5.

### A Mystery Trader arrives (`RandomEvent_MysteryTrader`)

1. Only when t > 39. The odds n: 2 when t mod 100 = 71, else 3 when t mod 100 = 33, else 4 when t mod 128 = 49,
   else nothing in odd years, else 7. `random(n)`: nothing unless 0 (and a new space object can be made).
2. A new trader (the lowest free trader number): warp 8 + `random(5)`.
3. **Path:** c0 = `random(400s + 361)` + 1020 and c1 = `random(400s + 361)` + 1020; the edges e0, e1 are 1020 and
   400s + 1380, in that order when `random(2)` is 0, else swapped. With r = `random(2)`: position (x, y) = (c0, e0)
   when r is 0, else (e0, c0); destination = (c1, e1) when r is 0, else (e1, c1). (It enters on one edge and heads
   for the opposite one.)
4. **Item:** b = 5 (t < 100), 3 (t < 250) or 2; +1 for warp below 10, −1 above 10. When `random(10)` < b: ships
   when `random(6)` is 0, else research. Otherwise bit i = `random(13)`; for bits 6, 7, 10 and 11 one more roll
   `random(13)` replaces it, and then bit 7 before t = 120, bit 10 before t = 150 and bit 11 before t = 180 become
   research when `random(2)` is not 0. (Bit 12 is ships.)
5. Every player gets **`trader.arrived`** `[trader]` (goto the trader).

### The Trader moves (phase 8, `MoveSpaceObjects(0)`)

For each trader, in order:

1. With warp w at most 12, when `random(25)` is 0 it is startled: when `random(3)` is 0 it also turns (a new
   destination: e = 400s + 1380 when `random(2)` is 0, else 1020; c = `random(400s + 361)` + 1020; when `random(2)`
   is 0 the destination is (e, c), else (c, e)); either way w increases by 1, and every player gets
   **`trader.course_changed`** `[trader]`.
2. It moves w² ly toward its destination like a fleet that moves part of the way (S12: each axis by its share,
   rounded half away from zero), unless w² ≥ trunc(distance), or the step lands on the destination: then it
   **arrives**: it is placed on the destination, w = max(w − 2, 6) + 1, it gets a new destination as in step 1, and
   every player gets **`trader.turned_back`** `[trader]`. It doesn't move further this year.
3. When there is any trader, the waypoint targets are updated (S12 `UpdateWaypointTargets`, with its draws); a
   waypoint that targets a trader follows it (deep space when it is gone).

### Meeting the Trader (phase 16b, `DoMysteryTrader`)

For each trader, in order:

1. **Fleets**, in fleet order, with ships and exactly on the trader's position. M = the fleet's ironium + boranium
   + germanium.
   - M < 5,000: when the fleet moved this year (S12: not `did_not_move`), its owner gets **`trader.refused`**
     `[fleet]` (goto the fleet). Next fleet.
   - The trader has met the owner already: **`trader.recovering`** `[fleet]` (goto the fleet). Next fleet.
   - Otherwise the trader has met the owner from now on; the owner's **`fleet.completed`** message for this fleet is
     removed, and the fleet is **absorbed** (it is gone, with its cargo). Then:
     - **Research** (the trader's item is research, or the owner has it already): when every tech field of the owner
       is at the top level: `random(5)`: 0 gives **`trader.nothing_to_teach`** `[fleet]`; otherwise go on as for a part
       below. Else levels L = min((M − 5000) div 1200 + 6, 10), then by the owner's tech level total T: 1 when T ≥
       108; 2 for 96 … 107; L − 3 for 84 … 95; L − 2 for 72 … 83; L − 1 for 60 … 71; L below 60. The owner gets
       **`trader.research`** `[fleet, L]` (**`trader.research_all_parts`** when the owner has all 13 bits, which a
       part grant never sets: unused). Then L times: when `random(4)` < 3 the field is `random(6)`, or the lowest field
       when that one is at the top level; else the lowest field (the first lowest); when the lowest is at the top
       level, stop. The field's research points become 2 × points + the points still needed for its next level
       (`Tech_CostForItem`, S05, when above 0), then the tech update runs without new points (S05: the levels and
       their messages).
     - **A part or hull** (an item the owner lacks): the item, or bit `random(13)` for research; while the owner has
       it, up to 25 more rolls `random(13)`; when all 25 were rolled (even if the last found an item the owner
       lacks), or the roll is bit 12: ships. A part or hull is added to the owner's
       `trader_parts` with **`trader.part`** `[fleet]` (goto the item; **`trader.hull`** for the Mini Morph,
       **`trader.planetary`** for the Genesis Device).
     - **Ships**: nothing for a computer player. Kind k = `random(4)` (`random(3)` after year 100); when above 0,
       k = 1 + `random(2)`. The owner's design slot: one identical to kind k's design, else the first free ship slot.
       With a slot and fewer than 512 fleets: count n = 2 when `random(3)` is 0, else 1; after year 100 (unless
       option 0x04), n += `random(t div 100 + 1)`; at most 5; for a Mini Morph n += `random(n + 1)`. A new fleet of the
       owner (S11's new fleet number), on the absorbed fleet's position and planet, marked as not moved this year, with n ships
       of that design (installed in the slot when it was free: built and in service 0 first), full fuel; the design
       counts n more built and in service. The owner gets **`trader.ships`** `[fleet, n]` (goto the new fleet).
       Without a slot or with 512 fleets: **`trader.ships_no_room`** `[fleet]`.
2. **Planets trading** (computer players of level 2 and up): for each planet in planet order owned by such a player
   the trader hasn't met, with a starbase: when its x is more than 100 east of the trader's, stop; when it is within
   100 ly (x² + y² ≤ 10,000) and holds at least 3,500 kT of surface minerals (level 2) or 5,000 (higher levels):
   - the trader's item is research: when the player's tech level total is below 150, the lowest field (the first
     lowest) gains a level, six times; the trader has met the player, and the planet loses 3,500 or 5,000 kT
     (germanium first, then boranium, then ironium). Otherwise nothing.
   - else: when the player has the item, up to 50 rolls `random(13)` for one the player lacks (ships count as
     lacked); when all 50 were rolled (even if the last found one): as for research. Found: it is added to the player's items, the trader has met the
     player, and the planet loses all its surface minerals. No messages.

## Randomness

All draws from the classic stream: the four events at 13e in order (each event's draws only as far as its
conditions get); the Trader's movement in phase 8, before packets move; its meetings at 16b, after battles and
bombing.

## Edge cases

- Events never fire with random events off; existing traders still move and trade.
- A comet or environment change on an unowned planet sends no owner message (comets still send the news to all).
- A fleet carrying 5,000 kT absorbed by a trader whose item the player has and with every field at the top level
  can get nothing (one in five).
- A fleet that waited on the Trader's position all year (or a gift fleet, marked as not moved) is never refused
  (the original's fleet flag 0x20, set on every fleet before movement and cleared when it moves).

## Known bugs

- B38 (fixed): the comet's message names shuffled axes (step 3), but the original changes axes 0 … k in order, so a
  small comet can name radiation and change gravity. We change the named axes; no draw changes. (The compat mod
  doesn't carry it: no fixture has random events yet.)

## Worked examples

None yet: a harness game with random events on is needed.

## Mod hooks

Content: the Trader's items and ship designs, `mystery_trader` parts. Formula ids: `events.comet`,
`events.environment_change`, `events.mineral_deposit`, `trader.arrival`, `trader.reward`. Phase hooks:
`production.random_events`, the Trader's movement (phase 8) and meetings (16b).

## Open questions

1. The option bit 0x04 that stops the extra Trader ships after year 100: which New Game option it is.
2. How the original numbers a new trader (we take the lowest free number), and whether a trader ever leaves (none seen yet: it bounces between edges).
3. Message parameters to confirm against a harness game (several message calls lost their arguments in the
   decompilation).
4. Whether ships absorbed by a trader leave their designs' count in service (the original only marks the fleet as
   having no ships; we leave the counts alone).
