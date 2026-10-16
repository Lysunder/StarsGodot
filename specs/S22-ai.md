# S22 Computer players (AI)

Status: draft (2026-10-14), first part: the AI step and personalities as data; second part: our own baseline
brain (2026-10-15: expansion, docks, terraforming, defenses, warships, bombers, defending, invasion, mineral
hauling); third part (2026-10-15, started): the original's personalities, beginning with the world they play in. The original personalities' own
play comes in later parts.
References: `RunComputerPlayers@1018:39f8`, `AI_PlayTurn@1080:0000`, `AI_InactiveHuman@1090:0000`,
`Designs_ComputeRatings@1030:09ae`, `AI_ScanFleets@1088:40ba`, `AI_InitScale@1088:5e0e`,
`AI_BuildOwnPlanetList@1088:60b2`, `DecodePlanetBlock@1068:1f0c`,
`CheckTurnFile` (turn file check before a computer player plays), personalities `AI_Robotoids`, `AI_Turindrones`,
`AI_Automitrons`, `AI_Rototills`, `AI_Cybertrons`, `AI_Macinti` (segments 1080-10a0), toolkit in segment 1088.

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
for inactive humans (`inactive`, the original's number 7). Their play is specified in later parts of this spec.
Until a personality's own brain exists it uses our **baseline** brain (below); the inactive personality uses the
**idle** brain, which gives no orders.

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
   And a 16-byte record per planet (`planet_info`), all 0.
2. **Design ratings** (`Designs_ComputeRatings`): every loaded ship design's rating (S20 `Design_Evaluate`, the
   formula `score.ship_rating`).
3. **Bombers in orbit** (`AI_ScanFleets`): for each other player's fleet in orbit of one of the player's planets
   with ships on a hull of class `ai_hull_class.bomber` (the original's hulls 16-19), byte 8 of that planet's record
   is 1.
4. **Minefield radii** (`AI_InitScale`): each loaded minefield's radius squared, trunc(sqrt(mines))².
5. **The player's planets** (`AI_BuildOwnPlanetList`): in planet order, then shuffled: for each place i from the
   first to the last but one, swap it with place i + `random(n − i)` (n planets). These are the turn's first draws.
   (In the tutorial the shuffle is skipped; we have no tutorial game.)

The world also keeps the packets and salvage the player sees this turn (and its own), and the wormholes it sees or
has seen; and for each planet the turn the player last saw it (this turn for its own).

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

Personality checks below name the personality: Robotoids, Turindrones, Automitrons, Rototills, Cybertrons, Macinti
(the original's 0-5).

### Classic designs (`AI_OutfitDesign`, `AI_CreateDesign`, `AI_FindDesignForHulls`)

A **template** (`ai_design_template`) is a hull and one part class per hull slot. A **part class**
(`ai_part_class`) is a list of groups of parts, each group best first. The best part of a class is the first part
the player can use (S04 tech and traits, Mystery Trader parts only once owned), searching the groups in order.

From a template, every slot holds the best part of its class, as many as the slot allows. When a slot's class has no
part the player can use, there is no design. The hull itself is not checked. The original would store a design with
a hull the race may not use; our design order refuses it.

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
such fleet at the same place. At most 32 fleets are kept to merge into; the rest wait for another pass. A merged fleet
leaves the list, so the fleet after it is passed over.

**Splitting** (`AI_SplitFleets(slots)`): while the player has fewer than 501 fleets, the first fleet with ships both
in those slots and in others splits them off; cargo and fuel follow the ships (S11).

**Safe speeds** (`AI_AvoidMinefieldsAll`, `AI_SetMinefieldSafeWarp`). Each of the player's fleets with somewhere to go
gets its next speed:

- Inside a known minefield of another player (not a speed bump, by the setup's radius squared): heavy fields warp 6;
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
- 4, claimed: another of the player's fleets heads there (for Robotoids and Macinti, to colonize).

The other personalities mark only once a turn. The target is the nearest free planet. For a fleet at one of the
player's planets before turn 120, a wormhole may be taken instead (`AI_PickWeighted`):

1. A wormhole is in reach within twice the planet's distance. The original squares the distance in 16 bits, so a
   wormhole whose square wraps past 32767 is always in reach.
2. Its score is 50 when unseen and farther than the planet, 90 when unseen and nearer, and 70 less 10 per percent of
   jump chance when seen (S18).
3. The best (the nearer of equals) is taken when a draw of 100 falls under its score.

### Classic freight

**Cargo** moves as `cargo_transfer` orders, held to what the giver has and the taker can hold (`AI_MoveCargo`).

**Colony ships** (`AI_CountColonyShips`). Easy players count only on even turns. Before turn 30 the answer is
"build". Later it is "build" when all of these hold:

- the colony fleets number at most universe size index x 20 + 10;
- they and the player's planets are at most four fifths of all planets;
- colony designs built, less those two, lie from 0 to 25; or there are fewer than 5 colony fleets and a draw of 1 in
  2 says so.

The original adds the planets of every player it has full data on, which in a turn file is the player alone.

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
1000, else (people - 400)/100 %; none when the target has 1000 or two thirds of home's. Turindrones' own way comes
with Turindrones.

**Depots** (`AI_PlanFreighterDepots`), kept in the memory. A record is a planet, a count of fleets and up to 8 fleet id
words (owner << 9 | number), 10 words in all. There are at most 64 records, and the byte count is records x 20 + 4.
Not Cybertrons or Macinti, from turn 20:

1. Records of planets the player lost are dropped.
2. The player's planets with a starbase (shuffled order) become depots.
3. Then rich planets: 80 hundred people; concentration squared x 4 plus surface over the three minerals 7000 or more;
   20 mines and 20 factories. Robotoids skip planets within 50 light years of another depot.
4. Each freighter not yet in a record joins the nearest depot with room.
5. Each depot with fewer than 4 freighters takes the last freighter of the first depot with 2 more than it.

## Randomness

Computer players draw from the classic stream, in player order, before any draw of turn generation (S01, S02). The
draws of each personality are listed with its part of this spec. The idle and baseline brains draw nothing.
A classic personality's turn starts with the setup's shuffle: n − 1 draws for a player with n planets. The
toolkit draws where the sections above say so, in the order the personality calls it.

## Edge cases

- A personality key with no content definition, or a definition naming a brain the game doesn't have: the player
  gives no orders this turn, and the host is told.
- Orders a brain gives that the rules reject are rejected as for a human (S11), and the rest still apply.
- An eliminated computer player does not play.

## Known bugs

None yet.

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
- Trait parameters `production.no_planetary_scanner` (AR) and `ai.no_packets_at_starbases` (PP).
- Brains are built in for now; script mods will be able to add brains (M14).

## Open questions

1. The order of the original's draws inside each personality (later parts), which golden AI games will check.
2. What exactly the inactive personality does each turn (`AI_InactiveHuman`): research plan, colony ships and
   scouts going home or settling.
