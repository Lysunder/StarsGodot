# S14 Mineral packets and salvage

Status: draft (2026-10-07), first pass. Launching, flight, decay, catching and impact damage of packets, and salvage
from scrapping in deep space and from mine hits, with salvage decay, implemented in `core/rules/packets.gd`.
Verified by mine1 turns 48-54: a ship scrapped in deep space (salvage, its decay), two packet items launched the
same year (merged), a packet landing on an unowned planet (a ninth of it), a packet overdriven three warps (50%
decay, pro-rated in the launch and arrival years) hitting a planet without a mass driver (colonists killed, a
defense destroyed). Catching and partial catching, Inter-stellar Traveler and Alternate Reality targets, mine salvage
and salvage overflow are unit-tested only. Not built yet: loading from and unloading into
salvage and packets (transport tasks and cargo transfers, with the original's random sharing when several players
load from one object), salvage from battles (S16), and Packet Physics terraforming on impact.
References: `Production_CompleteItem@10b0:0e68` (launch), `Planet_GetMassDriverWarp@1040:4f76`,
`MoveSpaceObjects@10a8:0f6e` (flight and impact), `Minefield_Decay@10b0:4166` (which decays packets),
`ProcessMinefieldHits@10b0:42a0` (packet and salvage decay), `DropSalvage@10e8:183a`,
`Planet_DefenseCoverage@1030:0262`, `Fleet_CheckMinefields@10a8:30b6` (mine salvage), `DoWaypointTaskPass@10a8:3ec6`
(scrap).

## Summary

A planet whose starbase has a mass driver can build mineral packets and fling them at another planet. A packet flies
in a straight line at its warp speed squared light years a year (half that in its first year), decaying if it was
launched faster than the driver is rated for. At the target a mass driver catches as much of it as its own speed
allows; the minerals land on the planet, and what wasn't caught hits it, killing colonists and destroying
defenses. Salvage is a pile of minerals left in deep space by ships scrapped or destroyed there; it decays each
year. Packets and salvage are the same kind of space object in the original and share one numbering per player.

## Data used

A packet or salvage pile (`Packet`, space object kind 1, record of 18 bytes):

| Field | Original | Meaning |
|---|---|---|
| `owner`, `number`, `x`, `y` | +0, +2, +4 | the launching or dropping player, its number, its position |
| `destination` | +6 low 10 bits | the target planet; salvage has 1023 (we store −1) |
| `warp` | +6 bits 10-13 | packet speed − 4 (we store the speed, 5..13; salvage 0) |
| `fresh` | +7 bit 6 | packet: it has moved at least once; salvage: dropped this year (skips one decay) |
| `minerals` | +8, +10, +12 | kT of ironium, boranium, germanium (16-bit) |
| `mass_tenths` | +14 low 14 bits | the mass shown, in tens of kT, kept as described below |
| `decay` | +14 bits 14-15 | the decay class: 0 none, 1 10%, 2 25%, 3 50% a year |

A planet's driver: `PartRules.driver_warp` of its starbase design (the best `driver_warp` among the design's parts,
one more when another slot holds a driver of that same best speed), 0 without a starbase or an owner. The planet's
`mass_driver_target` and `mass_driver_warp` (the speed setting, S03).

## Algorithm

### Launching (S09 production, items 14-17 and auto packets)

Before spending (S09 step 4.2), a packet item on a planet without a driver or without a target is removed with
**`production.packet_removed`** `[planet]`. Auto packets room: 0 without a driver or target, else 1000.

When n units of a packet item complete (auto packets build mixed packets):

1. Without a driver: **`production.packet_lost_no_driver`** `[planet]`, nothing else. Without a target:
   **`production.packet_lost_no_target`** `[planet]`.
2. Minerals: a single packet carries u × n of its mineral (u = trait parameter `production.packet_minerals`, 100,
   Packet Physics 70); a mixed packet m × n of each (`production.mixed_packet_minerals`, 40, PP 25); each at most
   32,760.
3. Speed s = the planet's speed setting; if it is below 5 or above b + 3 (b the best driver part's own speed,
   without the pair bonus), s = the driver's speed (with it). Overdrive o = s − the driver's speed when positive,
   else 0. The decay class is o, plus `packet.decay_class_bonus` (Inter-stellar
   Traveler 1) when o < 3.
4. If the player has a packet at the planet's position with the same speed, target and decay class whose
   `mass_tenths` is below 1,630, the minerals join it: each mineral grows (a sum above 32,767 becomes 32,760) and
   `mass_tenths` restarts from 0 and grows by (mineral + 9) div 10 per mineral; **`production.packet_merged`**
   `[planet, target]` (goto the planet). Otherwise a new packet (number as for any space object; when none is
   free, **`production.packet_removed`** `[planet]`) at the planet with those minerals, speed, target and class,
   `mass_tenths` = Σ (mineral + 9) div 10, not fresh; **`production.packet_launched`** `[planet, target]`.

### Flight (S02 phases 8 and 14)

Packets are taken in space-object order (owner, then number). Phase 8 ("before fleets") moves every packet; phase 14
("after production") moves only packets that are not fresh, which are the ones launched this year. A packet with no
minerals at all is deleted when its turn comes.

1. The packet becomes fresh. Its move M = s² light years, halved (integer) in phase 14.
2. d = the distance to the target planet (floating point). If trunc(d) > M, it moves toward the target: with
   f = M / d, x += trunc(dx × f ± 0.5), y += trunc(dy × f ± 0.5) (the sign of the half is the sign of the
   target's coordinate minus the packet's: + when greater, − otherwise). If that lands exactly on the target it
   has arrived; otherwise in phase 14 it decays for half a year (p = 50, below), and that is all.
3. Arrival: p = MulDiv(trunc(d), 100, M) clamped to 0..100, halved in phase 14; the packet decays for p (below). A
   packet that decays to nothing is gone. Otherwise it hits the target.

### Decay (`Minefield_Decay`)

Packets with a decay class decay by p percent of a year: the rate r is 10, 25 or 50 percent (Packet Physics: half,
`packet.decay_pct` 50), the minimum m 10 kT (PP 5, `packet.decay_min`). Each mineral that isn't 0 loses
max(mineral × r × p div 10000 (16-bit), m), at most what it has. A packet left with none is deleted; otherwise
`mass_tenths` = (total + 9) div 10. In phase 11 every packet in flight decays for a full year (p = 100); a packet
without a decay class never decays.

### Impact

1. Catch speed c = the target's driver (0 if unowned or without a starbase). C = c²; for an Inter-stellar
   Traveler owner of the target, C = C div 2 (`packet.catch_pct` 50). S = s².
2. If C ≥ S: the caught share F = 1000 and K = c. Else if c > 0: K = C, F = C × 1000 div S. Else K = c (0), F = 0.
3. The landing share L = (1000 − F) div 9 + F. Each mineral (negative counted as 0) adds mineral × L div 1000 to
   the planet's surface minerals; T = the total of the packet's minerals.
4. F = 1000: **`planet.packet_caught`** `[planet, packet owner, T]` to the planet's owner (goto the planet). The
   packet is deleted.
5. Otherwise the raw damage D = (S − K) × T div 160 (32-bit). (Packet Physics terraforming happens here: not built
   yet.) An unowned target takes nothing more (no message). Otherwise D = trunc(U × D), U the target's uncovered
   share as a 32-bit float: (1 − best × 0.001)^n, best the owner's best planetary defense value (`defense`, e.g.
   SDI 10) and n = min(defenses, operable defenses); U = 1 without defenses.
6. D = 0, or an Alternate Reality owner (`packet.no_damage`): **`planet.packet_caught`** when K > 0, else
   **`planet.packet_harmless`** `[planet, packet owner, T]`.
7. Colonists killed k = max(population × D div 1000, D) (in hundreds). If k ≥ the population (or negative):
   **`planet.packet_wiped_out`** `[planet, packet owner]` and the planet is depopulated (S08).
8. Otherwise defenses destroyed e = defenses × D div 1000; if that is 0 while there are defenses: 1 when
   `random(20)` < D, else 0; then e = max(e, D div 20), at most the defenses. Messages to the owner (goto the
   planet): with e = 0, **`planet.packet_damage_partly_caught`** (K > 0) or **`planet.packet_damage`** (K = 0)
   `[planet, T, packet owner, k]`; otherwise **`planet.packet_damage_defenses_partly_caught`** /
   **`planet.packet_damage_defenses`** `[planet, T, packet owner, k, e]`. Defenses −= e, population −= k.
9. The packet is deleted.

### Salvage (`DropSalvage`)

Salvage is dropped with three mineral amounts at a point, by a player, optionally onto an existing pile:

1. Nothing happens on a planet's position.
2. If all three amounts are 0, each becomes `random(10)` (three rolls, repeated until the sum isn't 0).
3. An existing pile: its minerals are added to the amounts and the pile is emptied (`mass_tenths` 0). Otherwise a
   new pile is made at the point (salvage, number as for any space object; none free: nothing).
4. The pile becomes fresh. Then, mineral by mineral and repeating while any amount is left: if
   `mass_tenths` × 10 + amount ≤ 30,000 the amount joins the pile (`mass_tenths` += (amount + 9) div 10);
   otherwise the pile takes (3000 − `mass_tenths`) × 10 of it, `mass_tenths` = 3000, and a new pile is started
   for the rest.

Where salvage comes from:

- **Scrapping in deep space** (S11 "Scrap"): the ships' minerals div 3 plus the minerals in the cargo, onto a new
  pile; colonists are lost. **`fleet.scrapped_in_space`** `[pile, fleet described]` (goto the pile).
- **Mine hits during movement** (S13) that destroy ships: the cargo minerals of the destroyed ships (all the cargo
  when the whole fleet is lost) onto the pile already at the hit point (any owner's), else a new one. **B35:** the
  original drops the minerals of the ships that survive and loses those of the destroyed ships (fix: the destroyed
  ships' share). When the whole fleet is lost and a pile exists afterwards, its owner gets
  **`fleet.mine_annihilated_salvage`** `[pile, fleet described, field owner, type, x, y]` (goto the pile) instead
  of `fleet.mine_annihilated`, and the field's owner **`minefield.annihilated_yours`** `[pile, fleet, type, x, y]`
  (goto the pile); without a pile, the field's owner gets that message with the field instead.

Salvage decay (phase 11): a fresh pile only stops being fresh. Otherwise each mineral that isn't 0 loses
max(mineral div 10, 10), at least down to 0; a pile left with none is deleted; else `mass_tenths` = (total + 9) div
10.

## Randomness

- `random(20)` at an impact that would destroy no defenses although there are some (step 8).
- `random(10)` × 3 (repeated) when salvage is dropped with no minerals.
- Packet Physics impact terraforming (not built): `random(200)` and `random(10)` per 100 kT per mineral.

## Edge cases

- A packet's minerals are 16-bit: launches and merges cap at 32,760.
- Packets ignore minefields and are not stopped by anything on the way.
- The phase-14 half move: a packet whose target is closer than half its move arrives in its launch year, with
  p halved.
- Salvage is never left on a planet (scrapping there deposits the minerals, S11).

## Known bugs

- **B35 mine salvage from the survivors:** see "Where salvage comes from". Fix: the destroyed ships' minerals.

## Mod hooks

- Trait parameters: `production.packet_minerals`, `production.mixed_packet_minerals` (S09), `packet.decay_pct`,
  `packet.decay_min`, `packet.decay_class_bonus`, `packet.catch_pct`, `packet.no_damage`.
- Rule constants: the decay rates, the damage divisor 160, the salvage pile cap.

## Open questions

1. The original's handling of the `fresh` bit of salvage loaded by transports (not built).
2. Whether the x87 `pow` of the defense coverage differs from ours in the last bits (the result is stored as a
   32-bit float, which hides most differences).
