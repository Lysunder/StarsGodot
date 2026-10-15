# S22 Computer players (AI)

Status: draft (2026-10-14), first part: the AI step and personalities as data; second part: our own baseline
brain (2026-10-15: expansion, docks, terraforming, defenses, warships, bombers). The original personalities' own
play comes in later parts.
References: `RunComputerPlayers@1018:39f8`, `AI_PlayTurn@1080:0000`, `AI_InactiveHuman@1090:0000`,
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

A brain asking for parameter *k* gets the level's value if the level map has *k*, else the personality's `params`
value, else the brain's own default. Personality and difficulty are therefore data; a mod can add a personality
for an existing brain, or change one's parameters, without code.

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
6. **War fleets** (only warships and bombers), in fleet order, without orders: away from home, when the planet
   where they are is not (as known) another player's, back to the homeworld (or the nearest planet with people);
   at home, every other idle war fleet there merges into it, and once it has `attack_ships` (5) ships it goes to
   the planet known to be another player's that is nearest home and within its reach. Battles there follow the
   default battle plan, and its bombers bomb a planet left without a starbase (S17); a planet bombed out becomes
   unowned, a target for colony ships.
7. **Queues**, the player's planets in planet order. With at least `colony_min_population` (150, units of 100
   colonists) people and the minerals for one ship on its surface: one colony ship while the player's colony ships
   (in flight, queued elsewhere and planned this turn) are fewer than `colony_ships` (2) plus one per 3 planets
   owned and some known planet is worth settling; one scout while its scouts are fewer than `scouts` (3) plus one per
   5 planets and some planet is still unscanned. From year index `war_turn` (40), with `warship_min_population`
   (300) people and the minerals: one warship while its warships are fewer than `warships` (3) plus one per 2
   planets, one bomber while its bombers are fewer than `bombers` (2) plus one per 3 planets. A dock on a planet
   without a starbase, with `dock_min_population` (300) people and the minerals, at least `dock_spacing` (200)
   light-years from the player's docks and the docks queued before it this turn. Then auto factories and auto
   mines (200 each), auto maximum terraforming (200) when the planet's habitability is below 100%, and auto
   defenses (200) with `defense_min_population` (50) people. The order is sent only when the queue differs (items,
   designs, starbase flags and counts).

Not yet: mineral transport, invasion with troops, defending against attacks, alliances.

## Randomness

Computer players draw from the classic stream, in player order, before any draw of turn generation (S01, S02). The
draws of each personality are listed with its part of this spec. The idle and baseline brains draw nothing.

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
- Brains are built in for now; script mods will be able to add brains (M14).

## Open questions

1. The order of the original's draws inside each personality (later parts), which golden AI games will check.
2. What exactly the inactive personality does each turn (`AI_InactiveHuman`): research plan, colony ships and
   scouts going home or settling.
