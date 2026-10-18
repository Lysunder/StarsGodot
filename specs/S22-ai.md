# S22 Computer players (AI)

Status: draft (2026-10-14), first part: the AI step and personalities as data; second part: our own baseline
brain (2026-10-15: expansion, docks, terraforming, defenses, warships, bombers, defending, invasion, mineral
hauling); third part (2026-10-15, started): the original's personalities, beginning with the world they play in, the toolkit
they share and (2026-10-16) Robotoids. The other personalities come in later parts.
References: `RunComputerPlayers@1018:39f8`, `AI_PlayTurn@1080:0000`, `AI_InactiveHuman@1090:0000`,
`Designs_ComputeRatings@1030:09ae`, `AI_ScanFleets@1088:40ba`, `AI_InitScale@1088:5e0e`,
`AI_BuildOwnPlanetList@1088:60b2`, `DecodePlanetBlock@1068:1f0c`,
`CheckTurnFile` (turn file check before a computer player plays), personalities `AI_Robotoids`, `AI_Turindrones`,
`AI_Automitrons`, `AI_Rototills`, `AI_Cybertrons`, `AI_Macinti` (segments 1080-10a0), toolkit in segment 1088;
Robotoids: `AI_Robotoids@1080:0462`, `AI_Robotoids_Designs@1080:1730`, `AI_Robotoids_Invade@1080:1b70`,
`AI_Robotoids_HasEscortStrength@1080:20f4`, `AI_ScoreColonyTarget@1080:2252`, `AI_ScoreColonyTarget2@1080:216c`,
`Pred_NotMyPlanet@1080:2154`, `Pred_MyPlanetWithStarbase@1088:3be2`.

## Summary

Computer players are ordinary players whose orders are made by the game instead of a person. Just before a turn is
generated, each one reads its own view of the game and gives the same kinds of orders a human gives (S11). Nothing
about them is special after that: their orders are checked and applied with everyone else's, and the turn is
generated the same way.

## Data used

- Per player (S03): `ai` (the personality key, empty for a human), `ai_level` (difficulty, 0-3), `active` (false
  for a human player marked inactive), `eliminated`.
- The personality's content definition (`ai_personality`, see "Personalities").
- The player's view of the game: its own planets, fleets, designs and settings, and what it has seen of the others
  (S15). A computer player never reads the host state beyond its view.
- The classic random stream (S01).

## Algorithm

### The AI step

Runs before turn generation (S02 "Before turn generation"), outside the turn pipeline.

1. Go through the players in index order.
2. A player plays in this step when it is still in the game (not eliminated) and either
   - is a computer player, with its personality; or
   - is a human player marked inactive, with the **inactive** personality, which only keeps things ticking over
     (research, and the starting fleets' and colony ships' simple errands).
3. A player that already has orders for this turn (an order file) does not play; its orders are used instead. (The
   original checks for the player's turn file and plays only when there is none.)
4. Otherwise the player's brain runs once on a fresh context: the player's view, the content, the classic random
   stream, the personality and the level. The brain keeps nothing from one turn to the next; anything it needs is
   read again from the view each turn, as in the original, where the AI's working memory is built at the start of
   its turn and freed at the end.
5. The brain's orders form the player's order set for the turn, exactly as if the player had sent them.

The original runs each computer player by reopening the game as that player, letting it play, writing its orders,
and finally reopening the host game. Our step works on the player's view directly and changes nothing in the host
state; only the classic stream advances.

### Personalities

A personality is content (`ai_personality`, id `ai_personality.<key>`, the key being `Player.ai`):

| Field | Meaning |
|---|---|
| `order` | display order |
| `brain` | which built-in brain plays it |
| `params` | named integer parameters the brain reads |
| `levels` | optional, one map per difficulty level (easiest first), the parameters that level changes |

A brain asking for setting *k* gets the level's value if the level map has *k*, else the personality's `params`
value, else the brain's declared default. Personality and difficulty are therefore data; a mod can add a personality
for an existing brain, or change one's settings, without code.

### Personality settings

Each brain declares the settings it reads: a key, a group (research, expansion, economy, military), the lowest
and highest value, and the default; their names and descriptions are in the language files (`ai_setting.<key>`,
groups `ai_setting_group.<group>`), so a personality editor can show any brain's settings. When content loads, a
personality that sets a key its brain doesn't declare, or a value out of the declared range, is an error. The idle
brain declares none; the baseline brain's are listed with it below.

**The game keeps its personalities.** When a game is created, each computer player gets a copy of its
personality's definition (`Player.ai_personality`: name, brain, params, levels), and the AI step uses that copy, so
the game plays the same wherever it is loaded, without the mod or user file the personality came from. Games made
by the original (and inactive human players) have no copy: the content definition of the key is used.

The original has six personalities, chosen by the computer player's race (keys `robotoids`, `turindrones`,
`automitrons`, `rototills`, `cybertrons`, `macinti`, in the original's numbering 0-5), and the housekeeping one
for inactive humans (`inactive`, the original's number 7). Each has a brain of its own, named after it, which a mod's personality may name too. Robotoids play with brain
`robotoids` ("Robotoids" below); the others are specified in later parts of this spec, and until a personality's
brain exists it uses our **baseline** brain (below). The inactive personality uses the **idle** brain, which gives
no orders.

Difficulty levels, easiest first: easy, standard, harder, expert (`ai_level` 0-3). Besides the AI's own play, the
level matters in the starting setup (S07) and in Mystery Trader dealings (S18).

### The baseline brain (our own)

Not a port of the original: a computer player of our own, so games have opponents before the ports exist and as
a fallback for personalities from mods. It reads only its view (S15: other planets as it knows them) and draws
nothing. Each turn, in this order:

1. **Research:** budget `research_pct` (15); field: the lowest tech level, ties in the order propulsion,
   construction, biotech, energy, electronics, weapons; next field: the lowest. No order when nothing changes.
2. **Turn 0:** the default queue for new colonies: auto factories and auto mines (200 each).
3. **Designs** (ship designs in the first free slots; a design's kind is recognised by its parts):
   - a scout (scout hull; the engine with the best merit; the longest-range scanner in the scanner-only slot; a
     fuel tank) and a colony ship (colony ship hull; that engine; a colonizer module). Merit: the fastest warp at
     which the design still goes 300 light-years (warp 10 only with warp-10-safe engines), then its range there.
     Saved when the player has none of that kind, or when it is faster than the best it has, or as fast with at
     least 120% of the range;
   - a warship: the last of destroyer, cruiser, battle cruiser, battleship, dreadnought the player has; every
     weapon slot with the weapon of the highest power × (range + 1) × accuracy % (beams 100%; sappers left out),
     armor slots with the best armor, shield-only slots with the best shield, the engine with the best merit;
     strength = the weapons' total score × (armor + shields). Saved when the player has no armed design (other than
     scouts), or this one is at least 130% as strong as its strongest;
   - a bomber: the last of mini bomber, B-17, B-52 the player has; every bomb slot with the people-killing bomb
     (normal or smart) of the highest kill rate; power = kill rates × counts; saved like the warship;
   - a troop transport and a mineral hauler: the last of small, medium, large and super freighter the player has,
     every slot taking mechanical parts with the cargo pod of the most room, armor slots with the best armor, the
     engine with the best merit; the two are the same ship under different names (the name tells the brain's roles
     apart). Saved when the player has none of the kind or the new one has at least 130% of the room;
   - a dock: a starbase design on the available starbase hull that docks ships (refuels them, S19) with the fewest
     resources, no parts. Saved when the player has no such bare design on that hull.
4. **Colony ships**, in fleet order, those without orders beyond where they are:
   - at an unowned planet with colonists: colonize it (waypoint 0's task);
   - empty at one of the player's planets: load colonists by hand, `colonists_share_pct` (25%) of the planet's
     people at most, up to the ship's room; then go to the best target;
   - empty elsewhere (its target was taken): go back to the nearest planet with `colony_min_population`;
   - the best target: the unowned planet (as known) with the highest habitability for the player, at least
     `min_value` (5), nearest on ties, that no other colony ship is heading for and that the ship can reach on its
     fuel; the task is colonize; the warp is the fastest, from the fleet's default down, whose fuel range covers the
     way.
5. **Scouts** (scout hulls without weapons), in fleet order, without orders: the nearest planet the player has
   never scanned that no other scout is heading for and that it can reach and come back from to one of the
   player's planets with a dock, at the fastest warp covering the round trip; otherwise the nearest such dock.
6. **Threats:** the player's planets with, within `defense_range` (60) light-years, another player's fleet seen
   this turn that has ships on a combat or bomber hull (what a sighting shows) and is not at a planet of its own
   owner (as known); nearest the homeworld first.
7. **War fleets** (only warships and bombers), in fleet order, without orders: away from home, at a threatened
   planet of the player, they stay; otherwise, when the planet where they are is not (as known) another player's,
   back to the homeworld (or the nearest planet with people). At home, every other idle war fleet there merges into
   it; then it goes to the first threatened planet it can reach (it stays when that is the homeworld); otherwise,
   once it has `attack_ships` (5) ships, to the planet known to be another player's that is nearest home and within
   its reach. Battles there follow the
   default battle plan, and its bombers bomb a planet left without a starbase (S17); a planet bombed out becomes
   unowned, a target for colony ships.
8. **Troop transports**, without orders: away from the player's planets and empty, back to the nearest planet with
   people; at one of its planets, the nearest planet known to be another player's, without a starbase (as known),
   that it can reach and take: the troops needed are the top of the population estimate (+1/8) over the share
   of troops its defenses let through (a defense class c lets about 101 − 6c percent of bombs through; troops
   get U + (1 − U)/4 through, S17) and the race's troop strength (`invasion.troops_pct`), times 130%, plus one;
   at most the transport's room and half the planet's people. It loads (or lands) the difference by hand and goes
   there with a transport task unloading all colonists (an invasion, S17). With no target it lands what it
   carries.
9. **Mineral haulers**, without orders: from the player's planet with the most surface minerals to the planet
   with `warship_min_population` people that is shortest of its scarcest mineral, when the source has at least
   half the hauler's room: a transport task loading all minerals at the source, then one unloading them all at
   the destination.
10. **Queues**, the player's planets in planet order. With at least `colony_min_population` (150, units of 100
   colonists) people and the minerals for one ship on its surface: one colony ship while the player's colony ships
   (in flight, queued elsewhere and planned this turn) are fewer than `colony_ships` (2) plus one per 3 planets
   owned and some known planet is worth settling; one scout while its scouts are fewer than `scouts` (3) plus one per
   5 planets and some planet is still unscanned. From year index `war_turn` (40), with `warship_min_population`
   (300) people and the minerals: one warship while its warships are fewer than `warships` (3) plus one per 2
   planets, one bomber while its bombers are fewer than `bombers` (2) plus one per 3 planets, one troop transport
   while its transports are fewer than `transports` (1) plus one per 8 planets; from year index `haul_turn` (30),
   likewise one mineral hauler while it has fewer than `haulers` (1) plus one per 6 planets. A dock on a planet
   without a starbase, with `dock_min_population` (300) people and the minerals, at least `dock_spacing` (200)
   light-years from the player's docks and the docks queued before it this turn. Then auto factories and auto
   mines (200 each), auto maximum terraforming (200) when the planet's habitability is below 100%, and auto
   defenses (200) with `defense_min_population` (50) people. The order is sent only when the queue differs (items,
   designs, starbase flags and counts).

Not yet: alliances and relations, minefields, packets, starbase weapons, judging an enemy's strength before
attacking.

### The classic world (the original's personalities)

The original runs each computer player by loading the game as that player (its turn file merged into its history
file, S15 "Planet history") and letting the personality change that loaded copy: queues, waypoints, designs,
settings. The host then turns the changes into the player's orders. Our classic personalities work the same way on
a **classic world**, built afresh each turn:

1. A copy of the game state.
2. The player's own planets, fleets, designs and settings as they are.
3. Every other planet as the player's planet history records it: owner, homeworld, starbase design (a starbase of
   that design, no damage), and, when it was ever scanned, environment, original environment, concentrations
   (with fractions), population estimate and defense class. Everything else is zero: no population, installations,
   queue, scanner, route or mass driver, and no surface minerals unless this turn's view saw it at level 4. A
   planet with no record has no owner and every value zero. Each planet's detail level is kept beside it (0 never
   seen, 1 or 3 from the history, 7 the player's own).
4. Other players' fleets only when the player's view has them this turn, in the host's fleet order (the order the
   turn file lists them): their position, planet and ships, with no cargo, no name and no waypoints beyond where
   they are.
5. Other players' ship and starbase designs only when the view has them: in full at level 7, otherwise the hull
   with every slot empty.
6. Minefields the player owns or knows (S13).

Each order the personality gives is applied to the world at once (S11 rules; a rejected one changes nothing and is
dropped), so its later choices see it, as the original's edits to its loaded game; the accepted orders are the
player's orders for the turn.

**Setup each turn** (`AI_PlayTurn`, before the personality), in this order:

1. The **working memory**: 4096 16-bit words the personality keeps from turn to turn. The first holds the bytes
   in use, itself included (2 when empty). The original keeps the words in use in the player's history file; we
   keep them in the player's knowledge (`ai_memory`), and drop them when the memory is empty; other words are 0.
   The personality's orders end with an `ai_memory` order (S11) carrying the words in use, when they differ from
   what the knowledge holds, so the memory reaches the host like any other order.
   And a 16-byte record per planet (`planet_info`), all 0.
2. **Design ratings** (`Designs_ComputeRatings`): every loaded ship design's rating (S20 `Design_Evaluate`, the
   formula `score.ship_rating`).
3. **Bombers in orbit** (`AI_ScanFleets`): for each other player's fleet in orbit of one of the player's planets
   with ships on a hull of class `ai_hull_class.bomber` (the original's hulls 16-19), byte 8 of that planet's record
   is 1.
4. **Minefield radii** (`AI_InitScale`): each loaded minefield's radius, rounded, plus 10 light years, squared:
   trunc(sqrt(mines) + 10.5)² (the constant is the double at DS:0x2050; turin1 turn 48).
5. **The player's planets** (`AI_BuildOwnPlanetList`): in planet order, then shuffled: for each place i from the
   first to the last but one, swap it with place i + `random(n − i)` (n planets). These are the turn's first draws.
   (In the tutorial the shuffle is skipped; we have no tutorial game.)

The player's **loaded planets** are those its turn file holds: its own and those the planet history records (the original's `g_planets`, against all the universe's planets). The world also keeps the packets and salvage the player sees this turn, its own included only when seen (its turn file lists just the objects in view; big1 turn 68: freighters pass over the player's own salvage out of scanner range), and the wormholes its turn file holds (those in view this turn: a wormhole seen in an earlier year is not there; turin1 turn 45: a colony ship's wormhole draw finds none, so no second draw); and for each planet the turn the player last saw it (this turn for its own). A planet the player has never
seen has the population estimate 4095 (the 12-bit field all set; big1 turn 62: a freighter does not carry people
there). The player's **planet count** is the number of planets it owns. Its turn file's player record counts the
planets it sees as well, but the brain reads the own count (turin1 turn 69: with 19 planets of its own and 30 in the
record, Turindrones build no freighter; big1 plays the same either way).

After each computer player plays, the original writes its log and history files, and each file draws a cipher salt
(`random(2000)`, S01): two draws per computer player, made by the AI step whatever the brain (big1: 10 a turn for
five players, turns 0-8 and later).

**Hull classes.** Where the original's personalities compare hull numbers, the hulls of each class are content
(`ai_hull_class`, a list of hulls), so a mod's hull can join a class:

| Class | Hulls (original numbers) |
|---|---|
| `bomber` | mini bomber, B-17, stealth bomber, B-52 (16-19) |
| `combat` | destroyer to dreadnought (6-10) |
| `escort` | frigate (5) |
| `multirole` | Nubian, Meta Morph (29, 31) |
| `freighter` | small to super freighter, privateer, rogue, galleon (0-3, 11-13) |
| `cargo_morph` | Meta Morph (31) |
| `colony` | mini colony ship, colony ship (14, 15) |

**The selection.** The original edits through a selection (`SetSelection`): one planet or one fleet. Choosing a
planet loads a copy of it (`g_curPlanet`). Choosing a fleet loads the copy of the fleet's planet unless that planet's
copy is loaded already (none in deep space). Choosing what is already chosen keeps the copy as it is. A production
edit works on the chosen planet's copy and reaches the world only when committed, and the copy is then reloaded.
Changes made to the copy and never committed are lost at the next choice. The toolkit below keeps the same
selection, because a few of its rules read the copy:

- the output estimate's research share;
- the mines check's in-place tries;
- Robotoids' troop loading.

A player counts as a **computer player** here when it is one, or is a human player marked inactive (the original
flags both the same way).

Personality checks below name the personality: Robotoids, Turindrones, Automitrons, Rototills, Cybertrons, Macinti
(the original's 0-5).

### Classic designs (`AI_OutfitDesign`, `AI_CreateDesign`, `AI_FindDesignForHulls`)

A **template** (`ai_design_template`) is a hull and one part class per hull slot. A **part class**
(`ai_part_class`) is a list of groups of parts, each group best first. The best part of a class is the first part
the player can use (S04 tech and traits, Mystery Trader parts only once owned), searching the groups in order.

From a template, every slot holds the best part of its class, as many as the slot allows. When the player cannot use
the hull (tech and traits, `GetPartInfo`), or a slot's class has no part it can use, there is no design. (big1: no
Robotoids player made a Nubian, which needs construction 26; they made destroyers in its slot.)

**Naming** (`AI_NameDesign`). The picture is the first of the hull's four that no design of that hull uses, or a draw
of 4 when all are used. The name is drawn from the hull's name list (`ai_design_names`: the first list naming the
hull; `utility` for any other hull; `starbase` for starbases) until no other design has it. Ship names are checked
against every ship design; starbase names against the starbase designs of the same hull. After 20 draws, a number
below 100 is drawn, then a name, and the design is called "name number".

The lists are our own, each as long as the original's:

| List | Names |
|---|---|
| scouts and frigates | 10 |
| capital ships | 16 |
| bombers | 12 |
| miners | 8 |
| colony ships | 8 |
| freighters | 8 |
| raiders | 8 |
| others | 8 |
| destroyers | 16 |
| starbases | 13 |

One name is in two lists (the bombers' 7th is the raiders' 4th), as in the original, so the same draws repeat. No
name is one of our starting design names.

**Saving** (`AI_SaveDesign`). The design gets this turn as its turn designed, and nothing built. A design already in
the slot is deleted first (orders `design_delete`, then `design_change`). A new ship design's rating counts as 0 for
the rest of the turn.

**Starbase designs** (`AI_CreateDesign`) come in sizes 1 (small), 2 and 3 (full):

- In slots 1, 3, 6 and 8 they are forts (template `orbital_fort`), and a medium fort is a full one. Elsewhere they
  are stations (template `space_station`).
- In smaller sizes, slots holding 4 or more keep a quarter (size 1) or half (size 2).
- At size 1, slots holding fewer lose one part if they hold more than one or are orbital slots, except for
  Cybertrons. A slot left with none is empty.

**Keeping starbase designs** (`AI_UpdateStarbaseDesigns`):

1. With slot 2 empty: a medium station there and a full one in 4.
2. With slot 1 empty: a small fort there. With slot 3 empty: a full fort there.
3. From turn 50, stations come in two generations, slots 0, 2, 4 and slots 5, 7, 9. The newest station design is the
   last of the latest turn designed among 0, 2, 4, 5, 7, 9. When it is 40 turns old and no design of the other
   generation still has starbases, the other generation is designed small, medium and full.
4. Forts work the same way, in generations 1, 3 and 6, 8 (small and full): the other generation is designed when
   neither of its designs has starbases.

**Newer starbase** (`AI_NewerStarbaseDesign05`, `...16`): slot 5 (6) when its design is newer than slot 0's (1's),
else 0 (1).

**Retiring** (`AI_FindDesignForHulls(low, high, age)`): among ship slots low to high, the newest design is the first
of the latest turn designed. Each design older than `age` turns is deleted when it has no ships left, even if it is
the one returned; otherwise it is marked obsolete. Also returned: the ships of those slots, at most 32000.

### Classic research (`AI_RunResearchPlan`)

A plan (`ai_research_plan`) is a list of steps, each a tech field and a level. The budget is set to the
personality's figure, then:

1. With every field at 24, the budget is 0 and the research order is sent.
2. The first step whose level is not reached gives the field researched. When that step is one level away, the next
   step's field becomes the next field. The order is sent.
3. With every step reached, the lowest field (the first of equals) is researched, and the order is sent only when
   that changes the field.

The budget reaches the host only with a research order, as in the original, which sends nothing else; the world uses
it at once. Robotoids' plan has 36 steps.

### Classic production (`BuildProductionList`, `AI_QueueProduction`, `AI_ManageProduction`)

**What a planet can build**, in this order, each with how many more:

1. Ship designs a dock there holds (mass within its capacity; stations take any), any number.
2. Starbase designs but the one it has, 1 each.
3. The genesis device when the player can build it, 1.
4. The four packets when the starbase has a mass driver, any number.
5. Factories and mines up to their maxima, at most 1020 at a time.
6. Defenses up to their maximum.
7. Alchemy, any number.
8. A planetary scanner when the planet has none (not for a race with `production.no_planetary_scanner`), 1.
9. Terraforming steps the planet still allows.
10. The auto items, any number, but those the race skips (`colony.skips_auto_<effect>`).

Designs that came with transferred ships are never listed.

**Editing.** Opening a planet's production copies its queue. Each item is held to what the list offers, and the
list's count is lowered by it. An item the list lacks becomes alchemy x0.

**Adding** puts an item first, last, or makes it the whole queue. With no edit open, adding opens one, holds the
count to the list (0 when the item is not listed) and commits. With an edit open, the count is taken as given (its
low 10 bits, as the original stores it). A planet with more than 200 queue items takes nothing.

**Committing** with changes gives the planet's `production_queue` order. A design item for an empty slot is left out:
the original sends it, and the year's production removes it.

**Estimates**:

- *Output* (`AI_EstimatePlanetOutput`): the surface plus this year's mining (-1 each with no people), and the
  resources less the research share. The share is left in when the selected planet copy gives only leftovers to
  research.
- *Queue cost* (`AI_EstimateQueueCost`): every item at its full count, auto items included, progress ignored.
- *Item cost* (`GetProductionItemCost`): S09's unit cost, times the count unless per unit; nothing for an empty
  design slot.
- *Completion* (`Production_SimulateQueue`, below).

**Completion** gives queue item k's first and last year, 1 being this year. A copy of the planet repeats each year:

1. It mines, and its concentrations wear.
2. It spends its resources, less the research share, on the items in order, as S09 step 5 spends.
3. An auto alchemy item that is not last is passed over, and the item after it may draw on alchemy. As the last item
   it may build up to 1020.
4. What an item carries over is spent first the next year.
5. Built mines and factories count from the next item on.
6. A spending result from "some built" down ends the year.
7. The people grow.

The first year is when a unit is first built. The last year is when the item is done, or the year before an auto
item stops short. An item not done in 99 years counts as 100, and one never begun before such a stop is [0, 0]. An
auto alchemy item that is not last is [-1, -1].

**The production pass** (`AI_ManageProduction`), after the fleets' orders:

1. Safe speeds for every fleet (Classic fleets).
2. Starbases at depots.
3. Each of the player's planets, in shuffled order:
   - Robotoids skip planets under 40 hundred people. The others skip planets under 60 hundred where `planet_info`
     byte 2 is clear.
   - Except Macinti, a planet skips when its queue costs more of some mineral than this year's output.
   - Robotoids, or byte 2 clear: a starbase step, else packets, else old scanners (never listed), else defenses.
     Cybertrons with byte 2 set: a starbase step only.
   - Personalities other than Robotoids that queued nothing try terraforming.
4. From turn (universe size index + 2) x 10, outside the tutorial: late defenses.
5. The mines check.

**Starbases at depots** (`AI_QueueStarbase`). Not Macinti; in a tutorial game only before turn 31. Each planet of the
player without a starbase that is a freighter depot, with 80 hundred people and byte 2 clear, appends the newer
station, unless a starbase is queued there. Cybertrons instead give each planet without a starbase that is 15%
habitable with 500 hundred people the newer station (all concentrations 16 or more), else the newer fort.

**Starbase steps** (`AI_QueueShip`). Not when a starbase is queued; not Cybertrons before turn 40; Macinti have their
own. On a planet with a starbase:

- One older than the newest generation (the newer station, or the newer fort) is replaced by the same size of the
  newest. The chance in 100 is 5 plus half the newest design's age past 10 turns (the whole age from 50).
- One of the newest generation grows one size with a chance of 6 in 100, when that design exists and the surface has
  200 of each mineral.

**Packets** (`AI_QueuePackets`) need all of these:

- not Cybertrons, and no packets queued;
- level 2 or more;
- 3001 minerals of output;
- a starbase whose best mass driver gives warp 10 or more;
- a draw of 1 in 4.

The reach squared is 7056, or 50625 with two of the best drivers, three times that when a surface mineral is over
12500. Targets are other players' planets seen in the last 2 turns, within reach, with a defense class under 14 or a
population estimate under 750. Races with `packet.no_damage` are left out, and starbase planets of races with
`ai.no_packets_at_starbases`. One target is drawn among them: each in turn replaces the pick on a draw of 1 in n.

The driver is aimed at it at warp 13 (a `planet_settings` order), and packets are appended:

- 80 of germanium when germanium output is over 20000, on a draw of 2 in 3;
- mixed: 30 when output is over 3000, 4000 and 3000; else 15 when over 1500, 2250 and 1500;
- else, per mineral over what it keeps (1250; boranium 2500), one per 200 over it, 1 to 25.

**Defenses** (`AI_QueueDefenses`): a planet of 1600 hundred people with fewer defenses than one per 80 hundred appends
up to 4, unless defenses are queued.

**Terraforming** (`AI_QueueStandardItem2`, not Robotoids or Cybertrons): a planet of 200 hundred people off the race's
ideal on some axis appends up to 4 steps, unless steps are queued.

**Late defenses** (`AI_LateGameDefenses`, `AI_PlanetDefenses`), at each planet with an enemy bomber in orbit, unless
defenses are queued, with 50 resources of output (R):

1. The count is R/25 (less a sixth of that above 5), as far as the list allows.
2. When a mineral (a fifth of its output, at most 100) allows fewer, m: m plus one per 150 of nine tenths of R left
   after alchemy for m, with 5 alchemy units per extra defense.
3. Both go to the top of the queue, alchemy above.

**The mines check** (`AI_FixupMineOrders`), each of the player's planets whose first item is not mines, alchemy or
terraforming:

1. If that item is not begun this year, although the resources of the years before it starts would pay for a unit,
   mines go to the top of the queue: as many as this year's resources buy, up to what next year's people can work.
   When that is none, auto alchemy x1. The queue is committed.
2. The original then tries the queue with auto alchemy and with fewer mines on the planet copy only. That reaches the
   world only when the copy is committed later without another choice in between.

**The last pass** (`AI_FinishTurn`, `AI_FillPlanetQueue`), each planet in shuffled order, with resources to spare
after its queue:

- Macinti terraform as far as a seventieth of them pays.
- Short of a mineral, and the queue not led by alchemy: mines at the top for what is left.
- With every mineral to spare: factories at the end (as many as germanium and resources pay for), then mines at the
  top.
- Mines and factories only up to what the people work, less those queued.
- With every field at 26, after turn 100: alchemy for the rest (one more), at the top when short.

### Classic fleets

**What a fleet is.** In design slot order:

- A combat hull makes a warship.
- The first escort hull decides alone: a warship with a rating above 0.
- A multirole hull counts as a warship with less than 500 kT of cargo and a rating.

Freighters are freighter hulls, or a cargo morph with 500 kT of cargo and a rating.

**New orders** (`AI_AddWaypoint`). A waypoint where the fleet is replaces its orders, task included. Elsewhere it
follows the fleet's current place, and later waypoints go. The toolkit's orders:

| Order | Speed and task |
|---|---|
| Colonize a planet (`AI_SendToPlanet`) | top speed without easing |
| Enter a wormhole (`AI_SendToPoint`) | top speed without easing |
| Go home (`AI_ReturnHome`): the nearest of the player's planets with a starbase (with more than 250 hundred people when asked) | warp 4 |
| Join a fleet | warp 6 |
| A warship's target | warp 4 |
| The nearest planet of another player within reach (`AI_SendToNearestObject`) | warp 4 |

Nearest searches keep the first of equals. They ask their condition only of candidates nearer than the best so far,
which matters when the condition draws.

**Joining** (`AI_Explore(low, high, near, far)`): the nearest of the player's fleets earlier in the fleet list with
ships in slots low to high. The fleet joins it within `near`, or within `far` on a draw of 1 in 2, clearing its task
first.

**A random planet** (`AI_PickRandomTarget`): each planet in reach, in order, replaces the pick on a draw of 1 in n.
When avoiding starbases, the pick is drawn again up to twice while it has one.

**Merging** (`AI_MergeFleetsByHull(slots)`): fleets with ships in those slots merge, in fleet order, into the first
such fleet at the same place (`MergeFleets@1048:78b6`): all of a merged fleet's ships move into the other as a ship move (S11 "Fleet orders", `fleet_move_ships`), so cargo, fuel and damage follow as for a ship move, not as for a merge order, and the emptied fleet is deleted. At most 32 fleets are kept to merge into; the rest wait for another pass. A merged fleet
leaves the list, so the fleet after it is passed over.

**Splitting** (`AI_SplitFleets(slots)`): while the player has fewer than 501 fleets, the first fleet with ships both
in those slots and in others splits them off; cargo and fuel follow the ships (S11).

**Safe speeds** (`AI_AvoidMinefieldsAll`, `AI_SetMinefieldSafeWarp`). Each of the player's fleets with somewhere to go
gets its next speed:

- Inside a minefield of another player in the player's turn file (seen this turn: one known from an earlier year is
  not there; turin1 turn 48), not a speed bump, by the setup's radius squared: heavy fields warp 6;
  standard warp 4, or 5 on a draw of 6 in 10; one more with `minefield.speed_bonus`.
- Elsewhere: the default warp (S12), as a computer player.

**Warships** (`AI_DirectWarship(own, enemies, spare_computers)`):

1. The prey is the nearest of the enemy fleets, in the order given. With `spare_computers`, computer players' fleets
   are left out. A fleet the `own` fleets already chase is passed over on a draw of 1 in 3. When this fleet has fewer
   than five times its chasers' ships, it is kept only on a draw of 14 in 15.
2. Prey within 180 light years is chased.
3. With no prey at all and `spare_computers`, the search runs again counting computer players.
4. With prey too far: under half its fuel capacity, the fleet goes home if it can. Otherwise it heads for the planet
   nearest the prey that none of `own` heads for.
5. Failing that, the nearest planet of another player.
6. Failing that, the nearest planet `planet_info` byte 9 leaves unmarked (one drawn when none).
7. A fleet already heading for a planet keeps its orders when the new target is a planet too.

**Colony targets** (`AI_RateColonyTargets`). Byte 15 of each planet's record marks it:

- 0, free: Robotoids and Macinti take any unowned planet, the others only unowned planets they can terraform to
  habitable (else 8);
- 1, the player's; 2, another player's;
- 4, claimed: another of the player's fleets heads there (for Robotoids and Macinti, to colonize);
- 0x10, unseen: for the other personalities, every planet the player hasn't loaded (they start by marking every planet
  0x10, then mark the loaded ones; Robotoids and Macinti start from 0).

The other personalities mark only once a turn. The target is the nearest free planet. For a fleet at one of the
player's planets before turn 120, a wormhole may be taken instead (`AI_PickWeighted`):

1. A wormhole is in reach within twice the planet's distance. The original squares the distance in 16 bits, so a
   wormhole whose square wraps past 32767 is always in reach.
2. Its score is 50 when unseen and farther than the planet, 90 when unseen and nearer, and 70 less 10 per percent of
   jump chance when seen (S18).
3. The best (the nearer of equals) is taken when a draw of 100 falls under its score.

A call that asks for no wormhole (Turindrones' colony ships) skips this part.

**Appending orders** (`AI_AddWaypoint` with its append flag): the waypoint follows the fleet's last one, or replaces it
when it is at the same place.

**Warship hulls** (`AI_HasWarshipHull`): a fleet with ships on a hull of class `ai_hull_class.warship` (scout,
frigate, destroyer, cruiser, battle cruiser, battleship, dreadnought). **Armed** (`Fleet_HasArmedShips`): ships of a
design with a weapon (S16 `Design_IsArmed`).

**Exploring** (`AI_ChooseColonyTarget(wormhole)`): when the colony targets weren't rated this turn they are, asking for
no wormhole. The target is the nearest planet marked 0x10 (unseen). When a wormhole is asked for and the fleet is at a
planet, a draw of 100 under 5 looks for one as above (`AI_PickWeighted`, against the unseen planet's distance); one
found replaces the planet.

**Hunting and exploring** (`AI_DirectFleet(own, enemies, spare_computers, wormhole)`), for Turindrones, Automitrons and
Rototills:

1. An armed fleet looks for prey among the enemy fleets, in the order given: with `spare_computers` computer players'
   fleets are left out; a fleet one of `own` already chases (its next waypoint targets it) is passed over on a draw of
   1 in 3 (drawn only for chased fleets). The prey is the nearest.
2. Prey within 180 light years is chased.
3. With no prey at all and `spare_computers`, the search runs again counting computer players. Without
   `spare_computers` the fleet explores (5).
4. With prey too far: under half its fuel capacity, the fleet goes home if it can, and is done. Otherwise it heads for
   the loaded planet nearest the prey that none of `own` heads for, unless there is none or it is the planet the fleet
   is at: then it explores.
5. Exploring, and for an unarmed fleet: the exploring target above (with a wormhole when asked). Without one, the
   planet the target score without sparing rates highest from the player's homeworld (no homeworld: none), else a
   planet drawn among all.
6. A fleet already heading for a planet keeps its orders when the new target is a planet too. A planet chosen gets
   byte 15 = 4 (claimed). The orders go at the fleet's top warp (S12's default warp without easing) and no task.

The **target score** (`AI_ScoreColonyTarget`, `AI_ScoreColonyTarget2`) is described with Robotoids; it is the
toolkit's, reading byte 10 as each personality sets it.

### Classic freight

**Cargo** moves as `cargo_transfer` orders (`AI_MoveCargo`). The amount is held to what the giver has and the taker
can hold before the order is given, so the order asks for what moves, and no order is given when nothing would; another
player's planet or fleet gives nothing.

**Colony ships** (`AI_CountColonyShips`). Easy players count only on even turns. Before turn 30 the answer is
"build". Later it is "build" when all of these hold:

- the colony fleets number at most universe size index x 20 + 10;
- they and the planet counts of the player records loaded are at most four fifths of all planets: the player's own
  count (above) and, for each other player, the planets its history knows to be theirs (the history file keeps that
  count for each player; big1 turn 30);
- colony designs built, less those two, lie from 0 to 25; or there are fewer than 5 colony fleets and a draw of 1 in
  2 says so.


**Freighter runs** (`AI_PlanTransport`), from the freighter's depot. Planets are scored per year of travel (distance
div 25, rounded up, at least 1):

- Home scores 25000 for a full freighter, else 20 per percent full from 35%.
- Another of the player's planets without a starbase (none queued) scores by the share of the freighter its minerals
  fill, no more than the room left. When home's scarcest mineral is under half the lowest before it, the others count
  half; under a quarter, only it counts.
- A planet with record byte 2 marked scores 25000 when the freighter is at home.
- Robotoids at home also carry people (65) to planets estimated at 61 or less (from 1101 hundred at home) or 14 or
  less (from 301).
- Planets other freighters of its kind head for are passed over.

Salvage within 200 light years on each axis (any distance toward smaller coordinates) scores the same way. Salvage
where the freighter is gets loaded: the scarce mineral first, then everything unless only that counts.

The freighter goes at warp 4:

- At a target planet it loads everything: only the scarce mineral when only that counts, or when the target has as
  much of it as there is room. At another player's planet it fills to 66% of the scarce mineral and 33% of the others.
- At home it unloads.
- At salvage it has no task.

Robotoids leaving home with people take some to the target: 300 hundred to another player's planet (100 when home has
900 or fewer). To their own small planets they take a share by home's size: 10% over 2000, 8% over 1500, 5% over
1000, else (people - 400)/100 %; none when the target has 1000 or two thirds of home's. Turindrones' freighters at
home load 1000 hundred people when home has more than 1200 hundred and the target is an owned planet (another
player's or theirs) with fewer people; whenever the target is an owned planet other than home they unload all
colonists there (turin1 turn 65).

**Depots** (`AI_PlanFreighterDepots`), kept in the memory. A record is a planet, a count of fleets and up to 8 fleet id
words (owner << 9 | number), 10 words in all. There are at most 64 records, and the byte count is records x 20 + 4.
Not Cybertrons or Macinti, from turn 20:

1. Records of planets the player lost are dropped.
2. The player's planets with a starbase (shuffled order) become depots.
3. Then rich planets: 80 hundred people; concentration squared x 4 plus surface over the three minerals 7000 or more;
   20 mines and 20 factories. Robotoids skip planets within 50 light years of another depot.
4. Each freighter not yet in a record joins the nearest depot with room.
5. Each depot with fewer than 4 freighters takes the last freighter of the first depot with 2 more than it.

### Robotoids

The brain `robotoids` (`AI_Robotoids`). After the setup, in this order:

**1. Research.** The starbase designs are kept up to date, the newer station is chosen (slot 5 when newer than 0, else
0), the freighter depots are planned, and plan `robotoids` is followed with a budget of 15% (0% before turn 10).

**2. Merging**, after turn 50: fleets with ships in slots 2-7, 9 or 10 merge; then fleets with slot-0 ships; then
fleets with ships in slots 14-15.

**3. This turn's thresholds.** The escort strength E is 4, and after turn 130 4 + (turn − 120) div 20, at most 50.
The bomber count B is 6, and after turn 115 6 + (turn − 100) div 22, at most 12. A fleet's **strength** is its ships
in slots 2-5 plus twice its ships in slots 6-7; its **bombers** are its ships in slots 9-10.

**4. Retiring** (Classic designs, `AI_FindDesignForHulls`), with an age A of 50 before turn 120, 70 before 200, else
100, all marking one set of obsolete slots:

1. slots 14-15: the warship design W. A design there on the hull of template `nubian` is never marked obsolete;
2. slots 11-13: the freighter design F, and how many ships of those slots exist;
3. slots 9-10: the bomber design;
4. slots 2-5: the morph design M;
5. slots 6-7, with age 3A/2: the battleship design S.

**5. Splitting**, after turn 80 (Classic fleets): ships of obsolete slots split off, then ships of slot 0, then of
slot 1, then of slots 11-13.

**6. Designs** (`AI_Robotoids_Designs`), each only for an empty slot. Tech levels: En energy, Wp weapons, Pr
propulsion, Co construction, El electronics, Bi biotech. "Drawn" means a draw of the template's number in its group
before each try, up to 5 tries, stopping at the first design made.

| Slots | When | Templates |
|---|---|---|
| 11, 12, 13 | Pr 2, and Co 4, 7, 10 for the three slots; 12 and 13 only when the slot before was designed more than 14 turns ago (an empty slot counts as designed in turn 0) | Co under 10: privateer A (11) or B (12, 13); else a meta morph freighter 0-5, drawn |
| 14 | Wp 5, El 6, Co 6, Pr 6, En 2 | five tries, each the Nubian, and when that cannot be made a destroyer A0-A3 drawn, stopping once a destroyer is made |
| 15 | El 10, Co 8, Pr 9, Wp 14, and the Nubian cannot be made | destroyer B0-B3, drawn |
| 2, 3, 4 | Wp 10, Co 10, Pr 9, En 6; 3 and 4 only when the slot before holds a design more than 12 turns old | meta morph warship A0-A3 (2, 4) or B0-B3 (3), drawn |
| 6, 7, 8 | Bi 4, El 10, Co 12, Pr 12, En 6, Wp 15; 7 and 8 after more than 20 turns | battleship A0-A3 (6) or B0-B3 (7, 8), drawn |
| 9, 10 | Wp 14; 10 after more than 15 turns | the munitions battleship, else B-52 A (9) or B (10) |
| 0 (any) | harder or expert level; slot 0 empty, or not on the hull of template `frigate_mine_layer` and with no ships left; Bi 4, El 5, Co 6, Pr 6, En 6 | slot 0's design is deleted, then the frigate mine layer |

The Nubian in slot 14 is made up to five times over, each replacing the last, with its picture and name drawn
again each time.

**7. Counts.** N, the player's fleets with ships in slots 14-15 (0 without a design W); and whether to build colony
ships, and the colony fleets (Classic freight).

**8. Targets.** Each planet of another player gets `planet_info` byte 10 = the population estimate div 250, plus 1,
at most 6; plus 1 more with a starbase. Its byte 9 is 1.

**9. Ships at starbases.** Each of the player's planets in shuffled order, with a starbase and 200 hundred people:
its production is opened, and when the queue holds no ship design:

1. K is the larger of (the player's planet count div 8) and (depots × 4). With design F, when F's slots have fewer than
   8K/10 ships, or fewer than K and a draw of 1 in 3: one F at the end.
2. When colony ships are to be built, or there are fewer than 26 colony fleets and `random(depots × 8)` is 0, and it
   is after turn 4: one ship of slot 1 at the end, two before turn 21. Then, at standard level or above, with the
   planet's people × the race's growth rate (in percent, doubled for HE) over 2300 and 36 resources, one more; at
   harder or above, over 3600 and with 51 resources, one more again. (The draw is made before the turn is checked.)
3. When slot 0 holds a design on the mine layer's hull, on a draw of 1 in 4: with n the slot-0 ships of the first of
   the player's fleets here that has some (0 when none), four slot-0 ships at the end when n is under 10 (or under 17
   on a draw of 1 in 10) and a draw of 1 in 2n + 1 says so.
4. The planet is **rich** when its first surface mineral under 5000 is germanium (ironium and boranium 5000 or more,
   germanium under).
5. With the bomber design, the first of the player's fleets here with strength E decides: with fewer than B bombers,
   6 (rich) or 4 ships of the bomber design at the end, and the planet is done.
6. With design M, when its ships number fewer than (all planets div 7) + 6, or on a draw of 1 in 2: the design is M,
   or S on a draw of 1 in 2 when there is an S. This year's output less the cost of the queue as it stood: when any
   of the four is negative the planet is done. Less three fifths of the design's cost (each of minerals and
   resources, rounded down): when any is negative, go on with 7; otherwise 5 (rich) or 1 of the design at the end.
7. With design W, when its ships number fewer than (all planets div 12) + 8: output less queue cost as in 6 (negative:
   done); then up to five times, less W's cost: negative, done; otherwise one W at the end.

The production is then committed.

**10. Fleets, first pass**, every fleet in fleet order:

- A fleet whose next waypoint is a space object more than 200 light years away drops its waypoints beyond where it is.
- Other players' fleets are listed as **enemies**, the latest first.
- A fleet with slot-0 ships, after turn 40, with no waypoints beyond where it is: with more than 6 of them, on a draw
  of 1 in 5, a random planet within 105 light years avoiding starbases (Classic fleets); when there is one and the
  fleet is not there, its task is cleared and it goes there at warp 4, and continues with the last two points below.
  Otherwise, without a task, it lays mines for ever (task data 5, 5); with a task it continues with the last two
  points.
- Any other fleet:
  - a **warship** (Classic fleets) is listed among the player's **warships**, the latest first, and a mine-laying task
    is cleared. When it has ships in slots 2-7 and a planet ahead (the next waypoint's planet, else the planet where
    it is), that planet's byte 10 gets 0x80 when it is set;
  - a **freighter**, looking at the planet where it is (when it has no waypoint beyond or a task here) or the next
    waypoint's planet: when that planet is not the player's and the freighter has no colonists aboard, it drops its
    waypoints beyond where it is and its task;
  - then the last two points.
- Before turn 21, a fleet with slot-0 ships scraps them (task scrap here).
- Otherwise a fleet with slot-1 ships and no waypoints beyond where it is, after turn 4 (or when the players start
  close, S07):
  - At harder or expert level, at another player's planet whose race lacks `ai.no_colonist_drops` (AR), with
    colonists aboard: a transport task here unloading all colonists (an invasion, S17), and on to the nearest of the
    player's planets with a starbase at warp 4.
  - Otherwise its colony target (Classic fleets). With none, at a planet it scraps. With one, at a planet it first
    loads 10 hundred colonists; it goes to colonize the planet, or into the wormhole.

**11. Freighters.** When one of the player's planets has a starbase (the first in shuffled order is the fallback
depot), each freighter of the player with no waypoints beyond where it is takes battle plan 4 (the fifth default
plan) and a run (Classic freight) from its depot, or the fallback.

**12. Fleets, last pass**, each of the player's fleets in fleet order:

1. When every slot it has ships in is obsolete: at a planet of the player's with a starbase, or on a draw of 1 in 5 at
   one without, it scraps. Otherwise it keeps going when it is in deep space heading for a planet, or goes home
   (Classic fleets). Done, unless there is no home.
2. With ships in slots 2-10: the invasion (below).
3. Otherwise a warship not heading for a fleet: when N is over 70 (50 from turn 121), or over 60 (40) on a draw of 1
   in 3, with fewer than 20 ships of design W (or on a draw of 1 in 20), it joins the nearest earlier fleet with ships
   in slots 14-15 within 36 light years, or 72 on a draw (Classic fleets). Failing that, `AI_DirectWarship` with the
   listed warships and enemies, sparing computer players when they form alliances.

**13. Production** (Classic production) and the last pass.

**The invasion** (`AI_Robotoids_Invade`), for a fleet with strength S and bombers T:

1. A fleet with waypoints beyond where it is keeps them when it heads for a fleet within 250 light years
   (distance² under 62501), or for a planet that is another player's, the player's own with a starbase, or not seen
   this turn. Other orders are planned again.
2. In deep space it heads for the nearest planet of another player within 150 light years (Classic fleets). Done.
3. At one of the player's planets with a starbase:
   - With S under E or T under B: at easy or standard level it stays; it stays when S is at most 2E and under 60;
     then on a draw of 10 above 4, when S is at most 3E or a draw of 10 is above 6, it stays when S is under 121 or a
     draw of 10 is above 6. Otherwise it sets out.
   - Otherwise it loads colonists from the selected planet copy: a tenth of its people from 3001 hundred, a fifteenth
     from 2001, a twentieth from 1001, none below; and sets out.
4. Elsewhere, with S at least E div 2 and T at least min(B div 2 − 1, 3):
   - At another player's planet: the troops needed X = its population estimate × 400 / (100 + (−1 − defense class) ×
     18 / 4), divisions truncating toward zero; C the colonists aboard. When C div 5 is at most X and either X is 200
     or more or C is under 351, it waits when X is over 9 or C under 151. Otherwise it drops (an invasion by hand,
     S17) the larger of C div 2 and 5X/4, at most C and 30000. Done.
   - At one of its own planets with more than 1000 hundred people it loads a fifth of them; and sets out.
   - Otherwise it sets out.
5. Elsewhere, weaker: its task is cleared. At harder or expert level it sets out anyway when S is over 2E and a draw
   of 10 is under 5, or S is over 4E and a draw of 10 is under 7, or S is over 120 and a draw of 10 is under 7 (each
   draw made only when its strength holds and nothing before set it out). Otherwise its target is the nearest of the
   player's planets with a starbase.
6. **Setting out**: the target is the planet rated highest by the target score from here, first sparing computer
   players' planets when they form alliances, then any.
7. With a target planet, its byte 10 gets 0x80 and the fleet goes there at warp 4. Without one, it heads for the
   nearest fleet of another player at warp 4; with none it stays.

**The target score** (`AI_ScoreColonyTarget`, `AI_ScoreColonyTarget2`): 0 for the planet the fleet is at and for one
whose byte 10 is 0 (and, sparing computer players, for theirs). Otherwise byte 10 plus 7 within 50 light years
(distance² under 2500), 5 under 10000, 4 under 22500, 3 under 40000, 2 under 90000, 1 under 250000. A score with 0x80
set counts only on a draw of 1 in 4, and is 0 otherwise.

### Turindrones

The brain `turindrones` (`AI_Turindrones@1080:234e`). After the setup, in this order. Checked against the harness game
turin1 (five Turindrones and an idle human, 80 turns): 72 turns match; of the others, 31, 55, 59 and 72 are comets (S25
B38), 61 damage on ship moves (B32), 71 a chaser that the original stops (B12); 19 is the fuel question big1 turns 8
and 12 share, and 77 is open (see Open questions).

**1. Research**, as for Robotoids (starbase designs, the newer station, depots), then plan `turindrones` with a budget
of 15% from the first turn.

**2. Merging**, each only when the first slot named holds a design: slots 4-7 and 13-15 when slot 13 does; slot 12;
slots 10-11 when slot 10 does; slots 2-3 when slot 2 does.

**3. This turn's thresholds.** The escort strength E is 3, and after turn 130 3 + (turn − 120) div 20, at most 50. The
bomber count B is 6, and after turn 115 6 + (turn − 100) div 22, at most 12. A fleet's strength is as for Robotoids
(ships in slots 2-5 plus twice those in 6-7).

**4. Retiring** (`AI_FindDesignForHulls`) with the age A of Robotoids, all marking one set of obsolete slots: slots 6-7
(the warship design W), 8-9 (the freighter design F and how many ships of those slots exist), 13-14 (the bomber design),
4-5 (the battleship design S), 12, 15 (the raider design R), 2-3 when construction is 7 or more, and 10-11 (the
destroyer design D).

**5. Splitting**, after turn 60: ships of obsolete slots split off.

**6. Designs** (`AI_Turindrones_Designs`), in this order. Tech levels as for Robotoids. "Spent" means the slot is empty
or no ships of its design are left.

| Slot | When | Template (`turindrones_…`) |
|---|---|---|
| 8 | empty; Pr 5, Co 8 | `freighter_rogue` |
| 9 | empty; Pr 7, Co 11 | `freighter_galleon` |
| 10 | empty; Wp 5, El 5, Co 4, Pr 5 | `destroyer`, up to 4 tries, each after a draw of 1 |
| 1 | spent | the design there is deleted unless it is on a privateer hull; `colony_ship` |
| 0 | spent | the design there is deleted; `scout` |
| 2 | spent; Co 7, El 4 | the design there is deleted; `miner` |
| 12 | spent; Co 4, Bi 4 | `mine_layer` |
| 13 | empty; Wp 8, El 7, Co 6 | `bomber` |
| 14 | empty; Wp 11, El 12, Co 15, Pr 9 | `bomber` |
| 4 | empty; Wp 5, El 6, Co 13, Pr 7 | `battleship_0`-`3`, drawn, up to 5 tries |
| 15 | empty; Wp 5, El 6, Co 13, Pr 7 | `freighter_rogue`, made five times over, each replacing the last |

Rogues and stealth bombers need Super Stealth, miners Advanced Remote Mining (S04): other races leave those slots empty.

**7. Planets.** First, P counts the loaded unowned planets the player has scanned (detail over 2) that it could
terraform to habitable. Then each loaded planet in planet order:

1. Its byte 9 is 1.
2. Unowned and scanned: byte 1 is its **mining worth**, each mineral's concentration halved, or 75 from 67, added up,
   at most 127.
3. The player's own: when its habitability is negative, byte 2 is 1. Otherwise, without a starbase or with fewer than
   200 hundred people, its leftover-to-research setting becomes "under 200 hundred people" (a `planet_settings` order
   when it changes). Otherwise its production is opened and, when the queue holds no ship design, ships are added
   (below), and it is committed.
4. Another player's: byte 10 is 2 with a starbase, else 1. When the player could terraform it to habitable, byte 3 is
   that habitability and Q (the other players' planets met so far, 0 at the start) grows by 1.

**Ships at a starbase planet**, at the end of the queue:

1. On turn 0, n starting at the universe's planet count: while n is above 0, one scout (slot 0), n less 30 (100 from
   191 planets). Later, when slot 0 holds a design on the scout template's hull (a frigate) with fewer ships than the
   planets div 4 (at most 32), and its ships built div 10 fewer than those: one scout.
2. K is the larger of (the player's planet count div 10) and (depots × 2). With Pr 5 and design F, when F's slots have
   fewer than K ships, or fewer than 10K/7 and a draw of 1 in 4: one F.
3. When P or Q is not 0 and the colony design has fewer than 2 ships: four of slot 1 (one at a time).
4. With a design in slot 12, on a draw of 1 in 3: with n the slot-12 ships of the first of the player's fleets here
   that has some (0 when none), three of slot 12 when n is under 10 (or under 17 on a draw of 1 in 8) and a draw of 1
   in 2n + 1 says so.
5. With the bomber design, the first of the player's fleets here with strength E decides: when it has B or more ships
   in slots 13-14, four of the bomber design, and the planet is done.
6. For S (fewer ships than all planets div 24, plus 4), W (div 12, plus 8), D (div 4, plus 12) and R (div 12, plus 8)
   in turn, each with a design: this year's output less the cost of the queue as it stands, the planet done when any of
   the four is negative; then up to five times, less the design's cost: negative, the planet is done; otherwise one of
   the design.

**8. Home** is the first of the player's planets (shuffled order) with a starbase; without one, the last of them; none
without planets.

**9. Fleets, first pass**, every fleet in fleet order. Other players' fleets are listed as enemies, the latest first;
the player's fleets with warship hulls (Classic fleets) as its warships. Then, for the player's fleets:

- With miners (slots 2-3) whose last waypoint has a task: in deep space with a next waypoint, that waypoint's task
  becomes remote mining (the original edits it in place) and its planet is marked mined (byte 1 | 0x80); at a planet
  another player owns, the fleet drops its waypoints beyond where it is and its task; at an unowned planet, that planet
  is marked mined.
- Otherwise, with no ships in slots 8-9: a fleet with colony ships (slot 1) looks at the planet where it is (no
  waypoints beyond) or its next waypoint's planet. When that planet has byte 3 set it is treated as a freighter's
  (below); otherwise, at another player's planet it drops its waypoints and its task.
- With ships in slots 8-9, the planet where it is (no waypoints beyond), else the next waypoint's planet, else none:
  - None: when its next waypoint is in deep space it drops its waypoints beyond where it is and its task.
  - Another player's planet: when the planet has byte 3 set, the fleet has colonists aboard, the owner's race lacks
    `ai.no_colonist_drops` (AR) and the planet has no starbase, a transport task unloading all colonists at warp 0
    replaces waypoint 0 (when it targets that planet) or waypoint 1; byte 3 gets 0x80; then it goes home (Classic
    fleets), which replaces waypoint 1. Otherwise it drops its waypoints and its task.

**10. Fleets, last pass**, each of the player's fleets in fleet order, after the colony targets are marked for rating
again:

- **Miners**: on turn 0 they scrap. At a planet worth less than 4 (byte 1, its mark included), the planet the **mining
  score** rates highest from here is appended to its orders, remote mining at warp 6; that planet is marked mined and
  this planet's worth cleared (its mark kept). The mining score of a planet: 0 for this one or with no worth; otherwise
  a draw of 100 (for every such planet): its worth when under 25 or it isn't marked, else 0.
- Fleets with waypoints beyond where they are are done.
- **Colony ships** (slot 1): with no colonists aboard and away from a planet of the player's with 50 hundred people:
  away from a planet of the player's with a starbase, they scrap when the colony design's first part is a starter
  engine (tag `ai_starter_engine`: Settler's Delight, Quick Jump 5, Fuel Mizer) or they cannot go home. Otherwise their
  colony target is taken (no wormhole); at one of the player's planets they load 25 hundred colonists first, and the
  planet to drop from is that one, else home. With a target, they go to colonize it (byte 15 = 4). Without one, the
  nearest planet to the drop planet (not itself) of another player with byte 10 = 1 and byte 3 set whose race takes
  drops gets byte 10 | 0x80, and the fleet goes there at warp 6, unloading all colonists.
- **Freighters** (slots 8-9): on turn 0 they scrap. Without a home the pass ends here (the remaining fleets do
  nothing). Otherwise a run (Classic freight) from their depot, else home.
- **Bombers** (slots 13-14): at a planet of the player's with a starbase they wait until they have B or more bombers and
  E div 2 ships in slots 4-5; at another player's planet they stay unless a warship (Classic fleets) of another player
  is there. Otherwise the planet rated highest by the target score from here (from home in deep space), first sparing
  computer players' planets when they form alliances, gets byte 10 | 0x80 and the fleet goes there at warp 4.
- **Scouts and destroyers** (slots 0, 10-11): with scouts, construction 6 and slot 0's design on the starting scout's
  hull, the fleet scraps. Otherwise hunting and exploring (Classic fleets), with the listed warships and enemies,
  sparing computer players when they form alliances, a wormhole asked for.
- **Mine layers** (slot 12) with no waypoints beyond and no task lay mines for ever (task data 5, 5).

**11. Production** (Classic production) and the last pass.

### Automitrons

The brain `automitrons` (`AI_Automitrons@1090:0400`). After the setup, in this order. Checked against the harness game
auto1 (five Automitrons and an idle human, 80 turns): 79 turns match; the other, 52, is a comet (S25 B38).

**1. Research**, as for Robotoids (starbase designs, the newer station, depots), then plan `automitrons` with no budget
before turn 10 and 20% from then on.

**2. Merging.** After turn 50, slots 2-3 and 9-12 into one fleet, then slot 6; after turn 30, slot 14.

**3. This turn's thresholds**, E and B as for Turindrones. A fleet's **strength** here is its ships in slots 11-12
plus twice those in 9-10 (`AI_Automitrons_HasEscortStrength`).

**4. Retiring** with the age A of Robotoids, one set of obsolete slots: slots 11-12 (the warship design W), 4-5 (the
freighter design F and how many ships of those slots exist), 2-3 (the bomber design) and 9-10 (the battleship design
S). Automitrons never design slots 11-12, so W is a design left there, if any.

**5. Splitting**, after turn 60: ships of obsolete slots split off.

**6. Designs** (`AI_Automitrons_Designs`), in this order; "empty" and "spent" as for Turindrones.

| Slot | When | Template (`automitrons_…`) |
|---|---|---|
| 4 | empty; Pr 5 | `freighter_medium` |
| 5 | empty; Pr 7 | `freighter_super` |
| 14 | empty; Wp 5, El 6, Co 4, Pr 5 | `destroyer`, up to 4 tries, each after a draw of 1 |
| 1 | spent | the design there is deleted; `colony_ship` (a medium freighter with a colonization module) |
| 0 | spent | the design there is deleted; `scout` |
| 6 | empty; Co 4, Pr 5, Bi 6 | `mine_layer` |
| 2 | empty; Wp 8, El 7, Co 6, Pr 7 | `bomber_b17` |
| 3 | empty; Wp 11, El 12, Co 15, Pr 9 | `bomber_b52` |
| 9 | empty; Wp 5, El 6, Co 13, Pr 7 | `battleship_0`-`3`, drawn, up to 5 tries |

Super freighters are an IS hull and the mine layer's parts are SD parts: other races leave those slots empty.

**7. Planets.** P counts the unowned planets as for Turindrones. Then each loaded planet in planet order:

1. Its byte 9 is 1.
2. The player's own with negative habitability: byte 2 is 1.
3. Otherwise, the player's own (or unowned) with a starbase and 1500 hundred people or more: its production is opened
   and, when the queue holds no ship design, ships are added (below), and it is committed.
4. Another player's: byte 10 is 2 with a starbase, else 1; byte 3 is 1 when the player could terraform it to
   habitable.

**Ships at such a planet**, at the end of the queue:

1. F as for Turindrones (K, Pr 5, the draw of 1 in 4).
2. When P is not 0, the colony design has no ships and the turn is after 10: one of slot 1.
3. Mine layers as Turindrones' slot 12, here slot 6.
4. With the bomber design, the first of the player's fleets here with strength E decides: when it has B or more ships
   in slots 2-3, four of the bomber design, and the planet is done.
5. For W (fewer ships than all planets div 12, plus 8) and S (div 24, plus 4) in turn, each with a design: as
   Turindrones' step 6.

**8. Home** is the first of the player's planets in planet order with a starbase (none without).

**9. Fleets, first pass**, every fleet in fleet order. Other players' fleets are listed as enemies, the latest first;
the player's combat fleets (`AI_IsCombatFleet`) as its warships. Then each of the player's freighter fleets and fleets
with colony ships (slot 1) looks at the planet where it is (no waypoints beyond), else its next waypoint's planet; with
none, or when that planet is unowned or the player's, nothing happens. At another player's planet: when byte 3 is set,
the fleet has colonists aboard and the owner's race lacks `ai.no_colonist_drops`, a transport task unloading all
colonists at warp 0 replaces waypoint 0 (when it targets that planet) or waypoint 1, and byte 3 gets 0x80; otherwise
the fleet drops its waypoints and its task. Unlike Turindrones, a starbase does not stop the drop and the fleet does
not go home after it.

**10. Fleets, last pass**, each of the player's fleets in fleet order, after the colony targets are marked for rating
again:

- A fleet with waypoints beyond where it is scraps when the scout design's engine has no ram scoop (tag
  `ai_scoopless_engine`) and the fleet has less than 2 mg of fuel; it does nothing else.
- **Mine layers** (slot 6) with no task lay mines for ever (task data 5, 5).
- **Colony ships** (slot 1): when the colony design is not on the template's hull, they scrap. With no colonists
  aboard and away from a planet of the player's with 200 hundred people: away from a planet of the player's with a
  starbase they scrap when the colony design's engine is one of the two cheapest (tag `ai_earliest_engine`: Settler's
  Delight, Quick Jump 5) or they cannot go home. Otherwise their colony target is taken (no wormhole); at one of the
  player's planets they load 150 hundred colonists; with a target they go to colonize it (byte 15 = 4).
- **Freighters**: without a home the pass ends here. Otherwise a run from their depot, else home.
- **Bombers** (slots 2-3): at a planet of the player's with a starbase they wait until a bomber slot has more than 1
  ship and a battleship slot (9-10) more than 2; at another player's planet they stay unless a combat fleet of another
  player is there. Otherwise as Turindrones' bombers (the target score from where they are, warp 4); in deep space
  from home (S25 B42).
- **Scouts** (slot 0): as the fleets with waypoints, they scrap when the scout design has no ram scoop and they have
  less than 2 mg of fuel; otherwise hunting and exploring (Classic fleets) as for Turindrones. Other fleets (destroyers,
  battleships without bombers) get no orders here.

**11. Production** (Classic production) and the last pass.

### Rototills

The brain `rototills` (`AI_Rototills@1090:1594`). Rototills make no designs of their own (their design step is an empty
function) and keep no fleets merged, split or retired. After the setup, in this order. Checked against the harness game
roto1 (five Rototills and an idle human, 80 turns): all 80 turns match.

**1. Research**, as for Robotoids (starbase designs, the newer station, depots), with no plan: the lowest field
(Classic research, every step done), with no budget before turn 20 and 15% from then on.

**2. Planets.** P counts the unowned planets as for Turindrones. Then each loaded planet in planet order:

1. Its byte 9 is 1.
2. Unowned and scanned: byte 1 is its mining worth, as for Turindrones.
3. The player's own with negative habitability: byte 2 is 1.
4. Otherwise, the player's own (or unowned) with a starbase and 1000 hundred people or more: its production is opened.
   When the queue holds no starbase design other than the first starbase slot's: on turn 0 two scouts are added and
   the queue is not given (so nothing changes); later, once a turn over all planets, one colony ship (slot 1) is added
   when the colony design has no ships or has fewer than P − 1. It is committed.
5. Another player's: bytes 10 and 3 as for Automitrons.

**3. Home** is the first of the player's planets in planet order with a starbase (none without).

**4. Fleets, first pass**, every fleet in fleet order. Other players' fleets are listed as enemies, the latest first;
the player's fleets with warship hulls as its warships. Then, for the player's fleets:

- With miners (slots 7-8): in deep space, the planet of the next waypoint is marked mined (byte 1 | 0x80); at a
  planet someone owns, the fleet drops its waypoints and its task; at an unowned planet, that planet is marked mined.
- Otherwise freighter fleets and fleets with colony ships drop their people or stop as for Automitrons.

**5. Fleets, last pass**, each of the player's fleets in fleet order, after the colony targets are marked for rating
again:

- **Miners** (slots 7-8) at a planet worth less than 4 move on as Turindrones' miners (no scrapping on turn 0).
- Fleets with waypoints beyond where they are are done.
- **Colony ships** (slot 1): with no colonists aboard and away from a planet of the player's with 50 hundred people,
  as Automitrons' colony ships. Otherwise their colony target is taken, with a wormhole asked for unless the colony
  design's engine is one of the two cheapest (tag `ai_earliest_engine`); at one of the player's planets they load 25
  hundred colonists; with a target they go to colonize it (byte 15 = 4), else into the wormhole when one was given.
- **Freighters**: without a home the pass ends here. Otherwise a run from their depot, else home.
- **Bombers** (slots 13-14): at a planet of the player's with a starbase they wait until a bomber slot has more than
  1 ship; otherwise as Automitrons' bombers (in deep space from home, S25 B42).
- **Scouts** (slot 0): when the scout design's engine is the starting scout's (tag `ai_starting_scout_engine`, Quick
  Jump 5) and the fleet has less than 2 mg of fuel, they scrap; otherwise hunting and exploring as for Turindrones.

**6. Production** (Classic production) and the last pass.

### Cybertrons

The brain `cybertrons` (`AI_Cybertrons@10a0:0000`). Cybertrons keep per-planet state in the working memory: a lasting
word **A** per planet (word 1 + planet id) and a word **B** per planet after them (word planets + 1 + id), cleared every
turn; the memory's use count covers the A words only. With an empty memory (use count 2) the whole memory is zeroed
and the use count set to (planets + 1) x 2. Checked against the harness game cyber1 (three Cybertrons, a Robotoids,
a Rototills and an idle human, 80 turns; the definition file can only pick personalities 1-4, so the three came from
a random pick), with the compat formulas for B44-B46 and B48: 75 turns match; 27, 58 and 59 are comets (S25 B38),
70 and 71 damage on ship moves (B32).

A: bits 0-2 the packet sector, 0x08 a colony ship queued, 0x10 a sector packet thrown, 0x60 a packet timer (one less
each turn), 0x80 a long throw under way. B: 0x01 no colony target, 0x06 people unloaded (a count to 3), 0x18
transports heading there (a count to 3), 0x20 few guards, 0x40 guarded; in the high byte, bits 1, 2 and 4 short of
ironium, boranium and germanium.

**1. Research**, as for Robotoids (starbase designs, the newer station; no depots for Cybertrons), then plan
`cybertrons` (42 steps) with a budget of 17%.

**2. Designs** (`AI_Cybertrons_Designs`), in this order. A *pool draw* of n over templates k0... tries up to n times,
each time a draw of the remaining count (n, n − 1, ... 1) picking template k0 + draw; it stops at the first design
made. Templates are `cybertrons_…`: `destroyer_0`-`9`, `privateer_0`/`1`, `scout` (a mine-laying frigate),
`b52_0`/`1`, `battleship_flag`, `nubian_flag`, `cruiser_0`-`8`, `battleship_0`-`6`, `nubian_0`-`2`.

1. A scout design not on a frigate with no ships left is deleted after turn 5 at levels 2 and 3; an empty slot 0 gets
   `scout`.
2. Slot 4, empty, after turn 30: `destroyer_0` up to turn 75, then (or when that fails) a pool draw of 5 from
   `destroyer_0`. Slot 5, empty, when slot 4's design is more than 20 turns old: likewise from `destroyer_5`.
3. Slot 2, empty, after turn 20: `privateer_0`. Slot 3, empty, when slot 2's design is more than 20 turns old:
   `privateer_1`.
4. The warship groups, slots 6-9 and 10-13, each when its first slot is empty and (group 6-9) after turn 40 or
   (group 10-13) slot 6's design is more than 30 turns old. The slot s starts at first + 2: a pool draw of 3 from
   `nubian_0`, of 4 from `battleship_3` and of 3 from `battleship_0`, each moving s down one when it makes a design.
   Then, while s is not below the first slot: cruisers, the first time a pool draw of 3 x (first − s + 3) from
   `cruiser_` (9 − that), later of 3 from `cruiser_0` (at the first slot) or `cruiser_3`; s moves down after each.
   Last, slot first + 3 gets the first of `nubian_flag`, `battleship_flag`, `b52_1`, `b52_0` that can be made.
5. Slots 14 and 15, each when empty and (14) after turn 30 or (15) slot 14's design is more than 20 turns old: a pool
   draw of 7 from `battleship_0`, failing that of 9 from `cruiser_0`, failing that of 10 from `destroyer_0`.

**3. Merging**, every turn: slot 0; 4-5; 14-15; 6-9; 10-13.

**4. This turn's numbers.** The wanted strength V is 1, after turn 50 (turn − 50) div 10 + 1, and after turn 100 plus
((turn − 100) div 10) x (turn div 100). E and B as for Turindrones.

**5. Retiring**, with age A 50 before turn 120, 70 before 200, 100 before 400, else 300: `AI_FindDesignForHulls`
for slots 4-5 (the destroyer D), 14-15 (the heavy design H) and 2-3 (the transport T and its ships), each newest kept
off the obsolete list (S25 B47). Then each group whose first design is older than A: from its top slot down, a design
with no ships is deleted (the first slot's only when no slot above it kept a design), the others marked obsolete.
The newest group G is the one whose first slot was designed last. After turn 80 obsolete ships split off, then slot 0,
slot 1, and slots 2-3 each split off on their own.

**6. Planets** (loaded, planet order): A's timer counts down; the player's starbase planets set B's short bits for
minerals under 10 (forts, slots 1, 3, 6, 8) or 1000 (stations); other players' planets get byte 10 = population
estimate div 250 + 1 (at most 6), plus 1 with a starbase, and byte 9 = 1.

**7. Fleets, first pass**, every fleet in fleet order; before each the colony targets are rated while they are not yet
(no wormhole). Other players' fleets are listed as enemies, the latest first. The player's fleets: with ships in
slots 14-15 they count as guards (Ng) and nothing else. Otherwise scouts count (fleets Ns, ships Ss). With ships in
slots 4-13 the fleet is listed as a warship; when the counter c (below) is under 6, or it has no planet waypoint next
and is in deep space, it counts as idle (Ni); else its planet (the next waypoint's, else where it is) gets byte 10's
mark when byte 10 is set, and it counts as busy (Nb). Without warships, a fleet with transports (slots 2-3), colonists
aboard and a planet waypoint next counts one more transport heading there (B 0x18, S25 B44). The counter c is B,
except that retiring group 6-9 this turn leaves it at 5, and group 10-13 at 9 (the original's leftover loop counter).

**8. Fleets, last pass**, each of the player's fleets in fleet order:

- A fleet with no ships outside obsolete slots: at one of the player's planets with a starbase, or without one on a
  draw of 1 in 5, it scraps. Otherwise, unless it is in deep space with somewhere to go, it goes home; when it cannot,
  it carries on below.
- Guards (slots 14-15) at a planet: the ships of designs newer than A − 10 turns, when any, mark the planet guarded
  (B 0x40), and few (0x20) when under 2V.
- Warships (slots 4-13): without destroyers (slot 4) they invade (below), then with no waypoints beyond, on a draw
  of 75 in 100, join the nearest fleet of their group before them (`AI_Explore` within 100 light years, 200 on a draw
  of 1 in 2). With destroyers: when 2 x destroyers reach V or the fleet has somewhere to go, `AI_DirectWarship`; then
  likewise join destroyers (slots 4-5).
- Fleets with no waypoints beyond: scouts before turn 6 scrap. Colony ships take their colony target (no wormhole);
  with none, the planet of waypoint 0 gets B 0x01; with one, they load 250 hundred colonists at one of the player's
  planets and go to colonize it (byte 15 = 4 for the new waypoint). Transports take battle plan 4 and the colonist
  transport (below). Scouts, after turn 40 with no waypoints beyond: when Ns reaches 56, or from 41 on a draw of 2 in 3,
  they join a scout fleet within 72 (108) light years, and stop there when they do; otherwise, with more than 6 ships
  on a draw of 1 in 5, a random planet within 105 light years that is not this one (`AI_PickRandomTarget`, starbases
  avoided) gets them, laying mines, at warp 4; otherwise they lay mines where they are for ever (task data 5, 5).

**Colonist transport** (`AI_Cybertrons_ColonistTransport`): in deep space the fleet heads for the planet nearest it.
At one of the player's planets it loads 1000 hundred colonists when the planet has more than 2000, else unloads 1000.
At another player's planet without a starbase whose owner takes drops it drops its people (as Turindrones, replacing
waypoint 0 or 1) and goes home. At an unowned planet or another kind it counts as loaded with colonists aboard. Loaded,
it heads for the nearest of the player's planets within 400 light years with under 200 hundred people and no transport
heading there, else the nearest whose people plus 210 per transport heading there stay under 1000 (fewer than 3
transports); with neither, at one of the player's planets it unloads 1000 and counts B 0x06 up; with one, that
planet's B 0x18 counts up. Empty, it heads for the nearest of the player's starbase planets with over 2200 hundred
people. It goes at its default warp, eased.

**Invasion** (`AI_Cybertrons_Invade`) is Robotoids' with these differences: strength is ships in slots 6, 7, 10, 11
plus twice those in 8 and 12, flagships those in 9 and 13; any planet of the player's is a gathering place (no starbase
needed) and no troops are loaded; at another player's planet the fleet stays; in deep space it seeks within 450 light
years. It uses Cybertrons' own E and B (S25 B43).

**9. Production**, each of the player's planets in the own-planet order, skipping a planet whose queue costs more of
something than its output. Growth g is people x the race's growth rate.

1. Habitability under 10: terraforming x (spare resources div 70 + 1), and the planet is done.
2. Habitability under what terraforming could reach, with over 70 resources to spare: one terraforming step.
3. With a station (not a fort):
   - A colony ship when (A 0x08 is clear or g > 5500), B 0x01 is clear and the colony design has fewer than 40 ships;
     A 0x08 is set (cleared otherwise); a second when g > 15000 before turn 100.
   - T when the planet has over 2000 hundred people, slot 2 has a design, T's ships are fewer than 50, B's unload count
     is 0, and an underfilled colony (as the transport's) lies within reach.
   - With a frigate scout design, on a draw of 1 in 4 while Ss is under 10000: four scouts, as Turindrones' mine
     layers (10, 17, a draw of 1 in 10, then of 2n + 1).
   - The guard choice: H when B 0x20, else none; when none, not guarded and Ng under 40: H on a draw of 50 in 100 with
     another player's planet within 300 light years, else of 10 in 100.
   - The economy (`AI_Cybertrons_Economy`), with D unless Ni passed 120 and G unless Nb passed 250: a draw of 100
     (kept), then, with fewer than 100 mines or factories of room, on a draw of 90 in 100 nothing, else of 60. Then
     with G and the kept draw over 50: two each of G's first two slots, one of the third on a draw of 75 in 100 and
     of the fourth on a draw of 50 in 100 (Nb + 1); with the guard and the kept draw over 25: one guard (Ng + 1);
     with D: one D (Ni + 1).

**10. Production pass** (Classic production) with the newer station, then **packets**, then the last pass.

**Packets** (`AI_Cybertrons_PlanPackets`), each of the player's starbase planets in the own-planet order. Output and
queue cost are this year's estimates; R is the output's resources.

1. *Feed* (no long throw, a fort with over 700 of some mineral): with n = (R div 2) div 5 of at least 7, the nearest of
   the player's starbase planets with no timer, short of a mineral this planet has over 700 of, within 3.5 x s²
   light years where s is the slower of the two drivers (each its speed plus 1 for a matched pair). Each mineral the
   target has under 10 (fort) or 1000 and this planet over 700: min(n, 7) packets first in the queue, n less those,
   the short bit cleared. The driver goes to the target at s.
2. *Attack* (no long throw; level 2-3, or level 1 on a draw of 1 in 3): S = the minerals left after the queue less 210,
   M = min((((R div 2) − 5) div 5) x 70, S), kept in memory word 2 x planets + 1. With S of at least 151, the nearest
   other player's planet with no timer whose owner takes drops, without a starbase or with a space dock, whose catcher
   speed c (its driver, or 0) differs from the throw speed v (this driver's speed + 3), within 2.5 x v² light years,
   with a population estimate p, where the packets needed K = (min(4p + 100, 1000) x 16000) div h (one less when exact;
   h = ((v² − c²) x (95 − defense class)) in 16 bits) are at most M x 0.875^(d / v²) with a matched pair, else 0.75^,
   truncated (d the distance). Then min(K, M) x (8/7 or 4/3)^(d / v²) kilograms go, 70 a packet, each to the mineral
   with the most left, first in the queue; the driver goes to the target at v; the target's timer is set; a throw
   longer than v² sets the long-throw bit, and the sector bit clears.
3. *Sector*: a planet with the sector bit and no long throw only clears it. Otherwise, without a long throw, a draw of
   7 gives the new sector (one more when it equals the old) and `AI_ChoosePacketTarget` a target; none ends here. With
   a long throw the target is the driver's (S25 B48). When the target's record has no timer and this planet has 170 of
   a mineral to spare after the queue (the one with the most), one packet of it goes first in the queue, the target's
   timer is set (S25 B45), and the sector bit is set when no long throw is under way; else the sector bit clears. The
   driver goes to v (to the target, unless a long throw was under way, which then ends).

**Choosing a sector target** (`AI_ChoosePacketTarget`): on the map W light years wide (origin 1000, 1000), from the
planet in the sector's direction (0 east, then counterclockwise in eighths, 2 toward y 0) to the map edge; then along
the edge by a draw of (3W div 10 − 1) less (3W div 20 − 1) (what passes a corner turns onto the other edge), and in from
the edge by a draw of v²; the planet nearest that point (lowest id on ties), unless it is the player's own or nearer
than v² light years (S25 B46).

## Randomness

Computer players draw from the classic stream, in player order, before any draw of turn generation (S01, S02). The
draws of each personality are listed with its part of this spec. The idle and baseline brains draw nothing.
A classic personality's turn starts with the setup's shuffle: n − 1 draws for a player with n planets. The
toolkit draws where the sections above say so, in the order the personality calls it. Robotoids, Turindrones, Automitrons,
Rototills and Cybertrons draw in the order of their steps above.

## Edge cases

- A personality key with no content definition, or a definition naming a brain the game doesn't have: the player
  gives no orders this turn, and the host is told.
- Orders a brain gives that the rules reject are rejected as for a human (S11), and the rest still apply.
- An eliminated computer player does not play.

## Known bugs

- B42 (S25): Automitrons and Rototills bombers stopped in deep space rate targets from a planet pointer that holds
  no planet (past the end of the list, or null), unless a freighter earlier in the fleet list found home; ours rate
  from home.
- B43-B48 (S25): Cybertrons' thresholds, fleet marks, packet records, sector reach, retirement and long throws
  (see Cybertrons).

## Worked examples

`tiny3ai` (harness): player 0 human, players 1 and 2 computer players. With player 0's orders given, the step adds
order sets for players 1 and 2, in that order. With the baseline brain and no human orders, both computer players
have at least 4 planets after 25 turns, with no order rejected. In `medium_clump` (288 planets, 3 computer players)
they hold 19-27 planets after 100 turns, and from about year 2480 their war fleets bomb out the idle human player's
homeworld.

## Mod hooks

- Content type `ai_personality` (above).
- Content type `ai_hull_class` (the classic personalities' hull classes).
- Content types `ai_part_class`, `ai_design_template`, `ai_design_names` and `ai_research_plan` (Classic designs and
  research).
- Trait parameters `production.no_planetary_scanner` (AR), `ai.no_packets_at_starbases` (PP) and
  `ai.no_colonist_drops` (AR).
- Brains are built in for now; script mods will be able to add brains (M14).

## Open questions

1. The order of the original's draws inside each personality, which golden AI games check (Robotoids: big1;
   Turindrones: turin1; Automitrons: auto1; Rototills: roto1; Cybertrons: cyber1). turin1 turn 77 is unexplained: the fleets' orders and moves match, but mining, a battle's
   token order and the wormholes come out differently, and no single draw added or removed, in the AI or in the
   turn up to the battle, makes it match.
2. What exactly the inactive personality does each turn (`AI_InactiveHuman`): research plan, colony ships and
   scouts going home or settling.
