# Modding StarsGodot

StarsGodot is built to be modded. This folder is the guide for mod makers.

**Status: experimental.** The mod API is version 1. Content mods (data files) work today. Script
mods, the mod manager and art packs are still being built. Each page says plainly what works now
and what does not exist yet ("not yet").

## Contents

| Page | What it covers |
|---|---|
| [quickstart.md](quickstart.md) | Make your first data-only mod (a new hull and a cheaper part) in under 30 minutes. |
| [content.md](content.md) | Every content type and field, part and hull stats and tags, rule constants. |
| [traits.md](traits.md) | Racial traits as data: trait parameters, and every parameter the rules read. |
| [formulas.md](formulas.md) | The `Ruleset`: formulas you can replace by id. |
| [phases.md](phases.md) | The turn pipeline: phase ids in order, and how phases can be added or replaced. |
| [scripts.md](scripts.md) | Script mods: what they can do, trust, and the determinism rules. |
| [cosmetic.md](cosmetic.md) | Cosmetic mods: strings and names today; art, themes and sound later. |
| [translating.md](translating.md) | Translations: a language as a cosmetic mod, and the template of every string. |
| [api/README.md](api/README.md) | API reference for every class in `core/`, generated from the code's doc comments. |

`content/README.md` (next to the base game's content) is the short reference for the file
formats. These pages explain the same rules in more detail.

## What a mod is

A mod is a folder with a `mod.json` manifest and some data files. **The base game is itself a
mod**: `content/core/` has the id `core` and loads through exactly the same code as every other
mod. So anything the base game does with data, a mod can do too: the 202 parts, 37 hulls, 24
traits, rule constants, starting fleets, message types and the computer players' settings are
all plain content files you can read for examples.

```
my_mod/
  mod.json            the manifest (required)
  content/            new definitions, and $replace of existing ones (*.json, any sub-folders)
  patches/            changes to definitions from earlier mods (*.json)
  lang/en.json        display names and other text, one file per language
```

## Two kinds of mod

The manifest's `kind` field says which kind a mod is.

| Kind | What it may contain | Effect on games |
|---|---|---|
| `gameplay` | `content/`, `patches/`, `lang/` | Changes the rules. It is part of the game's **ruleset hash**, so every player in a game needs the same gameplay mods at the same versions. Saves and play-by-email files record them. |
| `cosmetic` | `lang/` only, for now | Changes only how the game looks or reads. Each player can use their own. A cosmetic mod with a `content/` or `patches/` folder is refused. |

The ruleset hash covers every gameplay definition after all mods and patches are applied, plus
the list of gameplay mods and their versions. Text in `lang/` never changes the hash, even in a
gameplay mod. When a save or turn file was made with a different hash, the game says so instead
of loading it with the wrong rules.

## Where mods live

| Place | What |
|---|---|
| `res://content/<id>/` | Built-in mods, shipped with the game. Today that is only `core`. |
| `user://mods/<id>/` | Player-installed mods. The main menu's **Mods...** window lists them, turns them on and sets their order. |
| `res://tests/...` | Test-only mods (such as `tests/harness_compat`). They load only in test runs; the loader refuses them anywhere else. |

`user://` is Godot's per-user data folder. On Windows it is
`%APPDATA%\Godot\app_userdata\StarsGodot\`.

The **Mods...** window (main menu) shows every mod found, with its version, kind and whether it
has scripts. Tick the mods to use and order them with Up and Down; OK loads the content with them
and saves the choice (in `user://settings.cfg`, section `[mods]`). If they can't be used together,
the window says why and nothing changes. A mod with scripts asks once for trust in that version.
OK also re-reads every mod from disk, so while you work on a mod you can change its files and press
OK again to see the change, without restarting.

A saved game remembers its gameplay mods. Opening it turns those mods on for that game if they are
installed (in the versions it was played with), or says which are missing.

## Load order

The `ModLoader` (`core/mod/mod_loader.gd`) decides the order:

1. `core` always loads first.
2. Every other enabled mod loads after the mods it `depends` on, its `optional_depends` that are
   enabled, and the mods in its `load_after` list. It loads before the mods in its `load_before`
   list.
3. When several mods could go next, the one earlier in the player's list goes first.

Inside one mod, files load in this order: every `content/**/*.json`, then every
`patches/**/*.json`, then every `lang/*.json`. Each group is in sorted path order.

A cycle, a missing dependency, a version that doesn't match, or two enabled mods that conflict
are errors. Then no content loads at all. Content errors (a bad field, an unknown reference) are
all collected and reported together, each with its mod, file and line, for example:

```
my_mod:content/hulls.json:7: my_mod.hull.long_scout /mass: must be an integer, not 1.5
```

A game only starts when there are no errors.

## The manifest

See [quickstart.md](quickstart.md#2-write-the-manifest) for every field. The short version:

```json
{
  "id": "my_mod",
  "name": "My Mod",
  "version": "1.0.0",
  "api_version": 1,
  "kind": "gameplay",
  "depends": { "core": ">=0.1" }
}
```

## Tools

- **Validator.** `godot --headless --path . --script res://tools/validate_mod.gd -- <mod folder>`
  (add `--with <folder>` for each mod it needs). It reads the manifest, loads the game's core with
  your mod as the game would, reports every problem with its file and line, checks scripts against
  the [determinism rules](scripts.md#determinism-rules), and lists what the mod adds or changes.
  It exits with 1 when anything is wrong. Checking a script mod runs its entry script.
- **API reference.** `python tools/gen_api_docs.py` regenerates [api/](api/README.md) from the doc
  comments in `core/`.
- **Content tables.** `python tools/gen_content_docs.py` regenerates the tables in
  [content.md](content.md) and [traits.md](traits.md).

## Sample mods

Five small mods in `mods/` show the main kinds of change. Each passes the validator.

| Sample | Shows | Folder |
|---|---|---|
| Extra Hulls | data only: new hulls, a patch to a core hull, names | `mods/extra_hulls` |
| Fast Growth | replacing a formula (`economy.pop_growth`) | `mods/fast_growth` |
| Burrowers | a new primary race trait from parameters, plus a phase for its own behaviour | `mods/burrowers` |
| Supernovae | a new turn phase with its own random stream and turn message | `mods/supernova` |
| Retro Text | a cosmetic mod that changes wording only | `mods/retro_text` |

## Rules for mods

- **License.** Mods must be under a GPL-compatible license, like the game (GPL-3.0-or-later). See
  [scripts.md](scripts.md#trust).
- Every number in gameplay content is an integer. See [content.md](content.md).
- Gameplay scripts must be deterministic: the same inputs give the same turn on every computer.
  See [scripts.md](scripts.md#determinism-rules).
- Don't put other people's copyrighted text, art or sound in a mod you share.
