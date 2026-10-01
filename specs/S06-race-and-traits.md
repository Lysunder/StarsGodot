# S06 Race and traits

Status: draft (2026-09-30). Advantage-point algorithm read from the code, with its constant tables; checked by a
reference implementation that gives the original's preset values (Humanoid: 25 points left, as the original's race
wizard shows). Other presets computed, not yet confirmed against the original.
References: `Race_ComputeAdvantagePoints@10d8:2d30`, `Race_HabPoints@10d8:3278`, `Planet_HabValue@1040:474c`,
`Race_GetParam@10d8:21ee`, `Race_SetParam@10d8:2200`, `Race_HasTrait@10d8:2230`, `Race_GetGrowthRate@10d8:41d4`,
`GetPartInfo@1008:50f8`, `NewGameFromDefFile@1070:39d4`, race wizard dialogs `RACEWIZARDDLG1..6`.

## Summary

A race is a set of choices made in the race wizard: one primary trait, any number of lesser traits, three
habitability ranges, a growth rate, economy settings, and research costs per field. Each choice costs or gives
"advantage points"; a race is valid only when the points left are zero or more. This spec defines the race data,
the traits, the advantage-point calculation, which parts and hulls each trait unlocks or removes, and the six preset
races.

What each trait does during play is specified in the subsystem specs; the "Trait effects" table below is the index.

## Data used

| Field | Range | Meaning |
|---|---|---|
| Name, plural name | text | |
| Primary trait | one of 10 | see "Traits" |
| Lesser traits | any of 14 | see "Traits" |
| Habitability, per axis (gravity, temperature, radiation) | low, center, high in 0–100, or immune | the range of planet values the race lives in; the center is the ideal |
| Growth rate | 1–20 (%) | maximum yearly population growth (the wizard offers 1–20) |
| Resources per colonist | 7–25 | one resource per (value × 100) colonists |
| Factory output | 5–15 | resources per 10 factories per year |
| Factory cost | 5–25 | resources per factory |
| Factories operated | 5–25 | factories per 10,000 colonists |
| Mine output | 5–25 | kT of each mineral per 10 mines per year |
| Mine cost | 2–15 | resources per mine |
| Mines operated | 5–25 | mines per 10,000 colonists |
| Research cost, per field (energy, weapons, propulsion, construction, electronics, biotech) | 0, 1, 2 | 0 = expensive, 1 = normal, 2 = cheap (S05 confirms the cost factors) |
| Leftover points | 0–4 | what unspent points (up to 50) buy at the start: 0 surface minerals, 1 mineral concentrations, 2 mines, 3 factories, 4 defenses (S07) |
| Option: techs start at 3 | yes/no | expensive research fields start at tech 3 (S05) |
| Option: cheap factories | yes/no | factories cost 1 kT less germanium (S09) |

The original stores these in the player record: habitability as signed bytes with −1 for immune, the economy
settings and research costs as bytes clamped to the ranges above, the primary trait as an index, the lesser traits
and the two options as bits.

### Traits

Costs are advantage points consumed (positive costs points, negative gives points back). Original index in
brackets; the content ids are `trait.prt.<abbr>` and `trait.lrt.<abbr>`.

| Primary trait | Cost | | Lesser trait | Cost |
|---|---|---|---|---|
| [0] HE Hyper-Expansion | 40 | | [0] IFE Improved Fuel Efficiency | 235 |
| [1] SS Super-Stealth | 95 | | [1] TT Total Terraforming | 25 |
| [2] WM War Monger | 45 | | [2] ARM Advanced Remote Mining | 159 |
| [3] CA Claim Adjuster | 10 | | [3] ISB Improved Starbases | 201 |
| [4] IS Inner-Strength | −100 | | [4] GR Generalized Research | −40 |
| [5] SD Space Demolition | −150 | | [5] UR Ultimate Recycling | 240 |
| [6] PP Packet Physics | 120 | | [6] MA Mineral Alchemy | 155 |
| [7] IT Inter-stellar Traveler | 180 | | [7] NRSE No Ram Scoop Engines | −160 |
| [8] AR Alternate Reality | 90 | | [8] CE Cheap Engines | −240 |
| [9] JoaT Jack of All Trades | −66 | | [9] OBRM Only Basic Remote Mining | −255 |
| | | | [10] NAS No Advanced Scanners | −325 |
| | | | [11] LSP Low Starting Population | −180 |
| | | | [12] BET Bleeding Edge Technology | −70 |
| | | | [13] RS Regenerating Shields | −30 |

## Algorithm: advantage points

All arithmetic is integer, with division truncating toward zero, except inside the habitability points (below).
`g` is the growth rate clamped to 1–20; `H` the habitability points.

1. **Start** at 1650 points.
2. **Growth rate.**
   - g < 6: add (6 − g) × 4200; factor f = g.
   - 6 ≤ g ≤ 13: the start becomes 5250, 3900, 2250 or 1875 for g = 6, 7, 8, 9 (it stays 1650 for 10–13);
     f = 2g − 5.
   - 14 ≤ g ≤ 19: f = 3 × (g − 6). g = 20: f = 45.
3. **Habitability:** subtract (f × (H div 2000)) div 24.
4. **Habitability centers:** for each axis that isn't immune, add 4 × |center − 50|. If two or more axes are immune,
   subtract 150.
5. **Factories versus growth:** with fo = factories operated and fp = factory output, if fo > 10 or fp > 10:
   a = max(fo − 9, 1), b = max(fp − 9, 1) × (3 for HE, 2 otherwise). If fewer than two axes are immune, subtract
   (b × a × g) div 9; otherwise subtract (g × b × a) div 2.
6. **Resources per colonist** (pe, capped at 25): pe < 8: −2400; pe = 8: −1260; pe = 9: −600; pe = 10: 0;
   pe > 10: +120 × (pe − 10).
7. **Factory settings** (fp output, fc cost, fo operated). Compute
   - A = (fp − 10) × (−121 if fp ≥ 10, else −100),
   - B = (fc − 10) × 55 if fc > 10, else −60 × (10 − fc)²,
   - C = (fo − 10) × (−35 if fo ≥ 10, else −40),
   - S = A + B + C; if S > 700 then S = (S − 700) div 3 + 700;
   - if fo > 24: S −= 360; else if fo > 21: S += 45 × (17 − fo); else if fo > 16: S += 30 × (16 − fo);
   - if fp > 12: S += 60 × (12 − fp).

   Add S.
8. **Cheap factories option:** subtract 175.
9. **Mine settings and primary trait** (mp output, mc cost, mo operated). Compute
   - A = (mp − 10) × (−169 if mp ≥ 10, else −100),
   - B = 65 × (mc − 3) + 80 if mc ≥ 3, else −360,
   - C = (mo − 10) × (−35 if mo ≥ 10, else −40).

   Add A + B + C and subtract the primary trait's cost.
10. **Lesser traits:** subtract each chosen trait's cost. Let n₊ be the number chosen with a positive cost and n₋ the
    number with a negative cost, n = n₊ + n₋.
    - if n > 4: subtract 10 × n × (n − 4);
    - if n₋ − n₊ > 3: subtract 60 × (n₋ − n₊ − 3);
    - if n₊ − n₋ > 3: subtract 40 × (n₊ − n₋ − 3).
11. **NAS with some primary traits:** with No Advanced Scanners, subtract 280 for PP, 200 for SS, 40 for JoaT.
12. **Research costs:** s = Σ (setting − 1) over the six fields (−6 … +6, positive = cheaper).
    - s > 0: subtract 130 × s²; then add 1430 if s = 6, or 520 if s = 5.
    - s < 0: add 150, 330, 540, 780, 1050 or 1380 for s = −1 … −6; and if s < −4 and resources per colonist < 10,
      subtract 190.
13. **Techs-start-at-3 option:** subtract 180.
14. **AR with cheap energy research:** subtract 100.
15. **Result:** points div 3. Negative means the race is invalid (the original replaces such a race with the default
    Humanoid race when it loads a game definition).

### Habitability points H

H measures how much of the planet space the race can live on, counting what terraforming would add. The original
computes it in floating point (x87 doubles); see "Open questions".

1. Do three passes, p = 0, 1, 2, with terraform reach T = 0, 5, 15 (8 and 17 with Total Terraforming) and weight
   w = 7, 5, 6.
2. For each axis: if immune, use a single sample at 50 with span multiplier 11. Otherwise the sampled range is
   [max(low − T, 0), min(high + T, 100)], with width W = (upper − lower), 11 samples
   v_k = lower + (k × W) div 10 for k = 0 … 10, and span multiplier W / 100.
3. For every combination of samples (gravity, temperature, radiation): if p > 0, move each non-immune sample toward
   the race's center by up to T, and let r be the total distance still left over after that move (summed over the
   axes). Take the planet value h of that point (below); if r > T, h = max(h − (r − T), 0). Add w × h².
4. Sum the innermost axis (radiation) as integers, then multiply by its span multiplier: × 11 if immune, else
   (W × sum) div 100. Sum over temperature samples, multiply by the temperature span multiplier (as a real number);
   then sum over gravity samples and multiply by the gravity span multiplier.
5. H = round(total / 10) over the three passes (computed as truncate(total × 0.1 + 0.5)).

### Planet value for a race

Used by H above and by the planet economy (S08 refers to this section). For a planet with
values v (per axis) and a race with low, center c, high:

1. For each axis:
   - immune: add 10000 to the "good" sum;
   - v outside [low, high]: add min(distance outside, 15) to the "bad" sum;
   - otherwise, with halfwidth hw = c − low if v < c, else high − c, and d = |v − c|:
     closeness = 100 − (d × 100) div hw; add closeness² to the good sum. If 2d > hw, multiply the "ideal" factor
     (starting at 10000) by (2hw − (2d − hw)) and divide by 2hw.
2. If the bad sum is non-zero, the value is −bad (uninhabitable).
3. Otherwise value = (truncate(√(good / 3) + 0.9) × ideal) div 10000.

The original computes the square root in floating point. The +0.9 never falls within 0.03 of an integer boundary for
any integer input, so double precision reproduces it exactly.

## Growth rate in play

The race's effective growth rate is its chosen rate, doubled for Hyper-Expansion (`race.growth_rate_pct` 200).

## Part availability by trait

Some parts and hulls are only available to (or never available to) certain traits. The content records this as
`required_traits` (the race needs at least one) and `forbidden_traits` (the race may have none).

| Items | Rule |
|---|---|
| Settler's Delight; Mini-Colony Ship, Meta Morph hulls; Flux Capacitor | HE only |
| Stargates (all) | not HE |
| Pick Pocket, Chameleon, Robber Baron scanners; Shadow Shield; Depleted Neutronium; Transport Cloaking, Ultra-Stealth Cloak; Rogue, Stealth Bomber hulls | SS only |
| Gatling Neutrino Cannon, Blunderbuss; Battle Cruiser, Dreadnought hulls | WM only |
| Mine Dispenser 50; Laser Battery, Planetary Shield, Neutron Shield | not WM |
| Retro Bomb; Orbital Adjuster | CA only |
| Mini Gun; Croby Sharmor; Fielded Kelarium; Jammer 10, Jammer 50, Tachyon Detector; Super Freighter, Fuel Transport hulls | IS only |
| Smart, Neutron, Enriched Neutron, Peerless, Annihilator bombs | not IS |
| Mine layers other than Mine Dispenser 50 and Speed Trap 20; Energy Dampener; Mini and Super Mine Layer hulls | SD only |
| Speed Trap 20 | SD or IS |
| Mass drivers except Mass Driver 7 and Ultra Driver 10 | PP only |
| Stargates any/300, 100/any, any/800, any/any; Anti-Matter Generator | IT only |
| Orbital Construction Module; Death Star | AR only |
| Colonization Module; all planetary scanners and defenses | not AR |
| Fuel Mizer, Galaxy Scoop | IFE |
| Interspace-10 | NRSE |
| Ram-scoop engines (Radiating Hydro-Ram Scoop … Galaxy Scoop) | not NRSE |
| Total Terraform items | TT |
| Robo-Midget Miner, Robo-Ultra-Miner; Midget Miner, Miner, Ultra-Miner hulls | ARM |
| Robo-Midget, Robo-, Robo-Maxi-, Robo-Super-, Robo-Ultra-Miner; Midget Miner, Miner, Maxi-Miner, Ultra-Miner hulls | not OBRM |
| Space Dock, Ultra Station | ISB |
| Ferret, Dolphin, Elephant scanners; penetrating planetary scanners | not NAS |

Some parts also need the Mystery Trader (S18). Two parts are restricted to one hull (Settler's Delight to the
Mini-Colony Ship, the Orbital Construction Module to the Colony Ship); that is a design rule (S04/S11).

## Trait effects

Index of what each trait does in play, and where it is specified. Summarized from the original's descriptions and
the code read so far; each subsystem spec confirms the exact rule.

| Trait | Effects | Spec |
|---|---|---|
| HE | growth rate doubled; lower maximum population; cheap colony hull and engine; Meta Morph hull | S08, S06, S04 |
| SS | cloaking bonuses; cargo doesn't reduce cloaking; theft scanners; stealth hulls | S15, S04 |
| WM | colonists attack better; faster ships in battle; cheaper weapons; can't build some defenses or minefields | S16, S17, S09 |
| CA | terraforming for free, reverts when planets are left; chance of permanent environment improvement; retro bombs | S10, S17 |
| IS | colonists defend better; faster repair; colonists grow in fleets; cheaper defenses, dearer weapons; no smart bombs | S17, S19, S09 |
| SD | many minefield types; remote detonation; mines act as scanners; safer travel through enemy minefields | S13, S12 |
| PP | mass drivers up to warp 13; smaller packets; packet scanners; packet terraforming; second planet | S14, S07 |
| IT | all stargates, cheaper; scanning through gates; safer overgating; second planet | S12, S15, S07 |
| AR | lives on starbases; population from starbase type; remote mining of own worlds; Death Star | S08, S11 |
| JoaT | built-in penetrating scanner on Scout, Frigate and Destroyer; 20% higher maximum population | S15, S08 |
| IFE | 15% less fuel; Fuel Mizer and Galaxy Scoop; +1 starting propulsion | S12, S05 |
| TT | terraform with biotech only; up to 30%; 30% cheaper terraforming | S10 |
| ARM | extra mining hulls and robots; starts with two Midget Miners | S04, S07 |
| ISB | two more starbase designs; starbases 20% cheaper and 20% cloaked | S09, S15 |
| GR | research split: half to the current field, 15% of the total to every other field | S05 |
| UR | better scrap recovery | S11 |
| MA | mineral alchemy four times more efficient | S09 |
| NRSE | no ram-scoop engines; Interspace-10 instead | S04 |
| CE | engines half price; 10% chance engines fail above warp 6; +1 starting propulsion | S09, S12, S05 |
| OBRM | only the Mini-Miner; 10% higher maximum population | S04, S08 |
| NAS | no penetrating scanners; normal scanner range doubled | S15 |
| LSP | 30% fewer starting colonists | S07 |
| BET | new tech costs double until surpassed by one level; miniaturization 5% per level, up to 80% | S09 |
| RS | shields +40% and regenerate 10% per battle round; armor from armor parts halved | S04, S16 |

## Edge cases

- Growth rates outside 1–20 are clamped for the calculation.
- Resources per colonist above 25 count as 25.
- A race with all three axes immune gets no habitability-center points and pays the two-or-more-immune penalty.
- The original repairs an invalid race in a game definition by substituting the default Humanoid race.

## Worked examples

The six presets of the original's race wizard (and its "Random" template), with the habitability points and
advantage points left computed by this spec. Research: x expensive, n normal, c cheap, in field order
energy, weapons, propulsion, construction, electronics, biotech. Humanoid's 25 matches the original wizard.

| Race | Primary | Lesser | Gravity / Temperature / Radiation | Growth | Res./col. | Factories out/cost/oper. | Mines out/cost/oper. | Research | Leftover | Options | H | Points left |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Humanoid | JoaT | – | 15–85 / 15–85 / 15–85 | 15 | 10 | 10/10/10 | 10/5/10 | nnnnnn | 0 | – | 3293786 | 25 |
| Rabbitoid | IT | IFE TT CE NAS | 10–56 / 35–81 / 13–53 | 20 | 10 | 10/9/17 | 10/9/10 | xxcnnc | 4 | cheap factories | 1890954 | 32 |
| Insectoid | WM | ISB CE RS | immune / 0–100 / 70–100 | 10 | 10 | 10/10/10 | 9/10/6 | ccccnx | 1 | – | 4191058 | 43 |
| Nucleotid | SS | ARM ISB | immune / 12–88 / 0–100 | 10 | 9 | 10/10/10 | 10/15/5 | xxxxxx | 3 | techs at 3 | 8420542 | 11 |
| Silicanoid | HE | IFE UR OBRM BET | immune / immune / immune | 6 | 8 | 12/12/15 | 10/9/10 | nnccnx | 3 | – | 23958000 | 9 |
| Antetheral | SD | ARM MA NRSE CE NAS | 0–30 / 0–100 / 70–100 | 7 | 7 | 11/10/18 | 10/10/10 | cxcccc | 0 | – | 1248321 | 7 |
| Random (template) | HE | – | 17–83 / 17–83 / 17–83 | 15 | 10 | 10/10/10 | 10/3/10 | nnnnnn | 0 | – | 2938342 | 12 |

Centers: Humanoid 50/50/50; Rabbitoid 33/58/33; Insectoid –/50/85; Nucleotid –/50/50; Antetheral 15/50/85;
Random 50/50/50.

## Mod hooks

- Content: `trait` definitions with `cost`, `kind` and `params`; `required_traits` / `forbidden_traits` on parts and
  hulls. New traits from mods take part in the advantage-point calculation through their `cost` only (steps 10–11).
- Formulas (M5): `race.advantage_points`, `race.hab_points`, `planet.hab_value` (shared with S08).
- Trait parameters so far: `race.growth_rate_pct` (HE 200), `design.armor_part_pct` (RS 50), `design.shield_pct`
  (RS 140), `planet.max_pop_pct` (HE 50, JoaT 120), `planet.max_pop_extra_pct` (OBRM 110, applied last; S08). The step-specific rules for HE, PP, SS, JoaT and AR in steps 5, 11 and 14 are parameters of the Standard
  `race.advantage_points` formula, listed by primary trait.

## Open questions

1. **Floating point in H.** The original sums in x87 floating point (doubles stored between steps) and truncates
   once at the end. A double-precision implementation should match except when the total sits within rounding
   distance of a .5 boundary; and H only matters through H div 2000. Verify against the original for a set of races
   (harness: the race wizard, or games whose invalid-race repair reveals the sign).
2. Leftover-point choices 5 and 6 are allowed by the clamp table but have no label; check whether they mean anything.
3. Exact cost factors of the research settings and the techs-start-at-3 option (S05).
4. The race file format is our own (D6); nothing here depends on the original's race files.
