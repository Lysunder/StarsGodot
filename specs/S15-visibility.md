# S15 Visibility

Status: draft (2026-10-09), first part: scanner ranges and what scanning records in the game state (minefields
known and seen, wormholes tracked). Not yet: cloaking and what each player's view holds (fleets and planets seen and
at what detail, design knowledge, planet reports), Inter-stellar Traveler stargate scanning, Space Demolition
minefield scanning, and the waypoint changes the original makes when a target is out of sight.
References: `ComputeVisibility@1068:5872`, `Visibility_Reset@1068:58e4`, `Visibility_FleetScanners@1068:5d44`,
`Visibility_PlanetScanners@1068:6340`, `Visibility_PacketScanners@1068:6bc0`, `Visibility_Designs@1068:71a4`,
`Design_ScannerRange@1030:336a`, `Fleet_ScannerRanges@1030:31a2`, `Planet_ScannerRange@1030:302e`,
`Fleet_ComputeCloak@1078:1e02`, `Slot_CloakUnits@1078:20c8`, `Design_CloakUnits@1040:55f4`,
`Planet_MarkSeen@1068:51cc`, `Fleet_MarkSeen@1068:5028`, `WriteGameFile@1068:35b0`.

## Summary

At the end of each turn the original works out, player by player, what that player's fleets, planets and (Packet
Physics) packets can see, and writes the player's turn file from it. Most of the result only shapes the turn file,
but some of it stays in the game: which players know of each minefield and saw it this year, and which players
track each wormhole.

## Data used

- Scanner parts: `scan_range` (normal range) and `pen_range` (penetrating range) stats. Ship scanners with a
  penetrating range: Chameleon 45, Ferret 50, Dolphin 100, Robber Baron 120, Elephant 200 (the original reads them
  from a small table by part, not from the part record). Other parts with a normal range: Mega Poly Shell 80,
  Multi Contained Munition 150, Langston Shell 50. Planetary scanners: Viewer and Scoper ranges are normal only;
  the Snoopers' penetrating range is half their normal range.
- A race's primary trait and the No Advanced Scanners trait; its electronics tech level (Jack of all Trades).
- Minefield `known_by`, `seen_by`; wormhole `tracked_by`.

## Algorithm

### Scanner ranges

**A design** (`Design_ScannerRange`): N = Σ over parts count × (normal range)⁴, P = Σ count × (penetrating
range)⁴ (in floating point). A Jack of all Trades race's Scout, Frigate and Destroyer hulls add a built-in scanner:
N += (20 × electronics level)⁴ and P += (10 × electronics level)⁴ (seen: a scout at electronics 3 sees a field
29 ly away, mine1 turn 27). The normal range is trunc(⁴√N), doubled for No Advanced Scanners; it is −1 ("no
scanner") when N is 0 and the design has no scanner-category part (a Bat Scanner gives range 0). The penetrating
range is trunc(⁴√P).

**A fleet**: the largest normal and penetrating ranges among the designs it has ships of; a fleet without any
scanner has range 0 for scanning.

**A planet** (`Planet_ScannerRange`): an Alternate Reality planet sees trunc(√(10 × population in hundreds)); with
No Advanced Scanners that is × 1412 div 1000 and it has no penetrating range; otherwise, when the planet's starbase
is an Ultra Station or Death Star, a penetrating range of half that. Other planets: 0 without a planetary scanner;
otherwise the owner's best planetary scanner (by tech): its normal range (doubled for No Advanced Scanners) and,
for a Snooper, half its range as penetrating range.

**A Packet Physics packet in flight** scans speed² light years around it (no penetrating range).

### What scanning records (`ComputeVisibility`, at the end of the turn)

For each player in order, scanning runs fleets (fleet order), then planets (planet order), then packets (space
object order). d² is the squared distance from the scanner, R and P its normal and penetrating ranges:

- **A minefield** (the player's own included) not yet seen by this player this year:
  - by a fleet: seen when d² ≤ the mine count (the fleet is inside it), d² ≤ P², d² ≤ R² div 16, or the player
    already knows the field and d² ≤ R²;
  - by a planet: only within R (d² ≤ R²), and then when d² ≤ P², d² ≤ R² div 16, or the player already knows it;
  - by a packet: within R.

  A seen field gets the player in `known_by` and in `seen_by`. (A field just laid is seen by its owner this way:
  the layer is inside it.)
- **A wormhole** within R (d² ≤ R²), for a fleet or planet: the player tracks it (`tracked_by`) when it already
  tracks it, d² ≤ R² div 16 or d² ≤ P²; for a packet: within R.

`seen_by` is emptied at the start of each turn (S13, S02 phase 7).

## Randomness

None in this part. (Space Demolition minefield scanning, not built yet, draws `random(100)` per cloaked fleet inside
the race's fields while the turn files are written.)

## Edge cases

- A planet without a scanner has range 0: it still "sees" objects exactly at its position.
- Scanning happens after the turn's events: a field laid this year is seen by a fleet already inside it.

## Open questions

1. A game setting (bit 3 of the word at 1110:0080) replaces the Jack of all Trades built-in scanner by a fixed one
   (40 ly, penetrating 20 ly); which setting it is.
2. Which code sets a wormhole's `seen_by` (not the scanning code).
