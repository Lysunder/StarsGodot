# S15 Visibility

Status: draft (2026-10-09). First part: scanner ranges and what scanning records in the game state (minefields known
and seen, wormholes tracked). Second part: cloaking and each player's view of the turn (the other players' planets,
fleets and designs seen and at what detail, the players met, and the packets, wormholes and traders in view),
including Inter-stellar Traveler stargate scanning and Space Demolition minefield scanning. Not yet: what battles show
(M9), planets lost to invasion or bombing (S17, M9), the waypoint changes the original makes when a target is out of
sight, and planet reports kept from earlier years.
References: `ComputeVisibility@1068:5872`, `Visibility_Reset@1068:58e4`, `Visibility_FleetScanners@1068:5d44`,
`Visibility_PlanetScanners@1068:6340`, `Visibility_PacketScanners@1068:6bc0`, `Visibility_Designs@1068:71a4`,
`Design_ScannerRange@1030:336a`, `Fleet_ScannerRanges@1030:31a2`, `Planet_ScannerRange@1030:302e`,
`Fleet_ComputeCloak@1078:1e02`, `Slot_CloakUnits@1078:20c8`, `Design_CloakUnits@1040:55f4`,
`Planet_MarkSeen@1068:51cc`, `Fleet_MarkSeen@1068:5028`, `WriteGameFile@1068:35b0`, `WritePlanetDataBlock@1068:4926`,
`WriteFleetBlocks@1068:4c86`, `WriteBattleBlocks`, `Messages_MarkPlanetsSeen@1028:81b4`, `DoBombing@10e8:6e2a`,
`Bombing_SumFleetBombs@1030:0d6a`, `Fleet_CheckMinefields@10a8:30b6`, `MoveSpaceObjects@10a8:0f6e`,
`GenerateTurn@10a8:0000` (the per-design cache filled before the files are written).

## Summary

At the end of each turn the original works out, player by player, what that player's fleets, planets and (Packet
Physics) packets can see, and writes the player's turn file from it. Some of the result stays in the game: which
players know of each minefield and saw it this year, and which players track each wormhole. The rest is the player's
view of the turn: which of the other players' planets, fleets and designs the player sees and how much of each,
which other players the player has met, and which packets, wormholes and traders are in view. We keep each player's
view in the game state (`views`), because Space Demolition scanning draws random numbers and so cannot be redone
later.

## Data used

- Scanner parts: `scan_range` (normal range) and `pen_range` (penetrating range) stats. Ship scanners with a
  penetrating range: Chameleon 45, Ferret 50, Dolphin 100, Robber Baron 120, Elephant 200 (the original reads them
  from a small table by part, not from the part record). Other parts with a normal range: Mega Poly Shell 80,
  Multi Contained Munition 150, Langston Shell 50. Planetary scanners: Viewer and Scoper ranges are normal only;
  the Snoopers' penetrating range is half their normal range.
- Scanners that see more: the Pick Pocket and Robber Baron scanners (tag `steals_from_fleets`) see the cargo of
  fleets at their own position; the Robber Baron (tag `steals_from_planets`) also sees the minerals of the planet it
  orbits.
- Cloaking: each part's `cloak` stat (cloak units per part): Transport Cloaking 300, Stealth Cloak 70, Super-Stealth
  Cloak 140, Ultra-Stealth Cloak 540, Multi Function Pod 60, Shadow Shield 70, Langston Shell 20, Depleted
  Neutronium 50, Mega Poly Shell 40, Chameleon Scanner 40, Multi Contained Munition 20, Alien Miner 60, Orbital
  Adjuster 50, Multi Cargo Pod 20, Enigma Pulsar 20.
- Tachyon Detectors (tag `tachyon_detector`): the table of how much of an enemy's cloak remains, by the number of
  detectors on one design (capped at 17): 100, 95, 93, 91, 90, 89, 88, 87, 86, 86, 85, 84, 84, 83, 83, 82, 82, 81
  (percent; content constants `constant.scanner.tachyon_cloak_pct_<n>`).
- Race traits: Super Stealth (300 cloak units on every ship, `cloak.builtin_units`); Improved Starbases (40 cloak
  units on starbases, `cloak.starbase_units`); War Monger (sees other players' designs in full,
  `scanner.full_designs`); Packet Physics (packets scan, and every packet is in view, `scanner.packets`);
  Inter-stellar Traveler (stargates scan, `scanner.gates`); Space Demolition (minefields scan, `scanner.minefields`);
  Jack of all Trades, No Advanced Scanners and Alternate Reality as in the first part.
- Minefield `known_by`, `seen_by`; wormhole `tracked_by`.

## Algorithm

### Scanner ranges

**A design** (`Design_ScannerRange`): N = Σ over parts count × (normal range)⁴, P = Σ count × (penetrating
range)⁴ (in floating point). A Jack of all Trades race's Scout, Frigate and Destroyer hulls add a built-in scanner:
N += (20 × electronics level)⁴ and P += (10 × electronics level)⁴ (seen: a scout at electronics 3 sees a field
29 ly away, mine1 turn 27). The normal range is trunc(⁴√N), doubled for No Advanced Scanners; it is −1 ("no
scanner") when N is 0 and the design has no scanner-category part (a Bat Scanner gives range 0). The penetrating
range is trunc(⁴√P). The design's **tachyon factor** is the table value for its number of Tachyon Detectors (100
without any).

**A fleet**: the largest normal and penetrating ranges among the designs it has ships of, the smallest tachyon
factor among them, and whether any of them carries a scanner that sees cargo or planet minerals. A fleet without
any scanner has range 0 for scanning.

**A planet** (`Planet_ScannerRange`): an Alternate Reality planet sees trunc(√(10 × population in hundreds)); with
No Advanced Scanners that is × 1412 div 1000 and it has no penetrating range; otherwise, when the planet's starbase
is an Ultra Station or Death Star, a penetrating range of half that. Other planets: 0 without a planetary scanner;
otherwise the owner's best planetary scanner (by tech): its normal range (doubled for No Advanced Scanners) and,
for a Snooper, half its range as penetrating range.

**A Packet Physics packet in flight** scans speed² light years around it (no penetrating range).

### Cloaking

**Cloak units to percent** (both functions below): u ≤ 100: u div 2; u ≤ 300: (u − 100) div 8 + 50; u < 613:
(u − 300) div 24 + 75; otherwise with v = u − 612: v ≤ 512: v div 64 + 88; v < 1000: 96, or 97 when v ≥ 768;
otherwise 98.

**A fleet's cloak** (`Fleet_ComputeCloak`): for each design the fleet has ships of, U = the design's cloak units
(Σ count × `cloak` over its parts, plus 300 for Super Stealth) and M = design mass × ship count. With W = Σ U × M
and D = Σ M over the stacks, the cloak is 0 when W is 0; otherwise, except for Super Stealth, D also counts the
minerals and colonists aboard (kT); the percent is that of W div D. (The original switches to floating point when
the sums get too large; we use 64-bit integers, which agree.)

**A starbase's cloak** (`Design_CloakUnits`): the design's cloak units plus 40 with Improved Starbases plus 300 for
Super Stealth; 0 when the sum is 0 or above 25000, else its percent. Scanners use K = (100 − percent)²: K ≥ 10000
means no cloak.

**Seeing a cloaked fleet**: with cloak c (after a tachyon factor t: c × t div 100) and k = 100 − c, a scanner whose
squared range would reach the fleet (d² ≤ R²) sees it only when d² ≤ (k × R² div 100) × k div 100, and, for a fleet
in orbit, also d² ≤ (k × P² div 100) × k div 100.

**Seeing a cloaked starbase**: a penetrating scan within P sees the planet; it sees the starbase only when the
starbase's K ≥ 10000 or d² ≤ K × P² div 10000. Otherwise the planet is seen at level 2: "seen, starbase hidden".

### Detail levels

A planet seen this turn has a level: 1 a fleet without scanners orbits it, 2 scanned but its starbase hidden, 3
scanned (environment, concentrations, population, starbase), 4 also its surface minerals; the player's own planets
are level 7. A fleet seen has level 3 (position, ships, mass) or 4 (also its cargo); own fleets are 7. A design seen
has level 3 (hull only) or 7 (full). Levels only go up within a turn. Seeing a planet at level 1, 3 or 4 also sees
its starbase's design (at least level 3) and meets its owner; seeing a fleet sees the designs it has ships of.

### What scanning records (`ComputeVisibility`, at the end of the turn)

For each player in order (a player's pass only touches that player's view):

1. **Start** (`Visibility_Reset`): the view is empty. Each of the player's own fleets in orbit sees its planet at
   level 1 without scanners, else 3, or 4 when it carries a Robber Baron; also 4 when the fleet stayed put this
   turn, its first waypoint task is remote mining, the planet is unowned and the fleet's mining rate there is above
   0. A Packet Physics player has every packet in view. Every trader is in view.
2. **Fleet scanners**, the player's fleets in fleet order, each with ranges R, P and tachyon factor t:
   - a fleet marked by this turn's bombing (below) sees the planet it orbits at level 3;
   - with a cargo-seeing scanner, every other fleet at exactly the same position is seen at level 4;
   - every other fleet not yet seen: seen at level 3 when d² ≤ R² and, in orbit, d² ≤ P², cloak permitting;
   - minefields as in the first part (and the field's owner is met); packets within R are in view (their owner
     is met); wormholes as in the first part;
   - with a Robber Baron, the planet it orbits is seen at level 4;
   - with P > 0, every planet not yet seen at level 3 or more within P is seen at level 3, or 2 when its starbase
     stays hidden.

   In the same pass over all fleets, another player's fleet not yet seen that orbits one of the player's planets is
   seen at level 3.
3. **Planet scanners**, the player's planets in planet order, each with ranges R and P:
   - every fleet not yet seen within R (in orbit: within P), cloak permitting (no tachyon factor), at level 3;
   - minefields, packets and wormholes as for a fleet but only within R (first part);
   - an Inter-stellar Traveler player's planets with a starbase whose design has a stargate (range G > 0) see every
     planet not yet seen at level 3 or more that has a stargate of its own: when G is unlimited, always; otherwise
     within G and when that planet's starbase K ≥ 10000 or d² ≤ K × G² div 10000; at level 3;
   - with P > 0, planets within P as for a fleet.
4. **Packet scanners**: a Packet Physics player's packets in flight, each with range R = speed²: fleets not yet
   seen within R, cloak permitting (no orbit rule), at level 3; minefields, packets, wormholes and traders within
   R; planets not yet seen at level 3 or more within R, at level 3 or 2. A Space Demolition player's minefields, in
   space object order: every fleet not yet seen in deep space with d² ≤ the field's mine count is seen at level 3
   when it has no cloak, or when its cloak c ≤ `random(100)` (one draw per cloaked fleet in the field).
5. **Messages** (`Messages_MarkPlanetsSeen`): a planet named in one of the player's messages that says the player
   lost it (its colonists died off or left; also invaded, S17, and bombed out, M9) is seen at level 3.
6. **Designs**: every other player's design seen this turn gets level 3 (7 for a War Monger viewer), and a design
   shown in full this turn (below) level 7; its owner is met.

(Battles add to each participant's view when its file is written: the other players in the battle are met, every
token's design is shown in full, the fleets in it are seen at level 3 or more, and the battle's planet at level 1: M9.)

### Marks made during the turn

- **Bombing** (after the battles of the waypoint 1 step, `DoBombing`): when one of a player's fleets orbits another
  player's planet that has no starbase and its battle plan attacks that player, every fleet of the player at that
  planet is marked, carrying bombs or not. The bombs themselves come with M9.
- **Designs shown in full** (cleared at the end of the turn):
  - a fleet that hits a Space Demolition player's minefield, or is inside one that detonates, shows that player every
    design it has ships of (as before the damage), `Fleet_CheckMinefields`;
  - a Packet Physics packet that reaches a planet whose starbase has a mass driver shows its owner that starbase's
    design, `MoveSpaceObjects`.

The view keeps the other players' planets, fleets and designs (with their levels), the other players met, the
packets in view (own ones too), the wormholes tracked in this pass and the traders.

`seen_by` is emptied at the start of each turn (S13, S02 phase 7).

## Randomness

`random(100)` once per cloaked fleet not yet seen inside a Space Demolition player's minefield, in player order, then
minefield order, then fleet order, after the turn's other draws (the files are written last).

## Edge cases

- A planet without a scanner has range 0: it still "sees" objects exactly at its position, so other players' fleets
  orbiting it.
- Scanning happens after the turn's events: a field laid this year is seen by a fleet already inside it.
- A fleet in orbit is hidden from scanners without penetrating range.
- A planet's level 2 is written to the turn file as level 3 without its starbase.
- A minefield detonation also marks the fleets inside it the way bombing does, but the battles that follow clear that
  mark before scanning, so it changes nothing.

## Verification

- terra1, long1, follow1, gate1, prod1 and mine1 (all turns): every player's view matches the original's turn files
  (terra1 turn 30 has a battle: designs ignored).
- big1 (80 turns, 6 computer players, views only: our scanning run on each converted host state): matches except
  battles and invasions.

## Open questions

1. A game setting (bit 3 of the word at 1110:0080) replaces the Jack of all Trades built-in scanner by a fixed one
   (40 ly, penetrating 20 ly); which setting it is.
2. Which code sets a wormhole's `seen_by` (not the scanning code).
3. The players the original always writes into a turn file (a player-record flag besides "met"); not seen yet.
