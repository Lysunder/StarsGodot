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
| `long1/` | small universe, normal density, no random events, seed 2003; the M6 long game: one human (a JoaT race with Total Terraforming) playing normally, checked in batches: research, production, design changes, colonizing (cargo transfer by hand), a remote miner and a freighter route with repeat orders, new designs, a fleet split and long scouting routes | `t000` … `t035`, orders `t000` … `t006`, `t010`, `t012`, `t013`, `t015`, `t016`, `t020`, `t023`, `t024`, `t028` |
| `terra1/` | tiny, normal density, no random events, seed 2002; player 0 a JoaT race with Total Terraforming, player 1 a Claim Adjuster; each colonized a nearby planet (turn 0: load colonists through a waypoint task, colonize; orders given in the client); player 0 queued terraform items on its colony in turn 2; turn 28: player 0 merged fleets, split one off, set repeat orders, a battle plan and a fleet name (the client's merge button moves all ships, block 23); turn 29: player 0 scrapped a fleet at its homeworld starbase, merged one fleet into another by task and transferred that fleet to player 1; turn 30: player 0 set a default queue and built a colony ship (player 1's starbase fought the gift fleet: battle results ignored); turn 31: both players set orders, the colony ship ran out of fuel; turn 33: it colonized with the default queue; turn 36: player 1 loaded ironium and colonists at home and sent them to player 0's new colony, arriving in turn 40 (minerals unloaded, colonists an invasion: ground combat ignored); turn 42: player 0 created a design, replaced one, deleted one and queued the new one; turns 43-45: player 1 built a colony ship and tried the transport actions on it (load exactly, fill up to %, set amount, wait for %) | `t000` … `t003`, `t013` … `t046`, orders `t000` (both players), `t002`, `t028` … `t030`, `t031` (both players), `t036` (player 1), `t042`, `t043` … `t045` (player 1) |
| `prod1/` | tiny, normal density, no random events, 2 humans (same race file), seed 2001; player 0 gave production orders in the original client each turn | `t000` … `t005`, orders `t000` … `t004` |

**Orders:** `tNNN.pP.orders.json` holds player P's orders given in turn NNN (our order file format, S11), converted
from the original's `.x` file with `tools/harness/stars_orders.py`. The golden-turn test applies them before
generating the turn.

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

**Turn messages (S21):** `terra1`, `long1` and `prod1` also hold each player's messages of the turn, read from the
players' turn files (`.m1`, `.m2`) beside each host file with `python tools/harness/add_messages.py <fixture
folder> <run folder>`, which changes nothing else. Only numbers and content ids are stored (no text). The other
games kept no turn files: their `messages` is an empty list and the tests skip it. A message number without a
content id yet is kept as `legacy.message.<n>` with its raw parameters; the tests compare only the types built.
