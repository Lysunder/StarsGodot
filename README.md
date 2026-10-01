# StarsGodot

A clean-room reimplementation of the game mechanics of the classic 4X game **Stars!** (version 2.6i) in Godot 4.7.

Goals:

- **Faithful rules.** The default ruleset follows the original's turn order and integer math exactly, with its
  known bugs fixed. Turn results are checked against the original in a test harness.
- **Moddable from the core outward.** The base game is itself a content pack. Every formula and turn phase can be
  replaced, and race traits are data.
- **Single player against AI, hotseat and play-by-email.**

Status: early foundations. Nothing is playable yet.

This project contains no code, art, sound or text from the original game. See [CONTRIBUTING.md](CONTRIBUTING.md)
for the clean-room rules, layout and code style, and [specs/](specs/) for the rule specifications.

Stars! is a trademark of its respective owners. This project is not affiliated with or endorsed by them.
