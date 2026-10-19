# The turn pipeline and phases

When a year is generated, the game runs a list of **phases** in order. Each phase is one step of
the turn: apply the players' orders, move fleets, mine, grow population, fight battles, and so on.
Every phase has an id. The list is a `TurnPipeline` (`core/turn/turn_pipeline.gd`), so phases can
be added, replaced or switched off by id.

The order comes from the original game's turn generation and is written down in spec
`specs/S02-turn-order.md`. The order inside each phase (which players, fleets and planets go
first) is part of the rules too: changing it changes the results.

## Phase ids, in order

`StandardTurn.PHASE_IDS` (`core/turn/standard_turn.gd`). "Placeholder" phases exist so their id
can be used as an anchor, but they do nothing yet.

| # | Id | What happens | Class |
|---|---|---|---|
| 1 | `turn.seed_tutorial` | Tutorial games only: reseed the random numbers. | placeholder |
| 2 | `orders.apply` | Every player's orders, players in index order (S11). | `OrderPhases.Apply` |
| 3 | `orders.cleanup` | Bookkeeping after the orders. | placeholder |
| 4 | `fleets.resolve_targets` | Fleets following or chasing other fleets update their waypoints (S12). | `FleetPhases.ResolveTargets` |
| 5 | `wp0.tasks` | Waypoint tasks at the fleets' current waypoint: unloading, colonizing, ground combat, loading (S11). | `FleetPhases.Waypoint0Tasks` |
| 6 | `races.validate` | Check every race's settings. | placeholder |
| 7 | `minefields.reset` | Clear each minefield's "seen this turn" records (S13). | `SpacePhases.MinefieldsReset` |
| 8 | `space.move_before_fleets` | Packets in flight move and hit their targets; the Mystery Trader moves (S14, S18). | `SpacePhases.MoveBeforeFleets` |
| 9 | `fleets.move` | Fleets move: fuel, stargates, wormholes, mine hits on the way (S12, S13). | `FleetPhases.Move` |
| 10 | `planets.after_movement` | Bookkeeping after movement. | placeholder |
| 11 | `space.decay_and_detonate` | Minefields detonate and decay, then packets and salvage decay (S13, S14). | `SpacePhases.DecayAndDetonate` |
| 12 | `fleets.is_growth` | Colonists grow in Inner-Strength cargo holds (S19). | `FleetPhases.ColonistGrowth` |
| 13 | `production.mining` | Every populated planet is mined (S08). | `EconomyPhases.Mining` |
| 14 | `production.planets` | Each planet's resources go to research and its production queue (S09). | `EconomyPhases.Planets` |
| 15 | `production.growth` | Populations grow or shrink (S08). | `EconomyPhases.Growth` |
| 16 | `production.research` | Research points and new tech levels (S05). | `EconomyPhases.TechUpdate` |
| 17 | `production.random_events` | Random events, unless the game has them off (S18). | `EconomyPhases.RandomEventsPhase` |
| 18 | `space.move_after_production` | New packets move half a year; wormholes shift (S14, S12). | `SpacePhases.MoveAfterProduction` |
| 19 | `fleets.refuel` | Refuelling and fuel making (S12, S19). | `FleetPhases.Refuel` |
| 20 | `wp1.tasks` | Battles and bombing, then the waypoint tasks of fleets that arrived (S16, S17, S11). | `FleetPhases.Waypoint1Tasks` |
| 21 | `minefields.sweep` | Ships with beam weapons sweep minefields (S13). | `SpacePhases.Sweep` |
| 22 | `fleets.repair` | Fleets and starbases repair (S19). | `FleetPhases.RepairPhase` |
| 23 | `planets.ca_terraform` | Claim Adjuster terraforming (S10). | `PlanetPhases.ClaimAdjusterTerraform` |
| 24 | `planets.remote_terraform` | Terraforming by fleets (S10). | `PlanetPhases.RemoteTerraform` |
| 25 | `fleets.retarget` | Waypoints that target fleets are checked again (S12). | `FleetPhases.Retarget` |
| 26 | `planets.estimates` | The population and defense estimates other players see (S15). | `TurnEndPhases.Estimates` |
| 27 | `turn.advance` | The year advances. | `TurnEndPhases.Advance` |
| 28 | `score.update` | Scores, ranks, eliminations and victory (S20). | `TurnEndPhases.ScoreUpdate` |
| 29 | `designs.refresh` | Recompute cached design values. | placeholder |
| 30 | `turn.random_settings` | One random draw the original makes here. | `TurnEndPhases.RandomSettings` |
| 31 | `files.write` | The random draws the original makes when it writes each file, and each player's scanning (S01, S15). | `TurnEndPhases.FileDraws` |

The original's single production step is split into five phases (13 to 17), so a mod can put
something between, for example, mining and production. Several phases draw from the `classic`
random stream; a phase that moves, removes or adds such draws changes every later random number.

## Writing a phase

A phase is a class that extends `Phase` (`core/turn/phase.gd`), sets its id and overrides `run`:

```gdscript
# supernova_phase.gd
extends Phase
## A star explodes now and then and burns the planet's surface minerals.


func _init() -> void:
	super("my_mod.supernova")


func run(ctx: TurnContext) -> void:
	var rng := ctx.rng("mod.my_mod")
	for planet in ctx.state.planets:  # an Array: iterating it has a defined order
		if rng.random(1000) == 0:
			planet.surface.fill(0)  # surface minerals, kT of each mineral
```

Give your phases ids that start with your mod id. The base game's ids are listed above. Avoid
`class_name` in mod scripts: class names are global in Godot, so two mods could clash. Load your
scripts with `preload` or `load` instead.

What a phase gets in `ctx` (a [TurnContext](api/TurnContext.md)):

| Member | What it is |
|---|---|
| `ctx.state` | The [GameState](api/GameState.md): players, planets, fleets, minefields, packets and the rest. The phase changes it in place. |
| `ctx.content` | The frozen [ContentRegistry](api/ContentRegistry.md), with the ruleset as `ctx.content.ruleset`. |
| `ctx.orders` | This turn's orders, one [OrderSet](api/OrderSet.md) per player. |
| `ctx.research_spent` | Resources each player put into research this year (set by `production.planets`). |
| `ctx.rejected_orders` | Orders the order phase refused, one line each. |
| `ctx.rng(name)` | A named random stream (see [scripts.md](scripts.md#random-numbers)). Without a name, the `classic` stream. |
| `ctx.player(index)` | Shortcut for `ctx.state.players[index]`. |

To tell players something, send a turn message with
`TurnMessages.add(ctx.state, ctx.content, player, type, goto, params)`. `type` is the id of a
`message` definition; a mod adds its own message types as content (see
[content.md](content.md#message)), with the wording in `lang/en.json` as `<id>.text`.

The model classes are in `core/model/`; the [API reference](api/README.md) lists their fields
(for example [Planet](api/Planet.md) and [Fleet](api/Fleet.md)).

## Changing the pipeline

`TurnPipeline` methods:

| Method | What it does |
|---|---|
| `add(phase)` | Adds a phase at the end. The id must be new. |
| `insert_before(id, phase)` | Inserts a phase before the phase with that id. |
| `insert_after(id, phase)` | Inserts a phase after it. |
| `replace(id, phase)` | Puts another phase in that phase's place. |
| `disable(id)` | Skips that phase when the turn runs. |
| `ids()` | The phase ids in order. |
| `phase(id)`, `index_of(id)` | Find a phase. |
| `run(ctx)` | Runs every phase that is not disabled, in order. |

```gdscript
var pipeline := StandardTurn.pipeline()
pipeline.insert_after("production.growth", preload("supernova_phase.gd").new())
pipeline.disable("production.random_events")
```

A mod doesn't build the pipeline itself: `StandardTurn.generate` builds it fresh for every turn.
A mod's entry script changes the pipeline through its [ModApi](api/ModApi.md):
`api.insert_after(target, phase)`, `api.insert_before(target, phase)`,
`api.replace_phase(target, phase)` and `api.disable_phase(target)`. The changes are applied in
load order whenever a turn is generated (`StandardTurn.pipeline(content)`), and the loader
refuses one that names a phase that doesn't exist. A phase is a class that extends
[Phase](api/Phase.md), with an id of its own (start it with your mod id) and a `run(ctx)`.

The sample mod `mods/supernova` adds a phase after the random events:

```gdscript
func _mod_init(api: ModApi) -> void:
	api.insert_after("production.random_events", Flares.new(api.stream))


class Flares:
	extends Phase
	var stream: String

	func _init(p_stream: String) -> void:
		super("supernova.flares")
		stream = p_stream

	func run(ctx: TurnContext) -> void:
		var rng := ctx.rng(stream)
		...
```

`mods/burrowers` adds one after mining for its trait's behaviour.

## Hooks

Hooks (finer events inside phases, such as "a planet was colonized" or "a battle ended") are
planned but **not built yet**. `GameContext.hooks` is an empty placeholder, and no rule sends
hook events. Spec S02 plans `on_turn_start` before `orders.apply` and `on_turn_end` after
`score.update`; other specs list more in their "Mod hooks" sections.
