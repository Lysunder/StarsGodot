# Verification harness

Dev-only tools that read the original Stars! 2.6i's files and convert them to our save format, so golden-turn tests
can compare our engine with the original turn by turn (plan M4, specs S01, S03, S23). Nothing here ships: `tools/`
is excluded from every export, and this folder has a `.gdignore`.

| File | What it does |
|---|---|
| `starsfile.py` | Reads the original's file container: block framing, the cipher, headers, packed text (S23). |
| `stars_import.py` | Converts a game's `.xy` + `.hst` into our JSON save format (S03). |
| `test_starsfile.py` | Tests on synthetic files (no original files needed); CI runs them. |
| `../check_save.gd` | Loads save files with the core content and lists every problem. |
| `../diff_saves.gd` | Compares two save files field by field. |

Python 3.10 or later, standard library only.

## What you need

- **Your own licensed copy of Stars! 2.6i** (Windows 3.x version), registered. The original's files never go into
  this repository.
- **otvdm** (winevdm) v0.9.0 to run the 16-bit program on 64-bit Windows: `otvdm-v0.9.0.zip` from
  github.com/otya128/winevdm, sha256 `842b11aed5fa81f3e1d4272e0ee7d37f1a5a8f936de825309dda672835e16fd4`. It runs
  unpacked; its installer is not needed.

## Harness folder (outside the repository)

```
StarsHarness/
  otvdm/            otvdm, unpacked; the game's settings file ends up in otvdm/WINDOWS/
  game/             a copy of the game folder, a race file, definition files (.def)
  runs/<name>/tNNN/ the files of each generated turn
```

Work in a copy so the original installation stays untouched.

### Fixed start-up seed

The original seeds its random generator from the system clock when it starts (S01), so two runs of the same turn
differ. For reproducible turns the harness uses a second copy of the program in which that one clock read is
replaced by a constant (0x1234); nothing else changes. Its start-up generator state is then always the same (S01
clock method: `(5, 673)`), which is the default `--rng` of the importer. The small patch script lives in the
harness folder, not here.

## Making a fixture

1. **Write a definition file** (`<name>.def`, plain text, CRLF line ends):

   | Line | Content |
   |---|---|
   | 1 | game name |
   | 2 | universe size (0 tiny … 4 huge), density (0–3), player positions (0–3), random seed (optional) |
   | 3 | seven option flags, 0 or 1: maximum minerals, slower tech, accelerated start, no random events, computer alliances, public scores, galaxy clumping |
   | 4 | number of players |
   | then | one line per player: a race file name (the first player must be one), or `#1 1` for a computer player |
   | then | eight victory-condition lines: `0` (off) or `1 <value>` |
   | last | the universe file name (`<name>.xy`) |

2. **Create the game:** from `game/`, `..\otvdm\otvdm.exe <fixed-seed exe> -a <name>.def`. This writes
   `<name>.xy`, `<name>.hst` and one `.m` file per player, with no dialogs. With a seed on line 2, creation is
   reproducible.
3. **Generate turns one at a time:** `..\otvdm\otvdm.exe <fixed-seed exe> -g <name>.hst`, then copy `<name>.hst`
   to `runs/<name>/tNNN/`. One process per turn means every turn starts from the same start-up random state.
   (`-gN` generates N turns in one process, but then only the first turn's start state is known.) Human players
   without orders simply pass.
4. **Convert:**
   `python tools/harness/stars_import.py <name>.xy runs/<name>/tNNN/<name>.hst tNNN.json`
   - Names are neutral by default (`Race 0`, `Design 3`, `Planet 17`); `--keep-names` keeps the names found in
     the files, for local use only. Planet names are never available: the original keeps them as ids into its own
     name list.
   - `--rng S1,S2` sets the classic random stream's state at the start of the turn (see "Open questions").
5. **Check:** `godot --headless --path . --script res://tools/check_save.gd -- tNNN.json`
6. **Compare two turns:** `godot --headless --path . --script res://tools/diff_saves.gd -- A.json B.json`
   (`--ignore=/rng`, `--limit=N`).

Committed fixtures live in `tests/fixtures/golden/`, with a README describing how each was made. Commit only
converted files with neutral names: never the original's files, and never files converted with `--keep-names`.

## Rules

- The importer never decodes registration data: block type 9 is dropped as it is read, and the registration
  parts of headers and player records are not interpreted or documented (S23).
- Specs and code are written in our own words from the decompiled analysis; nothing from the original program is
  copied into the repository.

## Open questions

- Answered (S01): in a game without computer players the original makes no draws between start-up and turn
  generation, so the default `--rng` is exactly the state at the start of the turn. With computer players, their
  draws come first (S22). A second harness copy that also fixes the clock in the file-header code makes each
  file's salt show its `random(2000)` draw; locating those draws in the sequence gives the turn's total draw count,
  a check for our engine.
- Not converted yet: `.m` files (each player's view, S15), `.x` order files (a later pass of S23) and `.r` race
  files.
