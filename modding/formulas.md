# Formulas and the Ruleset

Some rules are **formulas**: functions registered under an id in a `Ruleset`
(`core/rules/ruleset.gd`). A rule that uses a formula never calls the function directly. It asks
the ruleset for the formula by id and calls whatever is registered there. So a mod can swap a
formula for its own version without touching the rest of the code.

Each game has its own ruleset. It belongs to the game's content (`ContentRegistry.ruleset`), never
to a global, and it is frozen once the mods have loaded.

## The Ruleset API

| Method | What it does |
|---|---|
| `register(id, formula)` | Adds a new formula id. Fails if the id exists. |
| `replace(id, formula)` | Replaces a registered formula. Fails if the id does not exist. |
| `has(id)` | True when the id is registered. |
| `formula(id)` | The registered `Callable`. |
| `ids()` | Every registered id, sorted. |

A formula is any GDScript `Callable`, usually a static function. Its arguments and result are
whatever the formula id defines (see the table below). A replacement must take the same
arguments and return the same kind of value.

Rules call a formula like this:

```gdscript
var rating: Callable = content.ruleset.formula(StandardRuleset.SHIP_RATING)
var value: int = rating.call(design, content)
```

## Formula ids

These are all the formulas registered today, by `StandardRuleset.build()`
(`core/rules/standard_ruleset.gd`). "Standard" means the rules of Stars! 2.6i with its known bugs
fixed.

| Id | Function | Arguments, result | What it computes |
|---|---|---|---|
| `battle.armor_damage` | `ArmorDamage.ships` | `(token: Dictionary, damage: int, kills_allowed: int) -> [ships left, damage left over, kills still allowed]` | How damage that gets through the shields hurts a stack of ships (S16). |
| `battle.starbase_damage` | `ArmorDamage.starbase` | `(token: Dictionary, damage: int) -> int` | A starbase's new damage after a hit, in 1/500 of its armor, or -1 when it is destroyed (S16). |
| `minefield.top_up` | `Minefields.top_up_share` | `(top_up: int, stack_ships: int, fleet_ships: int, first: bool) -> int` | A stack's share of the minimum mine damage, in proportion to its ships; `first` is true for the first stack hit (S13). |
| `score.ship_rating` | `Score.ship_rating` | `(design: Design, content: ContentRegistry) -> int` | A design's fighting value, used by the score (S20). |
| `score.player` | `Score.record` | `(state: GameState, content: ContentRegistry, player: int) -> Dictionary` | A player's score record, before ranks and victory conditions (S20). |
| `economy.pop_growth` | `PlanetEconomy.standard_growth` | `(planet: Planet, race: Race, content: ContentRegistry) -> int` | The colonists a year adds to (or takes from) a planet (S08). |
| `ai.cybertrons_marks_base` | `ClassicCybertrons.marks_base` | `(planets: int, last_loaded: int) -> int` | Computer player bookkeeping (S22). |
| `ai.cybertrons_packet_record` | `ClassicCybertrons.packet_record` | `(target: int) -> int` | Computer player bookkeeping (S22). |
| `ai.cybertrons_sector_reach` | `ClassicCybertrons.sector_reach` | `(reach: int) -> int` | Computer player bookkeeping (S22). |
| `ai.cybertrons_long_target` | `ClassicCybertrons.long_target` | `(driver_target: int, last_chosen: int) -> int` | Computer player bookkeeping (S22). |
| `ai.macinti_scout_cap_design` | `ClassicMacinti.scout_cap_design` | `(miner_slot: int) -> int` | Which design caps a computer player's scouts (S22). |
| `ai.macinti_all_rich` | `ClassicMacinti.all_rich` | `(count: int) -> bool` | Whether a computer player counts all minerals as rich (S22). |
| `ai.empty_slot_turn` | `ClassicWorld.no_empty_slot_turn` | `(held: int) -> int` | The turn an empty design slot reports (S22). |

Most of these exist because they are where the Standard rules fix a bug in the original game.
The test-only mod `tests/harness_compat` replaces them with the original behaviour, so automated
tests can compare our turns with the original's (see `tests/harness_compat/README.md`). It is a
working example of a mod that replaces formulas.

Each function's doc comment, and the spec it names, describe it fully. See the
[API reference](api/README.md) (for example [ArmorDamage](api/ArmorDamage.md) and
[Score](api/Score.md)).

## Not built yet

The project plan lists many more formula ids (mining, research cost, fuel use, hit chances and
others, named in each spec's "Mod hooks" section). Population growth is one so far
(`economy.pop_growth`); **the others are not registered yet.** Those rules are still plain functions in `core/rules/`. A mod cannot replace them until
they get a formula id.

Also not built yet:

- **Wrapping** a formula (calling the original from your version, `wrap(id, func(ctx, next))`).
  Today you can only replace it; a replacement can still call the Standard function directly,
  for example `Score.ship_rating(design, content)`.
- **A formula context object** (`FormulaContext`). Formulas take plain arguments for now.
- **Named rulesets** other than Standard.

## Replacing a formula from a mod

A mod replaces formulas from its entry script (see [scripts.md](scripts.md#the-entry-script)),
through `api.formulas`. A replacement must take the same arguments and return the same kind of
value as the formula it replaces. The sample mod `mods/fast_growth` replaces `economy.pop_growth`
with one that doubles every gain:

```gdscript
func _mod_init(api: ModApi) -> void:
	api.formulas.replace(PlanetEconomy.POP_GROWTH, growth)
```

A replacement formula must follow the [determinism rules](scripts.md#determinism-rules): integer
math, no clocks, no `randi()`, and a defined order for every loop.
