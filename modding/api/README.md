# API reference

Generated from the `##` doc comments in `core/` by `tools/gen_api_docs.py`. Do not edit these
pages by hand; change the doc comment and run the tool again.

**Status: experimental.** The mod API is version 1 (`ModLoader.API_VERSION`). There is no
separate `ModAPI` facade yet, so these pages list every public name in `core/`. Names that
start with `_` are internal and not listed. Anything here may still change before 1.0; the
classes most likely to stay are the ones listed first.

## Start here

| Class | File | Summary |
|---|---|---|
| [`ModManifest`](ModManifest.md) | `core/mod/mod_manifest.gd` | A mod's mod.json: identity, version, kind, dependencies and load-order hints (MODDING.md §2). |
| [`ModLoader`](ModLoader.md) | `core/mod/mod_loader.gd` | Reads mod manifests, works out the load order, and loads every mod's content into a fresh ContentRegistry (MODDING.md §2–4). |
| [`ModSource`](ModSource.md) | `core/mod/mod_source.gd` | Read access to one mod's files. |
| [`ContentRegistry`](ContentRegistry.md) | `core/content/content_registry.gd` | All content definitions of one game, keyed by type and string id. |
| [`ContentSchemas`](ContentSchemas.md) | `core/content/content_schemas.gd` | Schemas for every content definition type, and the validator that checks definitions against them. |
| [`Ruleset`](Ruleset.md) | `core/rules/ruleset.gd` | The game's replaceable formulas (MODDING.md §6): each is a Callable registered under an id. |
| [`StandardRuleset`](StandardRuleset.md) | `core/rules/standard_ruleset.gd` | The Standard formulas: 2.6i's rules with the known bugs fixed (S25). |
| [`TurnPipeline`](TurnPipeline.md) | `core/turn/turn_pipeline.gd` | The ordered phases of a turn (spec S02; MODDING §7). |
| [`Phase`](Phase.md) | `core/turn/phase.gd` | One step of turn generation (spec S02), identified by its id. |
| [`StandardTurn`](StandardTurn.md) | `core/turn/standard_turn.gd` | The Standard turn (spec S02): every phase in the original's order. |
| [`TurnContext`](TurnContext.md) | `core/turn/turn_context.gd` | What the phases of one turn work on: the game state, the content, and per-turn values that pass between phases. |
| [`RngStreams`](RngStreams.md) | `core/rng/rng_streams.gd` | The named random streams of one game (spec S01, "Our design: streams"). |
| [`StarsRandom`](StarsRandom.md) | `core/rng/stars_random.gd` | One random number stream: the combined generator of spec S01 (L'Ecuyer 1988). |
| [`RaceMath`](RaceMath.md) | `core/universe/race_math.gd` | Race wizard math (spec S06): habitability points and advantage points. |
| [`GameState`](GameState.md) | `core/model/game_state.gd` | The whole state of one game (spec S03): everything a turn reads and writes. |

## All classes, by folder

### `core/ai/`

| Class | Summary |
|---|---|
| [`AiBrains`](AiBrains.md) | The brains a personality can name (spec S22 "Personalities"): built into the game, by id, each with the settings a personality can give it (S22 "Personality settings"). |
| [`AiContext`](AiContext.md) | What a computer player works from (spec S22 "The AI step"): its view of the game, the content, the random stream it draws from, its personality and difficulty level. |
| [`AiPlayer`](AiPlayer.md) | A computer player's brain (spec S22): each turn `play` reads the context and gives the turn's orders through it. |
| [`BaselineAi`](BaselineAi.md) | Our own computer player (spec S22 "The baseline brain"): it grows an economy and spreads out. |
| [`BaselineBase`](BaselineBase.md) | What the baseline brain (BaselineAi, spec S22 "The baseline brain") works with: its constants, the turn's working state, and the helpers its decisions share (recognising its ships, distances and warps, planets with docks and people, design choices and quotas). |
| [`BaselineDesigns`](BaselineDesigns.md) | The baseline brain's ship designs (spec S22 "The baseline brain"): a scout (scout hull, the engine that goes furthest, the longest-range scanner, a fuel tank) and a colony ship (colony ship hull, that engine, a colonizer module); a dock (the cheapest starbase hull that docks and refuels ships, bare); a warship (the most advanced combat hull, every weapon slot with the strongest weapon, armor slots with the best armor, shield-only slots with the best shield, compared by `strength`); a bomber (the most advanced bomber hull, every bomb slot with the bomb that kills the most people, compared by `bomb_power`); a troop transport (the largest freighter hull, the best cargo pods, compared by cargo room) and a mineral hauler (the same ship under another name). |
| [`ClassicBrain`](ClassicBrain.md) | A brain playing one of the original's personalities (spec S22 "The classic world"): it builds the player's classic world from its view, lets the personality play on it, and gives the orders the personality gave, ending with the working memory for the next turn. |
| [`ComputerPlayers`](ComputerPlayers.md) | The AI step (spec S22 "The AI step"): before a turn is generated, every computer player still in the game that has no orders of its own makes them, in player order, drawing from the classic stream; so does every inactive human player, with the INACTIVE personality (housekeeping only). |

### `core/ai/classic/`

| Class | Summary |
|---|---|
| [`ClassicAutomitrons`](ClassicAutomitrons.md) | The original's Automitrons (spec S22 "Automitrons", `AI_Automitrons`): research by plan, designs by tech level (`AI_Automitrons_Designs`), freighters, colony ships, mine layers, bombers, warships and battleships built at big starbase planets, colony ships on freighter hulls settling, bombers going from planet to planet once escorted, and scouts hunting or exploring (`AI_DirectFleet`). |
| [`ClassicCybertrons`](ClassicCybertrons.md) | The original's Cybertrons (spec S22 "Cybertrons", `AI_Cybertrons`): research by plan, designs drawn from template pools (`AI_Cybertrons_Designs`), warship groups gathering and invading (`AI_Cybertrons_Invade`), colonist transports filling small colonies (`AI_Cybertrons_ColonistTransport`), mine-laying scouts, production by planet (`AI_Cybertrons_Economy`) and mineral packets thrown at their own planets and at others' (`AI_Cybertrons_PlanPackets`). |
| [`ClassicCybertronsPackets`](ClassicCybertronsPackets.md) | Cybertrons' mineral packets (spec S22 "Cybertrons", packets; `AI_Cybertrons_PlanPackets`): each starbase planet feeds a short planet near by, throws packets at another player's planet, or throws one toward a map sector (`AI_ChoosePacketTarget`). |
| [`ClassicDesigns`](ClassicDesigns.md) | How the classic personalities make and retire designs (spec S22 "Classic designs"): a design from a template (a hull and a part class per slot, each slot filled with the best part of its class the player can use, as many as the slot holds), a picture and a name drawn from the hull's name list, and the starbase designs every classic personality keeps up to date. |
| [`ClassicFleets`](ClassicFleets.md) | How the classic personalities move their fleets (spec S22 "Classic fleets"): what a fleet is, new orders (`AI_AddWaypoint` and its callers), merging and splitting, safe speeds in minefields, warships' targets (`AI_DirectWarship`) and colony ships' (`AI_RateColonyTargets`). |
| [`ClassicFreight`](ClassicFreight.md) | The classic personalities' cargo (spec S22 "Classic freight"): moving cargo, how many colony ships to keep (`AI_CountColonyShips`), freighter runs (`AI_PlanTransport`, `AI_PickUpSalvage`) and the freighter depots kept in the memory (`AI_PlanFreighterDepots`). |
| [`ClassicMacinti`](ClassicMacinti.md) | The original's Macinti (spec S22 "Macinti", `AI_Macinti`): research by plan, designs by tech and turn (`AI_Macinti_Designs`), starbase designs reviewed by age (`AI_Macinti_ReviewDesigns`), production by planet (packets between rich planets, colony ships, miners, scouts, bombers, warships, nubians, genesis devices), miners moving to rich planets, freighters moving people (`AI_Macinti_MovePopulation`), warships invading (`AI_Macinti_Invade`) or hunting. |
| [`ClassicMacintiFleets`](ClassicMacintiFleets.md) | Macinti's fleets (spec S22 "Macinti", fleets): colony ships settling, miners mining and moving to rich planets (`AI_Macinti_MoveToRichPlanet`), scouts laying mines, freighters moving people and minerals (`AI_Macinti_MovePopulation`), and warships invading (`AI_Macinti_Invade`) or hunting. |
| [`ClassicMacintiProduction`](ClassicMacintiProduction.md) | Macinti's production pass (spec S22 "Macinti", production): each of the player's starbase planets with 200 hundred people throws packets to a poorer driver planet, or queues freighters, colony ships, miners, scouts, bombers, warships, genesis devices and nubians. |
| [`ClassicPlanning`](ClassicPlanning.md) | The production every classic personality plans each turn (spec S22 "Classic production"): the pass over its planets after the fleets have their orders (`AI_ManageProduction`), with starbases, ships, packets, defenses and terraforming, the late-game defenses, the mines put ahead of a waiting item (`AI_FixupMineOrders`), and the last pass that fills each queue with factories and mines (`AI_FinishTurn`, `AI_FillPlanetQueue`). |
| [`ClassicProduction`](ClassicProduction.md) | How the classic personalities edit production (spec S22 "Classic production"): what the selected planet can build (`BuildProductionList`), queue edits committed as one order (`AI_QueueProduction`, `CommitProductionQueue`), and the estimates their choices rest on (`AI_EstimatePlanetOutput`, `AI_EstimateQueueCost`, `Production_SimulateQueue`). |
| [`ClassicResearch`](ClassicResearch.md) | How the classic personalities choose research (spec S22 "Classic research", `AI_RunResearchPlan`): a plan of steps (a tech field and a level), followed in order. |
| [`ClassicRobotoids`](ClassicRobotoids.md) | The original's Robotoids (spec S22 "Robotoids", `AI_Robotoids`): research by plan, warships and bombers kept in design slots by tech level (`AI_Robotoids_Designs`), ships built at starbases by what the planet can spare, colony ships, freighter runs, and fleets of warships and bombers gathering at home before they set out to invade (`AI_Robotoids_Invade`). |
| [`ClassicRototills`](ClassicRototills.md) | The original's Rototills (spec S22 "Rototills", `AI_Rototills`): no designs of their own and no research plan (the lowest field), colony ships built at big starbase planets one a turn, colony ships settling (through wormholes too), freighter runs, miners moving to rich planets, bombers going from planet to planet, and scouts hunting or exploring (`AI_DirectFleet`). |
| [`ClassicTurindrones`](ClassicTurindrones.md) | The original's Turindrones (spec S22 "Turindrones", `AI_Turindrones`): research by plan, designs by tech level (`AI_Turindrones_Designs`), scouts, colony ships, freighters, miners and mine layers built at starbase planets, warships and battleships by what the planet can spare, warships hunting or exploring (`AI_DirectFleet`), bombers going from planet to planet, colony ships dropping people on other players' undefended planets, and miners moving to rich planets. |
| [`ClassicWorld`](ClassicWorld.md) | The game as one of the original's computer players has it loaded (spec S22 "The classic world"): a copy of the state in which the player's own planets, fleets and designs are as they are, other players' and unowned planets are as its planet history knows them (S15), and other players' fleets and designs are there only as far as it has seen them. |

### `core/battle/`

| Class | Summary |
|---|---|
| [`ArmorDamage`](ArmorDamage.md) | Armor damage in battle, Standard (spec S16 "Damage", fix B09): within a battle a token keeps the exact damage of its damaged ships, so a hit adds only what it did; the stack's damage word (in 1/500 of the armor) is derived from it, rounded to nearest, after each hit. |
| [`BattleEngine`](BattleEngine.md) | One battle, round by round (spec S16 "Rounds", "Movement", "Firing", "Damage"): tokens move and fire, damage lands on the fleets and starbase as it happens, and every move and shot is recorded (S16 "The recording"). |
| [`BattleSetup`](BattleSetup.md) | Who fights and how battles start (spec S16 "Who fights", "Tokens"): fleets grouped by place, each group's sides, then the battle's tokens on their starting squares, shuffled. |
| [`Battles`](Battles.md) | The turn's battles (spec S16): at the start of the waypoint 1 step, every place where hostile fleets meet fights a battle in turn; each is recorded in `state.battles`, then its results follow (S16 "Battle results"): the messages, the tech bonus tries, an Alternate Reality planet emptied by the loss of its starbase, and the "fought this turn" marks. |

### `core/content/`

| Class | Summary |
|---|---|
| [`ContentError`](ContentError.md) | One problem found while loading mods or content: which mod, which file, which line, and what. |
| [`ContentRegistry`](ContentRegistry.md) | All content definitions of one game, keyed by type and string id. |
| [`ContentSchemas`](ContentSchemas.md) | Schemas for every content definition type, and the validator that checks definitions against them. |
| [`JsonReader`](JsonReader.md) | Strict JSON reader for content files. |

### `core/context/`

| Class | Summary |
|---|---|
| [`GameContext`](GameContext.md) | Everything one game needs to run its rules: content, ruleset, RNG streams and hooks. |

### `core/game/`

| Class | Summary |
|---|---|
| [`NewGame`](NewGame.md) | Creates a game for the UI (spec S07 through UniverseGenerator): the human player with the given race, then the other players chosen (computer players, and more humans for hotseat, S27), in a universe of the given size, density and player spacing. |

### `core/io/`

| Class | Summary |
|---|---|
| [`FolderModSource`](FolderModSource.md) | A mod in a folder (res://content/<id>, user://mods/<id>, or res://tests/... |
| [`ModValidator`](ModValidator.md) | The mod validator's checks (plan M14; MODDING.md §13; the command line is tools/validate_mod.gd): a mod folder's manifest; the game's core loaded with the mod (and the mods it needs), as the game would, so every content, patch, string and script problem comes with its file and line; the mod's scripts against the determinism rules (MODDING.md §8); and a list of what the mod adds or changes. |
| [`OrderFile`](OrderFile.md) | Our order file format (spec S11, "Order files"): one player's orders for one turn, as a JSON object with a header, in canonical form. |
| [`OrderSubmission`](OrderSubmission.md) | A player's orders sent to a play-by-email host (spec S27 "Play by email"): the orders for one year of one game, with an integrity checksum like the turn file's (TurnFile.checksum), so a file damaged on its way, or meant for another game, player or year, is refused. |
| [`PbemHost`](PbemHost.md) | The play-by-email host (spec S27 "Play by email"): a game kept in a folder, turned by the host player when every human player's orders are in. |
| [`PersonalityFile`](PersonalityFile.md) | A computer player's personality as the player keeps it (spec S22 "The personality editor"): a name, the brain that plays it, the brain's settings, and per difficulty level the settings that level changes, and whose built-in races it plays (one of the original's personalities, ComputerPlayers.race_for), in the same shape a game keeps (`Player.ai_personality`). |
| [`RaceFile`](RaceFile.md) | Our race file format (spec S06, "Race files and presets"): a JSON object with a header and one race, in canonical form. |
| [`SaveFile`](SaveFile.md) | Our save format (spec S03, "Saved form"): a JSON object with a header and the game state. |
| [`SaveStore`](SaveStore.md) | Reads and writes save files (format in SaveFile). |
| [`TurnFile`](TurnFile.md) | A player's turn file for play by email (spec S27 "Play by email"): the game as that player knows it, with an integrity checksum. |

### `core/mod/`

| Class | Summary |
|---|---|
| [`MemoryModSource`](MemoryModSource.md) | A mod held in memory: mod-relative path -> file text. |
| [`ModApi`](ModApi.md) | What a script mod's entry script gets while the mods load (MODDING.md §6, §7): `_mod_init(api)` may replace or add formulas and change the turn's phases. |
| [`ModLoader`](ModLoader.md) | Reads mod manifests, works out the load order, and loads every mod's content into a fresh ContentRegistry (MODDING.md §2–4). |
| [`ModManifest`](ModManifest.md) | A mod's mod.json: identity, version, kind, dependencies and load-order hints (MODDING.md §2). |
| [`ModSource`](ModSource.md) | Read access to one mod's files. |
| [`SemVer`](SemVer.md) | Version numbers ("1.2.0") and version constraints (">=1.0 <2.0") for mod manifests. |

### `core/model/`

| Class | Summary |
|---|---|
| [`Design`](Design.md) | A ship or starbase design (spec S03). |
| [`DesignSlot`](DesignSlot.md) | What one hull slot of a design holds: a part content id ("" = empty) and how many. |
| [`Fleet`](Fleet.md) | A fleet (S03). |
| [`GameSettings`](GameSettings.md) | Universe and rule options of one game (S03; generation inputs S07, victory S20). |
| [`GameState`](GameState.md) | The whole state of one game (spec S03): everything a turn reads and writes. |
| [`Minefield`](Minefield.md) | A minefield (S03, S13). |
| [`ModelObject`](ModelObject.md) | Base class of the game state entities (spec S03). |
| [`OrderSet`](OrderSet.md) | One player's orders for one turn (spec S11): a list of orders, each a Dictionary with a "type" and that type's fields, applied in list order. |
| [`Packet`](Packet.md) | A mineral packet or a pile of salvage (S03, S14). |
| [`Planet`](Planet.md) | A planet (spec S03, economy fields S08). |
| [`Player`](Player.md) | One player (spec S03): the race plus the player's state in this game. |
| [`QueueItem`](QueueItem.md) | One entry of a planet's production queue (spec S09): a standard item (content id of a `production_item`) or a design (ship or starbase slot), how many, and the progress of the first unit in percent of its cost. |
| [`Race`](Race.md) | A race definition (spec S06). |
| [`ShipStack`](ShipStack.md) | The ships of one design in a fleet (S03). |
| [`Starbase`](Starbase.md) | The starbase orbiting a planet (S03): the owner's starbase design slot and its damage. |
| [`StateDiff`](StateDiff.md) | Field-by-field comparison of two game states (used by the golden-turn runner, M4, and by PBEM consistency checks). |
| [`StateValidator`](StateValidator.md) | Checks a loaded game state against the content it is played with (spec S03, "Saved form"): value ranges, references between objects, references to content, and the limits. |
| [`Trader`](Trader.md) | The Mystery Trader's ship (S03, S18). |
| [`Waypoint`](Waypoint.md) | One waypoint of a fleet (S03, S11, S12). |
| [`Wormhole`](Wormhole.md) | One end of a wormhole (S03; movement S12, events S18). |

### `core/rng/`

| Class | Summary |
|---|---|
| [`RngStreams`](RngStreams.md) | The named random streams of one game (spec S01, "Our design: streams"). |
| [`StarsRandom`](StarsRandom.md) | One random number stream: the combined generator of spec S01 (L'Ecuyer 1988). |

### `core/rules/`

| Class | Summary |
|---|---|
| [`BattlePlans`](BattlePlans.md) | Battle plans (S11 `battle_plan` orders, S16): whom a fleet's plan attacks. |
| [`Bombing`](Bombing.md) | Bombing (spec S17, `DoBombing@10e8:6e2a`), right after the battles of the waypoint 1 step (S02): a player's fleets orbiting another player's planet without a starbase, when one of them has a battle plan that attacks that player, drop their bombs together. |
| [`Cloaking`](Cloaking.md) | Cloaking (spec S15 "Cloaking"): a fleet's and a starbase's cloak percent, and how a scanner's reach shrinks against them. |
| [`DefenseCoverage`](DefenseCoverage.md) | What a planet's defenses let through (`Planet_DefenseCoverage@1030:0262`, S17): the share of bombs (and packet damage, S14) that gets past n operable defenses of the best defense the owner has, (1 - value × 0.001)^n, or (1 - value × 0.0005)^n against smart bombs, kept as a 32-bit float like the original. |
| [`FleetOrders`](FleetOrders.md) | Fleet orders (spec S11 "Fleet orders"): splitting a fleet, moving ships between fleets with their cargo, fuel and damage, merging fleets, and deleting a fleet (waypoints that target it are retargeted). |
| [`FleetTargets`](FleetTargets.md) | Waypoints that target fleets (spec S12 "Waypoint targets", "Following a fleet"): the start of the turn (S02 phase 4) sets up following fleets and retargets waypoints whose fleet is gone or moved; phase 21 retargets again. |
| [`GroundCombat`](GroundCombat.md) | Ground combat (spec S17 "Ground combat", `ResolveGroundCombat@10b0:1e82`): colonists landed on planets during a task pass, or dropped by hand with the orders, are recorded per fleet and planet, then each planet is colonized or fought for, between the task passes of each pair (S02 5c and 16d). |
| [`Habitability`](Habitability.md) | How habitable a planet environment is for a race (spec S06, "Planet value for a race"; used by S08 and by the advantage points). |
| [`Minefields`](Minefields.md) | Minefields (spec S13, laying S11): laying mines, the yearly decay and the start-of-turn reset. |
| [`Movement`](Movement.md) | Fleet movement and fuel (spec S12): fuel use, the move toward the next waypoint, ram scoops, waypoints after movement, and refueling. |
| [`MysteryTrader`](MysteryTrader.md) | The Mystery Trader (spec S18): its arrival (a random event, `RandomEvent_MysteryTrader`), its movement in phase 8 (`MoveSpaceObjects`) and its meetings with fleets and planets in the waypoint 1 step (`DoMysteryTrader@1100:0784`). |
| [`Packets`](Packets.md) | Mineral packets and salvage (spec S14): launching packets from a mass driver, their flight, decay and impact, and dropping salvage, with its yearly decay. |
| [`PartRules`](PartRules.md) | Which parts and hulls a player can use, and simple design totals (spec S04, S06). |
| [`PlanetEconomy`](PlanetEconomy.md) | How a planet supports its owner (spec S08): maximum population, growth, installations, resources and mining. |
| [`PlanetEstimates`](PlanetEstimates.md) | What other players see of a planet's population and defenses (spec S15 "Estimates"; `UpdatePlanetEstimates@10b0:31da`, S02 phase 22): each populated planet's population give or take an eighth, in units of 400 colonists, and a 1-15 class for how much of a bombing its defenses stop. |
| [`Production`](Production.md) | Each planet's production for the year (spec S09 steps 3-6): research share, the queue, and what completed units do. |
| [`ProductionCosts`](ProductionCosts.md) | What production items cost a player (spec S09 steps 1-2b). |
| [`ProductionTemplates`](ProductionTemplates.md) | Production templates (S09 "Production templates"; the original's `ZIPPRODDLG@10c8:2d26` and the production window's template menu): the default queue for new colonies plus up to three of the player's own, each a list of auto-build items and a "contribute only leftover resources to research" setting. |
| [`RandomEvents`](RandomEvents.md) | Random events (spec S18), right after the production step's tech update unless random events are off (`DoRandomEvents@10b0:1c1a`): a comet strike, an environment change, a mineral deposit and a Mystery Trader's arrival, in that order. |
| [`Repair`](Repair.md) | Repair of ships and starbases, and colonists growing in Inner-Strength fleets (spec S19). |
| [`ResearchRules`](ResearchRules.md) | Research costs and the yearly tech update (spec S05). |
| [`Routes`](Routes.md) | Routes and default orders (spec S11 "Route"): a fleet idle at a planet with a route, or newly built there (S09), gets a waypoint at the route's destination; other idle fleets with mining robots get the remote mining or merge task. |
| [`Ruleset`](Ruleset.md) | The game's replaceable formulas (MODDING.md §6): each is a Callable registered under an id. |
| [`Score`](Score.md) | Scores, ranks, elimination and victory (spec S20), each turn right after the year advances (`UpdateScoresAndVictory@10b0:3b78`). |
| [`StandardRuleset`](StandardRuleset.md) | The Standard formulas: 2.6i's rules with the known bugs fixed (S25). |
| [`Stargates`](Stargates.md) | Stargate travel (spec S12 "Stargates"): a fleet whose next waypoint has warp 11 jumps from a stargate (or with Jump Gates on every ship) to a planet with a stargate; designs beyond the gates' limits are damaged or lost. |
| [`TechGain`](TechGain.md) | Tech gained from other players' ships (spec S24, partial): the bonus a planet owner may get when ships are scrapped at its starbase. |
| [`Terraforming`](Terraforming.md) | Terraforming (spec S10): reach from tech, targets toward or away from a race's ideal, single steps, the Claim Adjuster's yearly terraforming and remote terraforming by fleets. |
| [`WaypointTasks`](WaypointTasks.md) | Waypoint tasks (spec S11): the four task passes, and resolving colonization (S17). |
| [`WaypointWarp`](WaypointWarp.md) | The warp a waypoint gets by default (spec S12 "Default warp", `Waypoint_DefaultWarp@1050:5650`) and the fuel a fleet needs to reach a waypoint (`Waypoint_FuelNeeded@1048:6948`). |
| [`Wormholes`](Wormholes.md) | Wormhole placement and the yearly shift (specs S07 step 12.3, S12 "Wormholes shift"). |

### `core/turn/`

| Class | Summary |
|---|---|
| [`OrderRules`](OrderRules.md) | Validates and applies players' orders (spec S11 "Orders"): players in index order, each player's orders in list order, each checked against the state at that moment. |
| [`Phase`](Phase.md) | One step of turn generation (spec S02), identified by its id. |
| [`StandardTurn`](StandardTurn.md) | The Standard turn (spec S02): every phase in the original's order. |
| [`TurnContext`](TurnContext.md) | What the phases of one turn work on: the game state, the content, and per-turn values that pass between phases. |
| [`TurnMessages`](TurnMessages.md) | The players' turn messages (spec S21): `state.messages` holds one list per player, each message {type, goto, params}: a `message` content id, what its Goto shows (S21 "Goto codes") and its parameters, in the order the rules send them. |
| [`TurnPipeline`](TurnPipeline.md) | The ordered phases of a turn (spec S02; MODDING §7). |

### `core/turn/phases/`

| Class | Summary |
|---|---|
| [`EconomyPhases`](EconomyPhases.md) | The production phase's steps (spec S02 13a-13e): mining, planet production, population growth, the tech update and random events. |
| [`FleetPhases`](FleetPhases.md) | Fleet phases (spec S02 5, 9, 15, 16). |
| [`OrderPhases`](OrderPhases.md) | Order phases (spec S02 2). |
| [`PlanetPhases`](PlanetPhases.md) | Planet phases after the waypoint-1 tasks (spec S02 19, 20). |
| [`SpacePhases`](SpacePhases.md) | Space object phases (spec S02 7, 8, 11, 14, 17). |
| [`TurnEndPhases`](TurnEndPhases.md) | Phases at the end of a turn (spec S02 22, 23, 24, 26, 27). |

### `core/universe/`

| Class | Summary |
|---|---|
| [`RaceEditing`](RaceEditing.md) | The race wizard's habitability edits and its "1 in N planets" figure (M11 step 9; S06 "The race wizard"; the original's `Environment_OnMouse@10d8:1806`, `Environment_Paint`). |
| [`RaceMath`](RaceMath.md) | Race wizard math (spec S06): habitability points and advantage points. |
| [`RacePresets`](RacePresets.md) | The race wizard's presets (content type `race_preset`, spec S06 "Race files and presets"). |
| [`RandomRace`](RandomRace.md) | Rolls a race with the "random" setting anew at game creation (spec S06 "Random races"), drawing from the classic stream in the original's order. |
| [`StartingSetup`](StartingSetup.md) | S07 steps 9.5-12 for a universe made by UniverseGenerator: starting tech, homeworlds, starbase and ship designs, starting fleets, the extra planet, battle plans, wormholes and relations. |
| [`UniverseGenerator`](UniverseGenerator.md) | Creates a new game (spec S07), drawing from the classic stream in exactly the original's order, so the same seed and settings give the same universe. |

### `core/view/`

| Class | Summary |
|---|---|
| [`BattleReplay`](BattleReplay.md) | A battle record (S16 "The recording") as the battle viewer plays it back (M11 step 8; the original's `VCR_SeekTo@10e0:053e`, `VCR_TokenStatus@10e0:0f74`), plus the Battle Summary report's counts (`Battle_CountShips@10e0:02aa`, `Battle_CountLosses@10e0:03b8`). |
| [`DesignView`](DesignView.md) | What the ship designer (M11 step 5) asks of a player's view: their designs, the hulls and parts they can use, and a design's totals. |
| [`EnvironmentUnits`](EnvironmentUnits.md) | How the game shows environment values (spec S06 "Display units"): gravity in g, temperature in degrees C, radiation in mR, from the 0..100 scale every rule uses. |
| [`MessageText`](MessageText.md) | A turn message (S21) as text for the Messages pane: the type's wording from the language file with each `{n}` replaced by parameter n written out by its kind. |
| [`OrderPreview`](OrderPreview.md) | What the player's pending orders do (M11 UI): a copy of the state with the orders applied by the same OrderRules the turn generator uses, so the UI shows exactly what the next turn will start from. |
| [`PlayerView`](PlayerView.md) | What one player sees of a game (M11 UI): read-only summaries built from a state (normally the order preview) for the map and the panes. |
| [`ProductionEstimate`](ProductionEstimate.md) | When a planet's queue items will be built (M11, the Production tile's colours and Completion line, the Production window's completion years): the planet's production (S09) is run year by year on a copy, with mining and population growth after each year (as the original's estimate does), and each queue item is followed until it is done. |
| [`ReportView`](ReportView.md) | The report tables (M11 step 7; the original's `REPORTDLG@10f8:0000`): one row per own planet, own fleet, other player's fleet or battle, with the values each column shows, and the original's sort (`Report_SortRows@10f8:3bb2` and its comparator): by one column, forward or reverse, then by the column sorted before it; the order also sets the Command pane's Prev / Next order. |
| [`ScoreView`](ScoreView.md) | The score report's data (M11 step 7; S20 "What a player sees"): the score table, the victory conditions and the history graph's lines, from the players' score records the viewer may see: its own, and everyone's in a game with public scores once the turn is above 19. |

### `core/visibility/`

| Class | Summary |
|---|---|
| [`PlanetHistory`](PlanetHistory.md) | What each player remembers of the planets (spec S15 "Planet history"; the original's history file, `DecodePlanetBlock@1068:1f0c` merging the turn file into it, `WritePlanetDataBlock`): after each turn's scanning, every planet the player owns or saw this turn updates the player's record of it in `Player.knowledge["planets"]`, keyed by planet id: - always: `turn` (the year index it was last seen), `owner`, `homeworld`, `starbase_design`   (-1 none or hidden), and `detail`, the best detail it was ever seen at (1 or SCANNED); - when scanned this turn: `environment`, `environment_original`, `concentration`,   `concentration_fraction`, and, when owned, `population_estimate` and `defense_estimate`. |
| [`Retargeting`](Retargeting.md) | Orders changed by sight (spec S15 "Orders changed by sight"; `WriteGameFile@1068:35b0`): right after a player's scanning, patrolling fleets pick a target, and waypoints aimed at what the player no longer sees lose their target. |
| [`Scanning`](Scanning.md) | Scanner ranges, and what the end-of-turn scanning records (spec S15): which players know and saw each minefield, which track each wormhole, and each player's view of the turn: the other players' planets, fleets and designs seen and at what detail, the players met, and the packets, wormholes and traders in view. |
