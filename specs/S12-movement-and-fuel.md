# S12 Movement and fuel

Status: draft (2026-09-30), second pass. Movement, fuel, ram scoops, warp-10 damage, stargates with overgating,
wormholes, arrival, waypoint advancing with repeat orders, and refueling read from the code. Intercept retargeting
details remain open. The wormhole shift (added 2026-10-03) is implemented in `core/rules/wormholes.gd` and matches
the original's drift in golden turns (no jump seen yet). Movement, fuel use, ram scoops, waypoints after movement
and refueling implemented in `core/rules/movement.gd` (2026-10-04), matching the original in terra1 turns 0-2;
following fleets, stargates, wormhole jumps, minefields and warp-10 damage not yet.
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

### Cheap Engines failure

For a Cheap Engines race, a fleet travelling above warp 6 (not stargate travel) draws `random(10)`; on 0 the engines
don't engage, the player is told, and the fleet doesn't move this turn.

### Warp-10 engine damage

A fleet travelling at warp 10: for every ship whose design's engine is not one of Interspace-10, Enigma Pulsar,
Trans-Star 10, Trans-Galactic Mizer Scoop or Galaxy Scoop, draw `random(10)`; on 0 that ship is destroyed. Ships are
rolled design by design, one draw per ship. If no ships are left the fleet is gone; otherwise cargo is redistributed
over the remaining ships and the player is told how many were lost.

### Alternate Reality colonists in transit

An Alternate Reality fleet carrying more than 10 colonists (cargo units) loses (colonists + 11) × 3 div 100 of them
when it moves.

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
   move m = min(budget, distance to the target truncated to an integer); the fuel use is computed for m.
2. If the fleet has enough fuel for the move, subtract the fuel needed. Otherwise it moves only as far as its fuel
   allows and ends with 0 fuel; then its next waypoint's warp is lowered to the highest warp at which it uses no
   fuel (if that is warp 1 or less the fleet is stuck), with a message.
3. If the budget reaches the destination, the fleet is placed on it (on the planet if the waypoint targets a
   planet). Otherwise it moves along the straight line: x = x₀ + trunc((x₁ − x₀) × budget ÷ distance), likewise y,
   with the distance computed in floating point.
4. Minefields are checked along the path (S13) and may stop the fleet early.
5. A fleet that moves loses its "didn't move" mark.
6. **Ram scoops:** a fleet moving at warp w ≤ 8 makes fuel for each design whose engine uses no fuel at w: with e the
   number of engines on the design, k = e; if warp w + 1 is also free, k = 3e; if w + 2 is too, k = 6e; if w ≤ 7 and
   w + 3 is free as well, k = 10e. Fuel made = Σ ships × k × distance moved, added up to the free fuel space (the
   message shows at most 32,500).
7. **Radiating Hydro-Ram Scoop:** a fleet using it, carrying colonists of a race that isn't immune to radiation and
   whose radiation range center c = (low + high) div 2 is below 85, loses colonists × ((86 − c) div 2) div 100 (at
   least 1).
8. **Wormholes:** a fleet arriving on a wormhole is moved to the other end; both ends become known to its owner.
9. Fleet positions are kept inside the universe (1000 … width + 1000) by the retargeting step (S02 phase 4 and 21).

### Waypoints after movement

After all movement passes:

1. Waypoints that target a fleet are moved to that fleet's position (unless frozen because the target jumped through
   a gate); if the target no longer exists the waypoint becomes a deep-space waypoint.
2. A fleet that reached its next waypoint copies it into its current waypoint (if that targeted a fleet, it becomes
   the planet or deep space the fleet is at), then the reached waypoint is removed from the list. A fleet that moved
   only part of the way gets a new current waypoint in deep space at its position (warp 0, no task).
3. **Repeat orders:** with repeat on, the removed waypoint is appended at the end of the list, so the route loops.

### Refueling (S02 phase 15)

1. A fleet at a planet whose starbase belongs to its owner or a friend **and has a dock** (Space Dock and larger; an
   Orbital Fort has none) is refueled to full capacity.
2. Otherwise the fleet makes fuel: 50 mg per Anti-Matter Generator and 200 mg per ship with the Fuel Transport or
   Super-Fuel Xport hull, up to its capacity.

### Stargates (warp 11)

1. The fleet must be at a planet with a stargate owned by its owner or a friend, or every ship must have a Jump
   Gate.
2. The destination must be a planet with a stargate owned by the owner or a friend.
3. Races other than Inter-stellar Traveler can't take cargo through a gate: minerals and colonists are left on the
   source planet first; if colonists are aboard and the source planet isn't the owner's, the jump is refused.
4. **Limits, per design in the fleet**, with R the gate's range and L₁, L₂ the two gates' mass limits (−1 =
   unlimited; an unlimited range counts as 8000), d the jump distance and m the ship's mass:
   - d > 5R, or m > 5L for either gate: the jump is refused with a message ("out of range" / "too massive").
   - Survival S starts at 10000. For each limit exceeded (d > R, m > L₁, m > L₂) multiply by the factor
     (5X − x) × 2500 div X (X the limit, x the value), dividing by 10000 after the first: the factor falls linearly
     from 10000 at the limit to 0 at five times the limit. A factor below 1 destroys the design's ships outright.
   - Damage D = (10000 − S) div 100 percent.
5. **Applying damage D to a design's ships (n ships, armor A):**
   - Races other than Inter-stellar Traveler lose ships: for each ship draw `random(100)`; below D div 3 the ship is
     lost, and if already-damaged ships remain, a second draw `random(500)` against their damage level decides whether
     the lost ship was one of them.
   - The survivors take d = D × A div 100 damage each (at least 1). If already-damaged ships would reach their armor
     (d + their existing damage ≥ A) they are destroyed. The rest share the new average damage, and all count as
     damaged.
   - The player is told how many ships were lost (few, many, most).
6. The rule for which gate's range applies (source or destination) is to be confirmed; mass limits apply for both.

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
risk), overgating (`random(100)` per ship, plus `random(500)` for lost ships while damaged ships remain), minefield
hits (S13). After production (phase 14), per wormhole in number order: `random(100)` for the jump, then 2 draws
per position try.

## Edge cases

- A design with a partly filled engine slot can't move at all.
- A fleet with no fuel can still move at warps its engines do for free.
- Cargo goes on the most fuel-efficient ships first, which lowers fuel use for mixed fleets.

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

1. Intercepting and following: the retarget rules in `UpdateWaypointTargets` for fleets that become invisible, and
   the fix for B12 (a fleet "stuck" while a lower-numbered fleet targets it): our engine resolves follow chains in
   dependency order with cycle handling.
2. Which gate's range applies to a jump (source or destination).
3. The fuel adjustment after a move for fleets that started with enough fuel (the code sets fuel to at least the
   planned usage; purpose unclear).
