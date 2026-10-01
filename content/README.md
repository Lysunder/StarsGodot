# Content packs and mods

The base game is itself a mod: `content/core/`. Every other mod uses the same layout and rules. This page is the
reference for the file formats. The design behind them is described in `CONTRIBUTING.md` and the code docs
(`core/mod/mod_loader.gd`, `core/content/content_registry.gd`, `core/content/content_schemas.gd`).

## Layout

```
<mod_id>/
  mod.json          manifest (required)
  content/**.json   definitions
  patches/**.json   changes to definitions from earlier mods
  lang/<locale>.json  display strings, e.g. lang/en.json
```

Built-in mods live in `res://content/<id>/`; player mods in `user://mods/<id>/`.

## mod.json

| Field | Required | Meaning |
|---|---|---|
| `id` | yes | Lowercase letters, digits and `_`. Must be unique. |
| `name` | yes | Display name. |
| `version` | yes | `major.minor.patch`. |
| `api_version` | yes | Mod API version the mod was written for (currently 1). |
| `kind` | yes | `gameplay` (changes rules; all players need it) or `cosmetic` (strings, art, UI; per player). Cosmetic mods may not have `content/` or `patches/`. |
| `game_version` | no | Constraint on the game version, e.g. `">=0.1 <1.0"`. |
| `depends`, `optional_depends` | no | `{ "mod_id": "constraint" }`. Required dependencies must be enabled. |
| `conflicts` | no | Mod ids that cannot be enabled together with this one. |
| `load_after`, `load_before` | no | Load-order hints for mods that are enabled. |
| `authors`, `description`, `entry` | no | Informational; `entry` (script) is reserved for later. |

Constraints are space-separated terms that all must hold: `>=`, `<=`, `>`, `<`, `=` (or none) plus a version.
`""` and `"*"` accept anything.

**Load order:** `core` first; then every mod after its dependencies and `load_after` mods, and before its
`load_before` mods; ties follow the player's order. Within a mod: `content/`, then `patches/`, then `lang/`, each
in sorted path order. Cycles, missing dependencies, version mismatches and conflicts stop loading.

## Definitions (`content/`)

A file holds one definition object or a list of them. Every definition has a `type` and an `id`, and may have
`tags` (a list of strings). Unknown fields are errors.

**Ids** are dotted: `part.beam.laser`. New ids from `core` start with `<type>.`; new ids from any other mod start
with `<mod_id>.<type>.` (e.g. `extra_hulls.hull.long_scout`), so mods can never clash.

**Numbers are integers.** A decimal anywhere in gameplay content is an error. Use whole units or percentages.

| Type | Fields (required in bold) |
|---|---|
| `tech_field` | **`order`** |
| `trait` | **`kind`** (`primary`/`lesser`), **`cost`**, `params` (`{ "name": int }`), `excludes` (trait ids) |
| `part` | **`category`**, **`mass`**, **`cost`**, `tech` (`{ tech_field id: level }`), `stats` (`{ "name": int }`), `fuel_table` (engines: fuel use at warp 0–10, 11 integers), `required_traits`, `forbidden_traits` |
| `hull` | **`mass`**, **`cost`**, **`armor`**, **`slots`**, `starbase`, `tech`, `fuel`, `cargo`, `dock` (starbases: largest ship the dock builds, −1 = any), `initiative`, `required_traits`, `forbidden_traits` |
| `constant` | **`value`** |

`cost` is `{ "ironium", "boranium", "germanium", "resources" }`, all required. A hull slot is
`{ "accepts": [categories], "max": int, "required": bool }`. Part categories: engine, scanner, shield, armor, beam,
torpedo, bomb, mining_robot, mine_layer, orbital, planetary, electrical, mechanical, terraform (the last three are
also used for planet items that never go in a ship slot). Part stat names and their meanings are listed in spec S04.

**Race restrictions** on parts and hulls: `required_traits` lists traits of which the race must have **at least
one**; `forbidden_traits` lists traits of which it may have **none**. Both empty or absent means everyone can use it
(tech levels still apply).

**Trait costs** are in advantage points consumed: positive costs points, negative gives points back.

**Replacing** a definition from an earlier mod: define the same id and type with `"$replace": true`.

## Patches (`patches/`)

A file holds one patch object or a list of them. Each patch picks its targets with **either** `"target": "<id>"`
**or** `"select": { "type": "<type>", "tag": "<optional tag>" }`, then applies operations. Paths are dotted
(`"cost.resources"`, `"slots.0.max"`).

| Key | Effect |
|---|---|
| `"$remove": true` | Delete the targets. Anything still referring to them becomes an error. |
| `set` | `{ path: value }`. Creates missing objects along the path. |
| `add` | `{ path: int }`. Adds to an integer. |
| `pct` | `{ path: int }`. Multiplies by a percentage, truncating toward zero. |
| `ratio` | `{ path: [num, den] }`. Multiplies by num/den, truncating toward zero. |
| `append` | `{ path: [values] }`. Appends to a list (creating it if missing). |
| `remove_values` | `{ path: [values] }`. Removes the first matching entry of each value. |

Operations in one patch run in the order of that table. Patches apply in load order, so the last one wins.

```json
[
  { "target": "part.beam.laser", "set": { "stats.power": 12 }, "append": { "tags": ["cheap"] } },
  { "select": { "type": "hull" }, "pct": { "cost.resources": 90 } }
]
```

## Strings (`lang/<locale>.json`)

A flat object of key to text. Every definition needs an English name: key `<id>.name` in `lang/en.json`. Later mods
override earlier ones, which is how a cosmetic mod renames things or translates them. Strings never affect the
ruleset hash.

## Errors

Every problem is reported with mod, file and line, for example
`mymod:patches/f.json:4: part.beam.laser /mass: must be an integer, not 1.5`. Loading continues after an error so
one run lists as many problems as possible, but a game only starts when there are none.
