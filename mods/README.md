# Sample mods

Five small mods that show what a mod can do (plan M14). Each one is a folder with a `mod.json`; check any of them
with the validator:

```bash
godot --headless --path . --script res://tools/validate_mod.gd -- mods/extra_hulls
```

| Mod | Kind | Shows |
|---|---|---|
| `extra_hulls` | gameplay, data only | new hulls, a patch to a core definition, names in a language file |
| `fast_growth` | gameplay, script | replacing a formula (`economy.pop_growth`) |
| `burrowers` | gameplay, data and script | a new primary race trait (parameters) and a turn phase for its own behaviour |
| `supernova` | gameplay, script | a new turn phase with its own random stream and turn message |
| `retro_text` | cosmetic | changing the game's wording without touching the rules |

Mods with scripts are trusted code: the game loads one only after the player trusts that version of it. See
`modding/` for the full guide.
