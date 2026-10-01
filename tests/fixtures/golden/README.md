# Golden-turn fixtures

Host states of the original game, converted to our save format by `tools/harness/stars_import.py` (spec S23).
They hold only numbers, content ids and neutral names (`Race 0`, `Design 3`, `Planet 17`): no text, art or other
material from the original. Golden-turn tests compare our engine's turn N → N+1 against these.

| Folder | Game | Turns |
|---|---|---|
| `tiny2/` | tiny universe, normal density, 2 human players (same race, no orders), no random events, seed 4242 | `t000` … `t005` |
| `tiny3ai/` | tiny universe, normal density, 1 human player (no orders) and 2 computer players, random events on, seed 4242 | `t000` … `t005` |

## How they were made

With the harness (outside the repo; see `docs/plan/HARNESS_SPIKE.md`), using the copy of the original whose start-up
seed is fixed to 0x1234:

1. Create the game from a definition file: `starsfix.exe -a <name>.def`. The files above used:
   - line 2 `0 1 1 4242` (tiny, normal density, moderate positions, seed 4242);
   - line 3 `0 0 0 1 0 0 0` for `tiny2` (no random events), `0 0 0 0 0 0 0` for `tiny3ai`;
   - players: `tiny2` two copies of the same human race file; `tiny3ai` one human race file and two `#1 1` computer
     players;
   - victory: own 60% of planets (`1 60`), the other conditions off.
2. Generate each turn in a fresh process (`starsfix.exe -g <name>.hst`), so every turn starts from the same
   start-up random state, and keep each turn's `.hst`.
3. Convert: `python tools/harness/stars_import.py <name>.xy t00N/<name>.hst t00N.json`.

The random stream state in each file is the start-up state of the fixed-seed copy (S01 clock method with 0x1234).
For `tiny2` this is exactly the state at the start of turn generation (S01: no draws before it without computer
players), and each of its turns makes 7 draws. In `tiny3ai` the computer players draw first (S22).

Regenerate these files whenever the importer or the save format changes.
