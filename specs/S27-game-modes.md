# S27 Game modes

Status: draft
References: none (the original has no hotseat mode; its players each open their own turn file). S07 (relations at
the start), S20 (elimination and victory), S22 (the AI step).

## Summary

How a game is played on one machine: a single human against computer players, or several humans taking turns at
the same screen (hotseat). Play-by-email will be added here (M13).

## Data used

- Players: `ai` (empty for a human), `active`, `eliminated`, `relations`.
- The UI session (not game state): the human player at the controls, each human's orders for the year, and the
  humans who have ended their turn.

## Algorithm

### Players in a new game

The New Game window makes the first player a human with the chosen race. The other players are either the
computer players the difficulty level and universe size pick (S22 "Computer players in a new game"), or the list
Advanced Game gives, in its order: computer players and further human players, each with a race from the race list.
At most 16 players. Relations start as S07 sets them: every player the enemy of every other when exactly one human
(active) is in the game, otherwise all neutral.

### The year

1. The **humans who give orders** this year are the human players that are active and not eliminated, in player
   order.
2. The first of them is at the controls when a game is started or loaded (unless a save says otherwise, step 5).
3. **Ending a turn** keeps the orders of the player at the controls as submitted. If a human who gives orders has
   not submitted yet, the first such (in player order) comes to the controls, and nothing is generated.
4. Otherwise the year is generated with the submitted orders, the computer players adding theirs (S22). The first
   human who gives orders in the new year comes to the controls, and every human's orders start empty. Each human
   sees, when their turn begins, the orders of theirs the year refused.
5. **Saving** keeps, beside the game, each human's orders for the year and the round: the year, the player at the
   controls and the players who have submitted. Loading the same year restores them; anything for another year is
   ignored.

An eliminated human gives no orders, so a hotseat game goes on with the others. A single human player who has been
eliminated stays at the controls and may keep generating years to watch (step 4 with nothing but the computer
players' orders).

### Hand-off (hotseat)

With more than one human giving orders, the screen is covered whenever another human comes to the controls, and
when such a game is opened: the cover names the year, any human players wiped out since the last cover, and the
player whose turn it is, and the game shows only when that player begins. Their game opens on their homeworld (or
their first planet).

### Defeat notice

The original tells an eliminated player nothing unless the game has a winner (S20). The player at the controls is
told once that their race has been wiped out: on the year it happens, or when a game already lost is opened.

## Randomness

None.

## Edge cases

- Every human eliminated: the last player at the controls stays there and years go on.
- A save from before hotseat (one human, one orders file): loads as before.

## Worked examples

- Two humans and a computer player: the first gives orders and ends the turn (no year); the second does the same;
  the year is generated with both humans' orders and the computer player's, and the first human is up again
  (`tests/unit/ui/test_hotseat.gd`).

## Mod hooks

None.

## Open questions

- Play-by-email (M13): turn files per player, order files, checksums.
