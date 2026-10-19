# Traits and trait parameters

Primary racial traits (PRTs) and lesser racial traits (LRTs) are ordinary content: `trait`
definitions in `content/core/content/traits.json`. The rules never check "does this race have
trait X?". Instead, a trait carries **parameters**, and the rules read the parameters. So a mod can
make a new trait out of data alone, by combining parameters that already exist.

## The trait definition

```json
{
  "type": "trait",
  "id": "mymod.trait.burrowers",
  "kind": "lesser",
  "order": 14,
  "cost": 120,
  "params": { "planet.max_pop_extra_pct": 115, "scanner.range_pct": 80 }
}
```

| Field | Meaning |
|---|---|
| `kind` | `primary` or `lesser`. A race has exactly one primary trait and any number of lesser traits. |
| `cost` | Advantage points the trait uses up in the race wizard. A negative cost gives points back. New traits take part in the advantage-point sum through this number only (spec S06). |
| `order` | Position among the traits of its kind. The race wizard lists traits in this order, and random races pick traits by it. |
| `params` | Map of parameter name to integer (the table below lists the names the rules read). |
| `excludes` | Traits that should not be taken together with this one. Accepted, but no rule or screen checks it yet. |

Add `<id>.name` and `<id>.description` to `lang/en.json`. The race wizard shows both.

A new primary trait should also get a `starting_setup` definition (its starting tech, starbases
and fleets; see [content.md](content.md#starting_setup)). Without one the trait gets no
trait-specific starting items.

## How parameters are read

The rules call `RaceMath.trait_param(race, content, name, default)`:

1. The race's traits are taken in order: the primary trait first, then each lesser trait in the
   order the race lists them.
2. The **first** trait that sets the parameter decides its value. Values from several traits are
   not added or multiplied together.
3. If no trait sets it, the rule uses its own default. For most parameters the default is written
   in the rule (100 for a percentage, 0 for an on/off flag). A few production parameters
   (`production.alchemy_cost`, `production.terraform_cost`, `production.miniaturization_per_level`,
   `production.miniaturization_max`, `production.packet_resource_cost` and the packet costs) default
   to the rule constant of the same name, for example `constant.production.alchemy_cost`.

Each rule reads its parameter at the exact step where the original game applies the effect, so
the rounding stays the same as in Stars! 2.6i. That is why traits use named parameters and not a
general "multiply the result by X" system.

Flags are integers too: `1` means on, `0` (or not set) means off.

Some parameter names are built from content: `cost.<category>_adjust_pct` and
`cost.<category>_resources_pct` change the price of parts of a category (for example
`cost.beam_adjust_pct`), and `cost.tag.<tag>_adjust_pct` changes the price of parts with a tag
(`cost.tag.stargate_adjust_pct`). Any category or tag works, not only the ones the base game uses.

## Parts and hulls only some races can use

Parts and hulls have two more trait fields:

- `required_traits`: the race must have **at least one** of these traits.
- `forbidden_traits`: the race may have **none** of these traits.

Some base game traits work only this way. For example, a few lesser traits have no parameters at
all; their whole effect is which parts their races can or cannot build.

## The base game's traits

<!-- BEGIN GENERATED: traits -->
| Id | Name | Kind | Cost | Parameters |
|---|---|---|---|---|
| `trait.prt.HE` | Hyper-Expansion | primary | 40 | `race.growth_rate_pct` 200, `planet.max_pop_pct` 50, `race.ap_factory_growth_factor` 3 |
| `trait.prt.SS` | Super-Stealth | primary | 95 | `cloak.builtin_units` 300, `research.spy_pct` 50, `race.ap_nas_penalty` 200, `minefield.speed_bonus` 1 |
| `trait.prt.WM` | War Monger | primary | 45 | `battle.movement_bonus` 2, `scanner.full_designs` 1, `cost.beam_adjust_pct` 75, `cost.torpedo_adjust_pct` 75, `cost.bomb_adjust_pct` 75, `invasion.troops_pct` 165 |
| `trait.prt.CA` | Claim Adjuster | primary | 10 | `planet.revert_terraform_on_loss` 1, `production.terraform_cost_pct` 50, `cost.terraform_resources_pct` 50, `terraform.instant` 1, `colony.skips_auto_terraform` 1 |
| `trait.prt.IS` | Inner-Strength | primary | -100 | `production.defense_cost_pct` 60, `cost.beam_adjust_pct` 125, `cost.torpedo_adjust_pct` 125, `cost.bomb_adjust_pct` 125, `repair.fleet_pct` 200, `repair.starbase_pct` 150, `fleet.colonist_growth` 1, `invasion.defense_pct` 200 |
| `trait.prt.SD` | Space Demolition | primary | -150 | `minefield.reveals_designs` 1, `scanner.minefields` 1, `minefield.decay_per_planet` 1, `minefield.lay_while_moving` 1, `minefield.speed_bonus` 2, `minefield.detonate` 1 |
| `trait.prt.PP` | Packet Physics | primary | 120 | `packet.reveals_catcher` 1, `ai.no_packets_at_starbases` 1, `race.ap_nas_penalty` 280, `production.packet_mineral_cost` 70, `production.mixed_packet_mineral_cost` 25, `production.packet_resource_cost` 5, `production.packet_minerals` 70, `production.mixed_packet_minerals` 25, `packet.decay_pct` 50, `packet.decay_min` 5, `scanner.packets` 1, `packet.terraforms` 1 |
| `trait.prt.IT` | Inter-stellar Traveler | primary | 180 | `scanner.gates` 1, `production.packet_mineral_cost` 120, `production.mixed_packet_mineral_cost` 48, `cost.tag.stargate_adjust_pct` 75, `movement.gate_cargo` 1, `packet.decay_class_bonus` 1, `packet.catch_pct` 50 |
| `trait.prt.AR` | Alternate Reality | primary | 90 | `race.ap_cheap_energy_penalty` 100, `production.starbase_adjust_pct` 80, `production.genesis_keeps_installations` 1, `invasion.troops_pct` 0, `colony.starbase` 1, `transport.no_invasion` 1, `colony.skips_auto_mines` 1, `colony.skips_auto_factories` 1, `colony.skips_auto_defenses` 1, `message.orbital_colony` 1, `packet.no_damage` 1, `movement.transit_loss_pct` 3, `scanner.population_range` 1, `estimate.hides_population` 1, `production.no_planetary_scanner` 1, `ai.no_colonist_drops` 1, `planet.starbase_population` 1, `planet.no_installations` 1, `planet.root_mines` 1, `planet.root_resources` 1, `planet.orbit_miners` 1 |
| `trait.prt.JoaT` | Jack of All Trades | primary | -66 | `planet.max_pop_pct` 120, `race.ap_nas_penalty` 40, `start.tech_floor` 4, `scanner.builtin_per_level` 20 |
| `trait.lrt.IFE` | Improved Fuel Efficiency | lesser | 235 | `movement.fuel_usage_pct` 85 |
| `trait.lrt.TT` | Total Terraforming | lesser | 25 | `race.hab_terraform_reach_1` 8, `race.hab_terraform_reach_2` 17, `production.terraform_cost` 70, `research.quiet_basic_terraform` 1 |
| `trait.lrt.ARM` | Advanced Remote Mining | lesser | 159 | none |
| `trait.lrt.ISB` | Improved Starbases | lesser | 201 | `cloak.starbase_units` 40, `production.starbase_adjust_pct` 80 |
| `trait.lrt.GR` | Generalized Research | lesser | -40 | `research.current_field_pct` 50, `research.other_field_pct` 15, `research.focus_message` 1 |
| `trait.lrt.UR` | Ultimate Recycling | lesser | 240 | `scrap.recycling` 1 |
| `trait.lrt.MA` | Mineral Alchemy | lesser | 155 | `production.alchemy_cost` 25 |
| `trait.lrt.NRSE` | No Ram Scoop Engines | lesser | -160 | none |
| `trait.lrt.CE` | Cheap Engines | lesser | -240 | `cost.engine_adjust_pct` 50, `movement.engine_failure` 1 |
| `trait.lrt.OBRM` | Only Basic Remote Mining | lesser | -255 | `planet.max_pop_extra_pct` 110 |
| `trait.lrt.NAS` | No Advanced Scanners | lesser | -325 | `race.ap_scanner_restriction` 1, `scanner.range_pct` 200, `scanner.population_range_pmille` 1412 |
| `trait.lrt.LSP` | Low Starting Population | lesser | -180 | `start.population` 175 |
| `trait.lrt.BET` | Bleeding Edge Technology | lesser | -70 | `production.miniaturization_per_level` 5, `production.miniaturization_max` 80, `production.cost_at_tech_level_pct` 200, `battle.salvage_at_current_tech` 1 |
| `trait.lrt.RS` | Regenerating Shields | lesser | -30 | `battle.shield_regen` 1, `design.armor_part_pct` 50, `design.shield_pct` 140 |
<!-- END GENERATED: traits -->

## Parameters the rules read

"Set by" lists the base game traits that set the parameter and their values. "Read in" lists the
`core/` files that name it. To find out exactly what a parameter does, search the code for its
name, or read the rule spec in `specs/` that the file's doc comment names. Names built from content
(`cost.<category>_adjust_pct` and the others above) do not appear as plain text in the code, so
their "Read in" cell can be empty.

<!-- BEGIN GENERATED: params -->
| Parameter | Set by (core) | Read in |
|---|---|---|
| `ai.no_colonist_drops` | AR 1 | `classic_automitrons.gd`, `classic_cybertrons.gd`, `classic_cybertrons_packets.gd`, `classic_robotoids.gd` and 2 more |
| `ai.no_packets_at_starbases` | PP 1 | `classic_planning.gd` |
| `battle.movement_bonus` | WM 2 | `battle_setup.gd` |
| `battle.salvage_at_current_tech` | BET 1 | `battle_engine.gd` |
| `battle.shield_regen` | RS 1 | `battle_engine.gd`, `battle_setup.gd` |
| `cloak.builtin_units` | SS 300 | `cloaking.gd` |
| `cloak.starbase_units` | ISB 40 | `cloaking.gd` |
| `colony.skips_auto_defenses` | AR 1 | `classic_production.gd` |
| `colony.skips_auto_factories` | AR 1 | `classic_production.gd` |
| `colony.skips_auto_mines` | AR 1 | `classic_production.gd` |
| `colony.skips_auto_terraform` | CA 1 | `classic_production.gd` |
| `colony.starbase` | AR 1 | `battle_engine.gd`, `battles.gd`, `ground_combat.gd`, `random_events.gd` and 1 more |
| `cost.beam_adjust_pct` | WM 75, IS 125 |  |
| `cost.bomb_adjust_pct` | WM 75, IS 125 |  |
| `cost.engine_adjust_pct` | CE 50 |  |
| `cost.tag.stargate_adjust_pct` | IT 75 |  |
| `cost.terraform_resources_pct` | CA 50 |  |
| `cost.torpedo_adjust_pct` | WM 75, IS 125 |  |
| `design.armor_part_pct` | RS 50 | `part_rules.gd` |
| `design.shield_pct` | RS 140 | `part_rules.gd` |
| `estimate.hides_population` | AR 1 | `planet_estimates.gd` |
| `fleet.colonist_growth` | IS 1 | `repair.gd` |
| `invasion.defense_pct` | IS 200 | `ground_combat.gd` |
| `invasion.troops_pct` | WM 165, AR 0 | `baseline_ai.gd`, `ground_combat.gd` |
| `message.orbital_colony` | AR 1 | `economy_phases.gd` |
| `minefield.decay_per_planet` | SD 1 | `minefields.gd` |
| `minefield.detonate` | SD 1 | `order_rules.gd` |
| `minefield.lay_while_moving` | SD 1 | `waypoint_tasks.gd` |
| `minefield.reveals_designs` | SD 1 | `minefields.gd` |
| `minefield.speed_bonus` | SS 1, SD 2 | `classic_fleets.gd`, `minefields.gd` |
| `movement.engine_failure` | CE 1 | `movement.gd` |
| `movement.fuel_usage_pct` | IFE 85 | `movement.gd` |
| `movement.gate_cargo` | IT 1 | `stargates.gd`, `waypoint_warp.gd` |
| `movement.transit_loss_pct` | AR 3 | `movement.gd` |
| `packet.catch_pct` | IT 50 | `packets.gd` |
| `packet.decay_class_bonus` | IT 1 | `packets.gd` |
| `packet.decay_min` | PP 5 | `packets.gd` |
| `packet.decay_pct` | PP 50 | `packets.gd` |
| `packet.no_damage` | AR 1 | `classic_planning.gd`, `packets.gd` |
| `packet.reveals_catcher` | PP 1 | `packets.gd` |
| `packet.terraforms` | PP 1 | `packets.gd` |
| `planet.max_pop_extra_pct` | OBRM 110 | `planet_economy.gd` |
| `planet.max_pop_pct` | HE 50, JoaT 120 | `planet_economy.gd` |
| `planet.no_installations` | AR 1 | `planet_economy.gd` |
| `planet.orbit_miners` | AR 1 | `planet_economy.gd` |
| `planet.revert_terraform_on_loss` | CA 1 | `planet_economy.gd` |
| `planet.root_mines` | AR 1 | `planet_economy.gd` |
| `planet.root_resources` | AR 1 | `planet_economy.gd` |
| `planet.starbase_population` | AR 1 | `planet_economy.gd` |
| `production.alchemy_cost` | MA 25 | `production.gd`, `production_costs.gd` |
| `production.cost_at_tech_level_pct` | BET 200 | `production_costs.gd`, `waypoint_tasks.gd` |
| `production.defense_cost_pct` | IS 60 | `production_costs.gd` |
| `production.genesis_keeps_installations` | AR 1 | `production.gd` |
| `production.miniaturization_max` | BET 80 | `production_costs.gd` |
| `production.miniaturization_per_level` | BET 5 | `production_costs.gd` |
| `production.mixed_packet_mineral_cost` | PP 25, IT 48 | `production_costs.gd` |
| `production.mixed_packet_minerals` | PP 25 | `packets.gd` |
| `production.no_planetary_scanner` | AR 1 | `classic_production.gd` |
| `production.packet_mineral_cost` | PP 70, IT 120 | `production_costs.gd` |
| `production.packet_minerals` | PP 70 | `packets.gd` |
| `production.packet_resource_cost` | PP 5 | `production_costs.gd` |
| `production.starbase_adjust_pct` | AR 80, ISB 80 | `production_costs.gd` |
| `production.terraform_cost` | TT 70 | `production_costs.gd` |
| `production.terraform_cost_pct` | CA 50 | `production_costs.gd` |
| `race.ap_cheap_energy_penalty` | AR 100 | `race_math.gd` |
| `race.ap_factory_growth_factor` | HE 3 | `race_math.gd` |
| `race.ap_nas_penalty` | SS 200, PP 280, JoaT 40 | `race_math.gd` |
| `race.ap_scanner_restriction` | NAS 1 | `race_math.gd` |
| `race.growth_rate_pct` | HE 200 | `classic_cybertrons.gd`, `classic_macinti_production.gd`, `classic_robotoids.gd`, `planet_economy.gd` and 1 more |
| `race.hab_terraform_reach_1` | TT 8 | `race_math.gd` |
| `race.hab_terraform_reach_2` | TT 17 | `race_math.gd` |
| `repair.fleet_pct` | IS 200 | `repair.gd` |
| `repair.starbase_pct` | IS 150 | `repair.gd` |
| `research.current_field_pct` | GR 50 | `research_rules.gd` |
| `research.focus_message` | GR 1 | `research_rules.gd` |
| `research.other_field_pct` | GR 15 | `research_rules.gd` |
| `research.quiet_basic_terraform` | TT 1 | `research_rules.gd` |
| `research.spy_pct` | SS 50 | `research_rules.gd` |
| `scanner.builtin_per_level` | JoaT 20 | `scanning.gd` |
| `scanner.full_designs` | WM 1 | `scanning.gd` |
| `scanner.gates` | IT 1 | `scanning.gd` |
| `scanner.minefields` | SD 1 | `scanning.gd` |
| `scanner.packets` | PP 1 | `scanning.gd` |
| `scanner.population_range` | AR 1 | `scanning.gd` |
| `scanner.population_range_pmille` | NAS 1412 | `scanning.gd` |
| `scanner.range_pct` | NAS 200 | `scanning.gd` |
| `scrap.recycling` | UR 1 | `waypoint_tasks.gd` |
| `start.population` | LSP 175 | `starting_setup.gd` |
| `start.tech_floor` | JoaT 4 | `starting_setup.gd` |
| `terraform.instant` | CA 1 | `terraforming.gd` |
| `transport.no_invasion` | AR 1 | `waypoint_tasks.gd` |
<!-- END GENERATED: params -->

## Not built yet

These parts of the design in the project plan do not exist yet. Don't rely on them:

- **Modifier stacks**: generic `add` / `pct` / `ratio` modifiers with conditions (for example
  "+20 cloak while the fleet carries no cargo"). Not yet.
- **Trait hook scripts**: a trait that runs a script when something happens (a planet is
  colonized, a battle ends). There is no hook bus yet (`GameContext.hooks` is a placeholder).
  Not yet. Today a trait's own behaviour goes in a turn phase: the sample mod `mods/burrowers`
  is a new primary trait made of parameters, plus a phase after mining for what parameters
  can't say.
- **New parameters without code**: a parameter only does something when a rule reads it. A mod
  that needs a new kind of effect needs a script (see [scripts.md](scripts.md)).
