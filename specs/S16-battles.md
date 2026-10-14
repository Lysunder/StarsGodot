# S16 Battles

Status: draft (2026-10-11). First part: the battle recording, which the harness reads from the original's player turn
files and which our battle engine will produce in the same shape (`state.battles`). Second part: who fights, the
tokens and where they start. Third part: rounds, movement and target choice (3a), firing and damage (3b); built
(`BattleEngine`). Verified: the two fixture battles (terra1 turn 30, mine1 turn 69), and all 227 battles recorded in
big1 (80 turns, 6 computer players; 6,170 moves and shots), replayed from their recorded starting tokens at their place
in the random sequence (each big1 turn starts from the fixed start-up state; the setup's jitter and shuffle draws
locate the battle), match move for move and shot for shot.
Fourth part (4a): battles inside the turn and their results (tech bonus draws, Alternate Reality habitats, marks for
repair); verified by the fixture turns (terra1 turn 30, mine1 turn 69 now match whole) and by replaying each big1
turn's battles in sequence: all 227 start exactly where the previous battle's results left the random sequence.
Fourth part (4b): the battle messages; verified by the two fixture battles (a duel and a two-sided battle at a
starbase), the other cases read from the code only. Fourth part (4c): what a battle shows its participants (S15
"What scanning records", step 7); verified by the fixture turns and by all six players' views in the 80 turns of
big1 (designs, fleets, players met; the only differences left are planets lost or bombed out, S17).
Fix B09 (2026-10-11): exact armor damage within a battle; the verifications above run with the original's version
(harness_compat, D12). Without it, the fixtures differ only in one hit's damage word (mine1 turn 69).
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
`Fleets_RedistributeCargo@1048:6c1c`, `TryTechBonus@10e8:6112`, `NoteDesignTech@1078:244c`,
`Planet_Depopulate@1040:553a`, `RepairFleetsAndStarbases@10b0:28de`.

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
     stayed on its square and is armed (a disengaging token's move is always recorded).
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
that distance (ignoring range and the token's armor when the token's tactic is 0). The distance kept is the one the enemy
would choose: the lowest `score(taken, dealt)` under the enemy's own tactic (from its side, so the two values are
passed in the reverse order of the final score), the last one on ties. The square's rating is `score(the largest dealt kept, the sum of the taken
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

- A target's **value**: the design's resource and boranium cost per ship (as stored at the start of the turn: the
  original computes a design's cost when it loads the turn and the tech update doesn't refresh it) × its ship
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
defense / 100 when below 100, × (100 − 10d div the part's range) / 100 when d and that range are above 0 (the part's own range, without the
starbase's +1); hit kind 1 (power below
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
2. **Armor**, for ships (formula `battle.armor_damage`): a token with tactic 1 (disengage if challenged) starts
   disengaging (tactic 0, countdown 7). Within a battle a token keeps the exact damage of its damaged ships (fix
   B09, below), in 1/512,000 of a damage point; at the battle's first hit on it, it comes from the damage word: the
   damaged ships are (damaged percent × count div 100, at least 1), each with damage points × armor / 500. Then:
   - Damaged ships go first: while the damage covers what one has left (armor − its damage) and kills are allowed,
     it is destroyed. Then whole ships, armor each. (A torpedo hit may kill at most one ship per torpedo; when the
     kills run out, the rest of the hit is lost.)
   - What is left, with ships left, spreads evenly over all of them, the damaged ships' damage included: each
     ship's damage becomes (rest + damaged ships × their damage) div ships (in the fine units), and all are damaged
     (none when that is 0).
   - The damage word follows: damage points = each damaged ship's damage × 500 / armor, rounded to nearest (halves
     up), at most 499; damaged percent = damaged ships × 100 / ships, rounded up (0 with 0 points).
   The fleet's stack takes the new damage word; losses are recorded (`Token_RecordLosses`, below).
3. **A starbase** (formula `battle.starbase_damage`): it keeps its exact damage the same way (from the planet's
   starbase damage at its first hit); with the hit added, below its armor, the planet's starbase damage becomes
   that × 500 / armor rounded to nearest (at most 499); otherwise the starbase is destroyed (recorded with damage
   0xFA00, one ship killed): it leaves the planet (except an Alternate Reality race's), and the planet's queue loses
   its ship and packet items. Its token's damage word becomes the damage points with damaged percent 100.

The original's version (B09; the harness_compat mod's formulas): there is no exact damage; each hit starts again
from the damage word, a damaged ship having (damage points × armor div 500, at least 1) damage. The rest of a hit is
spread per ship rounded down (rounded up when there were damaged ships, their damage added), at least 1, and the
damage points are that × 500 div armor rounded up, at least 1 (damaged percent 100); with nothing left over, the
damaged percent becomes the damaged ships' share of the survivors, rounded up. A starbase's damage is its damage
word's points × armor div 500 plus the hit, the new damage that × 500 div armor, plus 1 when that leaves it
unchanged. So every hit adds at least 1/500 of the armor per ship.

**Losses** (`Token_RecordLosses`): the token and its fleet lose the ships; a fleet without ships is destroyed. The
lost ships take their share of the fleet's cargo (S12's cargo split) and leave salvage: a third of their mineral cost
(as stored at the start of the turn, but at current tech levels for a race with `battle.salvage_at_current_tech`,
Bleeding Edge Technology) plus that cargo; at a planet 80% of it (with a starbase there) or 50% lands on the planet, in deep space 75% becomes
salvage (S14). The losing design's technology is noted for the battle's tech bonus (part 4).

## Battle results (`FinishBattle`)

The battles of a turn are fought one after the other, in place order (above), at the start of the waypoint 1 step;
each battle's recording is added to the turn's battles, with id `(turn × 256 + 1 + k) mod 4096` for the turn's k-th
battle (from 0). Every fleet in a battle, and a starbase whose owner took part, is marked as having fought this turn.
When a battle ends:

1. **Alternate Reality habitat.** When the starbase was destroyed and its owner's race lives in its starbases
   (`colony.starbase`), the planet is emptied (S08 "Depopulation").
2. **Tech bonus** (`TryTechBonus`, S24), in player order. The need is, per field, the highest level any design that
   lost ships in this battle needs (hull and parts in use; noted at each loss, whoever owned the ships). A destroyed
   starbase is not noted. Each player in turn gets one try when:
   - it took part: unless the starbase of an Alternate Reality race was destroyed (then no participant tries); the
     planet (if any) must be unowned or its own; and in a battle of two sides it must still have ships there, or its
     starbase there survived;
   - it did not take part but owns the planet;
   - it did not take part but has a fleet at the place (a bystander). Fix B36: the original tests the bystanders'
     bit mask against the player's number instead of its bit, so most bystanders never try. Every bystander tries;
     the draws come from the classic stream when the original's test passes, else from the `fixes` stream.
3. **Destroyed fleets** (no ships left) are deleted after all of the turn's battles (S11 "Deleting a fleet"). The
   design counts of the ships and starbases destroyed go down as they are lost.

**Repair (S19).** A fleet that fought doesn't repair this turn; a starbase that fought doesn't repair, and fleets at
its planet repair at the rate for their owner's planet without a starbase.

## Battle messages

Sent in `FinishBattle`, player by player in player order, each player's message coming just before its tech bonus
try (S16 "Battle results"); a gained bonus adds its own message. Parameter kinds are S21's. Every message starts with
the place as a "where" (`object_kind`, `object`: -1 and the planet, or the position's x and y). The battle messages
go to the battle's recording (Goto `{"battle": id}`); the others are marked below.

**What is counted.** The engine keeps a loss table per owner and design slot: a mark when ships of that design took
armor damage (a ship token reaching the armor step of `Token_TakeDamage`, even if nothing died) and the ships killed.
After the battle, every design with ships left in a fleet at the place (any fleet there, also bystanders') gets a
"ships left" mark. Entries are read in owner, then slot order; for player p, its **own** entry is its last one with any
mark and the **enemy** entry the last one of any other owner. The battle's **ships** are all ships at the place before
the battle (bystanders' too) plus 1 for the starbase when its owner takes part; its **designs** the number of owner
and design pairs among them, likewise plus 1. A design is named as owner × 32 + slot; the starbase as its owner × 32
+ 16 + its starbase slot. In what follows "the starbase" is the planet's starbase (if any) of its owner, whether or
not that owner took part, and "destroyed" or "damaged" means the engine destroyed it or damaged it without destroying
it during the battle.

**A participant, when an Alternate Reality starbase was destroyed:** its owner gets `battle.habitat_lost_many` (more
than 1,000 hundred colonists) or `battle.habitat_lost`, the others `battle.habitat_destroyed`, all `[where, starbase
design, population]` (the colonists, in hundreds, before the planet was emptied). Nothing else for them.

**Other participants, battles of two sides, two "ships":** a duel. Own (or the starbase, when p has no entry) is
destroyed when its entry counts a kill (the starbase: destroyed); then p gets `duel_lost_to_damaged` when the enemy
(entry with a hit mark, or the starbase: damaged) was damaged, else `duel_lost`. Otherwise when the enemy is destroyed:
`duel_won_damaged` when own was damaged, else `duel_won`. Otherwise `duel_drawn`. Parameters `[where, own design,
enemy design]`. P may try the bonus unless own was destroyed.

**Two sides, two designs:** as the duel, with `stacks_*` types; a side is destroyed when its entry has no "ships left"
mark (the starbase: destroyed). The counts: own = its kills (1 for the starbase) plus the ships of own's slot in p's
fleets at the place; enemy = its kills (1 for the starbase) plus the ships of the enemy's slot in every fleet at the
place not counted for p, whoever owns it (the original's way: p's own fleets count for the enemy when p has no entry).
Parameters `[where, own design, own count, enemy design, enemy count]`.

**Otherwise.** Own lost = the kills in p's entries, enemy lost = the kills in all other entries; own total = own lost
plus the ships of p's fleets at the place now; enemy total = enemy lost plus the ships of all other fleets at the place
(bystanders' too). The starbase counts 1 in its owner's side's total, and 1 in the lost when destroyed. The **race**
named is the owner of the last enemy entry, or the starbase's owner when the starbase is not p's (the planet's owner
when there is neither). The own design (when own total is 1) is p's starbase if it has one, else its own entry; the
enemy design (when enemy total is 1) is the starbase when the race is the starbase's owner, else the enemy entry.

Two sides, parameters `[where, race, ...]`:

| Case | Type | Further parameters |
|---|---|---|
| enemy all lost, enemy total 1, own lost 0 | `won_one` | own total, enemy design |
| enemy all lost, enemy total 1 | `won_one_with_losses` | own total, enemy design, own lost |
| enemy all lost, own lost 0, own total 1 | `one_won` | own design, enemy lost |
| enemy all lost, own lost 0 | `won` | own total |
| enemy all lost | `won_with_losses` | own total, own lost |
| own all lost, own total 1, enemy lost 0 | `lost_one` | own design, enemy total |
| own all lost, own total 1 | `lost_one_with_kills` | own design, enemy total, enemy lost |
| own all lost, enemy lost 0, enemy total 1 | `lost_to_one` | own lost, enemy design |
| own all lost, enemy lost 0 | `lost` | enemy total |
| own all lost | `lost_with_kills` | enemy total, enemy lost |
| own total 1 | `one_drawn` | own design, enemy total, enemy lost |
| enemy total 1 | `drawn_against_one` | own total, enemy design, own lost |
| else | `drawn` | own total, enemy total, own lost, enemy lost |

P may try the bonus unless it lost everything (own lost = own total). More sides, parameters `[where, sides, ...]`,
and p may always try:

| Case | Type | Further parameters |
|---|---|---|
| own lost 0, enemy all lost | `melee_won` | own total |
| own lost 0; or enemy lost 0 and own not all lost | `melee` | own lost, own total, enemy lost, enemy total |
| enemy lost 0 (own all lost) | `melee_lost` | own total, enemy total |
| enemy all lost | `melee_won_with_losses` | own lost, own total |
| own all lost | `melee_lost_with_kills` | own total, enemy total, enemy lost |
| else | `fought` | (none) |

**Non-participants:** the planet's owner gets `battle.seen_from_planet` `[planet]` (Goto the planet); a bystander,
`battle.seen_by_fleet` `[fleet, where]` for its first fleet at the place (Goto that fleet; the original sends it only
when its faulty test passes, fix B36).

**Tech bonus messages** (Goto research): `battle.tech_gained` (a participant), `battle.tech_gained_orbit` (the
planet's owner) and `battle.tech_gained_watching` (a bystander), all `[where, field, amount]`, the amount being the
field's next level cost (with slow tech's doubling, though the points added are without it, S24).

(The original's message for fleets left out by its token limit, B08, has no counterpart.)

## Randomness (battles)

Setup: `random(15)` per ship token with an engine; the shuffle (one draw per token). Each round: square choices
(`random(k)` on ties, as above), steps (`random(count)` or `random(2)` on ties), `random(15)` per living token for the
jitter, and the firing draws (part 3b). After each battle: the tech bonus tries, in player order (S24: `random(100)`,
then 13 × `random(13)` and up to 6 × `random(6)` when it passes).

## Playback (battle viewer)

The viewer (`RunVcrDlg@10e0:0000`, `VCR_SeekTo@10e0:053e`, `VCR_TokenStatus@10e0:0f74`) replays a record without
the rules. Step −1 is the board at the start; step k shows event k. Going on to step k moves event k's token to its
square (255: it leaves the board) and lands its hits; when event k's round is later than any before, every token with
state bit 3 first regenerates a tenth of its full shields per ship (capped at full). A hit takes its killed ships off
the target's count, sets the target's damage word to the recorded one, and, when the target has shields and the hit
did shield damage (unpacked), sets its shields per ship to 0 if the shield damage is at least shields × the ships left,
else lowers them by the shield damage div the ships left. Going back replays from the start.

For display, a token's armor left is count × armor, plus, when it is damaged, (−(damage >> 7) × armor / 10) × n / 50
(truncating towards zero) for n = max(1, count × (damage & 127) / 100) damaged ships; each damaged ship's damage is
shown as max(1, (damage div 5) >> 7) percent. A step's armor damage is the armor its targets had before the step less
after it. Movement is shown as (rating + 2) / 4 moves a round.

**Battle Summary report** (`Battle_CountShips@10e0:02aa`, `Battle_CountLosses@10e0:03b8`), per battle the player was
in: the location; "O" when the player had a starbase there, else "T" when another player did; the sides; ships at the
start (each token's count, starbases included) in all, the player's and the others'; ship tokens (no starbases) by
hull class: unarmed (classes 0, 1, 6, 7), scout (2), warship (3), utility (4), bomber (5); the ships the player and the
others lost (the hits' killed counts by the target's owner), and what each side had left.

## Files (harness)

A record goes into each participant's turn file as block type 31; a record over 1 KiB continues in blocks of type 39
(the tokens and the events are split at token and event boundaries where they fit). `tools/harness/stars_battles.py`
reads them; the importer stores each turn's battles, by id, in `state.battles`.

## Known bugs

- B09 (fixed, compat): armor damage is rounded up per hit, at least 1 point and 1/500 of the armor per ship, so many
  small hits (a big stack under fire from many small weapons) do far more damage than they should: a hit of 1 point
  on 100 ships of 2,000 armor adds 1/500 of the armor to every one of them. We keep the exact damage within a
  battle and round only the stored damage word (see "Damage"). Since fixtures cannot avoid it, the test-only
  harness_compat mod keeps the original's version, and the golden turns and battle replays run with it (D12).
- B08 (fixed): the original's limit of 256 tokens (see "Who fights"). No compat version: no fixture battle comes near
  it (big1's largest has 12 tokens).
- B06 (not in 2.6i): said to make ships ignore a starbase's extra range when moving. The code counts it everywhere:
  in the token's ranges (`Token_ComputeWeapons`) and per weapon in the damage estimate (see "Estimated damage").
- B07 (not found): said to keep ships with sappers and range-2 beams from closing to range 2. The target search
  handles that mix on purpose (a token whose longest range is 3 checks its longest non-sapper beam against an
  enemy without shields, see "Target first"), and the estimate gives sappers nothing against an enemy without
  shields; staying at range 3 can follow from the tactic's score. No faulty step found; to revisit with a
  recorded battle that shows it.

## Open questions

1. The hit kinds seen (1, 4, 196): presumably beam, torpedo and a torpedo miss; to confirm with the firing rules.
2. The token bytes not decoded yet (offsets 6, 9–12 and 25).
