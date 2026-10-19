# Cosmetic mods

A cosmetic mod changes how the game looks or reads, never how it plays. Each player can use their
own cosmetic mods: they are not part of the ruleset hash and are never recorded in saves or turn
files. Set `"kind": "cosmetic"` in `mod.json`.

**Honest status:** today a cosmetic mod can only change text. Art packs, themes, sound and scene
overrides are planned but not built.

| Feature | Status |
|---|---|
| Text: rename things, reword messages and descriptions (`lang/<locale>.json`) | Works |
| Choosing a language in the game | Not yet: the interface always asks for English (`en`) |
| Art packs (hull, planet and part pictures by art id) | Not yet |
| Themes (a Godot `Theme` from a mod) | Not yet |
| Scene overrides (replace or add UI panels and map overlays) | Not yet |
| Sound and music | Not yet |
| Classic pack imported from your own copy of the original game | Not yet |

A cosmetic mod may contain only `mod.json` and `lang/`. One with a `content/` or `patches/`
folder is refused.

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
