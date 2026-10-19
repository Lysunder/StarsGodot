# Script mods

Most mods need only data (see [quickstart.md](quickstart.md)). A script mod adds GDScript code for
behaviour that data can't express: a new formula, a new turn phase, a new kind of effect.

## What works today

| Feature | Status |
|---|---|
| An entry script (`"entry": "my_mod.gd"` in `mod.json`) with `_mod_init(api)` | Works, for gameplay mods the player trusts (below). |
| Replacing or adding formulas through `api.formulas` ([formulas.md](formulas.md)) | Works. |
| Adding, replacing or disabling turn phases through `api` ([phases.md](phases.md#changing-the-pipeline)) | Works. |
| A random stream of the mod's own (`api.stream`, `"mod.<mod_id>"`) | Works. |
| `ruleset.gd` with `build(ruleset)` | Test mods only (mods under `res://tests/`); other mods use `entry`. |
| Hooks (`on_planet_colonized` and the like) and modifier stacks | Not yet. |
| New computer player brains | Not yet. Brains are built in (`AiBrains.IDS`); personalities are content. |
| Turning a mod on in the game | Not yet: the mod manager comes later. The validator and tests load mods today. |

### The entry script

```gdscript
extends RefCounted


func _mod_init(api: ModApi) -> void:
	api.formulas.replace(PlanetEconomy.POP_GROWTH, growth)
	api.insert_after("production.mining", MyPhase.new())


func growth(planet: Planet, race: Race, content: ContentRegistry) -> int:
	var change := PlanetEconomy.standard_growth(planet, race, content)
	return change * 2 if change > 0 else change
```

`_mod_init` runs once while the mods load, after the mod's content, patches and language files.
The [ModApi](api/ModApi.md) it gets has:

- `mod_id`: the mod's id.
- `formulas`: the game's [Ruleset](api/Ruleset.md), to `replace` or `register` formulas.
- `stream`: the name of the mod's own random stream, `mod.<mod_id>`.
- `insert_after(target, phase)`, `insert_before(target, phase)`, `replace_phase(target, phase)`,
  `disable_phase(target)`: changes to the turn's phases. The loader refuses a change that names a
  phase that doesn't exist.

Everything the script does is recorded in the game's content, so it applies to that game only.
The sample mods `mods/fast_growth`, `mods/burrowers` and `mods/supernova` are complete examples.

## Trust

A script mod runs ordinary GDScript with the same access as the game itself. Godot has no
sandbox for scripts, so **a script mod is trusted code**: it can read and write your files like
any program.

The game loads a script mod only when the player trusts that exact version of it. Trust is tied
to the SHA-256 of the mod's scripts (every `.gd` file, path and text): change one character and
the mod must be trusted again. Until then loading stops with "contains scripts: trust this
version first". The question itself will be asked by the mod manager, which comes later; today
the validator trusts the mod it checks, and code can pass trust to the loader
(`ModLoader.trusted[mod_id] = ModLoader.script_hash(source)`).

Planned (decision D10): script mods are allowed everywhere, including play-by-email games, and a
play-by-email host can choose to allow data-only mods only. Only install script mods from people
you trust.

**License.** The game is licensed under the GNU GPL, version 3 or later, and mods must be under a
GPL-compatible license (for example GPL-3.0-or-later, LGPL, MIT, BSD or Apache-2.0). There is no
exception for mods loaded through the mod system.

## Determinism rules

Every computer that generates a turn from the same game, orders and mods must get exactly the
same result. Play by email depends on it: the host generates the turn, and the players' copies
must agree with the host. The base game follows these rules, and gameplay scripts must too.
(Cosmetic code, which only draws things, may ignore them.)

### Random numbers

- Get random numbers only from the game's named streams: `ctx.rng(name)` in a phase
  ([TurnContext](api/TurnContext.md)), or `GameContext.rng(name)`. Each returns a
  [StarsRandom](api/StarsRandom.md). `random(bound)` gives an integer from 0 to bound - 1;
  `next_raw()` gives the raw value.
- A mod uses its own streams: `mod.<mod_id>` or `mod.<mod_id>.<name>` (lowercase letters, digits
  and `_`). The `classic` and `fixes` streams belong to the base rules. Drawing from them shifts
  every later draw of the base game.
- Each stream starts from the game's seed and the stream's name, the first time it is used, and
  its state is saved with the game ([RngStreams](api/RngStreams.md)). So adding a mod stream
  never changes another stream.
- Never use `randi()`, `randf()`, `randomize()`, `RandomNumberGenerator`, or anything that reads
  the time.

### Integer math

- Gameplay values are integers. Content can't hold decimals at all.
- Write percentages as integers and divide last: `value * pct / 100`. GDScript integer division
  truncates toward zero, which is what the rules expect unless they say otherwise.
- Avoid `float`. Floating-point results can differ between machines and compilers.

### Order

- Loop over arrays (`state.planets`, `state.players`, a fleet's stacks): their order is part of
  the saved game.
- Don't loop over a Dictionary whose insertion order could differ between machines. Sort its keys
  first.
- For content, use `ContentRegistry.ids(type)` (sorted by id) or `ids_in_order(type)` (the order
  the definitions were loaded).

### No outside state

- No `Time`, no `OS`, no file or network access in gameplay code.
- No globals: no autoloads, no singletons, no `static var` that changes. Everything a rule needs
  arrives through its context: the state, the content, the ruleset and the random streams.
- Content is frozen while a game runs. Don't try to change definitions from a script.

### Saving your own data

Keep anything your mod needs to remember in a `mod_data` dictionary, under your mod id:
`state.mod_data["my_mod"] = {...}`. The game state and most game objects have one (players,
planets, fleets, designs, minefields, packets, wormholes, races and the Mystery Trader). It is
saved with the game. Store only JSON-style values (numbers, text, true/false, lists and
dictionaries).

## Where the code is

| Class | File | For |
|---|---|---|
| [Ruleset](api/Ruleset.md) | `core/rules/ruleset.gd` | Formulas by id. |
| [TurnPipeline](api/TurnPipeline.md), [Phase](api/Phase.md) | `core/turn/` | Turn phases. |
| [TurnContext](api/TurnContext.md) | `core/turn/turn_context.gd` | What a phase works on. |
| [GameContext](api/GameContext.md) | `core/context/game_context.gd` | One game's content, ruleset and random streams. |
| [ModLoader](api/ModLoader.md) | `core/mod/mod_loader.gd` | Loading and ordering mods. |

The full list is in the [API reference](api/README.md). Everything there is experimental until
the mod API settles: names may change between versions, and `api_version` will go up when they
do.
