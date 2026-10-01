# S11 Orders and waypoint tasks

Status: draft (2026-09-30), first pass. Structure read from the code: which order kinds exist, when orders are
applied, which waypoint task runs in which pass, and the fleet order. The exact amounts of each transport action,
scrap recovery and mine-laying rates are marked for a second pass (see "Open questions").
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

**Task done:** when a task is complete the player gets a message and the fleet advances to its next waypoint.

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

At a planet with no owner, a fleet carrying colonists colonizes it; the colonization is recorded and resolved
together with ground combat (S17), so several players colonizing the same planet in one turn are resolved there.
If the planet has an owner, or the fleet has no colonists, or it isn't at a planet, the player gets a message.

**Fix B16:** the fleet must contain a ship with a colonization module (or an orbital construction module), checked
on the ships actually in the fleet. The original didn't check this.

### Scrap

Pass 1 only. At the fleet's own planet the colonists aboard join the planet's population. The ships are dismantled:
at a starbase or a planet the owner gets minerals and resources back; in deep space they become salvage.
Ultimate Recycling improves the recovery; scrapping can also give tech (S24).

**Fix B14:** recovery is based on the cost actually paid for each ship (stored with the ship), and never more than
the scrapping player's own cost for the design.

### Merge with fleet

Load passes only. The target fleet must exist, have ships, and belong to the same player; the fleet's ships join
it. Otherwise the player gets a message.

### Remote mining

Pass 3 only, for a fleet with mining robots that was at the planet before movement. Mining uses the fleet's mining
rate (sum of its robots, S04) with the planet's concentrations and wears them down (S08 "Mining"). Rules about which
planets may be remote mined (unowned, or the race's own for Alternate Reality) are part of the second pass.

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

1. Exact transport amounts for every action, including how "set amount to" and "set waypoint to" choose between
   loading and unloading, and the fuel "optimal" amount.
2. Scrap recovery percentages (with and without a starbase, with Ultimate Recycling and Bleeding Edge Technology).
3. Remote mining conditions (which planets, the "was already here" flag) and Alternate Reality's own-world mining.
4. Mine-laying rates and the Space Demolition rule for moving minelayers (S13).
5. When "task done" fires for each task, and how repeat orders loop.
6. Confirm the fleet order and the absence of a random player order with the harness (two players loading from
   the same planet in one turn).
