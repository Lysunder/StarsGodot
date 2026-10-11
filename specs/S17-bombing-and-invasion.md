# S17 Bombing and invasion

Status: draft (2026-10-11). First part: bombing, built (`core/rules/bombing.gd`, `core/rules/defense_coverage.gd`) and
unit-tested; read from the code (the floating-point parts from the disassembly), not yet checked against a game of
the original. Second part: ground combat (`core/rules/waypoint_tasks.gd`); verified by terra1 turn 40 (an invasion
beaten off) and by big1's views (every planet lost to an invasion is shown to its former owner).
References: `DoBombing@10e8:6e2a`, `Bombing_SumFleetBombs@1030:0d6a`, `Planet_DefenseCoverage@1030:0262`,
`Fleet_WillAttackPlayer@10e8:6db6`, `Planet_Depopulate@1040:553a`, `Messages_MarkPlanetsSeen@1028:81b4`,
`RunBattles@10e8:24aa` (calls the bombing), `ResolveGroundCombat@10b0:1e82`, `RecordTransfer@10b0:2fda`,
`TryTechBonus@10e8:6112`.

## Summary

Right after the battles of the waypoint 1 step, every player's fleets that orbit another player's planet without a
starbase, when one of them has a battle plan that attacks that player, drop their bombs on it together. Normal bombs
kill a share of the colonists (with a minimum) and destroy installations; smart bombs kill a share of the colonists
that compounds per bomb; retro bombs undo terraforming. The planet's defenses stop part of the bombs. A planet left
without colonists loses its owner.

Then, between the task passes, colonists landed on a planet fight for it: on another player's planet against its
population (the defenses stop some of the invaders), and among several invaders the strongest wins; an unowned planet
is simply colonized by the strongest.

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
get this message too). Fix B37: the original's "fleets" form shows nothing; we mark the planet for the bombers' owner,
who sees it at level 3 in the same step (no message changes; it only shows when all the bombers left the planet's
orbit before scanning, since the bombing mark shows it otherwise).

### Afterwards

A planet with no colonists left is depopulated (S08).

## Ground combat (`ResolveGroundCombat`)

Colonists landed on a planet (S11: unloaded onto another player's planet, or brought by a colonizing fleet) are
recorded per fleet and planet (`RecordTransfer`; a second landing of the same fleet on the same planet adds to its
record). Between the task passes of each pair (S02 5c, 16d) the planets are taken in the order of their first record;
for each:

1. **Coverage.** For an owned planet, the troops that get through: T = U + (1 - U) × 0.25 (U as for bombs, S17
   "Defenses"), stored as a 32-bit float; 1 for an unowned planet.
2. **Invaders.** Per record: the player's colonists grow by its colonists, and its strength by trunc(colonists ×
   troops percent div 100 × T) (trait parameter `invasion.troops_pct`: 110, War Monger 165, Alternate Reality 0;
   the product with T exact, as for bombs). The total strength is the sum.
3. **Defenders** (owned planet): defense = population × `invasion.defense_pct` div 100 (100; Inner Strength 200).
   - When defense > total strength, the defenders win: each invader (player order) gets **`planet.invasion_failed`**
     `[colonists, planet, owner]` and the owner **`planet.invasion_repelled`** `[planet, colonists, invader]`, or,
     when T < 1, **`planet.invasion_failed_defended`** `[colonists, planet, share stopped, owner]` (the share as
     trunc((1 - T) × 10000), hundredths of a percent) and **`planet.invasion_repelled_defended`**; all goto the
     planet. The population loses population × total div defense. Done.
   - Otherwise the planet is depopulated (S08) and the invaders fight among themselves as below.
4. **Winner.** Among the invading players in player order, the greatest strength wins; an exact tie for the greatest
   means everyone dies: each invader gets **`planet.invasion_all_died`** `[number of invaders, planet]` and a former
   owner **`planet.invaded_all_died`** (same parameters); the planet stays empty. "Second" is the greatest strength
   before the winner's in player order (0 when none).
5. **Messages** (goto the planet):
   - An unowned planet, one invader: **`planet.colonized`** `[planet]`, or **`planet.colonized_starbase`** for an
     Alternate Reality race; several: the winner **`planet.colonized_race_won`** `[number, planet]`, the others
     **`planet.colonized_race_lost`** `[number, planet, winner]`.
   - A taken planet: the winner **`planet.invasion_won`** `[former owner, planet]`, the other invaders
     **`planet.invasion_lost_race`** `[planet]`, the former owner **`planet.invaded`** `[winner, planet, the winner's
     colonists]` (computer players get it too; it shows the lost planet, S15). Then the winner tries the tech bonus
     (S24) with the former owner's tech levels as the need: **`battle.tech_gained`** `[-1, planet, field, amount]`
     (goto research) when it gains.
6. **Population.** The winner's colonists; when the total strength and the winner's strength are above 0, times
   ((total - defense) × winner's strength div total) div the winner's strength; then, with a second, times (winner's
   strength - second) div the winner's strength; at least 1.
7. The planet becomes the winner's (S11 "Colonizing an empty planet" step 4: default queue and settings, an Alternate
   Reality starbase; a taken planet too). An artifact found there (only on a planet that had no owner) gives the
   research points of step 5 there, with **`planet.artifact_found`** `[planet, field, points]`.

(The original also resolves colonists dropped by hand from the orders, `ApplyOrderBlock`: an Alternate Reality
race's, or any onto a planet with a starbase, die, and colonists dropped on an unowned planet without colonizing die
too. Hand transfers to other players' planets are not built yet, S11.)

## Randomness

Per bombing, from the classic stream: `random(T)` for the factories and `random(T)` for the defenses when their
remainders are above 0, then `random(1000)` for the colonists when its remainder is above 0. Bombings come in fleet
order, after the battles' draws.

Ground combat: a taken planet's tech bonus try (S24), then an artifact's `random(6)` field and `random(301)` points
(random events on).

## Edge cases

- A planet whose owner has no defense technology is not covered at all, whatever its defenses.
- A fleet whose plan doesn't attack the owner doesn't start a bombing, but bombs along with another fleet of its owner
  that does.
- The Orbital Construction Module and the Multi Contained Munition bomb (they are bombers in battles too, S16).
- Bombing an empty planet that still has an owner (population 0) depopulates it.

## Known bugs

- B37 (fixed): a planet bombed out by several fleets is shown to the bombers' owner like one bombed out by one fleet
  (see "Messages").

## Worked examples

Unit tests (`tests/unit/rules/test_bombing.gd`): ten Cherry bombs on 100,000 colonists, 100 factories and 50 mines
without defenses kill 25,000 colonists and destroy 100 installations; two Lady Fingers bomb out 200 colonists (the
minimum of 600 covers them); ten Smart bombs kill 12.3%; four Retro bombs move two axes 4 clicks each.

## Mod hooks

Part stats `kill_rate`, `installations`, `min_kill`, tags `smart`, `retro`; the defense part's `defense`.

## Open questions

1. Not yet checked against a game of the original (big1's computer players get only the bombed-out message): a
   harness game with bombing and a successful invasion is needed.
