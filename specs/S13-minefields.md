# S13 Minefields

Status: draft (2026-09-30). Hits during movement, damage, decay, sweeping and detonation read from the code; the
constant tables are in the code segment and match the community "Guts of Minefields" page. Bugs B01–B04 traced to
their code where possible.
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

The values in brackets are a second column the code selects for some fleets (the community page gives both; the
condition is an open question).

## Algorithm

### Hits during movement (S12 step 4)

For a fleet moving from A to B this turn:

1. **Speed:** c = the smallest of 3 … 10 with (move distance − 1) ≤ c². Bonus b = 2 for Space Demolition, 1 for
   Super-Stealth, else 0. If c ≤ 3 + b the fleet can't hit anything.
2. **Fields on the path:** every minefield of a player who isn't the fleet's owner or the owner's friend, whose
   circle the segment A–B crosses; for each, the distance along the path where the fleet enters and leaves it.
   Overlapping fields of the same type are merged into one stretch. Up to 8 stretches per type.
3. **Rolling:** take the stretches in order of entry distance. For a stretch of type t, if c > safe(t) + b:
   chance = (c − b − safe(t)) × rate(t) per 1000; for each light year inside the stretch draw `random(1000)`; the
   first draw below the chance is a hit at that light year. No hit: go to the next stretch.
4. **On a hit:** damage (below), and the fleet stops at the hit point.

### Damage from one hit

Per design stack in the fleet (n ships, e engines per ship, armor A, shields s per ship):

1. Space Demolition Mini and Super Mine Layer hulls take nothing from their owner's own fields.
2. Raw damage D = (n × perEngine(t) + E) × e, where E = minimum(t) − perEngine(t) × (ships in the fleet) if the fleet
   has at most 4 ships and that is positive, else 0. **E is added for the first design stack only** (see B04).
3. Shields take at most half: absorbed = min(s × n, D div 2).
4. Damage per ship = (existing damage of the stack + D − absorbed) div n. If it exceeds A, **all n ships of the stack
   are destroyed**; otherwise every ship in the stack is now damaged by that amount.
5. If no ships are left the fleet is destroyed. Speed-bump fields do no damage but still stop the fleet.

### Decay and detonation (S02 phase 11)

Each year, for each minefield:

1. **Detonation:** a Space Demolition field ordered to detonate checks every fleet inside it once (each fleet at most
   once per turn across all fields in the original, see B03), with the same damage rules.
2. **Decay rate** r = 4 × (planets inside) + 2 percent, or 1 × (planets inside) + 2 for a Space Demolition owner;
   at most 50; plus 25 when the field detonated.
3. Mines lost = max(mines × r div 100, r); at least 10 unless the field is a speed bump.
4. If that is the whole field or more, the field disappears.

### Sweeping (S02 phase 17)

1. **Fleets:** each fleet with a sweep rate (S04: Σ ships × power × range², gatlings count range 4, sappers don't
   sweep) sweeps every field of another player that it is inside and whose owner its battle plan attacks:
   amount = rate (one third in a speed-bump field), at least 2. The field is never reduced below distance² − 1
   (so it just stops containing the fleet), and never below 0. Both players are told; a field reduced to nothing
   disappears; the sweeping player now knows the field.
2. **Starbases** with beam weapons sweep the same way from their planet (starbases count beam range + 1).

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

1. What selects the second damage column (the community page lists both values; candidate: fleets with ram-scoop
   engines).
2. B02 root cause in the code.
3. The exact way stretches of the same type are merged and the 8-stretch limit.
4. Detonation details (which fields detonate: standard only; damage column used).
