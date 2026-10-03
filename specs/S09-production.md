# S09 Production

Status: draft (2026-10-02), second pass. Read from the decompiled code, with the disassembly for the per-planet loop
(`DoProduction`), whose control flow the decompiler garbles. Not yet harness-verified: no fixture has a production
queue yet (computer players' queues are made and spent inside the original's turn run, so they never appear in the
files; human queues need order files, S23). Packet launching is summarized here and specified with S14.
Implemented in `core/rules/production.gd` and `production_costs.gd` (2026-10-02), except terraforming items (S10),
packets (S14), route following for new fleets (S11) and Alternate Reality default orders; those items are dropped
from the queue with a warning until their specs are done.
References: `DoProduction@10b0:0000`, `Production_SpendOnItem@10b0:0756`, `Production_CompleteItem@10b0:0e68`,
`GetProductionItemCost@10c8:21e4`, `Design_ComputeCost@1048:7a92`, `Planet_FreeQueue@10b0:36d6`,
`Queue_RemoveShipItems@10c0:4900`, `Queue_RemovePacketItems@10c0:47ea`, `BestPlanetaryScanner`,
`Design_UpdateStats@1030:2dbe`, `Design_GetMineralCost@1030:3b60`, `CreateFleet@1030:1f2e`,
`Fleet_AddShips@10b0:1bc6`, `Fleet_SetDefaultOrders@1078:17c2`, `Fleet_FollowRoute@1078:13f8`,
`Planet_GetMassDriverWarp@1040:4f76`. The help file's page on upgrading starbases agrees with the upgrade price
below.

## Summary

Every year each owned planet turns its resources into research and into the items of its production queue, using
the minerals on its surface. Items are built top to bottom; an item that can't be finished keeps its progress and
stops the queue. Auto items are standing orders that build what the planet can use each year. Resources left at
the end go to research.

## Data used

| Data | Notes |
|---|---|
| Planet queue | ordered items; each: kind (standard item or design), item number, count (0–1023), progress of the first unit (0–100%) |
| Planet setting "only leftover to research" | `leftover_to_research` |
| Planet surface minerals, installations, environment | S08 |
| Player research percentage | 0–100 |
| Resources this year | S08 step 5, plus scrapping income (S11) |
| Part and hull costs, player tech levels | S04 |

### Standard items

| No. | Item | No. | Item |
|---|---|---|---|
| 0 | auto mines | 7 | factories |
| 1 | auto factories | 8 | mines |
| 2 | auto defenses | 9 | defenses |
| 3 | auto mineral alchemy | 10 | (unused; costs nothing, does nothing) |
| 4 | auto minimum terraform | 11 | mineral alchemy |
| 5 | auto maximum terraform | 12 | terraform |
| 6 | auto mineral packets | 13 | Genesis Device |
| | | 14, 15, 16 | ironium, boranium, germanium packet |
| | | 17 | mixed packet |
| | | 18–26 | planetary scanner of planetary part 0–8 |
| | | 27 | planetary scanner (the best the owner can build when it completes) |

Items 0–6 are **auto items**; each acts as its counterpart (mines 8, factories 7, defenses 9, alchemy 11, terraform
12, mixed packet 17) when it builds.

## Algorithm

### 1. Item costs

A cost is four numbers: ironium, boranium, germanium (kT) and resources. The cost of one unit:

| Items | Cost |
|---|---|
| mines (0, 8) | resources = the race's mine cost (S06) |
| factories (1, 7) | germanium 4 (3 with the "factories cost less germanium" option), resources = the race's factory cost. Under a game flag not yet identified (see open questions): 2 of each mineral (1 with the option) instead |
| defenses (2, 9) | the planetary defense part's cost (planetary part 9, S04); Inner-Strength: every component × 3 div 5 |
| alchemy (3, 11) | resources 100; Mineral Alchemy: 25 |
| terraform (4, 5, 12) | resources 100; Total Terraforming: 70; Claim Adjuster: halved (after the TT price) |
| mixed packet (6, 17) | each mineral 44 (Packet Physics 25, Inter-stellar Traveler 48), resources 10 (PP 5) |
| Genesis Device (13) | the part's cost (planetary part 14) with the player's cost rules (step 2) |
| single packets (14–16) | that mineral 110 (PP 70, IT 120), resources 10 (PP 5) |
| scanners (18–26) | the planetary part's cost with the player's cost rules (step 2) |
| scanner (27) | as item 18 (planetary part 0) |
| ship design | the design's cost (step 2a) |
| starbase design | the design's cost, or with a starbase already on the planet the upgrade price (step 2b); then Improved Starbases or Alternate Reality: every component − component div 5; then every component is halved, rounding up (the starbase hull and part tables hold doubled prices) |

### 2. Part cost for a player (`Design_ComputeCost`)

Start from the part's listed cost (S04).

1. **Miniaturization**, except for terraforming parts and planetary parts 0–13: m = the smallest margin
   (player level − required level) over the fields the part requires; if it requires none, the player's lowest
   tech level. If m > 0: m = min(m, 19); the discount is min(4m, 75)%, or with Bleeding Edge Technology
   min(5m, 80)%. Each non-zero component c becomes c − round(c × discount / 100) (rounded to nearest), at least 1.
2. **Trait prices:** Inter-stellar Traveler, orbital parts 0–6 (stargates): c − c div 4. War Monger, beams,
   torpedoes and bombs: c − c div 4. Inner-Strength, the same parts: c + c div 4. Claim Adjuster, terraforming
   parts: resources halved. Cheap Engines, engines: c − c div 2.
3. **Bleeding Edge Technology:** when no miniaturization applied (m < 1) and the part requires any tech, every
   component is doubled.

### 2a. Design cost (`Design_UpdateStats`)

The hull's cost and each slot's part cost, both for the design's owner (step 2), times the slot's count, summed per
component. The original keeps each total in 16 bits (wrapping); our totals are wide integers, and no buildable design
reaches 65536 in any component. The original stores the total with the design when the design is saved; when it
is recomputed after tech levels change is an open question (the turn's design refresh, S02 phase 25, does not
recompute it).

### 2b. Starbase upgrade price

When a starbase design is built on a planet that already has a starbase (old design O, new design N), start from
N's cost (step 2a), per component:

1. **Different hull:** c = max(c − O's cost div 2, c div 2).
2. **Same hull:** subtract the hull's cost (step 2) from c. Then for each slot k of O (in slot order, up to O's slot
   count) where both O and N have a part (count > 0): with o = O's count × O's part cost and n = N's count × N's
   part cost (per component, step 2):
   - same part: credit = min(n, o);
   - same category, different part: credit = n − max(n − (8 × o) div 10, (2 × n) div 10);
   - different category: credit = n − max(n − (7 × o) div 10, (3 × n) div 10);
   - c = max(c − credit, 0).

### 3. Each planet, in planet order

For each planet with an owner:

1. R = resources (S08), plus scrapping income: with s > 0 resources from ships scrapped at the planet this year
   (S11), R = R + (s × R) div (s + R).
2. **Empty queue:** all of R goes to research. Done.
3. A queue whose item list is allocated but has no items: the planet is skipped (no research). (An artifact of the
   original's memory handling; our queues are never in this state.)
4. Otherwise, unless the planet is set to "only leftover to research": research share = R × research percentage
   div 100 goes to research, R = R − share.
5. If R is 0, done. Otherwise build from the queue (step 4) with **available** = the planet's surface minerals and
   R resources.
6. After the queue: the planet's surface minerals become the available minerals; the available resources left go
   to research.

All research resources of a player are summed for the tech update (S05).

### 4. Building the queue

Items are taken from the top. For the item at position i (a flag "alchemy above" starts off):

1. **Count 0:** the item is removed (and, if the flag is on, the auto alchemy item above it too). Next.
2. **Checks for standard items:**
   - Scanners (18–27): if the planet already has a planetary scanner, the item is removed (message). Next.
   - Single packets (14–16) and the mixed packet (17): if the planet has no mass driver or no packet destination,
     the item is removed (message). Next.
   - Factories (7), mines (8), defenses (9): room = max(maximum, operable next year) − built (S08). Terraform (12):
     room = the number of terraforming steps still possible (S10). If count > room: message; if room ≤ 0 the item
     is removed (next), else count = room.
3. **Auto alchemy not at the bottom:** auto alchemy (3) that isn't the last item is not built; it turns the flag
   on for the next item. Next.
4. **Spend** on the item (step 5). If units were completed, apply them (step 6); if that installs nothing and the
   item is not an auto item, its count becomes 0 (removed at the next pass of step 1).
5. If the planet lost its owner, stop.
6. Depending on the result of step 5:
   - everything ordered was built: the item is removed;
   - an auto item that finished its share or stopped for lack of minerals: next item (flag off);
   - otherwise (a normal item not finished, or an auto item partly built): if step 5 produced a **carry-over item**,
     it is inserted at the top of the queue; the queue stops.

### 5. Spending on one item (`Production_SpendOnItem`)

C = the cost of one unit (step 1); p = the item's progress (0–100%); spent = C × p div 100 per component.

**Auto items** first get a working count: auto mines = operable mines next year − built; auto factories and auto
defenses likewise; auto alchemy 1000; auto minimum terraform = the remaining terraforming steps, but 0 when the
planet's population is not shrinking and its habitability is positive; auto maximum terraform = the remaining
terraforming steps; auto packets = 0 without a mass driver and destination, else 1000. A negative room is 0.
The queue entry of an auto item never changes.

Then, while units remain:

1. If the available minerals and resources cover C − spent in all four components: one unit is complete; take
   C − spent from available, the count drops by 1, progress and spent return to 0. Repeat.
2. Otherwise, the reachable progress a = the smallest, over components with C > 0, of: 100 if available ≥ C, else
   max(((t + 1) × 100) div C − 1, (t × 100) div C) with t = available + spent. Note the limiting component (the
   first one giving the smallest value) and its shortfall (C − spent − available).
3. Unless an **auto item is short of minerals**: pay up to a (for each component, C × a div 100 − spent moves from
   available into spent), progress = a. Then stop unless the alchemy flag is on and a mineral is short.
4. An auto item short of minerals without the alchemy flag stops here without paying.
5. **Alchemy** (flag on, a mineral is short): rate r = 100 resources per kT (Mineral Alchemy 25). n = min(available
   resources div r, the shortfall). If n > 0, every mineral gets + n and resources − n × r. If n equals the
   shortfall, go back to 1; otherwise stop, and if resources are left, they become a **carry-over** mineral
   alchemy item (count 1) with progress q = max(((x + 1) × 100) div r − 1, (x × 100) div r) for x = resources left,
   and resources − (q × r) div 100.

After the loop: completed mineral alchemy units (3, 11) add 1 kT of every mineral each to available. An auto item
that ended with progress gets a carry-over item: its counterpart (auto mines become mines, auto factories
factories, and so on; confirmed in a harness game) with count 1 and that progress. A normal item's
queue entry is updated (count and progress).

### 6. Completing units (`Production_CompleteItem`)

| Items | Effect |
|---|---|
| mines, factories, defenses | n = min(units, maximum − built) are added (maximum: S08); none if n < 1 |
| alchemy | nothing more (step 5 added the minerals) |
| terraform | per unit, one terraforming step (S10): one axis moves 1 toward the race's ideal, kept within 1–99 |
| packets | needs the mass driver (else nothing); launched toward the destination (S14) |
| Genesis Device (13) | every player is told; unless the owner is Alternate Reality the planet loses its mines, factories, defenses and scanner; for i = 0, 1, 2 in turn: surface mineral i becomes 0, environment axis i (and its original value) = a + b + 1 with a = random(50) then b = random(50), and concentration i = c + d + 25 with c = random(40) then d = random(40) |
| scanners (18–26) | the planet's scanner becomes planetary part (item − 18) |
| scanner (27) | the best planetary scanner the owner can build |
| ship designs | step 6a |
| starbase designs | step 6b |

A design whose parts are no longer available, or that was deleted, completes nothing (ships: with a message).

### 6a. Ships

Ships are built only on a planet with a starbase.

1. **Fewer than 512 fleets:** a new fleet (S03: the player's lowest free fleet number) is created at the planet with
   all n ships of the design in one stack, full fuel (S12), no cargo, and one waypoint at the planet. The design's
   built and existing counts grow by n. Then:
   - if the planet has a route (S11), the fleet gets a second waypoint at the route's destination with the route
     task, at a warp chosen as `Fleet_FollowRoute` does (S11);
   - otherwise default orders: a fleet with mining robots built over an Alternate Reality race's own planet is set
     to remote-mine it (other new fleets get no orders; the merge-with-a-miner rule applies only to unowned planets,
     S11).
2. **512 fleets:** the ships join the first of the player's fleets (fleet order) at the planet's position whose
   stack of that design holds fewer than 32766 − n ships. Damage carries over: with N ships in the stack, p its
   damaged percentage and D its damage (in 1/500 of the design's armor A): if N = 0 or p = 0 the stack becomes
   undamaged; otherwise k = max(N × p div 100, 1) damaged ships carry E = ((D × A div 10) × k) div 50 damage points;
   after adding the ships, p' = (k × 100) div (N + n) (1 if that is 0), k' = max(p' × (N + n) div 100, 1) and
   D' = ((E × 5) div k' × 100) div A. If no fleet qualifies, nothing is built (message).

### 6b. Starbases

1. A message tells the player the starbase was built (with its dock size).
2. If the planet already has a starbase and the new design's hull comes earlier in the hull list than the old one's
   (orbital fort, space dock, space station, ultra station, death star), every ship item is removed from the
   planet's queue and the remaining starbase items lose their progress.
3. If the planet had no starbase it now has one; otherwise the old design's existing count drops by 1.
4. The starbase's design becomes the new design; its damage stays.
5. Mass driver: the best mass driver of the new design (S14; one more warp when it has two drivers of that speed)
   becomes the planet's driver speed. Without a mass driver, the planet's packet destination is cleared and every
   packet item is removed from the queue.
6. The design's built and existing counts grow by 1.

### 6c. Packets

A packet item needs a mass driver and a destination. Each unit carries 100 kT of its mineral (Packet Physics 70), or
40 kT of each for the mixed packet (PP 25) (the cost of step 1 includes the loss of launching), at most 32760 kT per
mineral. The packet's speed comes from the driver's speed setting, with adjustments for overdriving and for
Inter-stellar Traveler races that S14 specifies. A packet launched this year from the same planet to the same
destination at the same speed absorbs the new minerals; otherwise a new packet is created (S14).

## Randomness

Only the Genesis Device draws: 12 draws per device, 4 per index (two for the environment axis, then two for the
concentration). Building
ships and route following (S11) do not draw.

## Edge cases

- Resources not spent are never lost: they go to research.
- Mines, factories and defenses paid for beyond the planet's maximum are lost (the item is removed).
- A count above the room is cut down with a message; auto items never change their queue entry.

## Mod hooks

- Formulas: `production.item_cost`, `production.part_cost` (miniaturization and trait prices), `production.spend`.
- Trait parameters to introduce: mine and factory germanium (cheap factories option), defense price (IS 60%),
  alchemy rate (MA 25), terraform price (TT 70, CA 50%), packet costs (PP, IT), starbase price (ISB, AR 80%),
  miniaturization (BET: 5 per level, 80 max; doubling at the tech level), part prices by category (IT stargates,
  WM/IS weapons, CA terraform, CE engines).
- New production items: a `production_item` content type with cost and completion effect (MODDING §7).

## Open questions

1. The global flag that switches factory costs to 2 of each mineral (`DAT_1110_0790` bit 0x800).
2. The new fleet's other initial values (name, battle plan, flags) belong to S03/S11; check against a harness game
   that builds a ship.
3. Packet launching and merging with packets launched the same year: exact fields and the speed rules (S14).
4. When the original recomputes a design's stored cost after its owner's tech levels change.
5. Messages (S21) are not specified here.
6. Starbase prices are halved (rounding up) at production time: the starbase hull and part tables hold doubled
   prices (the Space Station hull lists 1200 resources). Our content keeps the original's table values; confirm the
   halving with a harness game that builds a starbase.
7. The Bleeding Edge doubling for parts excluded from miniaturization reads an uninitialized value in the original;
   check the disassembly.
