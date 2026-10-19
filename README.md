# StarsGodot

A clean-room reimplementation of the game mechanics of the classic 4X game **Stars!** (version 2.6i) in Godot 4.7.

Goals:

- **Faithful rules.** The default ruleset follows the original's turn order and integer math exactly, with its
  known bugs fixed. Turn results are checked against the original in a test harness.
- **Moddable from the core outward.** The base game is itself a content pack. Every formula and turn phase can be
  replaced, and race traits are data.
- **Single player against AI, hotseat and play-by-email.**

## Status

The game is playable from start to finish, and is in playtesting:

- **The rules:** the full Stars! 2.6i turn (economy, research, production, movement, minefields, packets,
  scanning and cloaking, battles, bombing and invasion, random events, score and victory), checked turn by turn
  against games played in the original.
- **Computer players:** our own computer player and ports of the original's six personalities, at every difficulty.
- **Ways to play:** single player against the computer, hotseat, and play by email.
- **The interface:** the original's four-pane screen and its dialogs in a Windows 95 style of our own, with help
  (F1), a tutorial, a language setting and colour-blind palettes.
- **Mods:** the base game is itself a mod; data mods, formula and phase mods, script mods and cosmetic mods all
  work. See [modding/](modding/README.md).

Bug reports and suggestions are welcome as GitHub issues.

## Playing

Run the game from Godot 4.7 (open this folder as a project), or from a build (`tools/build.sh` below). Choose
**Tutorial** on the main menu for a guided first game, or **New Game...** to start one; the help (F1) explains the
rest.

The game uses its own pictures. If you own Stars! 2.6i, you can import the original's pictures from your own copy:
see **[CLASSIC_LOOK.md](CLASSIC_LOOK.md)**.

## Development

- **Godot 4.7.2** (standard build). Open the folder as a project; the game logic in `core/` runs headless.
- **Tests:** `GODOT_BIN=<path to Godot> bash tools/run_tests.sh` (script compile check plus the gdUnit4 suites in
  `tests/`). Harness tests: `python -m unittest discover -s tools/harness -p "test_*.py"`.
- **Lint:** gdtoolkit 4.5.0, `gdlint core tests tools` and `gdformat --check core tests tools`.
- CI runs all of these on every push.
- **Playtest build:** `GODOT_BIN=<path to Godot> bash tools/build.sh [out_dir]` exports the Windows build
  (needs Godot's export templates), stamps the version and commit into it, checks the pack with
  `tools/check_pack.py` and zips it with a short readme, by default into `../Stars builds/`.

See [CONTRIBUTING.md](CONTRIBUTING.md) for the clean-room rules, layout and code style, [specs/](specs/) for the
rule specifications, [content/README.md](content/README.md) for the content and mod format,
[modding/](modding/README.md) for the modding guide and API reference, and
[tools/harness/README.md](tools/harness/README.md) for the verification harness.

## Legal

This project contains no code, art, sound or text from the original game. Specs and code are written in our own
words from an analysis of how the game behaves. The verification harness and the classic look import ([CLASSIC_LOOK.md](CLASSIC_LOOK.md)) need your own copy of
the original, and never put its files in this repository or in the game's builds.

Stars! is a trademark of its respective owners. This project is not affiliated with or endorsed by them.

## License

[GNU General Public License](LICENSE), version 3 or (at your option) any later version
(`GPL-3.0-or-later`). Bundled third-party code and assets keep their own licenses:
gdUnit4 (`addons/gdUnit4/`, MIT) and three fonts under the SIL Open Font License 1.1 (`art/fonts/`): Cascadia Mono
by Microsoft, Terminus (TTF) by Dimitar Zhekov and Tilman Blumenbach, and W95FA by Alina Sava.
