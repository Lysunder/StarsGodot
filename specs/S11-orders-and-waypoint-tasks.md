# S11 Orders and waypoint tasks

Status: draft (2026-09-30), second pass. Structure, colonize, scrap, remote mining, mine laying and task completion
read from the code; transport amounts partly (see "Open questions"). Order application started (2026-10-03): the
production queue, research and planet orders are implemented (`core/turn/order_rules.gd`) and match the original in
a harness game with orders given in the client. Waypoint orders, transport at the owner's planet, colonize and
colonizing empty planets added (2026-10-04, `core/rules/waypoint_tasks.gd`), matching the original in terra1 turns
0-2. Fleet orders (split, ship moves, merge, repeat, rename, battle plan) added from the code (2026-10-04,
`core/rules/fleet_orders.gd`); ship moves, split, repeat and battle plan match the original in terra1 turn 28
(the client's merge button sends ship moves); merge orders (block 37) and damage not seen yet. Merge, scrap (at a
planet) and transfer tasks added (2026-10-04), matching the original in terra1 turn 29. Player defaults (default queue
for new colonies) added (2026-10-04), matching the original in terra1 turns 30-33; the Alternate Reality colony
starbase and the trait skips are not seen yet. Transport with every partner (2026-10-04): unloading minerals and an invasion at
another player's planet match the original in terra1 turns 36-40 (ground combat itself is S17); the refusals,
fleet partners and fix B26 have unit tests only. Design orders (block 27) added (2026-10-04), matching the original in
terra1 turn 42 (create, replace, delete); deleting a design with ships and fix B19 have unit tests only. Fill, wait,
set amount and set waypoint actions added (2026-10-04); fill, wait and set amount (unloading) match the original in
terra1 turn 45; the waiting cases and set waypoint have unit tests only.
References: `ApplyLoggedOrders@1040:649a`, `ApplyOrderBlock@1040:651e`, `DoWaypointTasks@10a8:0e92`,
`DoWaypointTaskPass@10a8:3ec6`, `CreateFleet@1030:1f2e`, `TransferCargo@1048:3aec`, `MergeFleets@1048:78b6`,
`RecordTransfer@10b0:2fda`, `Fleet_FollowRoute@1078:13f8`, `Fleet_SetDefaultOrders@1078:17c2`,
`Fleet_MiningRate@1078:193e`, `Fleet_MineLayRate@1078:1aea`, `ProcessCargoTransferQueue@10b0:1c2c`.

## Summary

Players don't change the game state directly: they send orders, which the host applies at the start of the next
turn (S02 phase 2), and they give fleets waypoints with tasks, which the host carries out in four task passes during
the turn: two at waypoint 0 (where the fleet starts) before movement, two at waypoint 1 (where it arrives) after
movement and battles.

Our order file format is our own (D6). This spec defines what each order means and how the host validates it.

## Data used

- Fleet: owner, fleet number, location (planet or deep space), ships per design, cargo (ironium, boranium,
  germanium, colonists, fuel), battle plan, waypoints.
- Waypoint: position, target (planet, fleet, deep space or space object), warp, task, and task data (for transport:
  one action and amount per cargo type).
- The global fleet list.

## Fleet order

The game keeps its fleet list sorted by owner (player index), then by fleet number. A new fleet takes the lowest
free number for its owner and is inserted at its sorted place. **Every per-fleet step in the turn uses this order**:
all of player 0's fleets by number, then player 1's, and so on. No random player order was found in the task passes
(see S02, which records the community belief that load tasks use a random player order).

## Orders

Applied at the start of turn generation, one player after another in player order, each player's orders in the
order given. Each order is validated against the state at that moment; an invalid order is rejected with a message
and has no effect (the original trusted its client more; see "Validation").

| Order | Effect |
|---|---|
| Cargo transfer by hand | Moves cargo between a fleet and a planet, another fleet, or deep space (jettison) at once, before any waypoint task. |
| Waypoint add / delete / change task | Edits a fleet's waypoint list. |
| Repeat orders | Turns the fleet's waypoint list into a loop. |
| Move ships between fleets | Moves ships from one of the player's fleets to another at the same place. |
| Split fleet / merge fleets | Creates a new fleet from some ships, or merges fleets at the same place. |
| Design change | Creates, changes or deletes a ship or starbase design (S09 for designs being built). |
| Production queue change | Replaces a planet's production queue (S09). |
| Battle plan / set fleet battle plan | Edits a battle plan, or picks one for a fleet (S16). |
| Research change | Research field, next field and research spending (S05). |
| Planet change | Planet settings such as its route destination and "contribute only leftover resources" (S09). |
| Player relations | Friend, neutral or enemy toward each other player (S16). |
| Rename fleet | Cosmetic. |

The original also had an order block for passwords, which is file mechanics, not a game rule. Its block 46 (named
"save and submit" in the decompilation notes) carries the player's defaults for new colonies (`player_defaults`
below).

### Order files (our format)

One file per player and turn: a JSON object in canonical form with `format` `"starsgodot-orders"`,
`format_version` 1, `game_version`, `player`, `turn` (the turn the orders were given in) and `orders`, a list of
objects each with a `type` and that type's fields. The file is checked for shape when read; each order is checked
against the state when the turn is generated.

### Orders implemented so far

- **`production_queue`** `{planet, items}`: the planet must be the player's; every item must be a known production
  item or one of the player's designs, with count 0–1023 and progress 0–100, or the whole order is rejected. The
  list replaces the planet's queue (an empty list clears it). Progress: an item with progress keeps it only if the
  old queue has an item of the same kind (same production item, or same design slot and starbase flag) with
  progress; that old item's progress is then used up (cleared), so each old item matches once; otherwise the new
  item's progress becomes 0. (The original keeps the progress value the order carries when it matches.)
- **`research`** `{percent, field, next}`: percent 0–100, field 0–5, next 0–7 (S05: 6 same field, 7 lowest field).
- **`planet_settings`** `{planet, leftover_to_research, mass_driver_target, mass_driver_warp, route}`: the planet
  must be the player's; destinations are planet ids or −1. The mass driver settings are kept only on a planet with
  a starbase (the original stores them with the starbase); the route and the leftover setting always.

- **`waypoint_add`** `{owner, fleet, index, waypoint}`: inserts the waypoint at index (0 … count).
  **`waypoint_change`** `{owner, fleet, index, waypoint}`: replaces the waypoint at index (below count).
  **`waypoint_delete`** `{owner, fleet, index, count}`: removes 1 or 2 waypoints from index. The fleet must be the
  player's (the original does not check this). An added or changed waypoint is never frozen. A waypoint with a task
  but without task data gets the task's empty data (the original fills missing words with zero).

References for these: `ApplyOrderBlock@1040:651e` (blocks 3, 4, 5, 29, 34, 35).

### Fleet orders

Every fleet order names a fleet of the ordering player (`owner` must be the player); the original checks only that
the fleets of a ship move have the same owner, and trusts the client for the rest.

- **`fleet_split`** `{owner, fleet}`: creates an empty fleet for the player with the lowest free number (rejected
  at the fleet limit), at the same place (planet or deep space) as the given fleet, with a copy of its waypoints,
  its repeat setting and its battle plan; no name, no ships, no cargo. The client always follows it with a ship move
  into the new fleet (an empty fleet left behind stays empty). `CloneFleetShell@1030:213c`, `CreateFleet@1030:1f2e`.
- **`fleet_move_ships`** `{owner, fleet, other, ships}`: `ships` lists `{design, count}` (design slot); a positive count
  moves that many ships of the design from `other` to `fleet`, a negative one from `fleet` to `other`. Both fleets
  must be the player's and at the same position. Each count is limited to what the giving fleet has (the original
  limits only the giving side, so a forged count would create ships). Then, per fleet, cargo, fuel and damage
  follow the ships (below), and a fleet left without ships is deleted. Block 23, `Fleets_RedistributeCargo@1048:6c1c`.
- **`fleet_merge`** `{owner, fleet, fleets}`: the listed fleets join `fleet` (the target), in list order. Fleets
  that are not the player's or not at the target's position are skipped (the original merges any listed fleet).
  An empty list means every other fleet of the player at the target's position, in fleet order. For each merged
  fleet its ships per design and its cargo are added to the target, and the fleet is deleted; the target keeps its
  waypoints, name, battle plan and repeat setting. Damage is combined (below). Block 37, `MergeFleetList@1030:2230`.
- **`fleet_repeat`** `{owner, fleet, repeat}`: turns repeating orders on or off. Block 10.
- **`fleet_rename`** `{owner, fleet, name}`: up to 31 characters; "" restores the default name. Block 44.
- **`fleet_battle_plan`** `{owner, fleet, plan}`: an index into the player's battle plans. Block 42.
- **`minefield_detonate`** `{minefield, detonate}`: the player's minefield (by number) detonates every year from
  now on (S13 "Detonation"), or stops. Block 43 (the field's id word, then the setting). The original accepts it for
  any field; we accept it only for a standard field of a race with the `minefield.detonate` trait parameter (Space
  Demolition), the only case its client offers.
- **`player_relations`** `{relations}`: the player's relation toward each player, one entry per player
  ("neutral", "friend" or "enemy"; the player's own entry is kept as given). Block 38 (one byte per player).
- **`message_filters`** `{filtered}`: replaces the list of message types the player has filtered out (S21
  "Filters"); each must be a message type; stored once each, sorted. Block 33 (a bitmap of message numbers).
- **`cargo_transfer`** `{owner, fleet, other, amounts}`: a transfer by hand, applied at once with the orders (before
  any waypoint task). `other` is `{"planet": id}` or `{"fleet": number, "owner": o}`; `amounts` gives five signed
  amounts (ironium, boranium, germanium, colonists, fuel), positive into the fleet. `other` can also be
  `{"deep_space": true}` (jettison: the fleet loses what it unloads, any type; nothing loads) or
  `{"packet": number, "owner": o}` (a packet or salvage pile at the fleet's position: minerals only, loads take
  what it has, unloads only its rounding room, S14). Unloads (negative) go first, then
  loads, each type in order; each is limited by what the giver has and the receiver's free space (cargo or fuel;
  planets take anything but fuel). What the receiver can't take stays with the giver (fix B20: the original lets it
  vanish). Built so far: the fleet's owner's own planet at the fleet's location, and the owner's fleets at the same
  position, jettisoning, and packets and salvage; transfers with other players' planets or fleets (queued in the
  original, S02 5f) are rejected for now. Blocks 1, 2 and 25 (amounts of 1, 2 or 4 bytes). `ApplyOrderBlock@1040:651e`,
  `TransferCargo@1048:3aec`.
- **`design_change`** `{starbase, slot, design}`: creates the player's ship design (slot 0–15) or starbase design
  (slot 0–9) in that slot, or replaces it. A design that still has ships (or starbases) in existence can't be
  changed (only deleted). The design must be valid (S04: a hull of the right kind, one entry per hull slot, each part
  accepted by its slot and within its maximum count, picture among the hull's four) and use only hulls and parts the
  player can use (tech and traits; the original trusts its client here). A created or replaced design starts with
  built and existing counts of 0 whatever the order says (the client sends zeros; seen in terra1 turn 42, where a
  replaced design's built count went from 1 to 0); the transferred mark is cleared. Queue items of that design keep
  their place; **fix B19**: their progress is converted by resources (see S09 step 7a). Block 27 (operation 1).
- **`design_delete`** `{starbase, slot}`: deletes the design. Ship design: every fleet of the player loses its ships
  of that design; the cargo and fuel that went with their capacity are lost (as a ship move into a fleet that is
  then discarded, without damage moving), and a fleet left without ships is deleted. Starbase design: every planet
  of the player with that starbase loses it, and those planets' queues lose their ship and packet items. Then the
  design leaves all of the player's queues. Block 27 (operation 0). `Fleets_SplitOutDesign@1048:748c`,
  `Planets_RemoveStarbaseDesign@1048:7426`, `RemoveDesignFromQueues@1048:7680`.
- **`player_defaults`** `{leftover_to_research, queue}`: the default queue for new colonies (at most 12 standard
  items, any progress dropped) and their "contribute only leftover resources to research" setting. Block 46, which
  copies up to 26 bytes into the player record.

**Cargo after a ship move.** Computed for each fleet from its state before the move (ships S, cargo, fuel):

- fuel lost = lost fuel capacity × fuel div fuel capacity, where fuel capacity is Σ ships × design fuel capacity
  over S and lost fuel capacity the same sum over the ships the fleet gave away;
- cargo lost L = lost cargo capacity × C div cargo capacity, with C the fleet's minerals plus colonists, the
  capacities as for fuel with design cargo capacity. Each of ironium, boranium, germanium and colonists in turn loses
  min(L × its amount div C, what is left of L); then, in the same order, each type that still has some loses 1 while
  anything is left of L (one pass).
- What a fleet loses goes to the other fleet. Both fleets' losses are computed before either is applied. (No
  capacity check on the receiving side; it gains at least the capacity that came with the ships.)

**Damage after a ship move**, per design moved: the giving fleet had c ships of it with d damaged (d = damaged
percent × c div 100) at damage e each; the receiving fleet c′ ships with d′ damaged at e′; n ships move, and the
damaged ones move first: m = min(n, d). Percentages are rounded up against the new counts.

- d = 0: if d′ > 0 the receiver's damaged percent becomes d′ × 100 / its new count.
- d > 0, d′ = 0: the receiver gets damage e and percent m × 100 / its new count.
- both > 0: the receiver's damage becomes (e × m + e′ × d′) / (m + d′) rounded up, percent (m + d′) × 100 / its new
  count. **Fix B32:** the original divides by the receiver's new ship count, so moving damaged ships into a stack with
  damaged ships loses damage.
- When d > 0 the giver's damaged percent becomes (d − m) × 100 / its new count, or no damage when m = d.

`paid` (B14) moves with the ships: the giver's stack gives paid × n div c of each amount.

**Damage after a merge**, per design: every fleet in the merge (target included) whose stack has any damage counts
max(1, damaged percent × count div 100) damaged ships carrying its damage each. With D damaged ships and total
damage T over all of them and N ships in the merged stack: damaged percent = D × 100 / N rounded up, damage =
T div D (none when D or N is 0).

**Deleting a fleet** (ship move, merge, colonize, scrap): every waypoint of any fleet that targets it is retargeted
to what is at its position: another fleet there (the ordering player's first, else the first in fleet order), else
the planet there, else deep space. `RetargetWaypointsFromFleet@1048:796c`, `FindObjectsAt@1030:294e`.

### Task data

Only waypoints with a task carry task data. Transport: `cargo`, five entries (ironium, boranium, germanium,
colonists, fuel), each `{action, amount}` with action `none`, `load_all`, `unload_all`, `load`, `unload`,
`fill_percent`, `wait_percent`, `load_optimal`, `set_amount` or `set_waypoint` (the original's numbers 0–9) and amount
0–4095. Other tasks keep the original's five words as `raw` until their rules are specified. When a task is done its
task data is cleared with it.

## Waypoint tasks

| # | Task | Where it runs |
|---|---|---|
| 0 | none | — |
| 1 | transport | every pass: unload actions in passes 1 and 3, load actions in passes 2 and 4 |
| 2 | colonize | every pass while the fleet is at the target planet |
| 3 | remote mining | pass 3 only, and only for a fleet that was already at the planet before movement |
| 4 | merge with fleet | load passes (2 and 4) |
| 5 | scrap | pass 1 only |
| 6 | lay mines | pass 3 (S13). A Space Demolition fleet also lays mines while its next waypoint has the lay-mines task. |
| 7 | patrol | handled with movement and battles (S12, S16) |
| 8 | route | an idle fleet (one waypoint) at its own planet that has a route follows the route; in pass 4 an idle fleet without a route gets default orders |
| 9 | transfer fleet to another player | pass 4 only |

**Passes** (S02): pass 1 and 2 use the waypoint the fleet starts the turn at (waypoint 0), before movement. Passes 3
and 4 use the waypoint the fleet is at after movement (its new waypoint 0, which was waypoint 1 if it arrived).
Ground combat and colonization are resolved between the two passes of each pair (S02 5c, 16d).

**Task done:** when a task finishes (transport, colonize, scrap, merge), the task is cleared from the fleet's current
waypoint. A fleet with no further waypoints also gets the "completed its assigned orders" message. Remote mining
and lay-mines (with years left) don't finish. Movement takes the fleet on to its next waypoint (S12).

### Transport

Each cargo type (ironium, boranium, germanium, colonists, fuel) has its own action and amount. The other side is the
planet, fleet, deep space or salvage at the waypoint.

| Action | Pass | Effect |
|---|---|---|
| Load all available | load | Take as much as the other side has, up to the fleet's free space. |
| Unload all | unload | Give everything of that type. |
| Load exactly n | load | Take n, limited by availability and space. |
| Unload exactly n | unload | Give n, limited by what the fleet has. |
| Fill up to n% | load | Take n% of the fleet's capacity (fuel capacity for fuel, cargo capacity otherwise; capped at 2,000,000; n × cap div 100, or n × (cap div 100) from 65,536 on), limited by free space and by what the other side has. **This adds to what is aboard**: the original does not subtract the cargo already carried (confirmed in terra1 turn 45:
5 kT aboard, fill to 40% of 25 kT, 15 kT after). If less than that (limited by free space) could be taken, the task stays and the fleet waits. |
| Wait for n% | load | As fill up to n%. Also, when nothing could be asked for (no free space, or n% of nothing), fuel always waits, and other cargo waits while the fleet has free cargo space. |
| Load optimal | load | Fuel (other side a fleet or deep space; skipped at planets like all fuel): with no next waypoint all fuel goes to the other side; otherwise the fuel beyond what the leg to the next waypoint needs (S12, distance rounded up, at that waypoint's warp) goes to the other side up to its free fuel space, and a fleet with less than it needs waits (nothing is loaded). Minerals: when the other actions are done and the fleet has free cargo space (or fuel optimal is set), a second round loads all available of each mineral with this action; the fuel step then runs after it. |
| Set amount to n | both | With d = n − carried: unload −d when d < 0 (unload pass); load d when d ≥ 0 (load pass), waiting while the other side has less than d. |
| Set waypoint to n | both | With d = what the other side has − n: unload min(−d, carried) when d < 0; load d when d > 0. |

Rules visible in the code (amounts to be confirmed, see "Open questions"):

- Fuel is skipped entirely when the other side is a planet (refueling is a separate phase, S12); with fleets and
  deep space it works like the other types.
- A task that waits stays on the waypoint; its fleet doesn't move while waypoint 0 has a transport task (S12), and
  the actions are tried again in the next passes and turns.
- A fleet can't load from a planet it doesn't own; the player gets a message. (Fix B15: colonists can never be
  loaded from a planet the fleet's owner doesn't own.)
- Unloading colonists onto another player's planet is an invasion (resolved in ground combat, S17).
- Unloading minerals in deep space destroys them (S14).
- Loading from a packet or salvage pile (anyone's) takes its minerals, up to the fleet's free space; colonists and
  fuel are skipped. The where of the messages is [65534, the object] (S21).
- Built so far: every action except load optimal, with every partner below, for minerals and colonists, and fuel
  between fleets (colonists move between the fleet's cargo and the planet's
  population units, 1 kT = 1 unit = 100 colonists). Loading takes what the other side has, up to the fleet's free
  cargo space (its designs' cargo capacity minus minerals and colonists carried) or free fuel space.

**The other side** comes from the current waypoint's target: a fleet (the target fleet, which must be at the same
position), a planet (the planet the fleet is at), a packet or salvage pile (the waypoint's target object; a target
that no longer exists ends the task when loading), or deep space. Minefields, wormholes and the Mystery Trader as
targets carry no cargo: the transport does nothing.

**Unloading** (passes 1 and 3), per cargo type in order (ironium, boranium, germanium, colonists, fuel); each unload
action is cleared once carried out:

| Other side | Minerals | Colonists | Fuel |
|---|---|---|---|
| The fleet owner's planet | to the surface | join the population | not transferred |
| Another player's planet | to the surface | an invasion, recorded for ground combat (S17), unless the planet has a starbase or the fleet's race lives in space (Alternate Reality, trait parameter `transport.no_invasion`): then refused | not transferred |
| An unowned planet | to the surface | refused (colonizing needs the colonize task) | not transferred |
| One of the player's fleets | up to its free cargo space | up to its free cargo space | up to its free fuel space |
| Another player's fleet | refused (fix B20; the original lets them vanish) | refused | up to its free fuel space, nothing if that player counts the giver as an enemy |
| A packet or salvage pile (S14) | up to the rounding room of its recorded mass (`mass_tenths` × 10 − its minerals) | skipped | skipped |
| Deep space | lost (the original's transfer target for deep space is a scratch record; no salvage is made); "unloaded", the where being the fleet's position | refused | stays aboard |

A refused colonist unload cancels the whole transport task (the original's "order canceled" messages): later cargo
types and the load actions are not carried out.

**Transport at a mining site:** when the waypoint is an unowned planet where one of the fleet owner's remote miners
rests (didn't move this turn, mining rate above 0; the first such fleet in fleet order), that miner fleet is the
other side instead: unloads go into its hold (and fuel tank), and loads take minerals from its hold first and the rest
from the planet's surface, while "what the other side has" for minerals is the planet's surface (seen in long1 turn
3: a freighter loading at a mini-miner's planet and leaving it its spare fuel). Before movement (passes 1 and 2) the
"didn't move" mark is last turn's in the original; we keep it only during a turn, so this is not built for those
passes yet.

**Loading** (passes 2 and 4) works only from the fleet owner's own planet or own fleets. From anything else (another
player's or an unowned planet, another player's fleet, deep space) the load is skipped. **Fix B26/B15:** the original
keeps the task, so the fleet waits at waypoint 0 until the load is canceled in pass 4 and loses its move; we skip the
impossible load, the task completes and the fleet moves on. (Stealing cargo with a robber-baron scanner, message
"has stolen", and picking up minerals from one's own remote-mining fleet at an unowned planet are not built yet;
see "Open questions".) The load pass ends the task unless an action waits.

### Colonize

At a planet with no owner, a fleet carrying colonists colonizes it. Conditions, in order (each failure sends the
player a message and the task stays):

1. The fleet is at a planet (not deep space).
2. The planet has no owner.
3. The fleet carries colonists.
4. At least one ship type in the fleet has a Colonization Module or an Orbital Construction Module in its design.

The fleet is then dismantled: 3/4 of the ships' mineral cost (per mineral, rounded down; the design cost as
stored, recomputed at current tech for Bleeding Edge) plus all minerals in the cargo go to the planet's surface,
each design's existing count drops by its ships, the fleet is gone, and the colonization (player, planet,
colonists) is recorded and resolved together with ground combat (S02 5c, 16d), so several players colonizing the
same planet in one turn are resolved there.

**Colonizing an empty planet** (the part of `ResolveGroundCombat@10b0:1e82` for unowned planets):

1. Per player, colonists = the sum of its records for the planet; strength = colonists × troops percentage div
   100 (trait parameter `invasion.troops_pct`: 110, War Monger 165, Alternate Reality 0).
2. The player with the greatest strength wins; an exact tie for the greatest means nobody colonizes (the colonists
   are lost). "Second" is the greatest strength before the winner's in player order.
3. Population = the winner's colonists, times (top − second) div top when a second player had strength; at least 1.
4. The planet becomes the winner's with that population. Its "only leftover to research" setting becomes the
   player's default, and, when the player's default queue has items, its queue becomes a copy of it, in order,
   leaving out auto items the race does not use (trait parameters `colony.skips_auto_<effect>`: Alternate Reality
   skips auto mines, factories and defenses, Claim Adjuster both auto terraform items). Alternate Reality
   (`colony.starbase`) also gets a starbase of its starbase design 0, whose built and existing counts grow by one.
   The player's guide says the default queue also applies to a planet taken over by invasion; to confirm in S17.
5. An artifact on the planet is removed; with random events on, the winner gains 100 + random(301) research
   points (scaled by population div 10 below 10 units) in field random(6) (draws in that order).

**Fix B16:** the original checks the *current* design of each ship type, so a design changed after the ships were
built gives the wrong answer. We check the ships actually in the fleet (each ship keeps the design it was built
with).

### Scrap

Pass 1 only (a scrap task at an arrival waypoint runs at the start of the next turn). Colonize shares this code
(3/4 of M, see "Colonize"). The fleet is dismantled; per mineral, with M = Σ over stacks of ships × the design's
cost of that mineral, divided by 4 (rounded down, per stack) for a transferred design:

| Where | Minerals recovered |
|---|---|
| Planet with a starbase | 4M / 5 |
| Planet with a starbase, planet owner has Ultimate Recycling | 9M / 10 |
| Planet without a starbase | M / 3 |
| Planet without a starbase, planet owner has Ultimate Recycling | 9M / 20 |
| Deep space | M / 3, left as salvage |

- Minerals in the cargo are added in full; colonists in the cargo join the population if the planet is the fleet
  owner's own.
- The recovery goes to the planet whoever owns it, and the Ultimate Recycling check is on the **planet's owner**.
- With Ultimate Recycling the ships' resource cost R (capped at 65,535) is also banked for the planet's next year;
  the message reports R × r / (R + r), where r is the planet's resources.
- Bleeding Edge Technology: the design's cost is recomputed with the scrapper's current tech first.
- Designs marked as having parts the player can no longer build count at a quarter of their cost.
- Scrapping at a planet with a starbase can give the planet's owner tech (S24): once per turn per player, a 50%
  roll, then a Mystery Trader part or tech points in a field where the scrapped designs need more tech than the
  owner has (`TryTechBonus@10e8:6112`); it draws from the generator even when nothing is gained (S24).
- Ultimate Recycling (trait parameter `scrap.recycling`) also banks the ships' resource cost for the planet's next
  year; not built yet.
- In deep space the minerals become salvage (S14); not built yet.
- Each design's existing count drops by its ships, as for colonize.

**Fix B14:** M uses the cost actually paid for each ship (stored with the ship), and never more than the scrapping
player's own cost for that design; this removes profit from scrapping other races' cheaper ships. Ships without a
recorded amount (converted from the original, or built before production records it) count at the design cost.

### Merge with fleet

Load passes only. Waypoint 0 must target a fleet that exists, has ships, is not the fleet itself, belongs to the
same player and is at the same position (the waypoint follows the target, so the original needs no distance check);
otherwise the player gets a message and the task stays. The fleet's ships then move into the target exactly as a
ship move of all its ships (cargo, fuel and damage follow, see "Fleet orders"), and the emptied fleet is deleted.
`MergeFleets@1048:78b6`.

### Remote mining

Pass 3 only, and only for a fleet that didn't move this turn (otherwise nothing happens and the task stays).
Conditions (each failure sends a message and clears the task):

1. It is at a planet (not deep space).
2. The fleet's mining rate is above 0: Σ ships × the design's mining robots' `mining_rate`, capped at 4,000.
3. The planet has no owner. (A fleet of an Alternate Reality race at an owned planet does nothing here and keeps
   its task; AR mines its own worlds during the mining phase, S08.)

(The "didn't move" mark comes from S12: every fleet is marked at the start of movement and the mark is cleared when
it moves; a fleet whose current waypoint has a transport or lay-mines task doesn't move. Built 2026-10-04; in
long1 turn 2 a mini-miner at an unowned planet.)

The planet is mined at that rate (S08 "Mining", remote form: rate × concentration, no mine-output factor); the yield
goes to the planet's surface. Remote mining never completes; it repeats every turn.

### Lay mines

Pass 3 only.

1. The fleet must not have moved this turn, except for Space Demolition races, whose moving fleets lay half.
2. The fleet's rate per mine type (standard, heavy, speed bump) is Σ ships × the design's `mines_…` stats, doubled
   for the Mini and Super Mine Layer hulls (S04). With no rate at all the player gets a message.
3. The task's number is how many more years to lay: 0 means this year only (the task then ends, its details
   cleared), 5 ("indefinitely") keeps it forever, any other number counts down (the client stores "2 years" as 1;
   seen in mine1 turn 0). Verified in mine1 (laying in place, merging into a field, laying while moving at half
   rate, full rate after arriving).
4. For each mine type with mines to lay: find the player's minefield of that type that already contains the fleet
   (distance² ≤ the field's mine count) and is nearest. If there is one and it holds at most 999,999 mines, the new
   mines join it and its center moves to the mine-weighted average of the two positions (integer division);
   otherwise a new field is created at the fleet's position (S13).
5. A Space Demolition fleet without a task at its current waypoint, whose next waypoint has the lay-mines task,
   also lays mines (at the moving rate) as it travels.

### Transfer fleet

Pass 4 only. The receiving player is task data word 0, counted without the giver (a value at or above the giver's
index means the next player). The transfer fails (message, task stays) when that player does not exist or is out of
the game, is an enemy of the giver (its relation toward the giver), the fleet carries colonists, a design finds no
slot, or the receiver is at the fleet limit. (The original also refuses for computer players with a "refuses gifts"
flag; not modelled.)

- Designs: each design of the fleet maps to the receiver's first transferred design with the same hull and the same
  parts (same count per slot and, where the count is not zero, the same part), else to the receiver's next free
  ship design slot (searching upward, each new design taking the next one) as a copy marked transferred, with zero
  counts. No slot left: the transfer fails.
- The receiver gets a new fleet (lowest free number) at the same place, with one waypoint there, the cargo, and the
  ships with their damage in the mapped slots; each mapped design's built and existing counts grow by the ships.
  The giver's fleet is deleted and its designs' existing counts drop.
- `DoWaypointTaskPass@10a8:3ec6` (task 9), `FindIdenticalDesign@1030:4dcc`.

### Default orders

An idle fleet without a route gets default orders in pass 4: a fleet with mining robots at a planet gets the remote
mining task, or merges into a mining fleet already there.

## Validation

The host checks every order and task against the actual state; nothing the client reports is trusted.

- Cargo: transfers need capacity on the receiving side and ownership or consent. Minerals cannot be sent to a
  foreign fleet or to a fleet without a cargo hold (fix B20). Loaded colonists are limited to what the source has
  (fix B30).
- Manual transfers and the colonize task follow a fixed order: order-time transfers first, then the task passes as
  above, so nothing is dropped silently (fix B17).
- A waypoint 0 load task that can't be carried out (for example at a foreign planet) completes as a no-op and the
  fleet proceeds (fix B26).
- Design changes to items under construction carry over progress by resources spent (fix B19, S09).

## Randomness

None found in the task passes themselves. Colonization and ground combat (S17), the Mystery Trader (S18) and
scrapping tech gain (S24) draw from the generator in their own specs.

## Edge cases

- A fleet with no ships is skipped.
- Colonizing and invading the same planet in the same turn are resolved together (S17).
- Merging into a fleet that was destroyed or transferred earlier in the turn fails with a message.

## Mod hooks

- Tasks are registered `TaskDef`s (MODDING §7) with ids `task.transport`, `task.colonize`, `task.remote_mine`,
  `task.merge`, `task.scrap`, `task.lay_mines`, `task.patrol`, `task.route`, `task.transfer`; each declares the
  passes it runs in.
- Hooks: `before_colonize`, `on_planet_colonized`, `on_fleet_scrapped`, `on_fleet_transferred`.

## Open questions

1. Exact transport amounts for "set amount to", "set waypoint to" and "load optimal" (fuel), and the rule that
   lets a fleet pick up minerals from the player's own remote-mining fleet at an unowned planet (seen in the target
   selection, not yet understood).
2. Confirm the fleet order and the absence of a random player order with the harness (two players loading from
   the same planet in one turn).
