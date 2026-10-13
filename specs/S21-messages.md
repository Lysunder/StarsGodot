# S21 Turn messages

Status: draft (2026-10-05). Read from the decompiled code; checked against the messages in the players' turn files of
the harness games (`terra1`, `long1`, `prod1`) by the golden-turn tests, for the message types listed below.
References: `AddMessage@1028:7344`, `AddMessageSimple@1028:7328`, `BuildMessageRecord@1028:7410`,
`RemoveMessages@1028:80fa`, `WriteMessages@1028:8308`, `LoadMessages@1028:8460`, `ExpandMessageCodes@1028:7778`,
`Message_Goto@1030:063e`, `Fleet_MsgRef@1030:1bca`, and the rules that send each message (listed per type).

## Summary

While a turn is generated, the rules send each player messages about what happened: items built, research levels
reached, colonies founded, cargo moved, fleets out of fuel and so on. A player reads them in the Messages pane, each
with a Goto that shows the planet, fleet or item it concerns. The message text is ours; this spec fixes which
messages are sent, when, in which order, and with which parameters.

## Data used

`state.messages`: one list per player, in the order the messages were sent. Each message:

- `type`: a `message` content id (`message.production.factories_built`, ...). The content defines its parameter
  kinds (`params`) and whether computer players get it (`ai`); the language file gives our wording.
- `goto`: what Goto shows, a small dictionary (see "Goto"); `{}` for nothing.
- `params`: the parameters, in order, each of the kind its type lists (see "Parameter kinds").

A turn's generation starts with empty lists (the original's host loads the game with no messages,
`Messages_Reset@LoadGame`). Messages are kept with the game until the next generation.

### Goto

| Goto | Shows |
|---|---|
| `{}` | nothing (tips) |
| `{"planet": id}` | a planet |
| `{"fleet": number, "owner": player}` | a fleet |
| `{"research": true}` | the research dialog |
| `{"item": id}` | a part or planetary item (the technology browser) |
| `{"hulls": true}` | the ship designer's hull list |
| `{"score": true}` | the score report (S20 end-of-game messages) |
| `{"minefield": number, "owner": player}` | a minefield |
| `{"packet": number, "owner": player}` | a packet or salvage pile |
| `{"battle": id}` | a battle's recording (S16; the battle viewer) |

### Parameter kinds

| Kind | Value |
|---|---|
| `number` | an integer (a count, kT, mg, years, percent) |
| `planet` | a planet id |
| `fleet` | a fleet: owner × 512 + fleet number |
| `fleet_designs` | a fleet described by its main design: number + 512 × main design slot, + 8192 when the fleet has more than one design (`Fleet_MsgRef`) |
| `design` | a ship design: owner × 32 + slot; slots 16 and up name the owner's starbase design slot − 16 |
| `player` | a player index |
| `cargo` | a cargo type: 0 ironium, 1 boranium, 2 germanium, 3 colonists, 4 fuel |
| `field` | a tech field index (`tech_field` order) |
| `item` | a part, hull or planetary item content id |
| `flag` | 0 or 1, as the type says |
| `axis` | an environment axis: 0 gravity, 1 temperature, 2 radiation |
| `axis_value` | an environment value with its axis: axis × 256 + value |
| `minefield` | a minefield: owner × 512 + its number |
| `space_object` | a minefield or a packet / salvage pile: kind (0 minefield, 1 packet) × 8192 + owner × 512 + number |
| `colonists` | a number of colonists in hundreds |
| `object_kind` | the first half of a "where": -1 (65535) when the second half names a planet or fleet, 65534 when it names a packet or salvage pile, else a position's x |
| `object` | the second half: the planet id, or 32768 + the fleet's `fleet` value; the `space_object` value; or the position's y |
| `basis_points` | hundredths of a percent (e.g. the share of bombs a planet's defenses stopped) |

In the original's files every parameter is a byte or a word, a 32-bit amount takes two (low word, high word) and an
item takes two (category mask, item number); the harness importer (`tools/harness/stars_messages.py`,
`stars_import.py`) turns them into the kinds above.

## Algorithm

`TurnMessages.add(player, type, goto, params)` appends a message to the player's list. Computer players get only
types marked `ai` (the original keeps only a few message numbers for them, `BuildMessageRecord`); none of the types
below is one of them.

### Production (S09; `DoProduction@10b0:0000`, `Production_CompleteItem@10b0:0e68`)

Per planet in planet order (the production phase):

1. An owned planet whose queue is empty: **`production.queue_empty`** `[planet]`, goto the planet, before anything
   else of that planet.
2. While the queue is worked through, each completed unit sends its message:
   - Mines, factories, defenses (also from auto items): first every earlier **single** message of the same kind for
     this planet this turn (`mine_built`, `factory_built`, `defense_built` with goto this planet) is removed and
     counted; with n = units installed now + messages removed: n = 1 sends **`<kind>_built`** `[planet]`, more sends
     **`mines_built` / `factories_built` / `defenses_built`** `[n, planet]`, goto the planet, at the end of the list.
     (Earlier plural messages are not merged: the original's `RemoveMessages` matches the single message number
     only.)
   - Ships: the new fleet (S09 step 6a) gets **`production.ship_built`** `[planet, design]` for one ship, or
     **`production.ships_built`** `[planet, count, design]`, goto the new fleet. (A planet with a route sends other
     messages; routes are not built yet. At the fleet limit the ships join a fleet: not seen yet.)
   - Terraforming, per step that changed an axis: **`production.terraformed`** `[planet, up, axis, axis_value]`,
     goto the planet: `up` 1 when the value went up, 0 when it went down; `axis_value` the axis's new value.
3. After the queue: **`production.queue_done`** `[planet]`, goto the planet, when the queue is now empty, or when
   the queue was worked to its end (only auto items left) and no auto item stopped short of minerals.

### Research (S05; `UpdateTechLevels@10b0:4c50`)

Each time a field gains a level (in the order S05 levels fields, several levels one after another):

1. **`research.level`** `[level, field, focus]`, goto research: `level` the new level, `field` the field, `focus`
   the field research goes on in: when `field` is the field being researched and the next-field setting is not
   "same field", the next field (the lowest field, computed after this level, for "lowest"), else the field being
   researched. Races with the trait parameter `research.focus_message` (Generalized Research) get
   **`research.level_focus`** instead, with the same parameters.
2. Then one message per item the player can now use (S04 `available`: every tech requirement met, traits allow
   it, a Mystery Trader item only once the player has it) whose requirement in `field` equals the new level, in
   the original's catalogue order: categories engine, scanner, shield, armor, beam, torpedo, bomb, mining robot,
   mine layer, orbital, starbase hulls, electrical, mechanical, terraform, ship hulls, planetary; within a
   category, the content's definition order (the core pack lists items in the original's item order).
   - Ship hulls: **`research.new_hull`** `[field, item]`, goto `{"hulls": true}`; starbase hulls:
     **`research.new_starbase_hull`** (not seen in a harness game yet).
   - Planetary defenses (a `defense` stat): **`research.new_defense`**; planetary scanners (a `scan_range` stat):
     **`research.new_scanner`**; anything else: **`research.new_item`**; all `[field, item]`, goto the item.
   - A race with `research.quiet_basic_terraform` (Total Terraforming) gets no message for items tagged
     `terraform_basic` (the three ±3 single-axis terraform items).

### New game (`CreateUniverse@1070:1334`)

Each human player: the four tips **`game.tip_filters`**, **`game.tip_waypoints`**, **`game.tip_designs`**,
**`game.tip_details`** (no parameters, goto nothing), then **`game.home_planet`** `[planet]`, goto the home planet.

### Fleet tasks (S11; `DoWaypointTaskPass@10a8:3ec6`)

- **Transport**, per cargo moved (and only when something moved): loads send **`fleet.loaded`** (minerals and
  fuel) or **`fleet.beamed_up`** (colonists), unloads **`fleet.unloaded`** / **`fleet.beamed_down`**, all
  `[fleet, amount, cargo, object_kind, object]`, goto the fleet; the "where" is the planet or the other fleet.
  "Load optimal" fuel handed to another fleet is an unload. At a mining site, cargo taken from the planet's
  surface sends **`fleet.miner_loaded`** `[fleet, amount, cargo, miner, planet]` (cargo from the miner's hold is
  an ordinary load). In the last load pass (pass 4) a load action (load all, load, fill, wait) from a planet the
  player doesn't own sends **`fleet.load_refused`** `[fleet, cargo]` and cancels the task. Not seen yet: loads
  from other players' fleets, unloads at a mining site, the refused colonist unloads.
- **Task done** (finished or canceled): a fleet with ships and no further waypoints whose waypoint had a task gets
  **`fleet.completed`** `[fleet]`, goto the fleet, replacing an earlier one for that fleet this turn.
- **Colonize**: the colony ship is taken apart as by scrapping at a planet without a starbase (the messages below;
  the planet has no owner yet, so only the first), and the new colony then sends **`planet.colonized`**
  `[planet]`, goto the planet (S02 5c).
- **Scrap** at a planet: **`fleet.scrapped`** (no starbase) or **`fleet.scrapped_starbase`** `[fleet_designs,
  minerals, planet]` to the fleet's owner, then **`planet.ships_scrapped`** / **`ships_scrapped_starbase`**
  `[fleet, minerals, planet]` to the planet's owner (none if unowned), both goto the planet; `minerals` is the
  kT added to the surface. (The scrap tech-gain variants, S24, are not seen yet.)
- **Merge**: **`fleet.merged`** `[fleet_designs of the merged fleet, target fleet]` to the target's owner, goto
  the target.
- **Transfer**: **`fleet.given`** `[fleet_designs of the old fleet, receiver]` to the giver and
  **`fleet.received`** `[giver, fleet_designs of the new fleet]` to the receiver, both goto the new fleet.

A fleet's main design (`Fleet_MainDesign@1030:27e4`) is the design with the most ships, the first slot on ties; a
hull tagged `fuel_transport` counts one ship less.

### Movement (S12; `MoveFleets@10a8:1f18`, `UpdateFleetTargetPositions@1078:1060`)

- Out of fuel: **`fleet.out_of_fuel_slower`** `[fleet, new warp]`, or **`fleet.out_of_fuel`** `[fleet]` when the
  warp could not be lowered (below 2).
- Ram scoops that made fuel, when the tank had room: **`fleet.ram_scoop`** `[fleet, fuel made]` (at most 32500).
- A fleet that reached its next waypoint and has no further one: **`fleet.completed`** `[fleet]`, unless that
  waypoint's task is still to do there (transport, colonize, remote mining, scrap, lay mines, patrol, or a route
  from its owner's planet that has a route).

### Population (S08; `GrowPopulations@10b0:3086`)

Per owned planet in planet order, after growth: a planet that lost colonists and still has some sends
**`planet.shrank`** `[planet, before, after]` when its value is negative, else **`planet.overcrowded`** `[planet,
lost]` (populations in colonists ÷ 100). A planet left with no colonists (and none waiting) sends
**`planet.died`** when the last growth worked out was negative, else **`planet.abandoned`**; races with
`message.orbital_colony` (Alternate Reality) get the `_orbit` forms. "The last growth worked out" carries over from
planet to planet, as in the original.

### Terraforming (S10)

- Claim Adjuster (`ClaimAdjusterTerraform@10b0:2ba4`): a permanent change sends **`planet.environment_improved`**
  `[planet, axis]`; a planet that terraformed itself sends **`planet.auto_terraformed`** `[planet, value %]`.
- Remote terraforming (`RemoteTerraform@10b0:2dc0`): to the fleet's owner, **`fleet.terraform_improved`**
  (friendly) or **`fleet.terraform_degraded`** `[fleet, planet, value before, value after]`, or the `_stuck`
  forms `[fleet, planet, value]` when the value didn't change; goto the fleet. When the planet is someone else's
  and its value changed, its owner gets the same message, goto the planet. Values are the planet owner's.

### Other subsystems

Battles (S16), bombing and ground combat (S17), fleets following fleets (S12), packets (S14), minefields (S13),
wormholes (S12), random events and the Mystery Trader (S18), score and victory (S20): their messages are listed in
their specs. What is still missing is in "Catalog coverage" below.

## Catalog coverage (2026-10-12)

The original's message table has 446 entries (`message_templates`); 61 of them (0x181 … 0x1bf) are other data,
leaving 385 messages. 287 have a content type here (`legacy_ids`), all with our own wording. No fixture turn holds
a message without one (none is imported as `legacy.message.N`; rand1's 104 turns included). The rest:

- **Never sent here (9):** checks of the registration and the race file's integrity (0x100 … 0x107, 0x117); and
  0x180, the battle board limit (fix B08, S16).
- **Client side (8):** written by the original's client when it reads a turn: new planets found (0x0aa … 0x0ae,
  0x15d), a packet on a collision course, a starbase finishing its queue (0x151, 0x152). For the user interface (M11).
- **With rules not built yet:**
  - hand transfers to other players' fleets and planets (S11): the transfer reports 0x042 … 0x049, 0x04a … 0x04d,
    0x0dd, and the colonists dropped by hand 0x002, 0x057, 0x058 (S17);
  - new ships following their planet's route (S09/S11): 0x031 … 0x034;
  - Ultimate Recycling's resources from scrapped ships (S11): 0x05c, 0x05d, 0x13e, 0x13f, 0x142, 0x143;
  - stealing cargo from other players' fleets (Robber Baron scanner, Super Stealth): 0x119;
- **Sent from a computed number, or unused in 2.6i (to trace with their subsystem):** battle summaries 0x00e …
  0x022, 0x013, defenses upgraded 0x03b, older bombing forms 0x065, 0x06f, 0x16b, 0x175, loads from other fleets
  0x079, 0x07a, auto-build limits 0x0af … 0x0b4, remote terraforming done 0x0bd, a starbase hull learned 0x0d0,
  packet pickups 0x0db, 0x0dc, packets without minerals 0x0fc, 0x112, 0x17f, a Trader variant 0x10d, transfer
  refusals 0x11c, 0x11d, 0x124, 0x125, rerouting 0x127, 0x128, over-limit orders 0x12a, 0x12f, battle recording
  counts 0x153, 0x154, and 0x11a (unused).

Added in this pass (each with its rule's spec): task refusals, which also end the task like any finished task
(colonize 0x051 … 0x054, merge 0x0f5, 0x0f6, remote mining 0x075 … 0x077, giving fleets away 0x148 … 0x14c, transport
0x055, 0x056, 0x11e, 0x120, 0x123, 0x135, 0x155, 0x165), transport shortfalls (0x121, 0x122) and fuel for the next
waypoint (0x03c, 0x03d, 0x126); production (starbases 0x0cd … 0x0cf, a planetary scanner 0x07c, a Genesis Device
0x11b, alchemy 0x08c, a second scanner 0x0b9, lost plans 0x04f, the fleet limit 0x0ba, 0x139); movement (Radiating
Hydro-Ram Scoop 0x074, Cheap Engines failing 0x0f2, overgating 0x0eb); spying (0x159); Mystery Trader parts learned
from wreckage and scrapped ships (0x13a … 0x13d, S24); Packet Physics terraforming (0x131 … 0x134, S14, fix B39).

## Filters

A player can mark message types as filtered out ("not important"); the list (`Player.message_filters`, type ids,
sorted, empty at the start) belongs to the player's game state and lasts for the rest of the game. It changes only
what the Messages pane shows: every message is still sent. The original keeps it as a bitmap of message numbers
(`SetMessageFilter@1028:8960`, DS:5508), saved in the player's files as block 33. The `message_filters` order (S11)
replaces the list.

- Some types are filtered together (content field `filter_group`, from the pairs and ranges in `SetMessageFilter`):
  the four cargo messages (loaded, beamed up, unloaded, beamed down); ship(s) built; factory/factories, mine(s) and
  defense(s) built. The original also groups some types we don't send yet (numbers 66-77 in pairs, 96-100, 106-110,
  121-122 and 145-168); add `filter_group` to them as they are built.
- Messages pane (`MESSAGEWNDPROC@1028:0000`, `Message_NextIndex@1028:6ef4`, `Message_PrevIndex@1028:6f66`,
  `MessagePane_DrawButtons@1028:6fc6`):
  - The year starts on the first message not filtered out; with none, the pane says so and shows "FILTERED"
    diagonally. The header counts every message ("n of total"; "0 of total" when all are filtered out).
  - The title bar's box shows a check (type shown) or an X (filtered out) for a turn message; clicking it (or "+")
    toggles the type and its group. The message stays on screen: while filtered and hidden it is replaced by a note
    that the type is now filtered, and Goto is disabled.
  - Prev and Next skip filtered messages, unless showing all.
  - While any of this year's messages is filtered, a magnifying glass at the right of the title bar ("-" key)
    switches between hiding them (minus) and showing them too (plus). Turning it on moves to the next filtered
    message (else the previous one); turning it off moves from a filtered message to the next one that is not (else
    the previous one). A filtered message shown this way has "FILTERED" diagonally behind its text.
  - The UI's own notes (after the turn messages) are never filtered.
- Not built yet: the "+" and "-" keys (with Up/Down and Enter for Prev/Next/Goto), and importing block 33 in the
  harness (fixtures have no filtered types).

## Edge cases

- A planet with no resources this year works no queue: only `queue_empty` (if its queue is empty).
- Messages to a player who has left the game: none are sent (`player` out of range).

## Known bugs

None found yet.

## Worked examples

- `terra1` turn 1, player 0: `queue_empty [23]` (its homeworld's queue is empty).
- `long1` turn 1: `factories_built [2, 85]`.
- `terra1` turn 14, player 0, energy level 5: `research.level [5, 0, 0]`, then `new_item [0,
  part.terraform.temp_terraform_7]` and `new_defense [0, part.planetary.missile_battery]`.

## Mod hooks

Message types are content (`message`), so a mod can add types and send them from its own phases or hooks; the
wording is in the language files.

## Open questions

- Carrying messages over for players who don't submit their turns (the original's turn file then holds one section
  per year): a hosting rule for M13.
