# S08 Planet economy

Status: draft (2026-09-30). Read from the code (decompiled C, with the floating-point parts taken from the
disassembly). Implemented in `core/rules/planet_economy.gd` (2026-10-02) except Alternate Reality; mining,
concentration wear, growth and resources match the original in golden turns (`tiny2`, homeworlds).
References: `Planet_HabValue@1040:474c`, `Planet_MaxPop@1040:48cc`, `Planet_PopGrowth@1030:46fc`,
`Planet_CapacityPct@1040:45aa`, `Planet_MaxMines@1040:49ea`, `Planet_OperableMines@1040:4a62`,
`Planet_EffectiveMines@1040:4b0c`, `Planet_MaxFactories@1040:4bec`, `Planet_OperableFactories@1040:4c64`,
`Planet_UnusedFactories@1040:4b8e`, `Planet_MaxDefenses@1040:4d0e`, `Planet_OperableDefenses@1040:4d56`,
`Planet_GetResources@1040:4de8`, `Planet_Mine@1020:3a72`. Community pages "Guts of population growth" and
"Overpopulation" used as oracles.

## Summary

How a planet supports a race: its habitability value, its maximum population, how the population grows or dies,
how many mines, factories and defenses the population can run, the resources it produces, and how mining yields
minerals and wears down the mineral concentrations. Terraforming (S10), production (S09), research (S05) and planet
defenses in combat (S17) are separate specs.

## Data used

| Data | Unit |
|---|---|
| Population P | units of 100 colonists (32-bit) |
| Extra colonists F | 0–99 single colonists kept with P (the total is 100 × P + F colonists) |
| Planet environment | gravity, temperature, radiation, 0–100 each |
| Mineral concentrations | 0–255 per mineral, plus a fractional byte per mineral (0 = none) |
| Surface minerals | kT per mineral (32-bit) |
| Mines, factories | built counts (0–4095 each) |
| Defenses | built count (0–4095) |
| Race settings | S06: habitability, growth rate, resources per colonist (pe), factory output (fp), factories operated (fo), mine output (mp), mines operated (mo) |

## Algorithm

All arithmetic is integer with division truncating toward zero, except the square roots noted.

### 1. Habitability value

As in S06 ("Planet value for a race"). The value h is a percentage, or negative when the planet is uninhabitable
(−h is then the summed distance outside the race's ranges, each axis capped at 15).

### 2. Maximum population M

1. Alternate Reality: M comes from the planet's starbase hull (none, 0, without a starbase owned by the race):
   Orbital Fort 2500, Space Dock 5000, Space Station 10000, Ultra Station 20000, Death Star 30000.
2. Otherwise: M = 100 × h, or 500 if h < 5 (this includes uninhabitable planets).
   - Hyper-Expansion: M = M − M div 2.
   - Jack of All Trades: M = M + M div 5.
3. Only Basic Remote Mining (after the above, all races): M = M + M div 10.

Capacity shown to the player: (M div 2 + 100 × P) div M, in percent, at most 999.

### 3. Population change per year

Let g be the race's effective growth rate in percent (S06: doubled for Hyper-Expansion).

**Uninhabitable planet (h < 0):** the loss is L = (−h × P) div 10 colonists, at least 1. Subtract L from the
population (taking whole units from P and the rest from F, borrowing a unit if needed).

**Habitable planet:**

1. r = g × h (in hundredths of a percent).
2. If P > M div 4:
   - c = (P × 1000) div M (fill level in tenths of a percent).
   - If P < M: r = ((1000 − c)² × r) div 562500 (crowding; 562500 = 750²).
   - Else if P < M + 10: no change at all this year.
   - Else (overcrowded): r = 4 × max(99 − c div 10, −300) (negative: deaths).
3. Change G in colonists: (r × P) div 100. (If (r div 100) × P is 10,000,000 or more, use that product instead, to
   stay in 32 bits.)
4. Add G to the population: whole units G div 100 to P, the remainder (sign kept) to F, carrying or borrowing one
   unit when F leaves 0–99. If G is exactly 0, add one colonist.

### 4. Installations

| Value | Rule |
|---|---|
| Maximum factories | max(M × fo div 100, 10); 0 for Alternate Reality |
| Operable factories | min(P × fo div 100, maximum factories), at least 1; 0 for AR |
| Factories used | min(built, operable) |
| Maximum mines | max(M × mo div 100, 10); 0 for AR |
| Operable mines | min(P × mo div 100, maximum mines), at least 1; 0 for AR |
| Effective mines | min(built, operable); for AR: trunc(√P) |
| Maximum defenses | h × 4, clamped to 10–100; 0 for AR |
| Operable defenses | min((P + 24) div 25, 1000, maximum defenses); 0 for AR |

"Next year" variants (used for the production display) take P after this year's growth.

### 5. Resources per year

1. Working population W = P; if P > M: W = min((P − M) div 2 + M, 2M) (the overcrowded part works at half rate,
   and nothing beyond three times capacity).
2. Normal races: resources = W div pe + (fp × factories used + 9) div 10.
3. Alternate Reality: resources = trunc(√(W / pe × e) × h' × 0.1 + 0.999), where e = max(energy tech, 1) and
   h' = max(h, 25). Computed in floating point.
4. At least 1 if the planet has any population.

### 6. Mining

For each mineral, in the order ironium, boranium, germanium:

1. The concentration C; on a homeworld, mining by the owner uses max(C, 30).
2. Raw output R = C × mines (effective mines for the planet's owner; a remote miner's mining rate otherwise).
   For the owner's own mining: R = (mp × R) div 10.
3. Yield = R div 100. If R mod 100 = q > 0 during turn generation, draw `random(100)`; if it is below q, add 1
   (a random rounding of the fraction). Outside turn generation (estimates shown to the player) the fraction is
   dropped.
4. Add the yield to the surface minerals.
5. **Concentration wear:** effort E = (C × mines) div 100, using the unscaled count (the mine-output setting does
   not speed up wear). While E > 0 and C > 1:
   - fraction f = the mineral's fractional byte, or 256 if it is 0;
   - d = 10 if C < 5, 25 if C < 25, C if C ≤ 100, else 100;
   - cost of the rest of this point: k = (f × 12500 div 256) div d;
   - if E < k: f' = ((k − E) × 256) div (12500 div d), at least 1; if f' ≥ f then f' = f − 1; store f'; if f' = 0,
     C decreases by 1. Stop.
   - else: C decreases by 1, the fraction resets to 0, E decreases by k, and the loop continues.

For Alternate Reality, mining a planet also includes the race's own remote-mining fleets in orbit (rules in S11).

### 7. Turn steps and depopulation

During turn generation (S02 13a, 13c), in planet order:

- **Mining:** every planet with an owner and population is mined by its owner (step 6).
- **Growth:** every planet with an owner and population grows (step 3). Then a planet with an owner but no
  population left is **depopulated**, and so is every planet without an owner (which changes nothing unless it
  still has a queue, a starbase, defenses or a scanner).
- **Depopulation:** for a Claim Adjuster owner the environment returns to the original values (trait parameter
  `planet.revert_terraform_on_loss`); the planet loses its owner, population, production queue, the "only leftover
  to research" setting, its starbase (and with it the mass driver setting), its defenses and its planetary scanner.
  Mines, factories and the single extra colonists stay. (`Planet_Depopulate@1040:553a`)

## Randomness

Mining draws `random(100)` once per mineral whose raw output has a non-zero remainder, in mineral order, for each
planet mined during turn generation. The order of planets and remote miners is part of the turn order (S02).

## Edge cases

- A planet with P = 0 and no owner neither grows nor mines.
- Population exactly at M (or up to M + 9) does not change: no growth, no deaths, and not even the one-colonist
  minimum.
- The minimum growth of one colonist applies whenever the computed change is exactly 0, including small planets.
- Concentration never wears below 1.

## Disagreements with community sources

- Overcrowding deaths: the community figure is 0.04% per percent over capacity. The code uses
  4 × (99 − c div 10) hundredths of a percent, which is one step more: 0.08% at 101%, 4.04% at 200%, capped at 12%.
- The rest (crowding factor 16/9 × (1 − fill)², half production for overcrowded population, nothing above 300%)
  agrees.
- Abandoning a planet: the 1996 player's guide says the starbase and all installations are destroyed. The code
  (`Planet_Depopulate`) removes the starbase, defenses and scanner but keeps mines and factories; we follow the code.
- The guide's figures for mine wear (12,500 ÷ concentration mine-years per point), the homeworld minimum
  concentration (30), the population limits by trait and the death rate on hostile planets agree with the code.

## Worked examples

Humanoid race (S06) unless noted; P in units of 100.

| Case | Inputs | Result |
|---|---|---|
| Hab value | planet 50/50/50 | 100 |
| Hab value | planet 30/60/85 | closeness 43, 72, 0; ideal 4642; value 22 |
| Hab value | planet 10/50/50 | −5 (gravity 5 below the range) |
| Max population | h = 22, JoaT | 2640 |
| Growth, uncrowded | P 250, h 22, g 15, M 2640 | +825 colonists: P +8, F +25 |
| Growth, crowded | P 1000, h 22, g 15, M 2640 | +22 units, F +60 |
| Overcrowded | P 5000, M 2640 | c 1893: r = −360; −180 units |
| At capacity | P 2640 or 2645, M 2640 | no change |
| Homeworld | 25,000 colonists, h 100, g 15 | +3750 colonists (P +37, F +50) |
| Uninhabitable | P 1000, h −12 | −1200 colonists (P −12) |
| Resources | P 250, pe 10, fp 10, 10 factories used | 25 + 10 = 35 |

## Mod hooks

- Formulas: `planet.hab_value`, `planet.max_pop`, `planet.pop_growth`, `planet.max_factories`,
  `planet.operable_factories`, `planet.max_mines`, `planet.operable_mines`, `planet.max_defenses`,
  `planet.operable_defenses`, `planet.resources`, `planet.mining`, `planet.concentration_wear`.
- Trait parameters (S06): `planet.max_pop_pct` (HE 50, JoaT 120), `planet.max_pop_extra_pct` (OBRM 110, applied last), the AR rules
  (starbase population table, √ resources and mines, no installations), the homeworld minimum concentration (30)
  as a rule constant.

## Open questions

1. AR resources use x87 extended precision without intermediate rounding; double precision should match except
   when the value lands within ~10⁻¹³ of a boundary. Verify with harness games using an AR race.
2. Which flag enables random mining rounding (set during turn generation); confirm it is set for every host-mode
   generation.
3. The defense coverage formula (`Planet_DefenseCoverage`) is left to S17.
