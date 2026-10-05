# StarsGodot

A clean-room reimplementation of the game mechanics of the classic 4X game **Stars!** (version 2.6i) in Godot 4.7.

Goals:

- **Faithful rules.** The default ruleset follows the original's turn order and integer math exactly, with its
  known bugs fixed. Turn results are checked against the original in a test harness.
- **Moddable from the core outward.** The base game is itself a content pack. Every formula and turn phase can be
  replaced, and race traits are data.
- **Single player against AI, hotseat and play-by-email.**

## Status

Nothing is playable yet. The foundations are in place:

- **Content and mods:** the base game's parts, hulls, traits and constants as a content pack (`content/core/`),
  loaded by a mod loader with dependencies, load order, patches and a ruleset hash.
- **Game state:** the data model, the original's random number generator, and our own save format with validation.
- **Verification harness:** a dev-only importer turns the original's host files into our save format, and a
  field-by-field diff compares states. Small converted fixtures (`tests/fixtures/golden/`) check this in CI.
- **Specifications:** the rules written up in our own words, one subsystem per spec (`specs/`).

Next: universe generation and the race wizard, then the turn engine (economy, orders, movement, combat).

## Development

- **Godot 4.7.2** (standard build). Open the folder as a project; the game logic in `core/` runs headless.
- **Tests:** `GODOT_BIN=<path to Godot> bash tools/run_tests.sh` (script compile check plus the gdUnit4 suites in
  `tests/`). Harness tests: `python -m unittest discover -s tools/harness -p "test_*.py"`.
- **Lint:** gdtoolkit 4.5.0, `gdlint core tests tools` and `gdformat --check core tests tools`.
- CI runs all of these on every push.

See [CONTRIBUTING.md](CONTRIBUTING.md) for the clean-room rules, layout and code style, [specs/](specs/) for the
rule specifications, [content/README.md](content/README.md) for the content and mod format, and
[tools/harness/README.md](tools/harness/README.md) for the verification harness.

## Legal

This project contains no code, art, sound or text from the original game. Specs and code are written in our own
words from an analysis of how the game behaves. The verification harness needs your own copy of the original and
never puts its files in this repository.

Stars! is a trademark of its respective owners. This project is not affiliated with or endorsed by them.

## License

[GNU General Public License v3.0](LICENSE). Bundled third-party code and assets keep their own licenses:
gdUnit4 (`addons/gdUnit4/`, MIT) and three fonts under the SIL Open Font License 1.1 (`art/fonts/`): Cascadia Mono
by Microsoft, Terminus (TTF) by Dimitar Zhekov and Tilman Blumenbach, and W95FA by Alina Sava.
