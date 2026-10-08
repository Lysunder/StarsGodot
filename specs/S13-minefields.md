# S13 Minefields

Status: draft (2026-09-30); second pass 2026-10-07. Laying (S11), decay, hits during movement, sweeping and
detonation implemented (`core/rules/minefields.gd`) and verified by the mine1 game (turns 0-48: a Space Demolition
race laying in place and while moving, fields merging, decay, two speed-bump hits, a fleet sweeping a speed-bump
field, a starbase sweeping a standard field back to its edge each turn, two fields detonating for two years:
another player's fleet and two of the owner's own fleets destroyed, the owner's mine layer spared); damage that
leaves ships alive, heavy fields and the unclamped starbase rate are unit-tested only. The constant tables are in the code segment (10a8:0e6e-0e8c) and match
the community "Guts of Minefields" page.
References: `Fleet_CheckMinefields@10a8:30b6`, `SegmentCircleIntersect@1038:ae30`,
`ProcessMinefieldHits@10b0:42a0` (decay and detonation), `SweepMinefields@10b0:45c4`, `Fleet_SweepRate@1078:1ca2`,
`Design_SweepRate@1078:1d1c`, `Fleet_MineLayRate@1078:1aea`, `ResetMinefieldTurnState@10b0:4592`,
`Minefield_Radius@1100:01a0` (actually counts planets inside a field). Mine laying is in S11.

## Summary

A minefield is a circle owned by one player, with a type (standard, heavy, speed bump) and a number of mines; its
radius is the square root of the mine count. Fleets of other players that travel through it faster than the type's
safe speed may hit it: a hit damages the fleet (speed bumps only stop it) and stops it there. Fields decay each year,
faster with planets inside; enemy fleets and starbases with beam weapons sweep them; Space Demolition can detonate
its standard fields.

## Data used

| Data | Notes |
|---|---|
| Field | owner, center (x, y), mine count (32-bit), type, "detonating" flag, which players have seen it |
| Radius | √(mine count); a point is inside when distance² ≤ mine count |
| Fleet | path this turn, ships per design, engines per design, armor, shields, damage state |

### Type table

| Type | Safe warp | Hit chance per ly, per warp over the safe warp | Damage per engine | Minimum fleet damage |
|---|---|---|---|---|
| Standard | 4 | 0.3% | 100 (125) | 500 (600) |
| Heavy | 6 | 1% | 500 (600) | 2000 (2500) |
| Speed bump | 5 | 3.5% | 0 | 0 |

The values in brackets are the second column, used when any ship in the fleet has an engine that burns no fuel at
warp 4 (the engine's fuel table entry for warp 4 is 0: ram scoops and the like).

## Algorithm

### Hits during movement (S12 step 4)

For a fleet moving from A to B this turn:

The check runs in each movement step after fuel is charged, over d = min(the move, trunc(the distance to the
waypoint − 0.99999)) light years (the same cut as ram scoops, S12; seen: a fleet 27.2 ly from its waypoint at warp 6
counts 26 ly, speed 5, and isn't checked against a speed-bump field, mine1 turn 32), along the line from the fleet to its next waypoint (not to where it will stop).

1. **Speed:** c = the smallest of 3 … 10 with (d − 1) ≤ c². Bonus b = 2 for Space Demolition, 1 for
   Super-Stealth, else 0. If c ≤ 3 + b the fleet can't hit anything. Nothing happens when the waypoint is where
   the fleet is.
2. **Fields on the path:** every minefield of another player who doesn't count the fleet's owner as a friend, in
   field order. For each: the point P of the line nearest the field's center (integer projection, divisions
   truncated); if its squared distance from the center is at least the mine count, nothing. Otherwise a = the
   distance from the fleet to P (truncated, negative when P is behind the fleet), h = √(mines − that squared
   distance) truncated; the stretch is enter = max(a − h, 0) to leave = min(a + h, d), kept when leave > 0 and
   enter < d. **B01:** for a vertical path the original takes the fleet's own position as P (fix: the proper
   projection).
   Stretches of one type are kept sorted by enter (at most 8): a new stretch goes before the first one it doesn't
   start after; if it ends more than 1 ly before that one starts it is inserted, otherwise the two join (the
   earlier enter, the later leave) and the joined stretch takes in the following stretches it reaches.
3. **Rolling:** take the stretches in order of entry distance (on equal entries the lower type first). For a
   stretch of type t, if c > safe(t) + b: chance = (c − b − safe(t)) × rate(t) per 1000; for each light year inside
   the stretch draw `random(1000)`; the first draw below the chance is a hit at enter + that light year. No hit: go
   to the next stretch. (Seen: two speed-bump hits at warp 6, mine1 turns 30 and 31.)
4. **On a hit:** damage (below); the move becomes the hit distance (when shorter than that cut distance) and
   the fleet's position is computed from it as for any partial move (S12); no ram-scoop fuel that step; a chasing
   fleet stops chasing. The hit point reported is the fleet's position plus (dx, dy) × hit ÷ L, with L the path
   length rounded to the nearest light year and each coordinate rounded to the nearest (halves away from zero;
   seen: 37.6 counts as 38).
5. **The field hit** is the field of that type (another player's, not a friend's) whose squared distance from the
   hit point minus its mine count is smallest. It loses mines div 20 (at least 10), or, when that is more than 50,
   mines div 100 (at least 50); a field left with nothing disappears. The fleet's owner now knows the field.
6. **Messages** (goto the fleet; the fleet given as its "where", 32768 + fleet): no damage (speed bumps)
   **`fleet.mine_stopped`** `[fleet, field owner, type, x, y]` to the fleet's owner and
   **`fleet.mine_stopped_yours`** `[fleet, type, x, y]` to the field's owner; damage without losses
   **`fleet.mine_damaged`** / **`fleet.mine_damaged_yours`** (plus the damage, the raw total before shields, at
   most 32,760); ships lost **`fleet.mine_destroyed_some`** / **`…_yours`** (plus the ships lost); the whole fleet
   lost **`fleet.mine_annihilated`** `[fleet described, field owner, type, x, y]` (no goto; the original's message
   to the field's owner then involves the salvage left behind, S14, not built yet).

### Damage from one hit

Per design stack in the fleet (n ships, e engines per ship, armor A, shields s per ship):

1. (Detonation only) Space Demolition's Mini and Super Mine Layer hulls take nothing from their owner's own
   fields.
2. Raw damage D = (n × perEngine(t) + E) × e, where E = minimum(t) − perEngine(t) × (ships in the fleet) if the fleet
   has at most 4 ships and that is positive, else 0. **The original adds E for the first design stack only (B04);
   our engine gives each stack E × n div (ships in the fleet).** e is the design's engine count.
3. Shields take at most half: absorbed = min(s × n, D div 2).
4. Damage per ship = (existing damage of the stack + D − absorbed) div n, where the existing damage is (damaged
   percent × n div 100) × A × damage div 500. If it exceeds A, **all n ships of the stack are destroyed** (they
   leave their design's count of ships in service); otherwise every ship in the stack is now damaged:
   damage = per ship × 500 div A (at least 1), 100% of them.
5. Lost ships take the cargo their capacity held with them (S11 "Cargo after a ship move"). If no ships are left
   the fleet is destroyed. Speed-bump fields do no damage but still stop the fleet. Destroyed ships leave salvage
   (S14, not built yet).

### Decay and detonation (S02 phase 11)

Each year, for each minefield:

1. **Detonation** (`ProcessMinefieldHits@10b0:42a0` calling `Fleet_CheckMinefields` with the field): a field
   ordered to detonate (S11 `minefield_detonate`) hits every fleet with ships inside it (squared distance at most
   the mine count), in fleet order: any owner, friends and the field's own owner included, wherever the fleet is
   going. No rolls. Each such fleet takes one hit of the field's type ("Damage from one hit"), except that the
   stacks of the field owner's own Mini and Super Mine Layer hulls take nothing (they don't count as lost or
   damaged, but their ships still count in the top-up's ship total). A detonation that does no damage (all stacks
   spared, or a speed-bump field) sends nothing. The field loses no mines from the hits. **B03:** the original
   marks a fleet when a detonating field checks it and skips marked fleets for the rest of the phase, so a fleet
   inside two detonating fields is hit once. Fix: every detonating field that contains the fleet hits it.
   Messages (x, y the field's center): the fleet's owner, when not the field's owner, gets
   **`fleet.detonation_damaged`** `[fleet, field owner, type, x, y, damage]` or
   **`fleet.detonation_destroyed_some`** `[…, damage, ships lost]` (goto the fleet), or when the whole fleet is lost
   **`fleet.mine_annihilated`** as for a hit; the field's owner gets **`fleet.detonation_damaged_yours`**
   `[fleet, type, x, y, damage]` or **`fleet.detonation_destroyed_some_yours`** `[…, damage, ships lost]` (goto the
   fleet), or when the whole fleet is lost **`minefield.annihilated_yours`** `[field, fleet, type, x, y]` (goto the
   field) for another player's fleet and **`minefield.annihilated_own`** `[fleet described, type, x, y]` (no goto)
   for one of its own. (A field owner of the Space Demolition race also learns the designs of the ships hit, by
   hits and detonations alike: S15.) Fleets left without ships are removed at the end of the phase.
2. **Decay rate** r = 4 × (planets inside) + 2 percent, or 1 × (planets inside) + 2 for a Space Demolition owner;
   at most 50; plus 25 when the field detonated.
3. Mines lost = max(mines × r div 100, r); at least 10 unless the field is a speed bump.
4. If that is the whole field or more, the field disappears.

### Sweeping (S02 phase 17)

1. **Fleets,** in fleet order: a fleet with a sweep rate R > 0 (Σ ships × the design's rate, S04 9: per beam slot
   count × power × r², r the range, 4 for gatlings, sappers nothing; 32-bit sums) sweeps, in field order, every
   field of another player
   - that its battle plan attacks (`Fleet_WillAttackPlayer@10e8:6db6`: the plan's attack setting 1 attacks
     players the fleet's owner calls enemies, 2 anyone not a friend, 3 everyone, 4 + n player n alone, 0 nobody),
   - and that contains the fleet (squared distance d² from the center at most the mine count M).

   Amount: A = R, or R div 3 in a speed-bump field; at least 2. When M − A < d² − 1, A = M − d² + 1 (the field
   keeps d² − 1 mines, just leaving the fleet outside; a fleet at the very center can sweep it all); at most M.
2. **Starbases,** in planet order: an owned planet with a starbase whose design has a sweep rate (the same sum,
   with every beam's r one more on a starbase hull) sweeps, the same way from the planet's position, every field
   of a player other than the planet's owner whom the owner doesn't count as a friend (the battle plan plays no
   part).
3. **Each sweep:** messages (below); the field loses A; a field left with less than 1 mine disappears, otherwise
   the sweeping player now knows it. **B34:** for a starbase the original marks the owner of the last fleet in
   the fleet list instead (fix: the starbase's owner).
4. **Messages:** to the sweeper's owner, a fleet: **`fleet.swept_mines`** `[fleet, A, field owner, type, x, y]`
   (goto the fleet), a starbase: **`planet.swept_mines`** `[planet, A, field owner, type, x, y]` (goto the planet);
   then to the field's owner **`minefield.swept`** `[field, A, type, x, y]` (goto the field; it doesn't say who),
   x and y the field's center.

## Randomness

`random(1000)` per light year inside each dangerous stretch until a hit, in fleet order during movement (S12) and in
field order during detonation.

## Known bugs

- **B01 north/south immunity:** the path-circle routine uses the starting y as the closest point when the path is
  exactly vertical (dx = 0) instead of projecting the field's center onto the path, so vertical paths usually miss.
  **Fix:** a correct projection. The rolls this adds come from the `fixes` stream.
- **B02 east/west speed-bump immunity:** same family; confirm in the code and fix the same way.
- **B03 detonation dodge:** a fleet is checked against only one detonating field per turn (a per-fleet "hit" mark).
  **Fix:** check each detonating field that contains the fleet; Mine Layer hulls stay immune to their owner's fields.
- **B04 damage allocation:** the minimum-damage top-up E goes entirely to the first design stack. **Fix** (decided):
  spread D over the stacks in proportion to ships × engines. Compat (D12): the test-only compat mod reproduces the
  original allocation.

## Edge cases

- A fleet moving warp 3 or slower is never hit; the bonus raises that for SD and SS.
- Mines never destroy part of a stack.
- Sweeping can't push a field's edge past the sweeping fleet.

## Worked examples

- Standard field, fleet at warp 9 (not SD/SS): chance (9 − 4) × 3 = 15 per 1000 per light year.
- A single-design fleet of 2 ships with 1 engine each hits a standard field: E = 500 − 100 × 2 = 300;
  D = (2 × 100 + 300) × 1 = 500 before shields.
- Field of 2,500 mines (radius 50) with 2 planets inside, owner not SD: r = 10%, loses 250 mines.

## Mod hooks

- Content: the type table as rule constants (`minefield.<type>.safe_warp`, `.hit_rate`, `.damage_per_engine`,
  `.min_damage`), trait parameters (SD bonus 2 and decay factor 1, SS bonus 1).
- Formulas: `minefield.hit_chance`, `minefield.damage`, `minefield.decay`, `minefield.sweep`.
- Hooks: `on_minefield_hit`.

## Open questions

1. B02 root cause in the code.
2. The word at +16 of a field's record, and which players scanning marks as seeing (+14, `seen_by`) and knowing
   (+10, `known_by`) a field (S15): the mine1 fixtures ignore both.
3. The argument of the square root for a (assumed the distance from the fleet to P).
