# S16 Battles

Status: draft (2026-10-11). First part: the battle recording, which the harness reads from the original's player turn
files and which our battle engine will produce in the same shape (`state.battles`). Second part: who fights, the
tokens and where they start. Third part: rounds, movement and target choice (3a), firing and damage (3b); built
(`BattleEngine`), and the two fixture battles (terra1 turn 30, mine1 turn 69) match move for move and shot for shot.
Not yet: the results after the battle (part 4), and battles inside the turn (they come with part 4).
References: `RunBattles@10e8:24aa`, `GroupFleetsByLocation@1030:11d0`, `GatherBattle@10e8:1ae2`,
`ResolveBattle@10e8:58c0`, `BuildBattleTokens@10e8:2cb4`, `Token_InitStats@10e8:2770`,
`Design_BattleComputers@10e8:2636`, `Token_ComputeWeapons@10e8:27c4`, `Token_SetClass@10e8:15f0`,
`Design_BattleMovement@10e8:216e`, `Design_IsArmed@10e8:158a`, `Design_IsBomberClass@10e8:14a0`,
`Fleet_DumpCargo@10e8:173e`, `ShuffleTokens@10e8:2c14`, `Token_TakeDamage@10e8:5234`, `Token_Fire@10e8:4310`,
`FinishBattle@10e8:62bc`, `WriteBattleBlocks`, `VCR_SeekTo@10e0:053e`, `GetMovesThisRound@10e8:5872`,
`BoardDistance@10e8:3122`, `Token_RegenShields@10e8:25ce`, `Token_ChooseTarget@10e8:356e`,
`Token_HasPrimaryTargets@10e8:37f0`, `Token_IsTargetClass@10e8:38ea`, `Token_RatePosition@10e8:3966`,
`Tactic_Score@10e8:3bdc`, `Token_Move@10e8:3c7a`, `Token_EstimateDamage@10e8:315a`, `CalcTorpedoHits@10e8:41b4`,
`Token_RecordLosses@10e8:4f0c`, `Battle_ApplyLosses@10e8:5050`, `PackLongToWord@1030:2ffe`,
`Fleets_RedistributeCargo@1048:6c1c`.

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

## Rounds

A battle lasts at most 16 rounds (0-15). Each round (`ResolveBattle`):

1. The players with a living token are noted. From round 1 on, the tokens of a Regenerating Shields owner that still
   have shields get back a tenth of their design's shields (`Token_RegenShields`), up to the full value. When only one
   player has living tokens the battle ends.
2. **Moves**: a starbase has none; every other living token gets `moves(rating, round)` = (rating + 2) div 4, plus one
   on some rounds: rating mod 4 = 0: even rounds; = 1: every round but those with round mod 4 = 2; = 3: rounds with
   round mod 4 = 0 (so a rating r moves (r + 2)/4 squares a round on average, half a square to two and a half).
3. **Movement**, in three passes (3, 2, 1): in each pass the tokens move from heaviest to lightest. A token's weight
   is mass + (jitter − 7) × mass × 2 div 100; starbases (mass 65535) and dead tokens never move. The order: start
   from a bound of 30000; repeatedly take every living mobile token whose weight equals the bound (token order), then
   lower the bound to the largest weight below it among tokens that have moves this round, until there is none. A
   token taken in pass p moves only if it has at least p moves left, and each move uses one.
   - A disengaging token (tactic 0): while its countdown is above 0 it counts down by one and moves; at 0 it leaves
     the battle (recorded as a move to square 255; it no longer takes part).
   - Otherwise the token moves (`Token_Move`, below). The move is recorded unless the token is a starbase, or it
     stayed on its square and is armed.
4. Every living token rolls a new weight jitter: `random(15)`, in token order.
5. A player still fights only while one of the players it attacks has a living token; the battle ends when fewer
   than two players still fight.
6. **Fire**: for each initiative from the highest to the lowest that some weapon has: the tokens whose initiative
   range contains it, from the last token to the first, fire (`Token_Fire`, part 3b) while at least two players still
   have living tokens. A shot is recorded only when it hit something.
7. The battle ends when fewer than two players are left, or after round 15.

## Movement (`Token_Move`)

A token chooses a square within reach and takes one step toward it.

**Target first** (`Token_ChooseTarget`): the class it aims at is its plan's primary target class when any living enemy
token has it (`Token_HasPrimaryTargets`), else its secondary. Its reach is its longest weapon range plus its moves
left (shortest range plus moves left for a tactic of 3 or 5 when its ranges differ). For each living enemy token of
that class, in token order, with distance d (the larger of the x and y differences; +1 when the enemy has at least as
many moves left): if d is within reach (and the enemy has shields, or for a token whose longest range is 3, the
longest non-sapper beam range also reaches, or the token has no such beam), the token has a target in reach: it looks
at all squares up to its moves left away. Otherwise the nearest such enemy that it could damage at all (estimated
damage at distance 0 above 0) becomes the square to head for, and it looks only at squares next to it.

**Target classes** (`Token_IsTargetClass`): 1 any; 2 starbase; 3 armed (class 3); 4 bombers and freighters (class 4
or 7); 5 unarmed (class 5, 6 or 7); 6 fuel transports (class 6); 7 freighters (class 7); 0 none.

**Rating a square** (`Token_RatePosition`): for each living enemy token, with d the distance from the square to it:
when the token has no more moves left than the enemy, the enemy may come closer or move away: the distances
considered run from d − 1 (at least 0) to the largest distance from the square to any square next to the enemy (on
the board); otherwise just d. For each distance considered: *dealt* = the token's estimated damage on the enemy at
that distance when the enemy is of the class aimed at (else 0), *taken* = the enemy's estimated damage on the token at
that distance (ignoring range and the token's armor when the token's tactic is 0). The distance kept is the one with
the lowest `score(taken, dealt)` (the last one on ties) — the two values are passed in this order here, the reverse of
the final score; the original does this. The square's rating is `score(the largest dealt kept, the sum of the taken
kept)`.

**Score** (`Tactic_Score`, 32-bit signed; lower is better) of (a, b) by tactic: 0, 2: b; 1, 5: −a; 3, 4: when a is 0,
b; otherwise −a × 100 div (b + 1), and −1 when that is not negative; other tactics: 0.

**Estimated damage** (`Token_EstimateDamage`) of token A on token T at distance d, over A's weapons in slot order
(32-bit): a weapon out of range (range + 1 on a starbase) adds nothing, unless ignoring range.
- A beam: power × count; × A's beam damage percent / 100 when not 0; at distance d > 0 reduced by
  (power × d / 10) div range; × T's beam defense / 100 when below 100; a sapper does at most A's ship count × T's
  shields; out of range (when ignoring range) divided by (d + 10 − range), at least the slot's count; then × A's
  ship count.
- A torpedo: n = A's ship count × count × 200; hits = the expected hits of n shots (`CalcTorpedoHits`, part 3b, with
  the part's accuracy and A's accuracy bonus); damage = power × hits div 200, plus power × (n − hits) div 1600 when T
  has shields; out of range divided as for beams (at least the slot's count).
- Unless ignoring T's armor, the total is at most T's remaining strength: (armor + shields) × count, less the damage
  already taken (armor × damage-points / 10 × damaged percent / 10 × count div 500), at least 1.

**Choosing the square** (`Token_Move`): every square within the reach found above (on the board) is rated; a
disengaging token's rating also gets +2 per token of its own on that square and −1 for its own square. Ratings of the
squares next to the token (and its own) are kept in a 3 × 3 grid. The lowest rating wins; on equal ratings the nearer
square wins; on equal rating and distance the k-th such square replaces the current choice when `random(k)` is 0. A
target square found by the target search replaces the choice.

**The step**: when the chosen square is at most one square away the token goes there. Otherwise it steps one square:
diagonally when the x and y distances are equal; when only y differs, one row toward it and to the column (of the 3
next to it) with the lowest grid rating (ties: `random(count)` picks among them); when only x differs, likewise; else
it compares the diagonal step with the straight step along the longer axis by their grid ratings (the lower wins;
equal: `random(2)` = 0 takes the diagonal). A step off the board leaves the token where it is.

## Firing (`Token_Fire`)

When a token fires at initiative i, each of its weapon slots whose initiative (part initiative + computer initiative,
at most 63) is i fires, in slot order. A weapon's range is the part's range, plus 1 on a starbase. Only living enemy
tokens (owners the token's side attacks) within range, of the primary or secondary target class, are targets. The
shot is recorded as an event; each damage application adds a hit to it. The event's last byte names the first token
hit.

**Gatling guns** (beam flag 2): damage = ship count × power × slot count, × the beam damage percent / 100 when not 0.
Every target in range takes it (× its beam defense / 100 when below 100), with no loss over distance; hit kind 1
(power below 200) or 2.

**Other beams and torpedoes** share out a pool: a beam pool of ship count × power × slot count, or a torpedo count of
ship count × slot count. While some is left, the token picks the best target (primary class first; the secondary class
only when no primary target is found) and fires at it:

- A target's **value**: the design's resource and boranium cost per ship (as stored at the start of the turn) × its ship
  count, kept to 16 bits, × 100. **Strength**: armor × count, less damage taken (as for the estimate; at least 1);
  shields × count.
- **Beam score**: the value × beam defense / 100 (when below 100); a sapper scores (value × 100 + shields − 1) div
  shields (nothing without shields); other beams value × 100 div (armor + shields + 1), at least 1.
- **Torpedo score**: the accuracy (below) — 0 or less scores nothing; X = shields × 100 div (accuracy div 2 + (100 −
  accuracy) div 8); Y = ((X × accuracy div −200 + armor) × 100) div ((m + 1) × accuracy) + X, m = 1 for capital
  missiles (Jihad, Juggernaut, Doomsday, Armageddon), else 0; Z = armor × 200 div accuracy; the score is the value div
  the smaller of Y and Z (nothing when that is 0 or less). The highest score wins (the first on ties).
- **Accuracy**: when the target's jamming is at most the firing token's accuracy bonus, accuracy + (bonus − jamming) ×
  (100 − accuracy) div 100; otherwise accuracy − accuracy × (jamming − bonus) div 100.

**A beam shot** at distance d: damage = the pool, × the beam damage percent / 100 when not 0, × the target's beam
defense / 100 when below 100, × (100 − 10d div range) / 100 when d and the range are above 0; hit kind 1 (power below
200) or 2. What the target does not absorb is left: the pool becomes the smaller of (pool − 1) and pool × left div
damage (none left: the pool is empty). (The original computes this in floating point when a value is 65536 or more.)

**A torpedo volley** of n torpedoes: hits = `CalcTorpedoHits(n)` (below). The power doubles for a capital missile
against a target without shields. When the target has fewer ships than n and hits × power exceeds its armor, the token
uses only as many torpedoes as it needs: for k from the target's ship count up to n, h = (hits × k + n − 1) div n and
misses k − h; the shields left after the misses (shields − misses × power div 8, at least 0) take half of the hits'
damage (h × power div 2) and the armor the other half plus what the shields could not take; the first k whose armor
damage reaches the target's armor is used. Then the misses do misses × power div 8 to the shields only (kind 0x84, as
a sapper), the hits h × power div 2 to the shields and the same to the armor (kind 4, at most one kill per torpedo),
and the torpedoes left are n − (hits + misses).

**`CalcTorpedoHits(n)`** with accuracy a and bonus b against jamming j: when j and b are both above 0, j −= b (if that
goes negative, b keeps the excess and j = 0; otherwise b = 0). With b left: a' = (100 − b) × (a − 100) div 100 + 100;
else with j: a' = (100 − j) × a div 100; else a' = a; at least 1. a' ≥ 100: all n hit. n > 200: a' × n div 100 hit.
Otherwise one `random(100)` per torpedo; it hits when below a'. (The damage estimate calls this too, so estimates of
up to 200 torpedoes draw random numbers.)

## Damage (`Token_TakeDamage`)

A hit records the target, the kind, ships killed, the shield damage (packed: a 13-bit value, shifted right by 2 until
it fits, with the number of shifts in the top 3 bits) and the target's damage word after it.

1. **Shields** (the token's shields × count) take the damage first: all of it when it is less (the shields per ship
   become (pool − damage) div count), else the pool is emptied and the rest goes on. A sapper hit on a token without
   shields does nothing (no hit). When nothing is left (or the hit is a sapper or torpedo miss) and no armor part was
   given, the hit ends; a torpedo hit absorbed this way is recorded with kind 0xC4.
2. **Armor**, for ships: a token with tactic 1 (disengage if challenged) starts disengaging (tactic 0, countdown 7).
   Ships already damaged go first: there are (damaged percent × count div 100, at least 1) of them, each with armor −
   damage (damage points × armor div 500, at least 1) left; while the damage covers one and kills are allowed, it is
   destroyed. Then whole ships, armor each. (A torpedo hit may kill at most one ship per torpedo.) What is left spreads
   over the survivors: with damaged ships it adds their damage and is rounded up, else rounded down, per ship (at
   least 1); damage points = that × 500 div armor rounded up (at least 1), damaged percent 100. With nothing left over,
   the damaged percent becomes the damaged ships' share of the survivors, rounded up. Damage points stay at most 499.
   The fleet's stack takes the new damage word; losses are recorded (`Token_RecordLosses`, below).
3. **A starbase**: its armor damage (in 1/500ths of its armor) plus the hit; below its armor, the planet's starbase
   damage becomes that × 500 div armor (+1 when unchanged); otherwise the starbase is destroyed (recorded with damage
   0xFA00, one ship killed): it leaves the planet (except an Alternate Reality race's), and the planet's queue loses
   its ship and packet items.

**Losses** (`Token_RecordLosses`): the token and its fleet lose the ships; a fleet without ships is destroyed. The
lost ships take their share of the fleet's cargo (S12's cargo split) and leave salvage: a third of their mineral cost
plus that cargo; at a planet 80% of it (with a starbase there) or 50% lands on the planet, in deep space 75% becomes
salvage (S14). The losing design's technology is noted for the battle's tech bonus (part 4).

## Randomness (battles)

Setup: `random(15)` per ship token with an engine; the shuffle (one draw per token). Each round: square choices
(`random(k)` on ties, as above), steps (`random(count)` or `random(2)` on ties), `random(15)` per living token for the
jitter, and the firing draws (part 3b).

## Files (harness)

A record goes into each participant's turn file as block type 31; a record over 1 KiB continues in blocks of type 39
(the tokens and the events are split at token and event boundaries where they fit). `tools/harness/stars_battles.py`
reads them; the importer stores each turn's battles, by id, in `state.battles`.

## Open questions

1. The hit kinds seen (1, 4, 196): presumably beam, torpedo and a torpedo miss; to confirm with the firing rules.
2. The token bytes not decoded yet (offsets 6, 9–12 and 25).
