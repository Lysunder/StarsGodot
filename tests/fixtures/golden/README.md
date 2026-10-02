# Golden-turn fixtures

Host states of the original game, converted to our save format by `tools/harness/stars_import.py` (spec S23).
They hold only numbers, content ids and neutral names (`Race 0`, `Design 3`, `Planet 17`): no text, art or other
material from the original. Golden-turn tests compare our engine's turn N → N+1 against these.

| Folder | Game | Turns |
|---|---|---|
| `tiny2/` | tiny universe, normal density, 2 human players (same race, no orders), no random events, seed 4242 | `t000` … `t005` |
| `tiny3ai/` | tiny universe, normal density, 1 human player (no orders) and 2 computer players, random events on, seed 4242 | `t000` … `t005` |
| `medium_clump/` | medium, normal density, farther positions, galaxy clumping, 1 human and 3 random computer players (one Packet Physics: extra planet), seed 1002 | `t000` |
| `small_maxmin/` | small, dense, close positions, maximum minerals, 1 human and `#2 2`, seed 1003 | `t000` |
| `tiny_accel/` | tiny, packed, distant positions, accelerated start, 1 human and `#3 3`, seed 1004 | `t000` |
| `small_sparse/` | small, sparse, moderate positions, slower tech, computer alliances, public scores, 2 humans, seed 1005 | `t000` |
| `tiny_random_ai/` | tiny, sparse, close positions, 1 human and 1 random computer player, seed 1009 | `t000` |
| `small_it/` | small, normal density, moderate positions, an Inter-stellar Traveler human race (extra planet) and `#1 1`, seed 1011 | `t000` |
| `medium_it_two_humans/` | medium, dense, farther positions, galaxy clumping, the IT race, the first human race and 1 random computer player, seed 1012 | `t000` |
| `tiny_it/` | tiny, normal density, close positions, the IT race and `#2 2`, seed 1013 | `t000` |
| `tiny_random_race/` | tiny, normal density, a random race (the race wizard's "Random" preset, S06) and `#1 1`, seed 1014 | `t000` |
| `small_two_random_races/` | small, normal density, two copies of the random race and the first human race, seed 1015 | `t000` |
| `tiny_random_races_only/` | tiny, sparse, close positions, two copies of the random race, seed 1017 | `t000` |
| `small_random_race_accel/` | small, dense, distant positions, accelerated start, the random race, `#3 2` and `#2 3`, seed 1018 | `t000` |
| `tiny_random_race_packed/` | tiny, packed, the random race and the IT race, seed 1019 | `t000` |

Every `t000` also checks the universe generator (S07); the later turns are for golden-turn tests.

## How they were made

With the harness (outside the repo; see `docs/plan/HARNESS_SPIKE.md`), using the copy of the original whose start-up
seed is fixed to 0x1234:

1. Create the game from a definition file: `starsfix.exe -a <name>.def` (`starsfix2.exe` for the turn-0-only games;
   it also fixes the clock in file headers, which changes nothing in the converted state). The files above used:
   - line 2 `0 1 1 4242` (tiny, normal density, moderate positions, seed 4242);
   - line 3 `0 0 0 1 0 0 0` for `tiny2` (no random events), `0 0 0 0 0 0 0` for `tiny3ai`;
   - players: `tiny2` two copies of the same human race file; `tiny3ai` one human race file and two `#1 1` computer
     players (`#a b`: personality a, skill level b, 0 = random; S07);
   - the turn-0-only games: line 2 `size density positions seed` and line 3's option flags as in the table;
   - victory: own 60% of planets (`1 60`), the other conditions off.
2. Generate each turn in a fresh process (`starsfix.exe -g <name>.hst`), so every turn starts from the same
   start-up random state, and keep each turn's `.hst`.
3. Convert: `python tools/harness/stars_import.py <name>.xy t00N/<name>.hst t00N.json`.

The random stream state in each file is the start-up state of the fixed-seed copy (S01 clock method with 0x1234).
For `tiny2` this is exactly the state at the start of turn generation (S01: no draws before it without computer
players), and each of its turns makes 7 draws. In `tiny3ai` the computer players draw first (S22).

Regenerate these files whenever the importer or the save format changes.
