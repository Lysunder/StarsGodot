# S16 Battles

Status: draft (2026-10-11). First part: the battle recording, which the harness reads from the original's player turn
files and which our battle engine will produce in the same shape (`state.battles`). Second part: who fights, the
tokens and where they start. Not yet: movement, targeting, firing, damage, retreat and the results (later parts).
References: `RunBattles@10e8:24aa`, `GroupFleetsByLocation@1030:11d0`, `GatherBattle@10e8:1ae2`,
`ResolveBattle@10e8:58c0`, `BuildBattleTokens@10e8:2cb4`, `Token_InitStats@10e8:2770`,
`Design_BattleComputers@10e8:2636`, `Token_ComputeWeapons@10e8:27c4`, `Token_SetClass@10e8:15f0`,
`Design_BattleMovement@10e8:216e`, `Design_IsArmed@10e8:158a`, `Design_IsBomberClass@10e8:14a0`,
`Fleet_DumpCargo@10e8:173e`, `ShuffleTokens@10e8:2c14`, `Token_TakeDamage@10e8:5234`, `Token_Fire@10e8:4310`,
`FinishBattle@10e8:62bc`, `WriteBattleBlocks`, `VCR_SeekTo@10e0:053e`.

## Summary

Every battle is recorded: where it was, who took part, every token (a stack of one design's ships, or a starbase) as
it was at the start, and then every move and every shot in order, with what each shot did. The original keeps these
records for its battle viewer and writes each into the turn file of every player who took part. They let our engine be
checked step by step, not only by the battle's outcome.

## The recording

**Header:**

| Field | Meaning |
|---|---|
| id | the battle's number: (turn × 256 + 1 + the battles before it this turn), low 12 bits |
| sides | the number of sides in the battle |
| players | the players who took part (bit mask) |
| size | the record's length in bytes |
| planet | the planet the battle was at, or −1 in deep space |
| x, y | the battle's position |

**Tokens**, in board order (shuffled, see below): each names its fleet (a ship token) or its planet
(a starbase token), its owner, kind (1 starbase, 2 ships), design (0–15 ship designs, 16 + slot for starbase designs),
starting square, its computer initiative, the initiative range of its weapons (255 when unarmed), torpedo jamming and
torpedo accuracy bonus, beam damage and beam defense percents, mass (65535 for a starbase: it never moves), shields
per ship, ship count, damage (packed like a fleet's: percent of ships damaged in the low 7 bits, armor points above),
its battle plan's targets (primary in the low four bits, secondary above) and tactic (low four bits; ship class
above), its weapons' range span (shortest × 16 + longest; 255 when unarmed), its movement rating (low four bits) and
its state word (bit 0 alive, bit 1 Tachyon Detector, bit 2 torpedoes, bit 3 shields regenerate, bit 4 set at the
start, bits 5-9 disengage countdown, bits 10-13 weight jitter, bits 14-15 moves left). Board squares are numbered
x + 16 × y on the 10 × 10 board.

**Events**, in the order they happened:

- a token **moves** to a square (255 when it leaves the battle), or **fires** from its square;
- each event records the round (0–15) and the token's disengage countdown;
- a shot lists its hits: the target token, the kind of hit, ships killed, damage to the target's shields (stored as a
  13-bit value shifted left by twice a 3-bit exponent) and the target's damage word after the hit.

## Who fights

Battles are fought after movement, at the start of the waypoint 1 step (S02), before bombing.

**Places.** Fleets at the same position are grouped; each group is taken in the order of its first fleet in fleet order,
and within a group the first fleet comes first and the others follow in reverse fleet order (the original links each
new fleet right after the first). A group's place is the first fleet's position and planet. Every fleet of a group is
handled once, whether or not it fights.

**Hostility**, per group (`attack[p]`: the players p's side attacks):

1. When the place is a planet: without a starbase, its owner (if any) is a bystander. With a starbase, its owner is
   present; when the starbase design is armed (a beam or torpedo) and the owner's first battle plan attacks someone,
   that plan sets `attack[owner]`.
2. Every fleet: its owner is present. When its battle plan has a primary target (not 0) and attacks someone, and the
   fleet has an armed ship, its plan sets `attack[owner]` and the place has an armed attacker.
3. A plan that attacks "enemies" adds every other player its owner counts as an enemy; "enemies and neutrals" adds
   those not counted as friends; "everyone" sets every other player (replacing what was there); "player n" adds
   player n. (Fix B05: the original writes a starbase's "everyone" and "player n" to a stale player instead of the
   starbase's owner; we write them to the owner.)
4. No battle without an armed attacker, or when no present player is attacked. Otherwise the fighting players start as
   those attacked; then, for each player in order: one whose attacks hit a fighting player fights too, and a fighting
   player attacks everyone who attacks it.
5. Then, over the group's fleets (repeated until a whole pass changes nothing): a present player not fighting takes the
   attacks of each fighting friend in turn; if a friend's attacks include another fighting friend of it, it stays out.
   With attacks it fights; without, it is no longer present.
6. The fleets of players no longer present stay out of the battle; their owners are bystanders. The number of sides
   is the number of fighting players.

(The original's limit of 256 tokens per battle, shared out by fleet order, is bug B08: we have no such limit.)

## Tokens

The battle's present players are numbered in player order; player k (counted from 0) of n sides starts on square
`START[n(n - 1)/2 + k]` (136 squares, grouped by number of sides: 0x44; 0x41, 0x58; 0x14, 0x88, 0x81; 0x11, 0x88,
0x81, 0x18; ...; content `battle_board.standard`, as [x, y] pairs).

**The starbase**, when the planet has one and its owner is present: kind 1, one "ship" of starbase design 16 + slot,
mass 65535, movement 0, targets "any" first and second, class 3 with tactic 5 (the original's test for an unarmed
starbase reads the computer initiative, which is never 255, so it always takes the armed values), and its armor
damage with 100% damaged when there is any.

**Ships**: each fleet in the battle, in group order, first drops its cargo when its battle plan says so (minerals onto
the planet, or as salvage in deep space, S14), then gets one token per design it has ships of (slot order): kind 2,
its fleet, count and damage (percent and armor points), then:

- **Computer initiative**: the hull's initiative plus 1 / 2 / 3 per Battle Computer / Super Computer / Nexus, at most
  63. **Torpedo accuracy bonus**: starting from 0, each computer (and each Multi Contained Munition, 10) raises it by
  its accuracy share of what is left: `bonus += (100 - bonus) × accuracy / 100`, one unit at a time.
- **Weapons** (beams and torpedoes): a weapon's initiative is its part's initiative plus the computer initiative (at
  most 63); its range is the part's range, plus 1 on a starbase. The token keeps the lowest and highest initiative and
  range (255 and 15 when unarmed). Torpedoes set state bit 2.
- **Torpedo jamming**: a product starting at 10000, multiplied by (100 - `jamming`) / 100 for each jamming part
  (Jammers, Multi Function Pod, Langston Shell, Mega Poly Shell, Alien Miner), one unit at a time, truncating; the
  jamming is 100 - (product + 50) div 100, at most 95 (0 without jamming parts); a starbase keeps three quarters of
  it (rounded up).
- **Beam damage**: with capacitors, 1000 × (100 + `beam_damage_pct`) / 100 per unit, at most 2550, div 10 (0 without
  capacitors). **Beam defense**: 1000 × (100 - `beam_deflection`) / 100 per Beam Deflector, div 10 (100 without).
- **Shields** per ship: the design's shields (S04). Energy Dampener: noted for the battle. Tachyon Detector: state
  bit 1.
- **Class**: armed 3; else bomber 4 (bombs, Multi Contained Munition, Orbital Construction Module); else fuel transport
  hull 6; else freighter 7 (cargo capacity); else 5. **Targets** are the battle plan's; the tactic is the plan's for an
  armed token, else 0. A tactic of 0 sets the disengage countdown to 7.
- **Movement** (`Design_BattleMovement`): no engine gives 0 (no mass, no draw). Otherwise the engine's speed is 10 for
  the Interspace-10, Enigma Pulsar, Trans-Star 10, Trans-Galactic Mizer Scoop and Galaxy Scoop, else the highest warp
  1-9 whose fuel use is below 121 (0 if none). Movement = speed - 4 + Σ `battle_move` (Maneuvering Jet 1,
  Overthruster 2, Multi Function Pod 1) + (Σ `battle_move_halves` (Enigma Pulsars, Alien Miners) + 1) div 2, +2 for a
  War Monger. The token's mass is the design's mass plus, for a design with cargo capacity, the fleet's minerals and
  colonists × the design's capacity div the fleet's capacity; a fleet that dumped its cargo moves 1 less. A
  `random(15)` sets the weight jitter. Movement -= (mass div 70) div the number of engines, then at most 8 and at
  least 0.

Then the tokens are shuffled: for each position i from the first, the token at i is swapped with the one at
i + `random(n - i)`. Afterwards every token gets state bits 0 and 4; an unarmed token's primary target becomes 0;
bit 3 is set for a Regenerating Shields owner's token with shields. When any token has an Energy Dampener, every ship
token's movement drops by 4 (to at least 0).

**Battle number**: the first battle of a turn is (turn × 256 + 1) mod 4096; each battle adds 1.

## Randomness

Per battle: `random(15)` for each ship token with an engine, in group and slot order; then the shuffle's draws (one
per token, the last being `random(1)`). The battle itself draws more (later parts).

## Files (harness)

A record goes into each participant's turn file as block type 31; a record over 1 KiB continues in blocks of type 39
(the tokens and the events are split at token and event boundaries where they fit). `tools/harness/stars_battles.py`
reads them; the importer stores each turn's battles, by id, in `state.battles`.

## Open questions

1. The hit kinds seen (1, 4, 196): presumably beam, torpedo and a torpedo miss; to confirm with the firing rules.
2. The token bytes not decoded yet (offsets 6, 9–12 and 25).
