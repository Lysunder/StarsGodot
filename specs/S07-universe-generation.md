# S07 Universe generation

Status: draft (2026-10-01), second pass; implemented in `core/universe/` (generator, starting setup), reproducing the
original's complete turn-0 state (all but names) for the fixture games. Covers the setup draws, the universe, the
players' starting tech, homeworlds, starting designs and fleets, the extra starting planet, wormholes and starting
relations. Verified against 16 games created by the original (seeds 4242, 777 and 1001-1013; every universe size
and density, every player-position setting, 2 to 8 players, 24 to 800 planets): the setup draws (count, names,
logos), every position, planet name, environment value, concentration, homeworld, homeworld mineral amount,
starting tech, starting fleet and wormhole match. The games cover galaxy clumping, maximum minerals, accelerated
start, slower tech, random computer players, every built-in computer race, two different human races, and the
extra planet of Packet Physics and Inter-stellar Traveler races. Not yet covered by a fixture: human random races,
the tutorial, and games set up from the New Game dialog.
References: `CreateUniverse@1070:1334`, `NewGameFromDefFile@1070:39d4`, `CompareInts@1038:8b46`,
`qsort@1108:069e`, `SeedRandomFromGameSeed@1038:8672`, `CreateStartingFleet@1070:38fe`,
`GetDesignTemplates@1008:50be`, `GetStarbaseTemplates@1008:50c4`, `SpaceObject_ValidatePosition@1100:0456`,
`InitDefaultBattlePlan@1070:0000`.

## Summary

A new game's universe is generated from the game settings (size, density, player positions, options) and the
random generator, which is seeded from the game seed (S01, game-seed method) when one is given. Planets are
scattered at random, thinned so that none are too close, optionally clumped, then given names, environments and
minerals. Homeworlds are chosen with spacing rules, and players are shuffled onto them.

Every step below draws from the classic stream in exactly the stated order. With the same seed and settings, our
generator must produce the same universe as the original.

## Data used

| Data | Notes |
|---|---|
| Universe size s | 0 tiny … 4 huge; width W = (s + 1) × 400 light years |
| Density d | 0 sparse, 1 normal, 2 dense, 3 packed |
| Player positions p | 0 close, 1 moderate, 2 farther, 3 distant |
| Number of players | 1 … 16 |
| Options | maximum minerals, accelerated start, no random events, galaxy clumping, tutorial (S23 option bits) |
| Minimum planet spacing | 12 light years (rule constant) |

All arithmetic is on integers; "div" truncates toward zero.

## Algorithm

### 0. Seeding and setup draws

When a game is created from a definition file with a seed, the classic stream is seeded with the game-seed method
(S01) while the file is read. The following draws come before the universe, in this order:

1. **Computer players** given as `#a b` (a = personality 1-6, b = skill level 1-4, 0 = random): if b is 0, draw
   random(4) for the level; then, if a is 0, draw random(6) for the personality. The race is the built-in computer
   race of that personality and level (S22 content; 6 x 4 races); built-in computer races have **no name** and
   **logo 0**. (Definition-file quirk, harness only: the original accepts a only up to 4 and b up to 6, and picks
   race number 4(a-1) + (b-1), so b = 5 or 6 selects a level of the next personality while the player keeps
   personality a and level b. Personalities 5 and 6 are reachable only through 0. Our generator takes the player's
   personality and level directly.)
2. **Races:** a human race whose advantage points are negative is replaced by the default race. Then, for each player
   in order whose race has no name: name = entry random(24) of the built-in race name list (our own list of 24).
3. **Duplicate names:** for each player i from 1 on, if its name equals an earlier player's: r = random(24); while
   name r is used by any player, r = (r + 1) mod 24; the player takes name r.
4. **Duplicate logos:** for each player i from 1 on whose logo is set, if an earlier player j (the first such) has
   the same logo: draw random(2); if it is not 0, player i's logo is cleared, otherwise player j's.
5. **Logos:** for each player in order whose logo is cleared (or was out of range): v = random(32); while another
   player has logo v, v = (v + 1) mod 32.

Examples: two players with the same race file make 3 draws (a name, a coin, a logo); one human and two built-in
computer races make 4 (two names, a coin, a logo); one human and five computer races made 14.

### 1. Planet count

1. N = W × W div 5000.
2. N = N + (N div 4) × (d − 1). (Sparse removes a quarter; dense adds one.)
3. If d = 3 (packed): N = N + N div 4.
4. N = min(N, 999).
5. The scatter count M = min(N + N div 7, 999).

Examples: tiny normal 32 (M 36); small normal 128 (M 146); huge packed 999.

### 2. Scatter

For each of the M positions in turn: x = 1010 + random(W − 19), then y = 1010 + random(W − 19).

### 3. Sort by x

The positions are sorted by x only, with the original's sort routine. Positions with equal x keep the order that
routine leaves them in, so it must be reproduced exactly (planet ids, and every later draw per planet, follow this
order). On a list a[0 … M−1], comparing by x:

1. If a[k + 1].x ≥ a[k].x for every k, stop (already sorted).
2. Keep a stack of ranges; start with (0, M − 1). While the stack is not empty, look at the top range (lo, hi):
   1. If lo ≥ hi, remove it and continue.
   2. Partition with the pivot a[lo]. Set L = lo, R = hi, i = lo, j = hi + 1. Repeat:
      - **Scan up:** increase i by one at a time; stop when i = hi, or when a[i].x > pivot.x. Whenever
        a[i].x < pivot.x on the way, set L = i.
      - **Scan down:** decrease j by one at a time; stop when a[j].x < pivot.x, or when a[j].x = pivot.x and j = lo.
        Whenever a[j].x > pivot.x on the way, set R = j.
      - If j > i: swap a[i] and a[j], set L = i and R = j, and repeat from the scan up (i and j continue from where
        they are).
      - Otherwise: swap a[lo] and a[j]; the partition is done.
   3. Replace the top range by the two parts (lo, L) and (R, hi), the smaller part on top: if hi − R ≥ L − lo,
      push (R, hi) then (lo, L); otherwise push (lo, L) then (R, hi).

The comparison is the plain difference of the x values (they never overflow).

### 4. Spacing

1. For each position k in sorted order that is not marked removed: for each later position q while
   x[q] ≤ x[k] + 12: if |y[k] − y[q]| ≤ 12 and (x[k] − x[q])² + (y[k] − y[q])² ≤ 144, mark q removed and count it.
   (The original marks a position by setting its y to −100, so a marked position is never close to another one.)
2. While fewer than M − N positions are marked: q = random(M); if q is not marked, mark it.
3. Drop the marked positions, keeping the order. The remaining count is the planet count N' (≤ N if spacing
   removed more than M − N).

### 5. Galaxy clumping (option)

Only with the galaxy clumping option. Repeat N' times:

1. j = random(N'), a planet.
2. Find the planet c ≠ j nearest to j (smallest squared distance; the first in order on ties).
3. With d² that squared distance, move j toward c (each coordinate separately, truncating division):
   - d² ≤ 144: no move;
   - d² < 325: j = (4j + c) div 5;
   - d² < 626: j = (2j + c) div 3;
   - d² < 1601: j = (j + c) div 2;
   - otherwise: j = (j + 2c) div 3.

Then sort again (step 3). Planet ids are the final positions in order: planet 0 is the first.

### 6. Names

For each planet in id order: r = random(999); while name r is taken, r = r + 1, wrapping to 0 after 998 (after 999
in the tutorial). The planet gets name id r. (The names themselves are our own list; S23 explains why the
original's list is not used.)

### 7. Environment and minerals

For each planet in id order (all planets are unowned, with no surface minerals and no population):

1. **Artifact:** unless random events are off, draw random(3); the planet has an artifact when it is 0.
2. **Gravity** = 1 + random(90) + random(10) (two draws, in that order). **Temperature** the same, then
   **radiation** = 1 + random(99). The original values (before terraforming) are the same.
3. **Tutorial only:** planet 5 gets −5 on all three values; planet 11 gets +20 gravity.
4. **Concentrations,** for ironium, boranium, germanium in order:
   - normally c = 31 + random(45) + random(45) (two draws); if radiation > 89, c = c + random(99 − c) div 2 (one
     more draw; when c ≥ 99 the draw still happens and adds 0);
   - with maximum minerals, c = 100 (no draws);
   - with accelerated start, if c < 40 then c = c + 5.
5. **Scarcity** (not with maximum minerals): t = random(27).
   - t < 9: for v = t + 1, then doubling while v < 16 (so 4, 3, 3, 2, 2, 2, 2, 1 or 1 times for t = 0 … 8): draw
     a = random(30), then k = random(3), and set concentration k to a + 1.
   - 9 ≤ t < 18: once: a = random(30), k = random(3), concentration k = a + 1.
   - t ≥ 18: nothing.

### 8. Homeworld mineral template

After all planets, three values are drawn for the homeworlds' starting surface minerals (used in the second pass):
for each mineral k in order, s = 10 + random(10 × concentration k of planet 0); if s < 200, s = s + 155 +
random(150); with accelerated start, s = s + s div 4.

### 9. Homeworlds

Squared distances throughout; P = number of players.

1. **Spacing band:** A = 6W; B = W² div P − A; D = 0 if B < 0, else 9B div 10. Base = p × D div 3 + A.
   Minimum m = 9 × Base div 10; near limit n = 7 × Base div 6.
2. **First homeworld:** up to 50 times: c = random(N'). If c lies inside the central square (both coordinates in
   W div 4 + 1000 … 3W div 4 + 1000), take it and stop. Otherwise keep the candidate whose squared distance to that
   square is smallest (the first one on ties). After 50 tries without a hit, take the kept candidate.
3. **The other homeworlds,** in order: the allowed box is both coordinates in L … H, with (L, H) = W × (3/20, 17/20)
   for fewer than 3 players, W × (1/10, 9/10) for 3 or 4, W × (1/20, 19/20) for 5 or more, each plus 1000.
   A candidate c is acceptable when it lies in the box and, against every homeworld chosen so far, its squared
   distance is at least 1 and at least m, and it is within n of at least one of them.
   - Up to 50 times: c = random(N'); stop at the first acceptable one.
   - If none was acceptable: from the last candidate, try c + 1, c + 2, … wrapping to 0 after N' − 1, until one is
     acceptable. If the scan comes back to where it started, the attempt fails.
4. **On failure:** m = m − Base div 35, n = n + Base div 35, and start again from step 2 (all homeworlds are chosen
   again, with new draws).
5. **Shuffle and starting tech,** for player i = 0 … P − 1 in turn:
   1. r = i + random(P − i); swap the homeworlds of i and r. Player i gets homeworld i.
   2. A race with the "random race" setting is generated now (S06, `GenerateRandomRace`; its draws come here).
   3. Starting tech (all fields start at 0), by primary trait: SS electronics 5; WM weapons 6, propulsion 1,
      energy 1; CA biotech 6, construction 2, energy 1, weapons 1, propulsion 1; SD propulsion 2, biotech 2; PP
      energy 4; IT propulsion 5, construction 5; AR energy 1; JoaT all fields 3; HE and IS none.
   4. With "techs start at 3": every field below 3 (4 for JoaT) whose research cost is expensive is raised to 3
      (4 for JoaT).
   5. Cheap Engines: propulsion + 1. Improved Fuel Efficiency: propulsion + 1, except in the tutorial.

### 10. Homeworlds and starting planets

For each player in index order, on its homeworld:

1. Owner = the player; a starbase of design slot 0; no artifact; homeworld; a planetary scanner.
2. 10 mines, 10 factories, 10 defenses. Population 250 (25,000 colonists), or 175 with Low Starting Population.
3. Surface minerals = the template (step 8). Concentrations = planet 0's, each at least 30.
4. **Leftover points** L = min(advantage points, 50) (S06). A computer player always gets L = 50, and at level 3 or
   above also 10% more population (population + population div 10).
5. With accelerated start: population = population × 2 × (growth rate + 5) div 10, with the race's growth rate
   (S06).
6. L is spent according to the race's leftover-points choice:
   - surface minerals: e = 10L div 4, q = 10L mod 4. The mineral with the least surface (the last one on ties)
     gets e + q, then every mineral gets e. A computer player of level 2 or above also gets the concentration
     bonus below;
   - concentrations: b = 1 if L is 1 or 2, else L div 2. The lowest concentration (the first one on ties) gets b;
     then every concentration gets (b + 1) div 2;
   - mines: + L div 2; factories: + L div 5; defenses: + (L + 5) div 10.
7. Alternate Reality: no mines, factories or defenses.
8. Environment: for gravity, temperature and radiation in turn, the middle of the race's range,
   low + (high − low) div 2, or 1 + random(99) for an immune axis. The original environment is the same.
9. Human players research at 15%. Every player researches energy next, with "same field" after it (S05), has no
   research points, and is neutral to everyone.
10. **Starbase designs:** slot 0 is template B0 (below), counted as 1 built and 1 existing; the other slots are empty.
    - Packet Physics: B0's first slot gets one Mass Driver 5. Outside tiny universes, slot 1 is B1 (1 built).
    - Inter-stellar Traveler (not in the tutorial): B0's first slot gets one Stargate 100/250. Outside tiny
      universes, slot 1 is a copy of B2 (1 built).
    - Alternate Reality: slot 1 is B0 (1 built) and slot 0 is B3 (none built); the homeworld's starbase is design 1.
11. Packet Physics: the homeworld's mass driver is set to warp 5 with no destination.

### 11. Starting fleets

The ship design templates T0 … T18 and starbase templates B0 … B3 are content (data below; our own names). "Fleet T"
means: copy template T into the player's next free design slot (counted as built and existing), and create a new
fleet (lowest free number, S03) of one such ship at the homeworld with full fuel. "Again" means one more fleet of the
same design, without a new design. For each player in index order, by primary trait:

1. Packet Physics: fleet T4. Warmonger: fleet T3; then, if construction tech is at least 3, fleets T7 and T13.
   JoaT: fleets T3 and T4. Super-Stealth: fleet T2 if energy tech is below 2, else T5; then, for a human player,
   fleet T1. Every other trait: fleet T2.
2. Hyper-Expansion: fleet T12, again, again. Inter-stellar Traveler: fleet T11. Alternate Reality: fleet T10.
   Otherwise: fleet T9.
3. Space Demolition: fleets T16 and T18. Claim Adjuster: fleet T17. Inter-stellar Traveler: fleets T7 and T8, then
   the extra planet outside tiny universes. Packet Physics outside tiny universes: the extra planet. JoaT: fleet T6
   if construction tech is below 4, else T8; then fleets T7 and T14.
4. Advanced Remote Mining without Only Basic Remote Mining: fleet T15, again.
5. **Part upgrades:** in every design the player now has, each slot whose part has a better version the player can
   use (S04: tech level and race restrictions) is upgraded to the first available entry of its list, in order:

   | Slot holds | Candidates, best first |
   |---|---|
   | Quick Jump 5 | Radiating Hydro-Ram Scoop (only if the race is immune to radiation, or its radiation center is above 84, or the design is not a Colony Ship), Daddy Long Legs 7, Fuel Mizer, Long Hump 6 |
   | Bat Scanner, Rhino Scanner | Possum, Mole, Rhino |
   | Mole-skin, Cow-hide Shield | Wolverine Diffuse, Cow-hide |
   | Tritanium, Crobmnium | Carbonic Armor, Crobmnium |
   | Laser, X-Ray Laser | Yakimora Light Phaser, X-Ray Laser |
   | Robo-Midget, Robo-Mini-Miner | Robo-Miner, Robo-Midget-Miner |
   | Alpha Torpedo | Beta Torpedo |
   | Lady Finger Bomb | Black Cat Bomb |

   A slot keeps its part when no candidate is available.
6. Alternate Reality: the homeworld has no planetary scanner.

**The extra planet** (Packet Physics and Inter-stellar Traveler outside tiny universes):

1. Among unowned planets in id order, with d² the squared distance to the homeworld and the band
   (15W div 100)² ≤ d² ≤ (23W div 100)²: each planet in the band is chosen with probability 1/k, k counting the
   planets in the band so far (draw random(k) per such planet; 0 means chosen). Outside the band, while nothing is
   chosen yet, remember the nearest planet (strictly nearer replaces). If no planet in the band was chosen, take the
   remembered one.
2. Its mass driver is set to warp 5 with no destination.
3. While the planet's habitability for the race (S08) is below 10, at most 100 times: each environment axis
   = 2 + random(97) (original = new). If 100 rerolls were made, the homeworld's environment is copied, even when
   the last reroll reached 10.
4. The player owns it, with a starbase of design 1, no artifact, 10 mines, 4 factories, a planetary scanner,
   population = homeworld population × 2 div 5, and surface minerals 100 + random(200) each. Then the homeworld's
   population = homeworld population × 4 div 5.
5. Fleet of design 0 (no new design) at the extra planet.

**Templates** (slot lists in hull slot order; "–" an empty slot):

| Template | Hull | Slots |
|---|---|---|
| T0 | `hull.small_freighter` | Quick Jump 5, Bat Scanner, Mole-skin Shield |
| T1 | `hull.small_freighter` | Quick Jump 5, Transport Cloaking, Mole-skin Shield |
| T2, T4 | `hull.scout` | Quick Jump 5, Bat Scanner, Fuel Tank |
| T3 | `hull.scout` | Quick Jump 5, Bat Scanner, X-Ray Laser |
| T5 | `hull.scout` | Quick Jump 5, Bat Scanner, Stealth Cloak |
| T6 | `hull.medium_freighter` | Quick Jump 5, Bat Scanner, Tritanium |
| T7 | `hull.destroyer` | Quick Jump 5, Laser, Alpha Torpedo, Bat Scanner, Tritanium ×2, Fuel Tank, Battle Computer |
| T8 | `hull.privateer` | Quick Jump 5, Crobmnium ×2, Bat Scanner, Laser, Alpha Torpedo |
| T9, T11 | `hull.colony_ship` | Quick Jump 5, Colonization Module |
| T10 | `hull.colony_ship` | Quick Jump 5, Orbital Construction Module |
| T12 | `hull.mini_colony_ship` | Settler's Delight, Colonization Module |
| T13 | `hull.mini_bomber` | Quick Jump 5, Lady Finger Bomb ×2 |
| T14 | `hull.mini_miner` | Quick Jump 5, Bat Scanner, Robo-Mini-Miner, Robo-Mini-Miner |
| T15 | `hull.midget_miner` | Quick Jump 5, Robo-Midget-Miner ×2 |
| T16 | `hull.mini_mine_layer` | Quick Jump 5, Mine Dispenser 40 ×2, Mine Dispenser 40 ×2, Bat Scanner |
| T17 | `hull.mini_miner` | Quick Jump 5, Bat Scanner, Orbital Adjuster, Orbital Adjuster |
| T18 | `hull.mini_mine_layer` | Quick Jump 5, Speed Trap 20 ×2, Speed Trap 20 ×2, Bat Scanner |
| B0 | `hull.space_station` | –, Laser ×8, Mole-skin ×8, Laser ×8, Mole-skin ×8, Mole-skin ×8, –, Laser ×8, –, Laser ×8, –, Mole-skin ×8 |
| B1 | `hull.orbital_fort` | Mass Driver 5, Laser ×6, Cow-hide ×6, Laser ×6, Cow-hide ×6 |
| B2 | `hull.orbital_fort` | Stargate 100/250, Laser ×6, Mole-skin ×6, Laser ×6, Mole-skin ×6 |
| B3 | `hull.orbital_fort` | –, –, –, –, – |

### 12. Finishing

1. If planet 0 is unowned, its surface minerals are cleared (the template was built there).
2. Every player gets the five default battle plans (S16).
3. **Wormholes:** pairs = random(r) + b, with (r, b) = (3, 0), (3, 1), (5, 1), (4, 3), (5, 4) for tiny … huge.
   For each pair, for each of its two ends in turn: create the wormhole (S03 numbering), stability = random(3);
   the second end and the first point at each other. Then place it: up to 100 times, x = 1000 + random(W),
   y = 1000 + random(W), and score the spot (below); stop at score 0; otherwise keep the first spot with the lowest
   score. If no try scored 0, use the kept spot.

   Score (lower is better): a spot outside 1000 … W + 1000, or exactly on a planet, a fleet or another object, is 15.
   Otherwise it starts at 0 and adds (bitwise or): 4 if outside 1010 … W + 990; against its partner, with d² the
   squared distance: 8 below 25, 4 below 100, 2 below 900, 1 below 4900; against every other wormhole: 8 below 16, 4
   below 64, 2 below 225, 1 below 900; against every planet: 8 below 25, 4 below 100, 2 below 400, 1 below 784.
4. **Relations:** if exactly one player is human (an inactive player counts as human), every player starts as every
   other player's enemy, and the game records that setting (S23 option 0x04). Otherwise all stay neutral.

## Randomness

All draws are on the classic stream, in the order of the steps: setup draws (step 0), scatter (2M), spacing
removals (step 4.2), clumping (step 5), names (N'), per planet: artifact, gravity (2), temperature (2), radiation,
three minerals (2 or 3 each), scarcity (1 + 2 per cut); the template (3 to 6); homeworld choice (variable); per
player the shuffle draw and any random race; per player the homeworld environment (one draw per immune axis); per
player the extra planet (one draw per planet in the band, then 3 per environment reroll, then 3 for minerals);
wormholes (count, then per end: stability and up to 100 positions of 2 draws).

## Edge cases

- `random(0)` and negative ranges still draw (S01): the radiation bonus relies on it when a concentration is 99
  or more.
- Equal x values are common (a tiny universe has 381 possible x values); only the exact sort gives the original's
  planet ids.
- If spacing removes more than M − N positions, the universe has fewer than N planets.

## Worked examples

From the harness (games created by the original, see `tests/fixtures/golden/README.md`):

- Tiny, normal density, 2 players, positions moderate, seed 4242, no random events: after 3 setup draws, 36
  positions, 32 planets; homeworlds planets 5 and 9; planet 0 has concentrations 27, 76, 76.
- The same with 1 human and 2 computer players and random events on: 4 setup draws; homeworlds 21, 30 and 19.
- Small, normal, 6 players, seed 777: 14 setup draws, 146 positions, 128 planets (10 pairs of equal x),
  homeworlds 107, 77, 91, 48, 94, 67.

## Mod hooks

- Rule constants: minimum planet spacing (12), planet count divisor (5000), name count (999), the homeworld box
  fractions and spacing factors.
- Formulas: `universe.planet_count`, `universe.planet_environment`, `universe.planet_minerals`,
  `universe.homeworld_spacing`. A replaced formula must keep its draw count for the classic sequence, or the rest of
  generation changes (which is fine for a mod: only Standard must match the original).
- Content: the starting design templates (T0 … T18, B0 … B3), the decision table of starting fleets per trait,
  the upgrade candidate lists, the built-in race names (24) and the wormhole count table.
- Hook: `on_universe_generated` (after the whole universe).

## Open questions

1. Games created from the New Game dialog (setup draws may differ from the definition-file path).
2. No fixture yet for human random races or the tutorial (a definition file cannot set the tutorial); confirm
   each with the harness.
3. One more global setting raises the homeworld concentration minimum to 25 instead of 30 in the original's code;
   which setting that is remains open.
4. The built-in computer races' data (S22).
5. The universe's y extent (the original keeps a height of W + 2000 for drawing; positions stay within
   1010 … W + 990).
