# S11 Orders and waypoint tasks

Status: draft (2026-09-30), second pass. Structure, colonize, scrap, remote mining, mine laying and task completion
read from the code; transport amounts partly (see "Open questions"). Order application started (2026-10-03): the
production queue, research and planet orders are implemented (`core/turn/order_rules.gd`) and match the original in
a harness game with orders given in the client.
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

The original also had order blocks for passwords and for "save and submit"; they are file mechanics, not game
rules.

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

References for these: `ApplyOrderBlock@1040:651e` (blocks 29, 34, 35).

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
| Fill up to n% | load | Take until the fleet holds n% of its capacity (fuel capacity for fuel, cargo capacity otherwise). |
| Wait for n% | load | As fill up to n%, and the fleet stays at the waypoint until it reaches n%. |
| Load optimal (fuel) | load | Fuel needed for the next leg. |
| Set amount to n | both | Load or unload to end with n. |
| Set waypoint to n | both | Load or unload so the planet ends with n. |

Rules visible in the code (amounts to be confirmed, see "Open questions"):

- Percent actions use n × capacity ÷ 100, with the capacity capped at 2,000,000 for this calculation.
- A fleet can't load from a planet it doesn't own; the player gets a message. (Fix B15: colonists can never be
  loaded from a planet the fleet's owner doesn't own.)
- Unloading colonists onto another player's planet is an invasion (resolved in ground combat, S17).
- Unloading onto deep space jettisons the cargo (salvage, S14).

### Colonize

At a planet with no owner, a fleet carrying colonists colonizes it. Conditions, in order (each failure sends the
player a message and the task stays):

1. The fleet is at a planet (not deep space).
2. The planet has no owner.
3. The fleet carries colonists.
4. At least one ship type in the fleet has a Colonization Module or an Orbital Construction Module in its design.

The fleet is then dismantled: 3/4 of the ships' mineral cost (per mineral, rounded down) plus all minerals in the
cargo go to the planet's surface, and the colonization is recorded and resolved together with ground combat (S17),
so several players colonizing the same planet in one turn are resolved there.

**Fix B16:** the original checks the *current* design of each ship type, so a design changed after the ships were
built gives the wrong answer. We check the ships actually in the fleet (each ship keeps the design it was built
with).

### Scrap

Pass 1 only. The fleet is dismantled; per mineral, with M = Σ ships × the design's cost of that mineral:

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
- Scrapping at a planet with a starbase can give the planet's owner tech (S24).

**Fix B14:** M uses the cost actually paid for each ship (stored with the ship), and never more than the scrapping
player's own cost for that design; this removes profit from scrapping other races' cheaper ships.

### Merge with fleet

Load passes only. The target fleet must exist, have ships, and belong to the same player; the fleet's ships join
it. Otherwise the player gets a message.

### Remote mining

Pass 3 only. Conditions (each failure sends a message; the task stays and is tried again next turn):

1. The fleet didn't move this turn (S12: every fleet is marked at the start of movement and the mark is cleared
   when it moves; a fleet whose current waypoint has a transport or lay-mines task doesn't move, which is how
   "wait for %" holds it).
2. It is at a planet (not deep space).
3. The planet has no owner. (A fleet of an Alternate Reality race at an owned planet does nothing here; AR mines its
   own worlds during the mining phase, S08.)
4. The fleet's mining rate is above 0: Σ ships × the design's mining robots' `mining_rate`, capped at 4,000.

The planet is mined at that rate (S08 "Mining", remote form: rate × concentration, no mine-output factor); the yield
goes to the planet's surface. Remote mining never completes; it repeats every turn.

### Lay mines

Pass 3 only.

1. The fleet must not have moved this turn, except for Space Demolition races, whose moving fleets lay half.
2. The fleet's rate per mine type (standard, heavy, speed bump) is Σ ships × the design's `mines_…` stats, doubled
   for the Mini and Super Mine Layer hulls (S04). With no rate at all the player gets a message.
3. The task's number is how many more years to lay: 0 means this year only (the task then ends), the "indefinitely"
   value keeps it forever, any other number counts down.
4. For each mine type with mines to lay: find the player's minefield of that type that already contains the fleet
   (distance² ≤ the field's mine count) and is nearest. If there is one and it holds at most 999,999 mines, the new
   mines join it and its center moves to the mine-weighted average of the two positions (integer division);
   otherwise a new field is created at the fleet's position (S13).
5. A Space Demolition fleet without a task at its current waypoint, whose next waypoint has the lay-mines task,
   also lays mines (at the moving rate) as it travels.

### Transfer fleet

Pass 4 only. The fleet is recreated as a fleet of the receiving player (new number for that player), with messages
to both.

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
