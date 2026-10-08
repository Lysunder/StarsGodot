# S19 Repair, refueling and colonist growth in fleets

Status: draft (2026-10-08). Implemented in `core/rules/repair.gd` (repair, growth) and `core/rules/movement.gd`
(refueling, S12). Starbase repair verified by terra1 turn 31 (12 points of damage repaired in one year); fleet
repair by mine1 turns 56-58 (two destroyers damaged by a detonation don't repair that year, repair 5 the year they
move home and 100 the next at their own starbase with a dock). Inner-Strength repair, the repair hulls and growth in
fleets are unit-tested only.
References: `RepairFleetsAndStarbases@10b0:28de`, `GenerateFleetFuel@10a8:1cfa`, `GrowColonistsInFleets@10b0:4aa4`.

## Summary

Each year damaged ships repair a little, more when they stay put and most at their own starbase with a space dock;
Inner-Strength races repair twice as fast, and fleets with a fuel transport hull repair faster. Starbases repair
too. Fleets at a friendly starbase with a dock fill their fuel tanks; elsewhere fuel transports and Anti-Matter
Generators make fuel. Colonists carried by Inner-Strength fleets grow on board.

## Data used

- A ship stack's damage (`damage`, 0..499, the share of a ship's armor in five-hundredths) and `damaged_percent`.
- A starbase's damage in armor points.
- Fleet turn marks: `did_not_move` (S12), `gated` (S12), `mine_hit` (S13: a hit during movement, including a
  speed bump's stop, or damage from a detonation).
- Hull stats `repair_bonus` (Fuel Transport 25, Super-Fuel Xport 50), `fuel_generation` (both 200 a ship), `dock`.
- Trait parameters `repair.fleet_pct` (Inner-Strength 200), `repair.starbase_pct` (IS 150),
  `fleet.colonist_growth` (IS 1).

## Algorithm

### Refueling (S02 phase 15, `GenerateFleetFuel`)

Already specified in S12 (`Movement.refuel_all`): a fleet with ships at a planet whose starbase has a dock and
belongs to the fleet's owner or someone who counts the fleet's owner as a friend fills its tanks; otherwise it makes
Σ ships × (50 per Anti-Matter Generator + 200 when the design's hull is a Fuel Transport or Super-Fuel Xport),
unless that would go past its fuel capacity, in which case it fills its tanks. (Until 2026-10-08 our hulls lacked
the 200.)

### Colonists growing in fleets (S02 phase 12)

Nothing happens (no rolls) unless some race has `fleet.colonist_growth`. Otherwise, in fleet order, each fleet with
ships and colonists aboard whose owner has it:

1. g = growth rate (percent) × colonists (hundreds) div 200. If g < 1: `random(3)`; unless that is 0 the fleet
   gets nothing; else g = 1.
2. As many as fit in the cargo hold (capacity minus minerals and colonists aboard) come aboard:
   **`fleet.colonists_grew`** `[fleet, colonists]` when that is more than 0 (goto the fleet).
3. The rest go down to the planet the fleet orbits if the fleet's owner owns it:
   **`fleet.colonists_overflowed`** `[fleet, colonists, planet]` (goto the fleet); otherwise they are lost.

### Repair (S02 phase 18)

1. **Fleets**, in fleet order: a fleet with ships that wasn't hit by mines or gated this turn and has a damaged
   stack repairs. Rate by where it is: 5 if it moved this year; else 10 in deep space; 15 at another player's
   planet; 25 at its owner's planet without a starbase; 40 at its owner's starbase without a dock; 100 at its
   owner's starbase with a dock. × `repair.fleet_pct` / 100. Plus the best `repair_bonus` of the hulls of its
   ships. Each damaged stack: if the amount is less than its damage, the damage drops by it; otherwise the stack is
   whole (damage 0, damaged 0%).
2. **Starbases**, in planet order: each starbase with damage repairs 50 × `repair.starbase_pct` / 100 armor points
   (at least down to 0).
3. The `mine_hit` and `gated` marks are cleared.

## Randomness

`random(3)` per growing Inner-Strength fleet whose growth is below 1 (only in games with an Inner-Strength race).

## Edge cases

- A starbase that fought this year doesn't repair (the original's mark; battles are M9).
- Fleets that fought don't repair either (the original sets the same mark as mine hits; M9).
- The fleet's location is its planet, if it orbits one, after movement and all waypoint tasks.

## Mod hooks

Trait parameters above; hull stats `repair_bonus`, `fuel_generation`; the rate constants.

## Open questions

1. Whether the original's battle mark on fleets is the same as the mine-hit mark (the code sets bit 0x40 in both
   places; to confirm with M9).
