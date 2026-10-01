# S05 Research

Status: draft (2026-09-30). Read from the code; the base cost table is the original's (it matches the community
"Research Costs" table exactly). Field switching after a level is gained is marked for harness confirmation.
References: `Tech_LevelCost@10d0:1546`, `UpdateTechLevels@10b0:4c50`, `Research_ResourcesThisYear@10d0:492e`,
`DoProduction@10b0:0000`. Community page "Research Costs" used as oracle.

## Summary

Each player has a level (0–26) in six fields: energy, weapons, propulsion, construction, electronics, biotech.
Resources spent on research become research points in the field being researched; when the points reach the cost
of the next level, the level goes up and research may continue in another field. Higher levels unlock parts and
hulls (S04) and improve several formulas.

How many resources go to research each year (the research percentage and leftover production) is part of
production (S09). Tech gained from battles, scrapping and invasion is S24.

## Data used

| Data | Notes |
|---|---|
| Tech level per field | 0–26 |
| Research points per field | 32-bit, the progress toward the next level |
| Current field | one of the six |
| Next field setting | a field (0–5), "same field" (6) or "lowest field" (7) |
| Research spent this year | resources put into research by production this year (S09) |
| Race research costs | per field: expensive, normal or cheap (S06) |
| Race: Generalized Research | trait |
| Game option "slow tech advances" | game setting |

## Algorithm

### Cost of the next level

To go from level L to L + 1 in a field:

1. c = base(L + 1) + 10 × (sum of the player's six tech levels).
2. Research cost setting of that field: expensive → c = 2c − c div 4 (75% more, rounding up); normal → unchanged;
   cheap → c = c div 2.

| Level | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 | 13 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| base | 50 | 80 | 130 | 210 | 340 | 550 | 890 | 1440 | 2330 | 3770 | 6100 | 9870 | 13850 |

| Level | 14 | 15 | 16 | 17 | 18 | 19 | 20 | 21 | 22 | 23 | 24 | 25 | 26 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| base | 18040 | 22440 | 27050 | 31870 | 36900 | 42140 | 47590 | 53250 | 59120 | 65200 | 71490 | 77990 | 84700 |

### Points each year

Called once per turn from production (S02 13d), with the year's research spending R of each player:

1. **Without Generalized Research:** the current field gets R points.
2. **With Generalized Research:** the current field gets (R + 1) div 2; each of the other five fields gets
   (3R + 19) div 20 (15%, rounded up).
3. **Slow tech advances:** points count half. The original does this by doubling the stored points before the
   comparison, doubling the cost, and storing (points + 1) div 2 afterwards; equivalent to halving the year's points
   with that rounding. Reproduce it exactly as described.

### Gaining levels

For each player in player order, for each field:

1. While the field is below 26 and its points reach the cost of the next level: subtract the cost, raise the level,
   and tell the player (new level; parts and hulls newly available).
2. When the current field gains a level and the next-field setting isn't "same field": the points left over move to
   the new field, chosen as the set field, or for "lowest field" the field with the lowest level (the first such
   field in field order). The next-field setting then becomes "same field", except "lowest field", which stays.
   Then check again (the new field may also gain levels).
3. A field at level 26 whose next setting is "same field" switches to "lowest field".

The tech update also runs during the waypoint phases (S02 5d, 16e), without new points, to apply levels gained from
tech trading (S24).

### Super-Stealth spying

After all players' points are added in the production call, if more than one player is active: for each
Super-Stealth player and each field, bonus = (total points all players added to that field this year ÷ number of
active players) ÷ 2, using integer division. If the bonus is above 1 it is added (halved with rounding up under slow
tech), the player is told, and levels are checked again.

## Randomness

None.

## Edge cases

- Levels stop at 26; points keep accumulating in a field at 26 only until it switches field.
- The sum of levels in step 1 includes the field being researched, so every level gained anywhere raises all costs
  by 10.
- Research cost "expensive" rounds the 75% surcharge up (2c − c div 4).

## Worked examples

- All six fields at level 3 (sum 18), next energy level 4, normal cost: 210 + 180 = 390. Expensive: 780 − 97 = 683.
  Cheap: 195.
- Generalized Research with R = 100: the current field gets 50; each other field gets (300 + 19) div 20 = 15
  (total 125).
- Super-Stealth spying with three active players who put 300, 0 and 600 points into weapons: (900 ÷ 3) ÷ 2 = 150.

## Mod hooks

- Formulas: `research.level_cost` (base table and setting factors as content: rule constants
  `research.base_cost` per level, `research.cost_per_level_sum` 10), `research.points` (Generalized Research split),
  `research.spy_bonus`.
- Trait parameters: Generalized Research split (50% current, 15% others), Super-Stealth spying (half the average).
- Content: the six `tech_field` definitions (order = field order).

## Open questions

1. Confirm the field-switching rules (step 2 and 3 of "Gaining levels") with the harness, including several levels in
   one year.
2. Which players count as "active" for spying (a per-player flag; probably not eliminated).
3. Starting tech levels per primary and lesser trait and the "techs start at 3" option belong to universe setup (S07).
