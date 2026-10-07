class_name StandardTurn
extends RefCounted
## The Standard turn (spec S02): every phase in the original's order. Phases not built yet are
## placeholders that do nothing, so their ids already exist for mods and tests.

## S02's phase ids, in order (production split into its steps 13a-13e).
const PHASE_IDS := [
	"turn.seed_tutorial",
	"orders.apply",
	"orders.cleanup",
	"fleets.resolve_targets",
	"wp0.tasks",
	"races.validate",
	"minefields.reset",
	"space.move_before_fleets",
	"fleets.move",
	"planets.after_movement",
	"space.decay_and_detonate",
	"fleets.is_growth",
	"production.mining",
	"production.planets",
	"production.growth",
	"production.research",
	"production.random_events",
	"space.move_after_production",
	"fleets.refuel",
	"wp1.tasks",
	"minefields.sweep",
	"fleets.repair",
	"planets.ca_terraform",
	"planets.remote_terraform",
	"fleets.retarget",
	"planets.estimates",
	"turn.advance",
	"score.update",
	"designs.refresh",
	"turn.random_settings",
	"files.write",
]


static func pipeline() -> TurnPipeline:
	var built := {}
	for p: Phase in [
		OrderPhases.Apply.new(),
		FleetPhases.ResolveTargets.new(),
		FleetPhases.Waypoint0Tasks.new(),
		SpacePhases.MinefieldsReset.new(),
		FleetPhases.Move.new(),
		SpacePhases.DecayAndDetonate.new(),
		FleetPhases.Refuel.new(),
		FleetPhases.Waypoint1Tasks.new(),
		EconomyPhases.Mining.new(),
		EconomyPhases.Planets.new(),
		EconomyPhases.Growth.new(),
		EconomyPhases.TechUpdate.new(),
		SpacePhases.MoveAfterProduction.new(),
		PlanetPhases.ClaimAdjusterTerraform.new(),
		PlanetPhases.RemoteTerraform.new(),
		FleetPhases.Retarget.new(),
		TurnEndPhases.Advance.new(),
		TurnEndPhases.RandomSettings.new(),
		TurnEndPhases.FileDraws.new(),
	]:
		built[p.id] = p
	var out := TurnPipeline.new()
	for id: String in PHASE_IDS:
		out.add(built.get(id, Phase.new(id)))
	return out


## Generates one turn: `state` becomes the next year's state. Returns the rejected orders.
static func generate(
	state: GameState, content: ContentRegistry, orders: Array[OrderSet] = []
) -> PackedStringArray:
	TurnMessages.clear(state)
	var ctx := TurnContext.new(state, content, orders)
	pipeline().run(ctx)
	return ctx.rejected_orders
