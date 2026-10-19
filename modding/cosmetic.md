# Cosmetic mods

A cosmetic mod changes how the game looks or reads, never how it plays. Each player can use their
own cosmetic mods: they are not part of the ruleset hash and are never recorded in saves or turn
files. Set `"kind": "cosmetic"` in `mod.json`.

**Status:** a cosmetic mod can change text and supply pictures by art id. Themes, sound and scene
overrides are planned but not built.

| Feature | Status |
|---|---|
| Text: rename things, reword messages and descriptions (`lang/<locale>.json`) | Works |
| Choosing a language in the game | Works: **Settings... > Language** lists the languages the mods have strings for. See [translating.md](translating.md). |
| Art packs: pictures by art id (`art/index.json`) | Works: ship and planet pictures (the Planet and Fleet tiles, the summary, the ship designer), part pictures (the designer), race logos (Player Relations, the score) and map objects (wormholes, packets, salvage, the Mystery Trader). |
| Themes (a Godot `Theme` from a mod) | Not yet |
| Scene overrides (replace or add UI panels and map overlays) | Not yet |
| Sound and music | Not yet |
| Classic pack imported from your own copy of the original game | Works: main menu, **Import Classic Look...** (pictures and turn-message wording). |

A cosmetic mod may contain `mod.json`, `lang/` and `art/`. One with a `content/` or `patches/`
folder is refused.

## Pictures

A mod supplies pictures in `art/`: PNG files and an `art/index.json` mapping art ids to them:

```json
{
  "art.hull.scout.0": { "file": "sheets/ships.png", "rect": [0, 0, 64, 64] },
  "art.planet.3": { "file": "planet3.png" }
}
```

`file` is a path inside `art/`; `rect` (x, y, width, height) picks part of a larger sheet and may
be left out. Mods turned on later win. Art ids follow one rule: `art.` plus the content id it shows,
plus `.<k>` for one of several pictures (a hull's four, `art.hull.scout.0` to `.3`) and `.small`
for a smaller version; planets are `art.planet.<0-27>` (a planet shows picture (its number + 8)
mod 28). Where no mod supplies a picture, the game draws its own. The classic import
(`classic_import/`, spec S26) writes exactly such a mod, `user://mods/classic/`.

## Text

A `lang/<locale>.json` file is a flat object of key to text. Mods load in order and a later mod's
text wins, so a cosmetic mod that loads after `core` can change any text the base game puts in its
language file:

```json
{
  "hull.scout.name": "Pathfinder",
  "part.beam.laser.name": "Light Laser",
  "message.production.queue_empty.text": "Nothing left to build on {0}."
}
```

The keys the game uses:

| Key | Used for |
|---|---|
| `<id>.name` | The display name of any definition (parts, hulls, traits, tech fields, constants, ...). |
| `<trait id>.description` | The trait's text in the race wizard. |
| `<message id>.text` | A turn message. `{0}`, `{1}`, ... are its parameters, filled in by kind (a planet name, a number, ...). Keep every placeholder the original text has. |
| `ai_setting.<key>.description` | A computer player setting's tooltip in the personality editor. |

The base game's file, `content/core/lang/en.json`, lists every key. If a key is missing in the
chosen language, the English text is used, and if that is missing too, the key itself is shown.

A translation would be a cosmetic mod with `lang/<locale>.json`, for example `lang/de.json`. It
loads fine today, but the interface has no language setting yet, so it would not be shown.
The sample mod `mods/retro_text` is a cosmetic mod of this kind: its `lang/en.json` rewrites a few
turn messages and hull names. Games with and without it play the same, and saves don't record it.

## What the interface looks like today

So you know what there is to change once art and theme mods exist:

- The "Classic 95" theme is built in code (`ui/theme/classic_theme.gd`). Players pick its font,
  font size, interface scale and colour palette in the settings dialog. The bundled fonts are in
  `art/fonts/` (all SIL Open Font License).
- Hulls are drawn from their content: each slot's `at` position and the hull's `cargo_area`
  (`ui/hull_schematic.gd`). A new hull from a gameplay mod is drawn the same way.
- There are no image or sound files from the original game in the project, and there never will
  be. The planned classic pack would be made on each player's own computer from their own copy of
  the game, and never shared.

## Rules for cosmetic mods

- Don't share text, pictures or sounds you don't have the right to share. That includes the
  original game's help text, messages and art.
- Cosmetic code (when script support arrives) only draws things. It must never change the game
  state.
