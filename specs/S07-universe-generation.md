# S07 Universe generation

Status: draft (2026-10-01), first pass: planet count, positions, the original's sort, spacing, clumping, planet
names, environment, mineral concentrations, the homeworld mineral template, homeworld choice and the player
shuffle. Verified against three games created by the original (seeds 4242 and 777; 32 and 128 planets; 2, 3 and 6
players): every position, name, environment value, concentration and homeworld matches. Player setup (homeworld
values, starting population, installations, tech, fleets, designs, the extra planet, battle plans), wormholes and
the draws made while reading the game definition follow in the second pass.
References: `CreateUniverse@1070:1334`, `NewGameFromDefFile@1070:39d4`, `CompareInts@1038:8b46`,
`qsort@1108:069e`, `SeedRandomFromGameSeed@1038:8672`.

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
5. **Shuffle:** for player i = 0 … P − 1 in turn: r = i + random(P − i); swap the homeworlds of i and r. Player i
   gets homeworld i.

## Randomness

All draws are on the classic stream, in the order of the steps: setup draws while reading the game definition
(second pass), scatter (2M), spacing removals (step 4.2), clumping (step 5), names (N'), per planet: artifact,
gravity (2), temperature (2), radiation, three minerals (2 or 3 each), scarcity (1 + 2 per cut); the template (3 to
6); homeworld choice (variable); the shuffle (P).

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
- Hook: `on_universe_generated` (after the whole universe, second pass).

## Open questions

1. The setup draws while reading the game definition (3, 4 and 14 in the examples), and for games created from the
   New Game dialog.
2. Galaxy clumping has no fixture yet; confirm with the harness.
3. Homeworld values, starting population, installations, tech, fleets, designs, the extra planet, battle plans and
   wormholes (second pass). Homeworlds lose any artifact (seen in the 6-player game).
4. The universe's y extent (the original keeps a height of W + 2000 for drawing; positions stay within
   1010 … W + 990).
