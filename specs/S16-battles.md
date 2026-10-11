# S16 Battles

Status: draft (2026-10-11). First part: the battle recording, which the harness reads from the original's player turn
files and which our battle engine will produce in the same shape (`state.battles`). Not yet: who fights, tokens and
the board, movement, targeting, firing, damage, retreat (later parts).
References: `RunBattles@10e8:24aa`, `ResolveBattle@10e8:58c0`, `BuildBattleTokens@10e8:2cb4`,
`Token_TakeDamage@10e8:5234`, `Token_Fire@10e8:4310`, `FinishBattle@10e8:62bc`, `WriteBattleBlocks`,
`VCR_SeekTo@10e0:053e`.

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

**Tokens**, in board order (the starbase first, when there is one): each names its fleet (a ship token) or its planet
(a starbase token), its owner, kind (1 starbase, 2 ships), design (0–15 ship designs, 16 + slot for starbase designs),
starting square, the initiative range of its weapons (255 when unarmed), beam damage and beam defense percents, mass
(65535 for a starbase: it never moves), shields per ship, ship count, damage (packed like a fleet's: percent of ships
damaged in the low 7 bits, armor points above), its battle plan's targets (primary in the low four bits, secondary
above) and tactic (low four bits; ship class above), its movement rating (low four bits) and its state word. Board
squares are numbered x + 16 × y on the 10 × 10 board.

**Events**, in the order they happened:

- a token **moves** to a square (255 when it leaves the battle), or **fires** from its square;
- each event records the round (0–15) and the token's disengage countdown;
- a shot lists its hits: the target token, the kind of hit, ships killed, damage to the target's shields (stored as a
  13-bit value shifted left by twice a 3-bit exponent) and the target's damage word after the hit.

## Files (harness)

A record goes into each participant's turn file as block type 31; a record over 1 KiB continues in blocks of type 39
(the tokens and the events are split at token and event boundaries where they fit). `tools/harness/stars_battles.py`
reads them; the importer stores each turn's battles, by id, in `state.battles`.

## Open questions

1. The hit kinds seen (1, 4, 196): presumably beam, torpedo and a torpedo miss; to confirm with the firing rules.
2. The token bytes not decoded yet (offsets 6, 9–12 and 25).
