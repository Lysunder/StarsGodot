# S17 Bombing and invasion

Status: draft (2026-10-11). First part: bombing, built (`core/rules/bombing.gd`, `core/rules/defense_coverage.gd`) and
unit-tested; read from the code (the floating-point parts from the disassembly), not yet checked against a game of
the original. Not yet: invasion and ground combat (second part).
References: `DoBombing@10e8:6e2a`, `Bombing_SumFleetBombs@1030:0d6a`, `Planet_DefenseCoverage@1030:0262`,
`Fleet_WillAttackPlayer@10e8:6db6`, `Planet_Depopulate@1040:553a`, `Messages_MarkPlanetsSeen@1028:81b4`,
`RunBattles@10e8:24aa` (calls the bombing), `ResolveGroundCombat@10b0:1e82`.

## Summary

Right after the battles of the waypoint 1 step, every player's fleets that orbit another player's planet without a
starbase, when one of them has a battle plan that attacks that player, drop their bombs on it together. Normal bombs
kill a share of the colonists (with a minimum) and destroy installations; smart bombs kill a share of the colonists
that compounds per bomb; retro bombs undo terraforming. The planet's defenses stop part of the bombs. A planet left
without colonists loses its owner.

## Data used

- Bomb parts: `kill_rate` (tenths of a percent of the colonists), `installations` (destroyed), `min_kill` (hundreds of
  colonists; the five normal bombs Lady Finger to Cherry 3, the Multi Contained Munition 3, the Orbital Construction
  Module 20), tags `smart` and `retro`. The Multi Contained Munition also has `kill_rate` 20 and `installations` 5.
- The planet: owner, population (hundreds), factories, mines, defenses, environment and its original values,
  starbase.
- The owner's best planetary defense (`defense` value, S04) and the operable defenses (S08).

## Algorithm

### Who bombs

In fleet order, a fleet with ships bombs when it orbits a planet that another player owns, the planet has no
starbase, and the fleet's battle plan attacks the planet's owner (S16 "Hostility": enemies; enemies and neutrals;
everyone; or that player). It bombs together with all of its owner's fleets at that planet (taken from it round the
place's fleets in their order, S16 "Places"); they are all marked (the mark scanning reads, S15) and none of them
starts a bombing of its own. Fleets destroyed in the battles take no part.

### The bombs (`Bombing_SumFleetBombs`)

Over the fleets, their designs with ships (slot order) and each design's parts (slot order), with n = the part's
count × the stack's ships:

- a retro bomb adds n retro bombs;
- a smart bomb multiplies the share of colonists left, starting at 1, by (1 + rate × -0.001), n times;
- any other part adds rate × n to the normal kill rate, `installations` × n to the installations and `min_kill` × n to
  the minimum kill (parts without these stats add 0).

The smart kill rate is trunc(left × -1000 + 1000 + 0.5), at most 1000. Nothing happens when all five sums are 0. (The
original multiplies in the x87's extended precision, storing the share as a double between parts; we use doubles.)

### Defenses (`Planet_DefenseCoverage`)

What gets through is U = (1 - value × 0.001)^n for normal bombs and Us = (1 - value × 0.0005)^n for smart bombs, n the
planet's defenses (at most the operable ones), stored as 32-bit floats; both are 1 for an unowned planet, one without
defenses, or an owner without a defense technology. (S14 uses U for packets.) When U < 1:

- normal = trunc(normal × U + 0.5), minimum = trunc(minimum × U + 0.5), smart = trunc(smart × Us + 0.5);
- installations = trunc(installations × (1 - (1 - U) × 0.5) + 0.5) (installations are covered half as well).

The original computes these in x87 extended precision, where the product of a 32-bit integer and a 32-bit float is
exact: we compute them exactly in integers from the float's mantissa and exponent.

### Installations

With T = factories + mines + defenses and K = installations, when K > 0 and T > 0:

1. factories lost = (factories × K) div T, plus 1 when the remainder r > 0 and `random(T)` < r; at most the factories;
2. defenses lost the same way from the defenses (its own `random(T)`); at most the defenses;
3. mines lost = K - defenses lost - factories lost, at most the mines (it can come out below 0, then no mines are lost).

### Colonists

With P the population, when P > 0 and any of the normal, minimum or smart rates is above 0:

1. killed by smart bombs s = P × smart div 1000, at most P - 1;
2. q = (P - s) × normal; killed = q div 1000, plus 1 when the remainder r > 0 and `random(1000)` ≤ r (at or below,
   unlike the installations' draws); plus s;
3. at least 1 when the normal rate is above 0; at least the minimum; at most P.

The planet loses the colonists and installations (a share below 0 changes nothing).

### Retro bombs

The retro bombs left are R = retro - trunc((1 - U) × retro × 0.5), at most 500. Each environment axis moves toward
its original value by up to R clicks; the clicks moved are added up.

### Messages

The bombers' owner gets one message (goto the first fleet, the one that started the bombing) and the planet's owner
one (goto the planet), each in a "one fleet" form or, when several fleets bombed, a "fleets" form. Parameters, as many
as the type takes: the first fleet, the planet, then:

| Case | Type (`bombing.` / `bombed.` + `fleets_` when several) | Further parameters |
|---|---|---|
| retro bombs moved something (sent first) | `retro` (one fleet: `bombing.retro` to both) | clicks |
| no colonists left | `wiped_out` | none |
| colonists killed, no installations | `killed` | colonists |
| installations destroyed, no colonists (one / more) | `one_installation`, `installations` | number |
| both | `killed_one_installation`, `killed_installations` | colonists, number |

The installations forms get `_defended` and a last parameter, the share of bombs stopped (trunc((1 - U) × 10000), in
hundredths of a percent), when U < 1. The number of installations is the sum of the three shares as computed (a
negative mines share counts). Some types keep fewer parameters than others (the original sends them all and each
keeps its own count): see the content.

The bombers' "one fleet" `wiped_out` makes the bombers' owner see the planet at level 3 (S15 step 5; computer players
get this message too); the "fleets" form does not (open question 1).

### Afterwards

A planet with no colonists left is depopulated (S08).

## Randomness

Per bombing, from the classic stream: `random(T)` for the factories and `random(T)` for the defenses when their
remainders are above 0, then `random(1000)` for the colonists when its remainder is above 0. Bombings come in fleet
order, after the battles' draws.

## Edge cases

- A planet whose owner has no defense technology is not covered at all, whatever its defenses.
- A fleet whose plan doesn't attack the owner doesn't start a bombing, but bombs along with another fleet of its owner
  that does.
- The Orbital Construction Module and the Multi Contained Munition bomb (they are bombers in battles too, S16).
- Bombing an empty planet that still has an owner (population 0) depopulates it.

## Known bugs

None fixed here yet.

## Worked examples

Unit tests (`tests/unit/rules/test_bombing.gd`): ten Cherry bombs on 100,000 colonists, 100 factories and 50 mines
without defenses kill 25,000 colonists and destroy 100 installations; two Lady Fingers bomb out 200 colonists (the
minimum of 600 covers them); ten Smart bombs kill 12.3%; four Retro bombs move two axes 4 clicks each.

## Mod hooks

Part stats `kill_rate`, `installations`, `min_kill`, tags `smart`, `retro`; the defense part's `defense`.

## Open questions

1. The "fleets" form of the bombed-out message doesn't reveal the planet to the bombers (`Messages_MarkPlanetsSeen`
   only knows the one-fleet form). An oversight of the original? Kept as is for now.
2. Not yet checked against a game of the original (big1's computer players get only the bombed-out message): a
   harness game with bombing is needed.
