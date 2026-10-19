# Content reference

Content is the game's data: parts, hulls, traits, rule constants, starting fleets, message types,
computer player settings and more. The base game's content lives in `content/core/content/`. A mod
adds to it, replaces parts of it, or patches it, with the same file format.

This page lists every content type and field. The tables between the "generated" markers come
from the code (`core/content/content_schemas.gd`) and from the base game's own files. To refresh
them, run `python tools/gen_content_docs.py`.

## How content files work

- A file in `content/` (any sub-folder, any name ending in `.json`) holds **one definition object or
  a list of them**. Files load in sorted path order.
- Every definition has a `type` (one of the types below) and an `id`. It may have `tags`, a list of
  text labels that rules and patches can look for.
- **Unknown fields are errors.** A typo such as `"armour"` is reported, not ignored.
- **Numbers are integers.** A decimal number anywhere is an error (`1.5`, and also `2.0`). Use whole
  units, percentages or tenths, as the field says.
- **Ids are dotted.** New ids from `core` start with `<type>.` (`part.beam.laser`). New ids from any
  other mod must start with `<mod_id>.<type>.` (`extra_hulls.hull.long_scout`). So two mods can
  never add the same id by accident.
- **References** (`ref` fields, such as a hull's `required_traits` or a starting design's `hull`)
  are checked after every mod has loaded. A reference to an id that does not exist, or to an id of
  the wrong type, is an error.
- **Every definition needs an English name.** Add the key `<id>.name` to `lang/en.json`. Traits
  also use `<id>.description` in the race wizard. Message types use `<id>.text` for their wording.
- To change a definition another mod made, use `"$replace": true` or a patch. See
  [quickstart.md](quickstart.md#change-content-from-another-mod).

When all mods are loaded, the content is frozen: nothing can change it during a game. The game then
hashes all gameplay content (the ruleset hash). Saves and play-by-email files record the hash, so
all players of a game must have the same gameplay mods.

## Content types

<!-- BEGIN GENERATED: types -->
Every definition also has the common fields:

| Field | Kind | Required |
|---|---|---|
| `type` | text | yes |
| `id` | id | yes |
| `tags` | list of text |  |

Type index: [`ai_design_names`](#ai_design_names), [`ai_design_template`](#ai_design_template), [`ai_hull_class`](#ai_hull_class), [`ai_part_class`](#ai_part_class), [`ai_personality`](#ai_personality), [`ai_research_plan`](#ai_research_plan), [`battle_board`](#battle_board), [`battle_plan_default`](#battle_plan_default), [`constant`](#constant), [`hull`](#hull), [`message`](#message), [`name_list`](#name_list), [`part`](#part), [`part_upgrade`](#part_upgrade), [`production_item`](#production_item), [`race_preset`](#race_preset), [`starting_design`](#starting_design), [`starting_setup`](#starting_setup), [`tech_field`](#tech_field), [`trait`](#trait).

### ai_design_names

Names the classic personalities give their designs of these hulls (no hulls: the list for any other hull; ai_design_names.starbase for starbases).

| Field | Kind | Required | Notes |
|---|---|---|---|
| `hulls` | list of id of a `hull` |  |  |
| `names` | list (at least 1) of text | yes |  |

The base game defines 10. Example from `content/core`:

```json
{
  "type": "ai_design_names",
  "id": "ai_design_names.scout",
  "hulls": [
    "hull.scout",
    "hull.frigate"
  ],
  "names": [
    "Seeker",
    "Lookout",
    "Pathmark",
    "Outrider",
    "Glimmer",
    "Farsight",
    "Skimmer",
    "Wanderer",
    "Trailblazer",
    "Starfinch"
  ]
}
```

### ai_design_template

A classic personality's design: a hull and a part class per hull slot.

| Field | Kind | Required | Notes |
|---|---|---|---|
| `hull` | id of a `hull` | yes |  |
| `slots` | list (at least 1) of id of a `ai_part_class` | yes |  |

The base game defines 138. Example from `content/core`:

```json
{
  "type": "ai_design_template",
  "id": "ai_design_template.meta_morph_warship_a0",
  "hull": "hull.meta_morph",
  "slots": [
    "ai_part_class.engine_scoop",
    "ai_part_class.beam_light",
    "ai_part_class.shield",
    "ai_part_class.shield",
    "ai_part_class.stealth_support",
    "ai_part_class.armor",
    "ai_part_class.armor"
  ]
}
```

### ai_hull_class

A class of hulls the classic personalities tell apart (S22 "The classic world"), where the original compares hull numbers.

| Field | Kind | Required | Notes |
|---|---|---|---|
| `hulls` | list of id of a `hull` | yes |  |

The base game defines 8. Example from `content/core`:

```json
{
  "type": "ai_hull_class",
  "id": "ai_hull_class.bomber",
  "hulls": [
    "hull.mini_bomber",
    "hull.b_17_bomber",
    "hull.stealth_bomber",
    "hull.b_52_bomber"
  ]
}
```

### ai_part_class

The parts the classic personalities put in a slot of a kind (S22 "Classic designs"): groups of parts, best first; the first part the player can use wins.

| Field | Kind | Required | Notes |
|---|---|---|---|
| `candidates` | list (at least 1) of list (at least 1) of id of a `part` | yes |  |

The base game defines 45. Example from `content/core`:

```json
{
  "type": "ai_part_class",
  "id": "ai_part_class.torpedo",
  "candidates": [
    [
      "part.torpedo.anti_matter_torpedo",
      "part.torpedo.omega_torpedo",
      "part.torpedo.upsilon_torpedo",
      "part.torpedo.rho_torpedo",
      "part.torpedo.epsilon_torpedo",
      "part.torpedo.delta_torpedo",
      "part.torpedo.beta_torpedo",
      "part.torpedo.alpha_torpedo"
    ]
  ]
}
```

### ai_personality

A computer player's personality (S22): the brain it runs, its parameters, per difficulty level (ComputerPlayers.LEVELS) the parameters that level changes, and the race it plays per level.

| Field | Kind | Required | Notes |
|---|---|---|---|
| `order` | integer >= 0 | yes |  |
| `brain` | one of `idle`, `baseline`, `robotoids`, `turindrones`, `automitrons`, `rototills`, `cybertrons`, `macinti` | yes |  |
| `params` | map: lowercase dotted key -> integer |  |  |
| `levels` | list (at most 4) of map: lowercase dotted key -> integer |  |  |
| `races` | list (at most 4) of objects (see below) |  | The race it plays at each level (built-in personalities). |
| `races[].primary_trait` | id of a `trait` | yes |  |
| `races[].lesser_traits` | list of id of a `trait` |  |  |
| `races[].hab_low` | list (exactly 3) of integer -1 to 100 |  |  |
| `races[].hab_center` | list (exactly 3) of integer -1 to 100 |  |  |
| `races[].hab_high` | list (exactly 3) of integer -1 to 100 |  |  |
| `races[].growth_rate` | integer >= 0 |  |  |
| `races[].resources_per_colonist` | integer >= 0 |  |  |
| `races[].factory_output` | integer >= 0 |  |  |
| `races[].factory_cost` | integer >= 0 |  |  |
| `races[].factories_operated` | integer >= 0 |  |  |
| `races[].mine_output` | integer >= 0 |  |  |
| `races[].mine_cost` | integer >= 0 |  |  |
| `races[].mines_operated` | integer >= 0 |  |  |
| `races[].research_costs` | list (at least 1) of integer 0 to 2 |  |  |
| `races[].leftover_points` | one of `surface_minerals`, `concentrations`, `mines`, `factories`, `defenses` |  |  |
| `races[].techs_start_at_3` | true / false |  |  |
| `races[].cheap_factories` | true / false |  |  |
| `races[].random` | true / false |  |  |

The base game defines 7. Example from `content/core`:

```json
{
  "type": "ai_personality",
  "id": "ai_personality.inactive",
  "order": 6,
  "brain": "idle"
}
```

### ai_research_plan

A classic personality's research order: steps of a tech field and a level.

| Field | Kind | Required | Notes |
|---|---|---|---|
| `steps` | list (at least 1) of objects (see below) | yes |  |
| `steps[].field` | id of a `tech_field` | yes |  |
| `steps[].level` | integer 0 to 31 | yes |  |

The base game defines 5.

### battle_board

The battle board (S16): its size and each side's starting square, by number of sides.

| Field | Kind | Required | Notes |
|---|---|---|---|
| `width` | integer >= 1 | yes |  |
| `height` | integer >= 1 | yes |  |
| `start_squares` | list (at least 1) of list (at least 1) of list (exactly 2) of integer >= 0 | yes |  |

The base game defines 1.

### battle_plan_default

A battle plan every player starts with (S16).

| Field | Kind | Required | Notes |
|---|---|---|---|
| `order` | integer >= 0 | yes |  |
| `tactic` | integer >= 0 | yes |  |
| `primary_target` | integer >= 0 | yes |  |
| `secondary_target` | integer >= 0 | yes |  |
| `attack` | integer >= 0 | yes |  |

The base game defines 5. Example from `content/core`:

```json
{
  "type": "battle_plan_default",
  "id": "battle_plan_default.standard",
  "order": 0,
  "tactic": 4,
  "primary_target": 3,
  "secondary_target": 1,
  "attack": 2
}
```

### constant

A named integer the rules read (see Rule constants below).

| Field | Kind | Required | Notes |
|---|---|---|---|
| `value` | integer | yes | The value. |

The base game defines 106. Example from `content/core`:

```json
{
  "type": "constant",
  "id": "constant.planet.starbase_population.orbital_fort",
  "value": 2500
}
```

### hull

A ship or starbase hull (S04).

| Field | Kind | Required | Notes |
|---|---|---|---|
| `starbase` | true / false |  | True for starbase hulls. |
| `tech` | map: id of a `tech_field` -> integer >= 0 |  | Minimum tech level per field to build it. |
| `mass` | integer >= 0 | yes | Mass in kT. |
| `cost` | object (see below) | yes |  |
| `cost.ironium` | integer >= 0 | yes |  |
| `cost.boranium` | integer >= 0 | yes |  |
| `cost.germanium` | integer >= 0 | yes |  |
| `cost.resources` | integer >= 0 | yes |  |
| `armor` | integer >= 0 | yes | Armor points. |
| `fuel` | integer >= 0 |  | Fuel capacity, mg. |
| `cargo` | integer >= 0 |  | Cargo capacity, kT. |
| `initiative` | integer >= 0 |  | Battle initiative. |
| `pictures` | integer >= 0 |  | The first of the hull's design pictures. |
| `rank` | integer >= 0 |  | Starbases: replacing a starbase by one of lower rank clears ship items from the queue (S09). |
| `dock` | integer >= -1 |  | Starbases: largest ship mass the dock can build (-1 any, 0 no dock). |
| `class` | integer 0 to 7 |  | The hull's class for battle-plan targets and reports: 0 colony, 1 freighter, 2 escort, 3 capital, 4 utility, 5 bomber, 6 miner, 7 fuel transport (S12, S16). |
| `stats` | map: lowercase dotted key -> integer |  | See Stats and tags below. |
| `slots` | list (at least 1) of objects (see below) | yes |  |
| `slots[].accepts` | list (at least 1) of one of `engine`, `scanner`, `shield`, `armor`, `beam`, `torpedo`, `bomb`, `mining_robot`, `mine_layer`, `orbital`, `planetary`, `electrical`, `mechanical`, `terraform` | yes | Part categories the slot takes. |
| `slots[].max` | integer >= 1 | yes | How many parts fit. |
| `slots[].required` | true / false |  | Accepted, but no rule reads it yet. |
| `slots[].at` | list (exactly 2) of integer >= 0 |  | Where the slot sits in the designer's hull picture: [x, y] in half-slot grid units. |
| `cargo_area` | list (exactly 4) of integer >= 0 |  | The cargo bay in the designer's hull picture: [x1, y1, x2, y2], half-slot grid units. |
| `mystery_trader` | true / false |  | Needs the Mystery Trader's item for this hull (Player.trader_parts). |
| `trader_bit` | integer >= 0 |  | Its bit in the Mystery Trader's items (S18). |
| `required_traits` | list of id of a `trait` |  | The race needs at least one of these. |
| `forbidden_traits` | list of id of a `trait` |  | The race may have none of these. |

The base game defines 37.

### message

A turn message type (S21); its wording is the string `<id>.text`.

| Field | Kind | Required | Notes |
|---|---|---|---|
| `params` | list of one of `number`, `own_design`, `minefield_type`, `minefield`, `space_object`, `colonists`, `amount`, `population`, `planet`, `fleet`, `fleet_designs`, `design`, `player`, `players`, `cargo`, `field`, `item`, `flag`, `axis`, `axis_value`, `object_kind`, `object`, `basis_points` | yes | One kind per parameter, in order (S21 "Parameter kinds"). |
| `ai` | true / false |  | Computer players get it too. |
| `filter_group` | text |  | Types with the same group are filtered together (S21 "Filters"). |
| `reveals_planet` | true / false |  | The planet the message is about becomes seen by its reader (S15). |

The base game defines 307. Example from `content/core`:

```json
{
  "type": "message",
  "id": "message.production.queue_empty",
  "params": [
    "planet"
  ]
}
```

### name_list

A list of names: planet names and race names (S07).

| Field | Kind | Required | Notes |
|---|---|---|---|
| `names` | list (at least 1) of text | yes | The names, in order. |

The base game defines 2. Example from `content/core`:

```json
{
  "type": "name_list",
  "id": "name_list.races",
  "names": [
    "Aldrani",
    "Bevrok",
    "Calistri",
    "Dorvane",
    "Elluvian",
    "Fenwari",
    "Galdric",
    "Hesperan",
    "Ismori",
    "Jovrel",
    "Kethari",
    "Lumarin",
    "Morvex",
    "Norrith",
    "Ostravi",
    "Pellune",
    "Quorani",
    "Rhodari",
    "Sylvane",
    "Tevrani",
    "Ulvaric",
    "Vexilli",
    "Wyrrani",
    "Zephiri"
  ]
}
```

### part

A ship or starbase part, or a planetary item (S04).

| Field | Kind | Required | Notes |
|---|---|---|---|
| `category` | one of `engine`, `scanner`, `shield`, `armor`, `beam`, `torpedo`, `bomb`, `mining_robot`, `mine_layer`, `orbital`, `planetary`, `electrical`, `mechanical`, `terraform` | yes | The kind of part, and which hull slots take it. |
| `tech` | map: id of a `tech_field` -> integer >= 0 |  | Minimum tech level per field to build it. |
| `mass` | integer >= 0 | yes | Mass in kT. |
| `cost` | object (see below) | yes |  |
| `cost.ironium` | integer >= 0 | yes |  |
| `cost.boranium` | integer >= 0 | yes |  |
| `cost.germanium` | integer >= 0 | yes |  |
| `cost.resources` | integer >= 0 | yes |  |
| `stats` | map: lowercase dotted key -> integer |  | See Stats and tags below. |
| `fuel_table` | list (exactly 11) of integer >= 0 |  | Engines: fuel use at warp 0 to 10. |
| `miniaturize` | true / false |  | False: its price never drops with tech (S09). |
| `required_traits` | list of id of a `trait` |  | The race needs at least one of these. |
| `forbidden_traits` | list of id of a `trait` |  | The race may have none of these. |
| `mystery_trader` | true / false |  | Needs the Mystery Trader's item for this part (Player.trader_parts). |
| `trader_bit` | integer >= 0 |  | Its bit in the Mystery Trader's items (S18). |

The base game defines 202. Example from `content/core`:

```json
{
  "type": "part",
  "id": "part.armor.tritanium",
  "category": "armor",
  "mass": 60,
  "cost": {
    "ironium": 5,
    "boranium": 0,
    "germanium": 0,
    "resources": 10
  },
  "stats": {
    "armor": 50
  }
}
```

### part_upgrade

Starting designs swap a part in `from` for the first candidate the player can use (S07).

| Field | Kind | Required | Notes |
|---|---|---|---|
| `from` | list (at least 1) of id of a `part` | yes | The parts to replace. |
| `candidates` | list (at least 1) of objects (see below) | yes | Replacements, best first; the first the player can use wins. |
| `candidates[].part` | id of a `part` | yes | The replacement part. |
| `candidates[].skip_on_hull` | id of a `hull` |  |  |
| `candidates[].unless_radiation_center_above` | integer |  |  |

The base game defines 8. Example from `content/core`:

```json
{
  "type": "part_upgrade",
  "id": "part_upgrade.engine",
  "from": [
    "part.engine.quick_jump_5"
  ],
  "candidates": [
    {
      "part": "part.engine.radiating_hydro_ram_scoop",
      "skip_on_hull": "hull.colony_ship",
      "unless_radiation_center_above": 84
    },
    {
      "part": "part.engine.daddy_long_legs_7"
    },
    {
      "part": "part.engine.fuel_mizer"
    },
    {
      "part": "part.engine.long_hump_6"
    }
  ]
}
```

### production_item

A standard production queue item that is not a ship or starbase (S09).

| Field | Kind | Required | Notes |
|---|---|---|---|
| `order` | integer >= 0 | yes | The item's number in the original's list. |
| `effect` | one of `mines`, `factories`, `defenses`, `alchemy`, `terraform`, `packet`, `genesis`, `scanner` | yes | What building it does. |
| `auto` | true / false |  | A standing (auto) item (S09). |
| `builds` | id of a `production_item` |  | Auto items: the plain item a partly built unit becomes. |
| `minimum` | true / false |  | Auto terraforming: only while still needed. |
| `best` | true / false |  | Scanner: the best one the owner can build. |
| `part` | id of a `part` |  | The part whose price it costs, or that it installs. |
| `mineral` | one of `ironium`, `boranium`, `germanium`, `mixed` |  | Packets: which mineral. |

The base game defines 27. Example from `content/core`:

```json
{
  "type": "production_item",
  "id": "production_item.auto_mines",
  "order": 0,
  "effect": "mines",
  "auto": true,
  "builds": "production_item.mines"
}
```

### race_preset

A ready-made race offered in the race wizard (S06); fields left out keep the default race's values.

| Field | Kind | Required | Notes |
|---|---|---|---|
| `primary_trait` | id of a `trait` | yes | The race's primary trait. |
| `lesser_traits` | list of id of a `trait` |  | The race's lesser traits. |
| `hab_low` | list (exactly 3) of integer -1 to 100 |  | Lowest habitable value per axis (gravity, temperature, radiation); -1 immune. |
| `hab_center` | list (exactly 3) of integer -1 to 100 |  | Centre of the habitable range per axis; -1 immune. |
| `hab_high` | list (exactly 3) of integer -1 to 100 |  | Highest habitable value per axis; -1 immune. |
| `growth_rate` | integer >= 0 |  | Maximum growth rate, percent. |
| `resources_per_colonist` | integer >= 0 |  |  |
| `factory_output` | integer >= 0 |  |  |
| `factory_cost` | integer >= 0 |  |  |
| `factories_operated` | integer >= 0 |  |  |
| `mine_output` | integer >= 0 |  |  |
| `mine_cost` | integer >= 0 |  |  |
| `mines_operated` | integer >= 0 |  |  |
| `research_costs` | list (at least 1) of integer 0 to 2 |  | Per field: 0 expensive, 1 normal, 2 cheap. |
| `leftover_points` | one of `surface_minerals`, `concentrations`, `mines`, `factories`, `defenses` |  | What unspent advantage points buy. |
| `techs_start_at_3` | true / false |  |  |
| `cheap_factories` | true / false |  |  |
| `random` | true / false |  |  |
| `order` | integer >= 0 | yes | Position in the wizard's list. |

The base game defines 7. Example from `content/core`:

```json
{
  "type": "race_preset",
  "id": "race_preset.default",
  "order": 0,
  "primary_trait": "trait.prt.JoaT"
}
```

### starting_design

A design template for starting fleets and starbases (S07).

| Field | Kind | Required | Notes |
|---|---|---|---|
| `hull` | id of a `hull` | yes | The design's hull. |
| `slots` | list of objects (see below) | yes | One entry per hull slot, in order; {} leaves a slot empty. |
| `slots[].part` | id of a `part` |  | The part. |
| `slots[].count` | integer >= 1 |  | How many. |
| `picture` | integer >= 0 |  | The design's picture. |

The base game defines 28. Example from `content/core`:

```json
{
  "type": "starting_design",
  "id": "starting_design.courier",
  "hull": "hull.small_freighter",
  "slots": [
    {
      "part": "part.engine.quick_jump_5",
      "count": 1
    },
    {
      "part": "part.scanner.bat_scanner",
      "count": 1
    },
    {
      "part": "part.shield.mole_skin_shield",
      "count": 1
    }
  ],
  "picture": 0
}
```

### starting_setup

What a trait changes about a player's start (S07); the game uses the primary trait's setup for `tech`, the homeworld and starbases, and adds the lesser traits' `tech_bonus` and `fleets`.

| Field | Kind | Required | Notes |
|---|---|---|---|
| `trait` | id of a `trait` | yes | The trait this setup belongs to. |
| `tech` | map: id of a `tech_field` -> integer >= 0 |  | Primary trait: starting tech level per field. |
| `tech_bonus` | map: id of a `tech_field` -> integer >= 0 |  | Lesser trait: tech levels added. |
| `tech_bonus_outside_tutorial` | map: id of a `tech_field` -> integer >= 0 |  | Lesser trait: tech levels added except in the tutorial. |
| `starbases` | list of objects (see below) |  | Starbase designs the player starts with. |
| `starbases[].slot` | integer >= 0 | yes | The starbase design slot. |
| `starbases[].design` | id of a `starting_design` | yes | The design template. |
| `starbases[].built` | true / false |  | False: the design exists but none is built. |
| `starbases[].min_universe_size` | integer >= 0 |  |  |
| `starbases[].outside_tutorial` | true / false |  |  |
| `starbases[].tutorial_only` | true / false |  |  |
| `homeworld_starbase` | integer >= 0 |  | The starbase design slot on the homeworld. |
| `homeworld_mass_driver_warp` | integer >= 0 |  | The homeworld mass driver's starting warp. |
| `homeworld_installations` | true / false |  | False: the homeworld starts with no mines, factories or defenses. |
| `homeworld_scanner` | true / false |  | False: the homeworld starts without a scanner. |
| `fleets` | list of objects (see below) |  | Starting fleets, each added when its conditions hold. |
| `fleets[].design` | id of a `starting_design` |  | The design template. |
| `fleets[].count` | integer >= 1 |  | How many fleets of it (default 1). |
| `fleets[].extra_planet` | true / false |  | Instead of a fleet: an extra colonized planet. |
| `fleets[].min_tech` | map: id of a `tech_field` -> integer >= 0 |  | Only with at least these tech levels. |
| `fleets[].below_tech` | map: id of a `tech_field` -> integer >= 0 |  | Only with tech levels below these. |
| `fleets[].human_only` | true / false |  | Only for human players. |
| `fleets[].forbidden_traits` | list of id of a `trait` |  | Not for races with any of these traits. |
| `fleets[].min_universe_size` | integer >= 0 |  | Only from this universe size up. |
| `fleets[].outside_tutorial` | true / false |  | Not in the tutorial. |
| `fleets[].tutorial_only` | true / false |  | Only in the tutorial. |

The base game defines 13. Example from `content/core`:

```json
{
  "type": "starting_setup",
  "id": "starting_setup.prt.HE",
  "trait": "trait.prt.HE",
  "starbases": [
    {
      "slot": 0,
      "design": "starting_design.citadel"
    }
  ],
  "fleets": [
    {
      "design": "starting_design.pathfinder"
    },
    {
      "design": "starting_design.seedling",
      "count": 3
    }
  ]
}
```

### tech_field

A research field (S05).

| Field | Kind | Required | Notes |
|---|---|---|---|
| `order` | integer >= 0 | yes | Position of the field (0 to 5 in the base game). |

The base game defines 6. Example from `content/core`:

```json
{
  "type": "tech_field",
  "id": "tech_field.energy",
  "order": 0
}
```

### trait

A primary or lesser racial trait (S06); see traits.md.

| Field | Kind | Required | Notes |
|---|---|---|---|
| `kind` | one of `primary`, `lesser` | yes | Primary or lesser. |
| `order` | integer >= 0 |  | Position among the traits of its kind (race wizard, random races). |
| `cost` | integer | yes | Advantage points used; negative gives points back. |
| `params` | map: lowercase dotted key -> integer |  | Trait parameters (traits.md). |
| `excludes` | list of id of a `trait` |  | Traits not to combine with this one (no rule checks it yet). |

The base game defines 24. Example from `content/core`:

```json
{
  "type": "trait",
  "id": "trait.prt.HE",
  "kind": "primary",
  "order": 0,
  "cost": 40,
  "params": {
    "race.growth_rate_pct": 200,
    "planet.max_pop_pct": 50,
    "race.ap_factory_growth_factor": 3
  }
}
```

### Message parameter kinds

The values of a `message` definition's `params` list:

| Kind | Notes |
|---|---|
| `number` |  |
| `own_design` | a design slot of the player who gets the message |
| `minefield_type` | a minefield type: 0 standard, 1 heavy, 2 speed bump |
| `minefield` | a minefield: its owner × 512 + its number |
| `space_object` | a minefield or a packet / salvage pile: kind × 8192 + owner × 512 + number |
| `colonists` | colonists in hundreds (one word) |
| `amount` |  |
| `population` |  |
| `planet` |  |
| `fleet` |  |
| `fleet_designs` |  |
| `design` |  |
| `player` |  |
| `players` | several players: a list of player indices (the original's one-bit-per-player word) |
| `cargo` |  |
| `field` |  |
| `item` |  |
| `flag` |  |
| `axis` |  |
| `axis_value` |  |
| `object_kind` |  |
| `object` |  |
| `basis_points` | hundredths of a percent |
<!-- END GENERATED: types -->

## Stats and tags

Parts and hulls carry most of their effects in `stats`, a map of name to integer. The schema
accepts any lowercase name there, so a mod can add a stat for its own rules. But a stat only has
an effect when some rule reads it. The tables below list the stats and tags the base game uses and
where the rules read them. Spec `specs/S04-parts-and-hulls.md` explains the units in more detail.

<!-- BEGIN GENERATED: stats -->
#### Part stats

| Stat | Meaning | Core parts with it | Read in |
|---|---|---|---|
| `accuracy` | Torpedo base accuracy, percent. | torpedo | `baseline_designs.gd`, `battle_engine.gd` |
| `armor` | Armor points added to the ship. | armor, mechanical, shield | `baseline_designs.gd`, `part_rules.gd`, `research_rules.gd`, `battle_replay.gd` and 2 more |
| `battle_move` | Whole steps added to the ship's battle movement. | electrical, mechanical | `battle_setup.gd` |
| `battle_move_halves` | Half steps of battle movement; n such parts add (n + 1) / 2. | engine, mining_robot | `battle_setup.gd` |
| `beam_damage_pct` | Capacitors: percent added to beam damage. | electrical | `battle_setup.gd`, `score.gd` |
| `beam_deflection` | Percent taken off incoming beam damage. | mechanical | `battle_setup.gd` |
| `cargo_capacity` | Cargo capacity added, kT. | mechanical | `baseline_designs.gd`, `part_rules.gd`, `player_view.gd` |
| `cloak` | Cloak units (S15 turns them into a percentage using ship mass). | armor, beam, electrical, engine, mechanical, mining_robot, scanner, shield | `cloaking.gd`, `report_view.gd` |
| `defense` | Planetary defense coverage value. | planetary | `defense_coverage.gd`, `production.gd`, `research_rules.gd`, `player_view.gd` |
| `driver_warp` | Mass driver: the warp it throws packets at. | orbital | `packets.gd`, `part_rules.gd`, `player_view.gd`, `report_view.gd` |
| `fuel_capacity` | Fuel capacity added, mg. | electrical, mechanical | `part_rules.gd`, `player_view.gd` |
| `fuel_generation` | Fuel made each year, mg. | electrical | `movement.gd`, `waypoint_warp.gd` |
| `gate_mass` | Stargate: the heaviest ship it can send, kT (-1: any). | orbital | `stargates.gd`, `report_view.gd` |
| `gate_range` | Stargate: how far it can send, ly (-1: any distance). | orbital | `stargates.gd`, `scanning.gd` |
| `initiative` | Battle initiative added. | beam, electrical, torpedo | `battle_engine.gd`, `battle_setup.gd`, `battle_replay.gd` |
| `installations` | Bombs: installations destroyed per bomb. | beam, bomb | `bombing.gd`, `score.gd` |
| `jamming` | Percent removed from enemy torpedo accuracy, applied once per part. | armor, electrical, mining_robot, shield | `battle_setup.gd`, `battle_replay.gd` |
| `kill_rate` | Bombs: population killed, tenths of a percent per bomb. | beam, bomb | `baseline_designs.gd`, `bombing.gd`, `score.gd` |
| `min_kill` | Bombs: minimum colonists killed per bomb. | beam, bomb, mechanical | `bombing.gd` |
| `mines_heavy` | Heavy mines laid per year. | mine_layer |  |
| `mines_speed_bump` | Speed bump mines laid per year. | mine_layer |  |
| `mines_standard` | Standard mines laid per year. | beam, mine_layer |  |
| `mining_rate` | Remote mining rate. | mining_robot | `waypoint_tasks.gd` |
| `pen_range` | Penetrating scanner range, ly. | planetary, scanner | `scanning.gd` |
| `power` | Weapon damage. | beam, torpedo | `baseline_designs.gd`, `battle_engine.gd`, `part_rules.gd`, `score.gd` |
| `range` | Weapon range, battle squares. | beam, torpedo | `baseline_designs.gd`, `battle_engine.gd`, `battle_setup.gd`, `movement.gd` and 3 more |
| `remote_terraform` | Remote terraforming per year. | mining_robot | `terraforming.gd` |
| `scan_range` | Normal scanner range, ly. | armor, beam, planetary, scanner, shield | `baseline_designs.gd`, `production.gd`, `research_rules.gd`, `player_view.gd` and 1 more |
| `shield` | Shield points added to the ship. | armor, shield | `baseline_designs.gd`, `part_rules.gd`, `research_rules.gd`, `design_view.gd` and 1 more |
| `terraform` | Terraforming reach, in environment units (S10). | terraform | `production.gd`, `production_costs.gd`, `research_rules.gd`, `terraforming.gd` |
| `torpedo_accuracy` | Battle computers: percent added to torpedo accuracy. | beam, electrical | `battle_setup.gd` |

#### Hull stats

| Stat | Meaning | Core hulls with it | Read in |
|---|---|---|---|
| `fuel_generation` | Fuel made each year, mg. | `hull.fuel_transport`, `hull.super_fuel_xport` | `movement.gd`, `waypoint_warp.gd` |
| `mine_laying_pct` | Hull: not read by any rule yet; the doubling comes from the hull tag `mine_layer`. | `hull.mini_mine_layer`, `hull.super_mine_layer` |  |
| `repair_bonus` | Hull: repair bonus to the fleet it travels with. | `hull.fuel_transport`, `hull.super_fuel_xport` | `repair.gd` |

#### Part tags

Tags starting with `ai_` are hints for the computer players only.

| Tag | Meaning | Core categories | Read in |
|---|---|---|---|
| `ai_earliest_engine` | Computer player hint. | engine | `classic_automitrons.gd`, `classic_rototills.gd` |
| `ai_scoopless_engine` | Computer player hint. | engine | `classic_automitrons.gd` |
| `ai_starter_engine` | Computer player hint. | engine | `classic_fleets.gd` |
| `ai_starting_scout_engine` | Computer player hint. | engine | `classic_rototills.gd` |
| `antimatter_generator` | Marks the fuel-making electrical part. | electrical |  |
| `capacitor` | Beam capacitor (stacks with other capacitors). | electrical | `score.gd` |
| `capital_missile` | Capital missile (S16). | torpedo |  |
| `colonizer` | Colonization module: the ship can colonize. | mechanical | `baseline_base.gd`, `baseline_designs.gd`, `waypoint_tasks.gd`, `waypoint_warp.gd` |
| `energy_dampener` | Slows every ship in the battle. | electrical | `battle_setup.gd` |
| `full_default_warp` | Engine whose default warp is not eased down to a nearby free speed (S15). | engine | `retargeting.gd` |
| `gatling` | Beam that hits every target in its square. | beam | `battle_engine.gd`, `part_rules.gd` |
| `genesis_device` | Genesis Device (S09). | planetary |  |
| `jump_gate` | Ship part that works like a stargate. | mechanical | `stargates.gd` |
| `lbu` | Bomb that only destroys installations. | bomb |  |
| `mass_driver` | Orbital part that throws mineral packets. | orbital |  |
| `normal` | Normal (population-killing) bomb. | bomb | `baseline_designs.gd`, `new_game.gd`, `game_settings.gd`, `bombing.gd` and 1 more |
| `orbital_adjuster` | Mining robot that terraforms remotely. | mining_robot |  |
| `orbital_construction` | Orbital construction module. | mechanical | `battle_setup.gd` |
| `penetrating` | Planetary scanner with a penetrating range. | planetary |  |
| `radiating` | Engine that kills some colonists in the cargo hold each year. | engine | `movement.gd` |
| `retro` | Retro bomb: undoes terraforming. | bomb | `bombing.gd` |
| `sapper` | Beam that only damages shields. | beam | `baseline_designs.gd`, `battle_engine.gd`, `part_rules.gd`, `score.gd` |
| `smart` | Smart bomb: its own kill rate and defense coverage (S17). | bomb | `baseline_designs.gd`, `bombing.gd` |
| `stargate` | Orbital stargate. | orbital |  |
| `steals_from_fleets` | Scanner that sees (and lets the owner steal) fleet cargo. | scanner | `scanning.gd` |
| `steals_from_planets` | Scanner that can also steal from planets. | scanner | `scanning.gd` |
| `tachyon_detector` | Lowers enemy cloaking. | electrical | `battle_setup.gd`, `cloaking.gd` |
| `terraform_basic` | Basic terraforming item. | terraform | `research_rules.gd` |
| `terraform_gravity` | Terraforms gravity. | terraform | `terraforming.gd` |
| `terraform_radiation` | Terraforms radiation. | terraform | `terraforming.gd` |
| `terraform_temperature` | Terraforms temperature. | terraform | `terraforming.gd` |
| `terraform_total` | Terraforms every axis. | terraform | `terraforming.gd` |
| `warp10_safe` | Engine takes no damage at warp 10. | engine | `baseline_designs.gd`, `battle_setup.gd`, `movement.gd`, `retargeting.gd` |

#### Hull tags

| Tag | Meaning | Core hulls | Read in |
|---|---|---|---|
| `builtin_scanner` | Hull has a small built-in scanner. | `hull.destroyer`, `hull.frigate`, `hull.scout` | `scanning.gd` |
| `fuel_transport` | Hull counts as a fuel transport. | `hull.fuel_transport`, `hull.super_fuel_xport` | `battle_setup.gd`, `fleet_orders.gd` |
| `mine_layer` | Hull doubles the mines its mine layers lay. | `hull.mini_mine_layer`, `hull.super_mine_layer` | `classic_automitrons.gd`, `classic_turindrones.gd`, `minefields.gd`, `research_rules.gd` |

"Read in" lists the `core/` files that contain the name as a quoted string. It is a text
search, so it can miss names the code builds (`"mines_" + type` reads the three `mines_`
stats; `cost.tag.<tag>_adjust_pct` prices parts by tag) and can list files that use the
same word for something else (`normal`). A stat or tag that no rule reads has no effect.
<!-- END GENERATED: stats -->

## Rule constants

Rule constants are `constant` definitions: a single integer each. The rules read them by id with
`ContentRegistry.constant(id)`. To change one, patch its `value`:

```json
{ "target": "constant.start.population", "set": { "value": 400 } }
```

Be careful with some of them. The `constant.limits.*` values are hard limits the rest of the
game is built around, and `constant.research.max_level` must match the number of
`constant.research.base_cost_<n>` constants.

Some trait parameters use the constant with the same name as their default (for example
`production.alchemy_cost` falls back to `constant.production.alchemy_cost`). See
[traits.md](traits.md).

<!-- BEGIN GENERATED: constants -->
| Id | Value | Meaning |
|---|---|---|
| `constant.planet.starbase_population.orbital_fort` | 2500 | Alternate Reality population at a orbital fort |
| `constant.planet.starbase_population.space_dock` | 5000 | Alternate Reality population at a space dock |
| `constant.planet.starbase_population.space_station` | 10000 | Alternate Reality population at a space station |
| `constant.planet.starbase_population.ultra_station` | 20000 | Alternate Reality population at a ultra station |
| `constant.planet.starbase_population.death_star` | 30000 | Alternate Reality population at a death star |
| `constant.battle.max_rounds` | 16 | Battle rounds |
| `constant.research.max_level` | 26 | Highest tech level |
| `constant.research.cost_per_level_sum` | 10 | Research: cost added per tech level owned |
| `constant.research.base_cost_1` | 50 | Research: base cost of level 1 |
| `constant.research.base_cost_2` | 80 | Research: base cost of level 2 |
| `constant.research.base_cost_3` | 130 | Research: base cost of level 3 |
| `constant.research.base_cost_4` | 210 | Research: base cost of level 4 |
| `constant.research.base_cost_5` | 340 | Research: base cost of level 5 |
| `constant.research.base_cost_6` | 550 | Research: base cost of level 6 |
| `constant.research.base_cost_7` | 890 | Research: base cost of level 7 |
| `constant.research.base_cost_8` | 1440 | Research: base cost of level 8 |
| `constant.research.base_cost_9` | 2330 | Research: base cost of level 9 |
| `constant.research.base_cost_10` | 3770 | Research: base cost of level 10 |
| `constant.research.base_cost_11` | 6100 | Research: base cost of level 11 |
| `constant.research.base_cost_12` | 9870 | Research: base cost of level 12 |
| `constant.research.base_cost_13` | 13850 | Research: base cost of level 13 |
| `constant.research.base_cost_14` | 18040 | Research: base cost of level 14 |
| `constant.research.base_cost_15` | 22440 | Research: base cost of level 15 |
| `constant.research.base_cost_16` | 27050 | Research: base cost of level 16 |
| `constant.research.base_cost_17` | 31870 | Research: base cost of level 17 |
| `constant.research.base_cost_18` | 36900 | Research: base cost of level 18 |
| `constant.research.base_cost_19` | 42140 | Research: base cost of level 19 |
| `constant.research.base_cost_20` | 47590 | Research: base cost of level 20 |
| `constant.research.base_cost_21` | 53250 | Research: base cost of level 21 |
| `constant.research.base_cost_22` | 59120 | Research: base cost of level 22 |
| `constant.research.base_cost_23` | 65200 | Research: base cost of level 23 |
| `constant.research.base_cost_24` | 71490 | Research: base cost of level 24 |
| `constant.research.base_cost_25` | 77990 | Research: base cost of level 25 |
| `constant.research.base_cost_26` | 84700 | Research: base cost of level 26 |
| `constant.limits.players` | 16 | Players |
| `constant.limits.fleets_per_player` | 512 | Fleets per player |
| `constant.limits.default_queue_items` | 12 | Items in the default production queue |
| `constant.limits.ship_designs` | 16 | Ship designs per player |
| `constant.limits.starbase_designs` | 10 | Starbase designs per player |
| `constant.limits.waypoints` | 87 | Waypoints per fleet |
| `constant.limits.ships_per_stack` | 32767 | Ships of one design in a fleet |
| `constant.limits.space_objects` | 4050 | Objects in space |
| `constant.limits.space_object_numbers` | 512 | Minefields, packets or other space objects per player |
| `constant.limits.battle_tokens` | 256 | Battle tokens |
| `constant.start.population` | 250 | Starting colonists (hundreds) |
| `constant.start.tech_floor` | 3 | Tech level of expensive fields with techs start at 3 |
| `constant.start.leftover_cap` | 50 | Most leftover advantage points spent at the start |
| `constant.race.growth_rate_min` | 1 | Race: minimum growth rate |
| `constant.race.growth_rate_max` | 20 | Race: maximum growth rate |
| `constant.race.resources_per_colonist_min` | 7 | Race: minimum colonists per resource |
| `constant.race.resources_per_colonist_max` | 25 | Race: maximum colonists per resource |
| `constant.race.factory_output_min` | 5 | Race: minimum factory output |
| `constant.race.factory_output_max` | 15 | Race: maximum factory output |
| `constant.race.factory_cost_min` | 5 | Race: minimum factory cost |
| `constant.race.factory_cost_max` | 25 | Race: maximum factory cost |
| `constant.race.factories_operated_min` | 5 | Race: minimum factories operated |
| `constant.race.factories_operated_max` | 25 | Race: maximum factories operated |
| `constant.race.mine_output_min` | 5 | Race: minimum mine output |
| `constant.race.mine_output_max` | 25 | Race: maximum mine output |
| `constant.race.mine_cost_min` | 2 | Race: minimum mine cost |
| `constant.race.mine_cost_max` | 15 | Race: maximum mine cost |
| `constant.race.mines_operated_min` | 5 | Race: minimum mines operated |
| `constant.race.mines_operated_max` | 25 | Race: maximum mines operated |
| `constant.universe.wormholes_random_0` | 3 | Random extra wormhole pairs, universe size 0 |
| `constant.universe.wormholes_base_0` | 0 | Fixed wormhole pairs, universe size 0 |
| `constant.universe.wormholes_random_1` | 3 | Random extra wormhole pairs, universe size 1 |
| `constant.universe.wormholes_base_1` | 1 | Fixed wormhole pairs, universe size 1 |
| `constant.universe.wormholes_random_2` | 5 | Random extra wormhole pairs, universe size 2 |
| `constant.universe.wormholes_base_2` | 1 | Fixed wormhole pairs, universe size 2 |
| `constant.universe.wormholes_random_3` | 4 | Random extra wormhole pairs, universe size 3 |
| `constant.universe.wormholes_base_3` | 3 | Fixed wormhole pairs, universe size 3 |
| `constant.universe.wormholes_random_4` | 5 | Random extra wormhole pairs, universe size 4 |
| `constant.universe.wormholes_base_4` | 4 | Fixed wormhole pairs, universe size 4 |
| `constant.production.factory_germanium` | 4 | Production: germanium per factory |
| `constant.production.alchemy_cost` | 100 | Production: resources per mineral alchemy |
| `constant.production.terraform_cost` | 100 | Production: resources per terraform step |
| `constant.production.packet_mineral_cost` | 110 | Production: mineral cost of a packet |
| `constant.production.mixed_packet_mineral_cost` | 44 | Production: mineral cost of a mixed packet, per mineral |
| `constant.production.packet_resource_cost` | 10 | Production: resource cost of a packet |
| `constant.production.packet_minerals` | 100 | Production: minerals carried by a packet |
| `constant.production.mixed_packet_minerals` | 40 | Production: minerals carried by a mixed packet, per mineral |
| `constant.production.miniaturization_per_level` | 4 | Production: miniaturization per tech level, percent |
| `constant.production.miniaturization_max` | 75 | Production: maximum miniaturization, percent |
| `constant.production.miniaturization_levels` | 19 | Production: tech levels that count for miniaturization |
| `constant.production.starbase_price_pct` | 50 | Production: starbase price, percent of the listed price |
| `constant.limits.queue_count` | 1023 | Limit: units in one queue item |
| `constant.terraform.permanent_chance` | 10 | Terraform: one in this many years a Claim Adjuster planet changes permanently |
| `constant.terraform.permanent_population` | 1000 | Terraform: population (units) that makes the permanent change certain |
| `constant.scanner.tachyon_cloak_pct_0` | 100 | Scanning: cloak left against 0 Tachyon Detectors (%) |
| `constant.scanner.tachyon_cloak_pct_1` | 95 | Scanning: cloak left against 1 Tachyon Detectors (%) |
| `constant.scanner.tachyon_cloak_pct_2` | 93 | Scanning: cloak left against 2 Tachyon Detectors (%) |
| `constant.scanner.tachyon_cloak_pct_3` | 91 | Scanning: cloak left against 3 Tachyon Detectors (%) |
| `constant.scanner.tachyon_cloak_pct_4` | 90 | Scanning: cloak left against 4 Tachyon Detectors (%) |
| `constant.scanner.tachyon_cloak_pct_5` | 89 | Scanning: cloak left against 5 Tachyon Detectors (%) |
| `constant.scanner.tachyon_cloak_pct_6` | 88 | Scanning: cloak left against 6 Tachyon Detectors (%) |
| `constant.scanner.tachyon_cloak_pct_7` | 87 | Scanning: cloak left against 7 Tachyon Detectors (%) |
| `constant.scanner.tachyon_cloak_pct_8` | 86 | Scanning: cloak left against 8 Tachyon Detectors (%) |
| `constant.scanner.tachyon_cloak_pct_9` | 86 | Scanning: cloak left against 9 Tachyon Detectors (%) |
| `constant.scanner.tachyon_cloak_pct_10` | 85 | Scanning: cloak left against 10 Tachyon Detectors (%) |
| `constant.scanner.tachyon_cloak_pct_11` | 84 | Scanning: cloak left against 11 Tachyon Detectors (%) |
| `constant.scanner.tachyon_cloak_pct_12` | 84 | Scanning: cloak left against 12 Tachyon Detectors (%) |
| `constant.scanner.tachyon_cloak_pct_13` | 83 | Scanning: cloak left against 13 Tachyon Detectors (%) |
| `constant.scanner.tachyon_cloak_pct_14` | 83 | Scanning: cloak left against 14 Tachyon Detectors (%) |
| `constant.scanner.tachyon_cloak_pct_15` | 82 | Scanning: cloak left against 15 Tachyon Detectors (%) |
| `constant.scanner.tachyon_cloak_pct_16` | 82 | Scanning: cloak left against 16 Tachyon Detectors (%) |
| `constant.scanner.tachyon_cloak_pct_17` | 81 | Scanning: cloak left against 17 Tachyon Detectors (%) |
<!-- END GENERATED: constants -->
