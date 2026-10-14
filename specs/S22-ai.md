# S22 Computer players (AI)

Status: draft (2026-10-14), first part: the AI step and personalities as data. The personalities' own play comes in
later parts.
References: `RunComputerPlayers@1018:39f8`, `AI_PlayTurn@1080:0000`, `AI_InactiveHuman@1090:0000`,
`CheckTurnFile` (turn file check before a computer player plays), personalities `AI_Robotoids`, `AI_Turindrones`,
`AI_Automitrons`, `AI_Rototills`, `AI_Cybertrons`, `AI_Macinti` (segments 1080-10a0), toolkit in segment 1088.

## Summary

Computer players are ordinary players whose orders are made by the game instead of a person. Just before a turn is
generated, each one reads its own view of the game and gives the same kinds of orders a human gives (S11). Nothing
about them is special after that: their orders are checked and applied with everyone else's, and the turn is
generated the same way.

## Data used

- Per player (S03): `ai` (the personality key, empty for a human), `ai_level` (difficulty, 0-3), `active` (false
  for a human player marked inactive), `eliminated`.
- The personality's content definition (`ai_personality`, see "Personalities").
- The player's view of the game: its own planets, fleets, designs and settings, and what it has seen of the others
  (S15). A computer player never reads the host state beyond its view.
- The classic random stream (S01).

## Algorithm

### The AI step

Runs before turn generation (S02 "Before turn generation"), outside the turn pipeline.

1. Go through the players in index order.
2. A player plays in this step when it is still in the game (not eliminated) and either
   - is a computer player, with its personality; or
   - is a human player marked inactive, with the **inactive** personality, which only keeps things ticking over
     (research, and the starting fleets' and colony ships' simple errands).
3. A player that already has orders for this turn (an order file) does not play; its orders are used instead. (The
   original checks for the player's turn file and plays only when there is none.)
4. Otherwise the player's brain runs once on a fresh context: the player's view, the content, the classic random
   stream, the personality and the level. The brain keeps nothing from one turn to the next; anything it needs is
   read again from the view each turn, as in the original, where the AI's working memory is built at the start of
   its turn and freed at the end.
5. The brain's orders form the player's order set for the turn, exactly as if the player had sent them.

The original runs each computer player by reopening the game as that player, letting it play, writing its orders,
and finally reopening the host game. Our step works on the player's view directly and changes nothing in the host
state; only the classic stream advances.

### Personalities

A personality is content (`ai_personality`, id `ai_personality.<key>`, the key being `Player.ai`):

| Field | Meaning |
|---|---|
| `order` | display order |
| `brain` | which built-in brain plays it |
| `params` | named integer parameters the brain reads |
| `levels` | optional, one map per difficulty level (easiest first), the parameters that level changes |

A brain asking for parameter *k* gets the level's value if the level map has *k*, else the personality's `params`
value, else the brain's own default. Personality and difficulty are therefore data; a mod can add a personality
for an existing brain, or change one's parameters, without code.

The original has six personalities, chosen by the computer player's race (keys `robotoids`, `turindrones`,
`automitrons`, `rototills`, `cybertrons`, `macinti`, in the original's numbering 0-5), and the housekeeping one
for inactive humans (`inactive`, the original's number 7). Their play is specified in later parts of this spec.
Until a personality's brain exists it uses the **idle** brain, which gives no orders.

Difficulty levels, easiest first: easy, standard, harder, expert (`ai_level` 0-3). Besides the AI's own play, the
level matters in the starting setup (S07) and in Mystery Trader dealings (S18).

## Randomness

Computer players draw from the classic stream, in player order, before any draw of turn generation (S01, S02). The
draws of each personality are listed with its part of this spec. Idle brains draw nothing.

## Edge cases

- A personality key with no content definition, or a definition naming a brain the game doesn't have: the player
  gives no orders this turn, and the host is told.
- Orders a brain gives that the rules reject are rejected as for a human (S11), and the rest still apply.
- An eliminated computer player does not play.

## Known bugs

None yet.

## Worked examples

`tiny3ai` (harness): player 0 human, players 1 and 2 computer players. With player 0's orders given, the step adds
order sets for players 1 and 2, in that order.

## Mod hooks

- Content type `ai_personality` (above).
- Brains are built in for now; script mods will be able to add brains (M14).

## Open questions

1. The order of the original's draws inside each personality (later parts), which golden AI games will check.
2. What exactly the inactive personality does each turn (`AI_InactiveHuman`): research plan, colony ships and
   scouts going home or settling.
