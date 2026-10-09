# S12 Movement and fuel

Status: draft (2026-09-30), second pass. Movement, fuel, ram scoops, warp-10 damage, stargates with overgating,
wormholes, arrival, waypoint advancing with repeat orders, and refueling read from the code. Intercept retargeting
details remain open. The wormhole shift (added 2026-10-03) is implemented in `core/rules/wormholes.gd` and matches
the original's drift in golden turns (no jump seen yet). Movement, fuel use, ram scoops, waypoints after movement
and refueling implemented in `core/rules/movement.gd` (2026-10-04), matching the original in terra1 turns 0-2;
following fleets, stargates, wormhole jumps, minefields and warp-10 damage not yet. Third pass (2026-10-06):
waypoint targets, following and chasing fleets read from `GenerateTurn`, `UpdateWaypointTargets`, `MoveFleets` and
`UpdateFleetTargetPositions`; implemented and verified by the follow1 game (turns 0-3: follow orders with a chain
and a failure, chasing a moving fleet, a chaser chasing a chaser in steps, a chased fleet merged away); the
retargeting draws are not seen there (a merged fleet's chasers are retargeted by the fleet deletion, S11).
Stargates (2026-10-06) implemented in `core/rules/stargates.gd` and verified by the gate1 game (an Inter-stellar
Traveler race, turns 0-1: a jump within the limits, jumps over both gates' mass limit with damage, damage adding
up on a second jump, a ship destroyed by its old and new damage, a jump to a planet without a gate); not yet seen:
ship losses and cargo left behind (other races), out of range, too massive, Jump Gates, other players' gates.
Wormhole jumps (2026-10-07) implemented in `core/rules/movement.gd` and verified by follow1 turn 13 (a scout with
a waypoint on a wormhole jumps to the far end; both ends seen, the far end tracked). The tracked mark is also set by
scanning (`Visibility_FleetScanners@1068:5d44`, S15): until visibility is built, a waypoint on a wormhole that the
player only sees through scanners can be lost sooner than in the original.
References: `MoveFleets@10a8:1f18`, `Fleet_CalcFuelUsage@1048:6312`, `Fleet_RamScoopFuel@1030:3726`,
`Fleet_UseStargate@1078:0962`, `Fleet_AllHaveJumpGate`, `UpdateWaypointTargets@1030:42c8`,
`UpdateFleetTargetPositions@1078:1060`, `RetargetFollowers`, `Fleet_CheckMinefields@10a8:30b6`,
`GenerateFleetFuel@10a8:1cfa`, `MoveSpaceObjects@10a8:0f6e`, `SpaceObject_ValidatePosition@1100:0456`, the
wormhole jump chance at 1100:0742 (named `Packet_GetWarp` in the notes). Community "Fuel Usage" and "Overgating" pages as oracles.

## Summary

Each turn every fleet with a destination moves toward its next waypoint at that waypoint's warp, up to warp² light
years, burning fuel that depends on its engines, its mass and its cargo. Fleets can run out of fuel, lose ships at
warp 10 with unsafe engines, jump through stargates and wormholes, and hit minefields on the way (S13).

## Data used

- Fleet: position, ships per design, cargo (with fuel in mg), waypoints (position, target, warp 1–10 or 11 for
  stargate travel, task).
- Designs (S04): engines and their fuel table (warp 0–10), mass, cargo and fuel capacity.
- Race traits: Improved Fuel Efficiency, Cheap Engines, Inter-stellar Traveler, Alternate Reality.

## Algorithm

### Which fleets move

At the start of movement every fleet is marked "didn't move" (S11 uses this mark). A fleet stays where it is when:

- it has no ships, or no next waypoint;
- its next waypoint's warp is 0;
- its current waypoint has a transport task (so "wait for %" holds it, S11) or a lay-mines task with years left.

Fleets are handled in fleet order (S11). Movement repeats for up to 11 passes so that fleets whose waypoint targets
another fleet move after their target; a pass only handles fleets not yet settled.

### Waypoint targets (S02 phases 4 and 21; `UpdateWaypointTargets@1030:42c8`)

Run at the start of the turn (phase 4, before following, below), after the turn's terraforming (phase 21), and
in phase 14 when a wormhole has vanished (not built yet). For each fleet in fleet order:

1. **Waypoint 0:** unless it targets a planet, its task is transport or merge, or the fleet is following (below),
   it becomes the planet the fleet orbits, else deep space.
2. The fleet's position (and waypoint 0's) is kept inside the universe: 1000 … width + 1000 on each axis.
3. For each later waypoint (from waypoint 0 for a following fleet) that targets a fleet and isn't frozen (a target
   that jumped through a gate, S12 stargates): if the target still exists, is at the waypoint's position, and isn't
   another player's fleet that went through a gate this turn, the target is marked **claimed**. Otherwise the
   waypoint is **retargeted** among the fleets at the waypoint's position owned by the old target's owner, in fleet
   order (the fleet itself can be one):
   - The heaviest one (ships' mass plus cargo, not fuel) with a ship of the class the moving fleet's battle plan
     prefers as its primary target: a later one replaces the best so far when heavier, or when equal and
     `random(2)` = 0. Classes by hull: 0 colony ships, 1 freighters, 2 scouts, frigates and destroyers, 3 cruisers
     and larger warships, 4 privateers, rogues, galleons, mine layers, Nubian and morphs, 5 bombers, 6 miners,
     7 fuel transports. Primary target 3 (armed ships) takes classes 2–4, 4 classes 1 and 5, 5 (unarmed) a fleet
     with no ship of classes 2–4, 6 class 7, 7 class 1; targets 0–2 match nothing.
   - Meanwhile one candidate is picked at random: with n the count so far, it replaces the pick when
     `random(n)` = 0, and, if n > 1 and it is already claimed, also `random(2)` ≠ 0.
   - The heaviest matching fleet wins, else the random pick; the waypoint takes it (and its position), and it is
     marked claimed. With no candidate the waypoint is left as it is.
   Claimed marks last for the turn's start (they are cleared when the first waypoint-task pass reaches the fleet).
4. A waypoint that targets a wormhole takes its current position while the fleet's owner tracks it (scanners,
   S15, or having come out of it). A wormhole that has moved while not tracked is lost: the waypoint stays at its
   last known position as deep space, with **`fleet.wormhole_vanished`** `[fleet]` (none when the wormhole no
   longer exists).

### Following a fleet (S02 phase 4, `GenerateTurn@10a8:0000`)

A fleet whose only waypoint (waypoint 0) targets a fleet is **following** it (the player sets this by choosing a
fleet at its position as waypoint 0):

1. At the start of the turn every fleet's following mark is set or cleared by that rule, then the waypoint targets
   are updated (above).
2. Then up to 8 rounds, while any follower changed in the previous round; each round goes over the fleets in fleet
   order. For a follower F with its target T:
   - T has a next waypoint: F gets a waypoint 1 copied from T's waypoint 1 (position, target, warp and task) but
     keeping F's own waypoint-0 task details (transport amounts and so on), and stays marked.
   - T exists with only a waypoint 0 that itself targets a fleet (a chain): F waits for a later round.
   - Otherwise (T gone, or not going anywhere): message **`fleet.follow_failed`** `[fleet]`, goto the fleet, and F
     is no longer following.
3. F moves normally toward its copied waypoint. At the end of movement a following fleet doesn't advance its
   waypoints: its waypoint 1 is dropped and it gets **`fleet.follow_done`** `[fleet]`, goto the fleet. Its
   waypoint 0 has become its new position (as for any fleet that moved), so the follow order ends, unless it
   didn't move.

### Chasing a fleet (`MoveFleets@10a8:1f18`, passes)

A fleet whose waypoint 1 targets a fleet that exists **chases** it: in the first movement pass it does everything up
to the move (Cheap Engines, warp-10 damage, Alternate Reality losses) and then waits, remembering its budget
B = w². Later passes (up to 11 in all) repeat while any chaser has budget left:

1. Its waypoint 1 takes the target's current position (unless frozen).
2. The step is the remaining budget when the target has finished moving this turn; otherwise the smaller of the
   remaining budget and (B + 4) div 5 (B the whole budget: remaining plus moved).
3. The move toward the target's position is made as for any fleet (distance rounded up, arrival, rounding, ram
   scoops for this step), except that fuel is charged for the whole distance chased so far: the fuel already used
   this turn is put back and the use for (moved + step) is taken. The fuel range used to cut the move short is the
   range with the fuel left, less what was moved.
4. If it didn't arrive, the step is added to what was moved and taken from the budget; with budget left (and fuel),
   it takes part in the next pass.
5. A fleet arriving on its target in a later pass marks the target as finished moving (the original then stops a
   target that was itself chasing: B12; our engine doesn't).

Each fleet's first-pass work happens once; only chasers take part in later passes, in fleet order.
Fourth pass (2026-10-09): warp-10 damage and Alternate Reality transit losses implemented (`Movement._move`).
mine1 turn 64: a one-ship fleet lost to its warp-10 roll (destroyed, its design's count lowered) next to a
two-ship fleet whose rolls both passed. Losing some of a fleet's ships and the Alternate Reality losses are
unit-tested only.

### Cheap Engines failure

For a Cheap Engines race, a fleet travelling above warp 6 (not stargate travel) draws `random(10)`; on 0 the engines
don't engage, the player is told, and the fleet doesn't move this turn.

### Warp-10 engine damage

A fleet travelling at warp 10: for every ship whose design's engine is not one of Interspace-10, Enigma Pulsar,
Trans-Star 10, Trans-Galactic Mizer Scoop or Galaxy Scoop, draw `random(10)`; on 0 that ship is destroyed. Ships are
rolled design by design, one draw per ship. The lost ships leave their design's count of ships in service. If no
ships are left the fleet is gone: **`fleet.engines_exploded`** `[fleet]`, and it doesn't move. Otherwise the cargo
their capacity held is lost (S11 "Cargo after a ship move") and the player is told: one ship
**`fleet.warp10_ship_lost`** `[fleet]`, more **`fleet.warp10_ships_lost`** `[ships, fleet]` (goto the fleet).
The engines are tagged `warp10_safe` in content.

### Alternate Reality colonists in transit

An Alternate Reality fleet carrying more than 10 colonists (cargo units) loses (colonists + 11) × 3 div 100 of them
when it moves (trait parameter `movement.transit_loss_pct` 3): **`fleet.colonists_died_in_transit`**
`[colonists, fleet]`. Order for a moving fleet, once, before its first step: the Cheap Engines roll, then these
losses, then the warp-10 rolls; none of them for stargate travel.

### Fuel use

For a move of distance d (light years) at warp w:

1. For each design in the fleet: the engine is the part in the design's first engine slot. If that slot isn't
   completely filled, the ship can't move (it counts as using an enormous amount of fuel). Otherwise f = the engine's
   fuel table value at warp w; with Improved Fuel Efficiency, f = f − (15f) div 100.
2. The fleet's cargo (minerals and colonists, not fuel) is spread over its designs in increasing order of f: each
   design takes up to its total cargo capacity before the next.
3. usage = Σ over designs with f > 0 of (f × d × m) div 2000, where m = the design's mass × ship count + the cargo
   it carries. For large values the original uses floating point to avoid overflow; the result is the same
   quantity.
4. Fuel needed = (usage + 9) div 10 mg.

(Community check: 1 mg moves 200 kT one light year at fuel factor 100, which is the same ÷ 20000.)

The same routine also gives the fleet's range with its current fuel: (fuel × 1000) div (usage for 1000 ly).

### Moving

1. The move budget is w² light years; a fleet following another fleet uses the target's current position. The
   move m = min(budget, trunc(distance to the target + 0.9999)), so the distance is rounded up (the constant is in
   the data segment at 1110:1fb8; seen in the harness: 9.2 ly cost fuel for 10, terra1 turn 40); the fuel use is
   computed for m.
2. If the fleet has enough fuel for the move, subtract the fuel needed. Otherwise it moves only as far as its fuel
   allows and ends with 0 fuel. Either way, a fleet whose tank is empty after a move that used fuel, and that did
   not get within reach of its target (m + 0.99999 ≤ distance) or could not move at all, has **run out of fuel**
   (seen in long1 turn 31: exactly enough fuel for a 36 ly leg, still out of fuel): its next waypoint's warp is
   lowered to the highest warp at which it uses no
   fuel (if that is warp 1 or less the fleet is stuck), with a message.
3. If the budget reaches the destination, the fleet is placed on it (on the planet if the waypoint targets a
   planet). Otherwise it moves along the straight line: with r = m ÷ distance in floating point,
   x = x₀ + trunc((x₁ − x₀) × r + h), where h = +0.5 when x₁ > x₀ and −0.5 otherwise (rounding to the nearest light
   year, halves away from zero; the constants are in the data segment at 1110:1f98), likewise y. (Seen in the
   harness: a move of 36 ly with Δy = −173 lands at −36, terra1 turn 31.) A fleet arrives when m covers the distance rounded down (trunc(distance)
   ≤ m), so it can arrive although fuel was charged for the distance rounded up (seen in long1 turn 15: 36.7 ly at
   warp 6, and terra1 turn 33: 1.4 ly at warp 1); a fleet whose rounded position is its target's has also arrived.
4. Minefields are checked along the path (S13) and may stop the fleet early.
5. A fleet that moves loses its "didn't move" mark.
6. **Ram scoops:** a fleet moving at warp w ≤ 8 makes fuel for each design whose engine uses no fuel at w: with e the
   number of engines on the design, k = e; if warp w + 1 is also free, k = 3e; if w + 2 is too, k = 6e; if w ≤ 7 and
   w + 3 is free as well, k = 10e. Fuel made = Σ ships × k × s, where s = min(m, trunc(distance − 0.99999)) (the
   constant is at 1110:1fc8; a 1.4 ly arrival makes nothing, a 2.2 ly move counts 1; seen in long1 turn 28 and
   terra1 turn 32), added up to the free fuel space (the message shows at most 32,500). A fleet that ran out of fuel
   this turn makes none.
7. **Radiating Hydro-Ram Scoop:** a fleet using it, carrying colonists of a race that isn't immune to radiation and
   whose radiation range center c = (low + high) div 2 is below 85, loses colonists × ((86 − c) div 2) div 100 (at
   least 1).
8. **Wormholes:** a fleet that arrives on its waypoint's position when that waypoint targets a wormhole (merely
   passing over one does nothing) comes out at the other end: both ends are marked seen by its owner, the far end
   is marked known (tracked) by its owner, other players' waypoints that target the fleet are frozen at the near
   end (`RetargetFollowers`), and the fleet and its waypoint are placed on the far end. The rest of the step
   (ram scoops, waypoints) then sees it there. A wormhole that jumps (phase 14) is no longer tracked by anyone.
9. Fleet positions are kept inside the universe (1000 … width + 1000) by the retargeting step (S02 phase 4 and 21).

### Waypoints after movement

After all movement passes:

1. Waypoints that target a fleet (from waypoint 1) are moved to that fleet's position (unless frozen because the
   target jumped through a gate); if the target no longer exists the waypoint becomes a deep-space waypoint
   (`UpdateFleetTargetPositions@1078:1060`). A following fleet only drops its waypoint 1 (above).
2. A fleet that reached its next waypoint copies it into its current waypoint (if that targeted a fleet, it becomes
   the planet or deep space the fleet is at), then the reached waypoint is removed from the list. A fleet that moved
   only part of the way has its current waypoint moved to its position as a deep-space waypoint; the waypoint keeps
   its warp and task (seen in the harness: warp 6 kept, terra1 turn 36).
3. **Repeat orders:** with repeat on, the reached waypoint is also appended at the end of the list, so the route
   loops, unless the list had only two waypoints or the last waypoint is at the reached one's position
   (`Fleet_RemoveWaypoint@1048:6230`; seen in long1 turn 1: a two-waypoint route with repeat on ends with one
   waypoint).

### Refueling (S02 phase 15)

1. A fleet at a planet whose starbase belongs to its owner or a friend **and has a dock** (Space Dock and larger; an
   Orbital Fort has none) is refueled to full capacity.
2. Otherwise the fleet makes fuel: 50 mg per Anti-Matter Generator and 200 mg per ship with the Fuel Transport or
   Super-Fuel Xport hull, up to its capacity.

### Stargates (warp 11; `MoveFleets@10a8:1f18`, `Fleet_UseStargate@1078:0962`, `Fleet_StargateRange@1078:0e10`)

A fleet whose next waypoint has warp 11 jumps through stargates in the first movement pass. It makes no Cheap
Engines roll, no warp-10 damage roll, uses no fuel and isn't checked against minefields. A planet's stargate is the
first stargate part on its starbase's design (`Planet_GetStargate@1030:0af8`). "Owned by the fleet's owner or a
friend" means the planet's owner is the fleet's owner or has the fleet's owner as a friend. Each refusal below is a
message and the fleet stays where it is.

1. **Source:** if waypoint 0 is a planet with a stargate, the planet must be owned by the owner or a friend
   (**`fleet.gate_source_not_ours`** `[fleet, planet, planet]`, goto the fleet; every refusal message's goto is the fleet). With no stargate there, every ship must
   carry a Jump Gate (`Fleet_AllHaveJumpGate@1030:4bde`), else **`fleet.gate_none_here`** `[fleet, where]` (where is a pair:
   −1 and the planet, or the position's x and y).
2. **Destination:** waypoint 1's planet (or the planet at its position): none, **`fleet.gate_no_destination`**
   `[fleet, where]` (the position); no stargate there, **`fleet.gate_none_there`** `[fleet, destination, where]` (the original passes the
   destination where the text has the source);
   not owned by the owner or a friend, **`fleet.gate_blocked`** `[fleet, destination, destination, destination]` (likewise).
3. With a Jump Gate and no source stargate, the destination's gate stands for the source gate too.
4. **Cargo:** races other than Inter-stellar Traveler can't take cargo through a gate (not with a Jump Gate): with
   colonists aboard at a planet that isn't the owner's the jump is refused (**`fleet.gate_colonists`**
   `[fleet, planet]`); otherwise all minerals and colonists are put on the source planet first, with a message to
   the fleet's owner, and the same to the planet's owner if that is another player (goto the planet):
   **`fleet.gate_unloaded_minerals`** `[fleet, kT, planet]`, **`fleet.gate_unloaded_colonists`**
   `[fleet, colonists, planet]` or **`fleet.gate_unloaded_both`** `[fleet, colonists, kT, planet]` (colonists in
   units of 100). The cargo stays unloaded even if the jump is then refused.
5. **Limits, per design in the fleet** (in slot order), with d the distance (truncated), m the design's mass (the
   ship, not its cargo), R the **source** gate's range (unlimited = 8000) and L₁, L₂ the source and destination
   gates' mass limits (unlimited: no limit):
   - d > 5R: refused, **`fleet.gate_out_of_range`** `[fleet, source, destination]`; m > 5L₁ or m > 5L₂: refused,
     **`fleet.gate_too_massive`** `[fleet, source, destination, design slot]`. The first design that fails stops the
     check.
   - Survival S starts at 10000. For each limit exceeded, in the order range, L₁, L₂, the factor is
     (5X − x) × 2500 div X (X the limit, x the value); S becomes the factor for the range and S × factor div 10000
     for a mass limit. A factor below 1 means the design's ships are all lost (damage 100%).
   - The design's damage D = (10000 − S) div 100 percent.
6. **Applying D to a design** with n ships, armor A, and before the jump p% of them damaged by e/500 of A
   (k = p × n div 100 damaged ships, at least 1 if p > 0):
   - D = 100: all n ships are lost.
   - Races other than Inter-stellar Traveler: for each of the n ships draw `random(100)`; below D div 3 the ship is
     lost, and then, while damaged ships remain (k > 0), a draw `random(500)` below e makes the lost ship one of
     them (k − 1).
   - Survivors: the old damage is c = e × A div 500 (at least 1 when e > 0), the new d′ = D × A div 100 (at
     least 1). If k > 0 and c + d′ ≥ A, the k damaged ships are destroyed. The survivors' damage becomes
     ((d′ × survivors + c × k) div survivors) × 500 div A (at least 1) with 100% of them damaged. **B33:** the
     original keeps k after destroying the damaged ships, so their old damage still counts; our engine sets k to 0
     first.
7. Lost ships leave their design's count of ships in service. If no design has ships left the fleet is lost (**`fleet.gate_lost`** `[fleet, source, destination]`, goto the
   fleet). Otherwise, when ships were lost, the cargo the lost ships' capacity held is lost as for a ship move (S11
   "Cargo after a ship move", the lost ships moving to a fleet that vanishes), and the owner is told:
   **`fleet.gate_lost_few`** (fewer than a quarter of the ships), **`fleet.gate_lost_most`** (more than half) or
   **`fleet.gate_lost_some`**, each `[fleet, source, destination, ships lost]`.
8. The fleet is placed on the destination. Other players' waypoints that target it are frozen at its old position
   (`RetargetFollowers@1078:133e`). The fleet is marked as gated this turn (no repair, S19).

### Wormholes shift (S02 phase 14)

After production, every wormhole end, in wormhole number order (S03), moves:

1. **Jump or drift:** chance c = (age div 5) + stability − 2, kept within 0–6 (percent). One draw `random(100)`;
   below c the wormhole **jumps**: its age becomes 0 and the record of players who have been through it is cleared.
   Otherwise it **drifts** and its age grows by 1.
2. **New position:** up to 100 tries. A drift try is x = old x − 12 + random(25), y = old y − 12 + random(25); a
   jump try is x = 1000 + random(W), y = 1000 + random(W) (W the universe width). A try that lands exactly on the
   old position is skipped (no score). Otherwise it is scored as when wormholes are placed (S07 step 12.3, the
   wormhole's partner counting as its partner); a score of 0 is taken at once. Otherwise the position with the
   lowest score is kept (the first such), and used after the last try.

The two ends move independently. Packets launched this year move in the same phase (S14).

## Randomness

In fleet order: Cheap Engines (`random(10)` per fleet above warp 6), warp-10 damage (`random(10)` per ship at
risk), overgating (`random(100)` per ship, plus `random(500)` for each lost ship while damaged ships remain), minefield
hits (S13). After production (phase 14), per wormhole in number order: `random(100)` for the jump, then 2 draws
per position try.

## Edge cases

- A design with a partly filled engine slot can't move at all.
- A fleet with no fuel can still move at warps its engines do for free.
- Cargo goes on the most fuel-efficient ships first, which lowers fuel use for mixed fleets.
- Hints from the player's guide, to confirm in the code when these parts are written: a fleet can exceed a
  stargate's mass or range limit up to five times and still arrive, always damaged and possibly destroyed; Alternate
  Reality colonists in a fleet lose 3% a year in transit.

## Worked examples

- Scout (mass 14 with Quick Jump 5 and Bat Scanner) at warp 5 (f = 100) for 25 ly: 100 × 25 × 14 div 2000 = 17;
  fuel (17 + 9) div 10 = 2 mg.
- Same with Improved Fuel Efficiency: f = 100 − 15 = 85; 85 × 25 × 14 div 2000 = 14; fuel 2 mg.
- Overgating: Stargate 100/250, a 150 kT ship jumping 300 ly (both gates 100/250): range factor
  (1250 − 300) × 2500 div 250 = 9500; mass factor (500 − 150) × 2500 div 100 = 8750 for each gate;
  S = 9500 × 8750 div 10000 = 8312, then × 8750 div 10000 = 7273; D = (10000 − 7273) div 100 = 27%; loss chance per
  ship 27 div 3 = 9% (none for Inter-stellar Traveler).
- Ram scoop: Galaxy Scoop is free up to warp 9, so at warp 6 one engine gives k = 10 (warps 7, 8, 9 also free); a
  single ship moving 36 ly makes 10 × 36 = 360 mg.

## Mod hooks

- Formulas: `movement.fuel_use`, `movement.move_budget`, `movement.engine_failure` (Cheap Engines),
  `movement.warp10_damage`, `movement.stargate`.
- Content: engines' `fuel_table`, the `warp10_safe` behaviour (to become an engine tag), trait parameters
  (IFE 15%, CE failure 10%).

## Open questions

1. Retargeting a waypoint whose fleet is gone or moved (`UpdateWaypointTargets`) is read from the code but not yet
   seen in a fixture: a fleet deleted by an order or task already has its chasers retargeted (S11), so it mostly
   matters for other players' fleets going out of sight (S15). Also unconfirmed: whether "other player's fleet
   that went through a gate" is the flag read there, and the effect of B12 (a chaser reached by another chaser
   stops: our engine doesn't stop it).
2. The fuel adjustment after a move for fleets that started with enough fuel (the code sets fuel to at least the
   planned usage; purpose unclear).
