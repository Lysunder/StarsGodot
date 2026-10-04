# S24 Tech trading (tech gain)

Status: draft (2026-10-04), first part: the bonus for ships scrapped at a starbase. Battle and invasion gains and
Mystery Trader parts are not read yet.
References: `TryTechBonus@10e8:6112`, `NoteDesignTech@1078:244c`, `Tech_LevelCost@10d0:1546`,
`DoWaypointTaskPass@10a8:3ec6` (scrap).

## Summary

A player can learn from other players' ships: when ships are scrapped at a planet with a starbase, the planet's
owner may gain research points in a field where the ships' parts are more advanced than its own tech, or a Mystery
Trader part found among them. At most one such gain per player per turn.

## Data used

- The scrapped fleet's designs: the tech each hull and part in use needs (S04), and whether any is a Mystery
  Trader part.
- The receiving player's tech levels, research points per field, and a per-turn mark "already gained this turn"
  (turn-only, cleared when the turn advances; S02 phase 25).

## Algorithm

When a fleet is scrapped at a planet with a starbase (S11 "Scrap"), after the minerals are recovered:

1. Need: for each tech field, the highest level any hull or part in use (slot count above zero) of the fleet's
   designs needs (stacks with ships only).
2. If the planet's owner already gained this turn, nothing happens (no draws).
3. Draw `random(100)`; at 49 or below nothing happens.
4. Thirteen times: draw `random(13)`, a Mystery Trader part kind; if the scrapped ships hold that part, the player
   does not have it yet, and `random(100)` is below the part's chance, the player gains the part and the mark is set
   (not built yet: no Mystery Trader part is marked in content, so only the 13 draws are made).
5. Six times: draw `random(6)`, a field; if the player's level in it is below the need, the player gains research
   points in that field equal to the cost of its next level (S05, without the slow-tech doubling), the mark is set,
   and the tries stop.

The points join the field's research points; levels follow at the next tech update (S05).

## Randomness

All draws from the classic stream, in the order above: `random(100)`, then 13 × `random(13)` (each followed by
`random(100)` only when that part kind was seen), then up to 6 × `random(6)`. The draws happen even when the ships
need no more tech than the player has, which shifts every later draw of the turn (seen in the harness: the
homeworld's mining fraction rounded differently, terra1 turn 29).

## Edge cases

- Scrapping one's own ships at one's own starbase normally gains nothing (own tech is at least what the designs
  need) but still draws.
- Scrapping at a planet without a starbase, or in deep space, never calls the bonus.

## Known bugs

None known.

## Worked examples

terra1 turn 29 (harness): player 0 scrapped its own Mini-Miner at its homeworld starbase; nothing was gained, and
the turn matches only with the draws made.

## Mod hooks

None yet; planned: `tech_gain.bonus` formula, `on_tech_gained` hook.

## Open questions

1. Mystery Trader part kinds and chances (the 13 entries `NoteDesignTech` fills).
2. The battle and invasion callers.
