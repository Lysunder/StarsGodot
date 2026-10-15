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

1. A working memory of 4096 16-bit words, all 0 except the first, 2; and a 16-byte record per planet, all 0.
2. **Design ratings** (`Designs_ComputeRatings`): every loaded ship design's rating (S20 `Design_Evaluate`, the
   formula `score.ship_rating`).
3. **Bombers in orbit** (`AI_ScanFleets`): for each other player's fleet in orbit of one of the player's planets
   with ships on a hull of class `ai_hull_class.bomber` (the original's hulls 16-19), byte 8 of that planet's record
   is 1.
4. **Minefield radii** (`AI_InitScale`): each loaded minefield's radius squared, trunc(sqrt(mines))².
5. **The player's planets** (`AI_BuildOwnPlanetList`): in planet order, then shuffled: for each place i from the
   first to the last but one, swap it with place i + `random(n − i)` (n planets). These are the turn's first draws.
   (In the tutorial the shuffle is skipped; we have no tutorial game.)

**Hull classes.** Where the original's personalities compare hull numbers, the hulls of each class are content
(`ai_hull_class`, a list of hulls), so a mod's hull can join a class. So far: `ai_hull_class.bomber` (mini bomber,
B-17, stealth bomber, B-52).

## Randomness

Computer players draw from the classic stream, in player order, before any draw of turn generation (S01, S02). The
draws of each personality are listed with its part of this spec. The idle and baseline brains draw nothing.
A classic personality's turn starts with the setup's shuffle: n − 1 draws for a player with n planets.

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
- Brains are built in for now; script mods will be able to add brains (M14).

## Open questions

1. The order of the original's draws inside each personality (later parts), which golden AI games will check.
2. What exactly the inactive personality does each turn (`AI_InactiveHuman`): research plan, colony ships and
   scouts going home or settling.
