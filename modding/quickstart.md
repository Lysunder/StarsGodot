# Quickstart: your first mod

This guide makes a small data-only mod, step by step. It adds a new hull and a new armor part,
makes an existing part cheaper, and gives everything a name. You need a text editor and the game.
No programming.

Plan for about 30 minutes:

| Step | Time |
|---|---|
| 1. Make the folder | 2 min |
| 2. Write the manifest | 3 min |
| 3. Add a hull | 10 min |
| 4. Add a part | 5 min |
| 5. Name things | 3 min |
| 6. Change existing content | 5 min |
| 7. Check it | 2 min |

The finished mod is about 60 lines of JSON in four files.

## 1. Make the folder

Pick a mod id: lowercase letters, digits and `_`, starting with a letter. This guide uses
`my_mod`. Make this layout:

```
my_mod/
  mod.json
  content/
    hulls.json
    parts.json
  patches/
    cheaper_laser.json
  lang/
    en.json
```

Player mods will live in `user://mods/my_mod/` (see [README.md](README.md#where-mods-live)).

All files are UTF-8 JSON. JSON has no comments, so don't copy the `//` notes in this guide into
your files.

## 2. Write the manifest

`my_mod/mod.json`:

```json
{
  "id": "my_mod",
  "name": "My First Mod",
  "version": "1.0.0",
  "api_version": 1,
  "kind": "gameplay",
  "authors": ["Your Name"],
  "description": "A long-range scout hull, ceramic armor and a cheaper laser.",
  "depends": { "core": ">=0.1" }
}
```

Every field the loader knows (`core/mod/mod_manifest.gd`). Any other field is an error.

| Field | Required | Meaning |
|---|---|---|
| `id` | yes | The mod's id. Lowercase letters, digits and `_`. Must be unique. `harness_compat` is reserved. |
| `name` | yes | Display name. |
| `version` | yes | Your mod's version, `major.minor.patch` (one to three numbers, `1.2` means `1.2.0`). |
| `api_version` | yes | The mod API version you wrote it for. Must be `1` today. |
| `kind` | yes | `gameplay` (changes the rules) or `cosmetic` (text only; see [cosmetic.md](cosmetic.md)). |
| `game_version` | no | Which game versions it works with, for example `">=0.1 <1.0"`. Empty means any. |
| `authors` | no | List of names. |
| `description` | no | One or two sentences. |
| `depends` | no | Mods that must be enabled, with a version rule: `{ "core": ">=0.1" }`. |
| `optional_depends` | no | Mods it works with when they are enabled: they load first, and their version must match. |
| `conflicts` | no | List of mod ids that cannot be enabled together with this one. |
| `load_after`, `load_before` | no | Lists of mod ids. Only order hints: they don't make a mod required. |
| `entry` | no | Reserved for script mods. Nothing reads it yet. |

A version rule is a list of terms separated by spaces, all of which must hold. Each term is an
operator (`>=`, `<=`, `>`, `<`, `=`, or none for `=`) and a version. `""` or `"*"` accepts any
version. The base game (`core`) is version `0.1.0` today.

## 3. Add a hull

`my_mod/content/hulls.json` (a content file holds one definition or a list of them):

```json
[
  {
    "type": "hull",
    "id": "my_mod.hull.long_scout",
    "tech": { "tech_field.construction": 4, "tech_field.propulsion": 3 },
    "mass": 12,
    "cost": { "ironium": 6, "boranium": 2, "germanium": 5, "resources": 16 },
    "armor": 30,
    "fuel": 300,
    "initiative": 1,
    "pictures": 16,
    "class": 2,
    "slots": [
      { "accepts": ["engine"], "max": 1, "at": [1, 3] },
      { "accepts": ["scanner"], "max": 1, "at": [7, 3] },
      { "accepts": ["mechanical", "electrical"], "max": 2, "at": [5, 3] },
      { "accepts": ["shield", "armor"], "max": 1, "at": [3, 3] }
    ],
    "tags": ["builtin_scanner"]
  }
]
```

What the fields mean:

- `id` must start with `<your mod id>.hull.`. The loader refuses other new ids, so mods can never
  clash.
- `tech`: the tech levels needed to build it. Leave it out and every player can build it from the
  start.
- `mass` is in kT, `fuel` in mg, `cargo` (not used here) in kT. `cost` needs all four fields.
- `slots`: each slot lists the part categories it `accepts` and how many parts fit (`max`). `at`
  is where the slot is drawn in the ship designer, in half-slot grid cells (`[x, y]`). Look at
  `content/core/content/hulls.json` for the base game's layouts.
- `pictures`: which of the existing design pictures the hull uses (16 is the Scout's).
- `class`: what battle plans and reports call it (2 = escort; the full list is in
  [content.md](content.md#hull)).
- `tags`: `builtin_scanner` gives the hull the small built-in scanner the base game's scouts
  have. Tags are explained in [content.md](content.md#stats-and-tags).

All numbers are whole numbers. `12.5` or even `12.0` is an error.

## 4. Add a part

`my_mod/content/parts.json`:

```json
[
  {
    "type": "part",
    "id": "my_mod.part.armor.ceramic",
    "category": "armor",
    "tech": { "tech_field.construction": 2 },
    "mass": 40,
    "cost": { "ironium": 3, "boranium": 0, "germanium": 2, "resources": 9 },
    "stats": { "armor": 60 }
  }
]
```

A part's effects are its `stats`. Armor needs only `armor`; a beam weapon has `range`, `power`
and `initiative`, and so on. [content.md](content.md#stats-and-tags) lists every stat the rules
read. To limit a part to some races, add `required_traits` (the race needs at least one) or
`forbidden_traits` (the race may have none).

## 5. Name things

Every new definition needs an English name, or loading fails with `no English name`.
`my_mod/lang/en.json` is a flat object of key to text:

```json
{
  "my_mod.hull.long_scout.name": "Long Scout",
  "my_mod.part.armor.ceramic.name": "Ceramic Plate"
}
```

The key is the id plus `.name`. Other languages go in `lang/<locale>.json` (for example
`lang/de.json`); English is the fallback.

## 6. Change existing content

You can change any definition from `core` or from a mod that loads before yours. There are three
ways.

### Patch: change some fields

`my_mod/patches/cheaper_laser.json`:

```json
{ "target": "part.beam.laser", "pct": { "cost.resources": 80 } }
```

This makes the Laser cost 80% of its resources (5 becomes 4: integer math truncates toward
zero). A patch names its targets with **either** `"target": "<id>"` **or** a selector, then lists
operations. Paths use dots: `cost.resources`, `stats.power`, `slots.0.max`.

| Operation | Example | Effect |
|---|---|---|
| `set` | `"set": { "stats.power": 12 }` | Sets a value. Creates missing objects along the path. |
| `add` | `"add": { "armor": 25 }` | Adds to an integer (negative to subtract). |
| `pct` | `"pct": { "cost.resources": 80 }` | Multiplies an integer by a percentage, truncating. |
| `ratio` | `"ratio": { "mass": [2, 3] }` | Multiplies an integer by a fraction, truncating. |
| `append` | `"append": { "tags": ["cheap"] }` | Adds values to the end of a list (creating it if missing). |
| `remove_values` | `"remove_values": { "tags": ["cheap"] }` | Removes the first matching entry of each value from a list. |

One patch can hold several operations; they run in the order of this table. A patch file can
hold a list of patches. Patches apply in load order, so when two mods change the same field, the
later mod wins.

A **selector** patches every definition of a type, or every one with a tag:

```json
{ "select": { "type": "hull", "tag": "builtin_scanner" }, "add": { "fuel": 50 } }
```

### Replace: swap a whole definition

Put a definition in `content/` with an existing id and `"$replace": true`. Every field must be
given again: fields you leave out are gone, not kept.

```json
{
  "type": "part",
  "id": "part.armor.tritanium",
  "$replace": true,
  "category": "armor",
  "mass": 50,
  "cost": { "ironium": 5, "boranium": 0, "germanium": 0, "resources": 10 },
  "stats": { "armor": 55 }
}
```

The type must stay the same. Replacing keeps the existing English name; you can override it in
your `lang/en.json`.

### Remove: delete a definition

In `patches/`:

```json
{ "target": "part.torpedo.alpha_torpedo", "$remove": true }
```

Anything else that still refers to the removed id (a starting design, a computer player's part
list, ...) becomes an error, so removing core content usually means patching those references
too. Prefer `required_traits` or a patch over removing.

<a id="change-content-from-another-mod"></a>
To change another mod's content, add it to `depends` or `load_after`, so it loads before yours.

## 7. Check it

<a id="try-it"></a>

**Validator.** From the game's project folder:

```
godot --headless --path . --script res://tools/validate_mod.gd -- path/to/my_mod
```

Every problem is reported as `mod:file:line: message`, for example
`my_mod:content/parts.json:8: my_mod.part.armor.ceramic /mass: must be an integer, not 40.5`.
Fix the first few and run it again: one mistake can cause several messages. When all is well it
lists what the mod adds or patches and ends with `OK: no problems found.`

**In the game.** Put the mod's folder in `user://mods/` (the Mods window's **Open Mods Folder**
button opens it), open **Mods...** in the main menu, tick your mod and press OK. Start a new game:
the new hull is in the ship designer once your construction tech reaches it.

**Common mistakes:**

| Message | Fix |
|---|---|
| `new hull ids from this mod must start with 'my_mod.hull.'` | Prefix new ids with your mod id and the type. |
| `no English name: add "<id>.name"` | Add the key to `lang/en.json`. |
| `must be an integer, not 12.5` | Use whole numbers. |
| `unknown field "armour"` | Check the spelling against [content.md](content.md). |
| `unknown hull 'hull.scuot'` | A reference to an id that doesn't exist. Check the spelling. |
| `duplicate id '...' (use $replace or a patch)` | The id exists already. Pick a new id, or replace or patch it. |
| `patch target '...' does not exist` | The target id is wrong, or its mod loads after yours. |

## Next steps

- Browse `content/core/content/` for examples of every type.
- [traits.md](traits.md): make a new racial trait from existing parameters.
- [content.md](content.md): every field of every type.
- `mods/extra_hulls`: the Extra Hulls sample mod, a larger version of this guide.
