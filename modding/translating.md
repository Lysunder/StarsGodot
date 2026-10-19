# Translating the game

A translation is a cosmetic mod with one strings file per language. Once it is installed and turned on in
**Mods...**, its language appears under **Settings... > Language**. English fills in anything a translation leaves
out, so a translation can be done a part at a time.

## The files

```
my_translation/
  mod.json              {"id": "my_translation", "kind": "cosmetic", ...}
  lang/de.json          German
  lang/help/de.json     (optional) the help, kept in its own file
```

The file name is the locale code Godot uses: `de`, `fr`, `pt_BR`, `zh_CN`. Every `lang/**/<locale>.json` file of the
mod is read, so a translation may split its strings over as many files as it likes.

## Where to start

[translation_template.json](translation_template.json) holds every string the game shows, with its English text.
Copy it to `lang/<locale>.json` in your mod and translate the values, never the keys. It has three kinds of keys:

- **`ui.<English text>`**: the interface's own text: menus, buttons, labels, window titles, tooltips. The key is
  the English text itself.
- **`<content id>.name`** and other content keys: the names of parts, hulls, traits, tech fields and so on, and the
  turn messages' wording (`message.*`).
- **`help.*`**: the help topics. `help.<topic>.title` and `help.<topic>.body`; `help.index` lists the topics in
  order (leave it alone unless you add topics).

You can delete keys you haven't translated: English is used for them.

## Placeholders and markup

- Keep every `%s`, `%d` and `%.2f` in the same order: the game fills them in. `%%` is a percent sign.
- In the help, keep the markup: `## ` headings, `- ` bullets, `**bold**`, `[[topic]]` and `[[topic|text]]` links
  (translate only the text after `|`), `{key:action}` and `{keys}` (the player's keys).
- Part, hull and trait names are the original game's names in English. Translating them is up to you.

## What isn't translated yet

- A few pieces of text that the game's rules put together (fleet names such as "Scout #3", waypoint labels such
  as "Space (120, 340)" and some report cells) are still English.
- Fonts: the bundled fonts cover Latin, Greek and Cyrillic letters. Other scripts need a font mod, which isn't
  possible yet.

## Keeping the template current

The template is generated from the game's code and content:

```
python tools/gen_ui_strings.py
```

CI fails when it is out of date. The same tool wraps new format strings in the interface in `tr()`
(`--list` shows them, `--wrap` changes the code).
