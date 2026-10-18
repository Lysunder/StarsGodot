# S27 Game modes

Status: draft
References: none (the original has no hotseat mode; its players each open their own turn file). S07 (relations at
the start), S20 (elimination and victory), S22 (the AI step).

## Summary

How a game is played: a single human against computer players, several humans taking turns at the same screen
(hotseat), or several humans each on their own machine, sending files to a host (play by email).

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

### Play by email

**The host's folder** holds `host.json` (the format, a game id, the game's name), the game itself (`game.json`, a
save), a turn file for each human player and the order files they send back. The game id is the first 16 hex digits
of the SHA-256 of the new game's save text. The host tool (`tools/host.gd`, headless) has three commands:

1. `new <folder> <setup>`: makes the game from a setup file (universe options; the players in order, humans from
   race files or presets, the first one human, computer players by personality and level) and writes every human
   player's turn file, `<name>-p<N>.turn` (N counting from 1).
2. `status <folder>`: the year, and for each human who gives orders (step 1 of "The year") whether their orders
   are in.
3. `generate <folder> [--force]`: when every such human's orders are in (with `--force`, the missing ones give
   none), generates the year with them and the computer players' orders (S22), saves the game, moves the orders
   used to `done/<turn>/` and writes every human player's new turn file (an eliminated one too). A game made with
   other gameplay content than the host's is refused (S03).

An order file is refused, and its player counted as waiting, when it is damaged (checksum), names another game id,
another player than its name says, or another year.

**A turn file** holds the game as its player knows it:

- the player's own planets, fleets, designs, settings, messages, knowledge (planet history, S15) and view of the
  year in full;
- every other planet as the player's planet history records it (owner, homeworld, starbase, and when ever scanned,
  environment, original environment, concentrations, population and defense estimates; this year's surface
  minerals only when seen at that detail); a planet never seen has no owner and every value zero;
- other players' fleets only when seen this year: position, planet and ships, with no cargo, name, battle plan,
  repeat or waypoints beyond where they are;
- other players' designs only as far as seen (in full, or the hull with its slots empty); a starbase design the
  planet history records counts as seen (its hull);
- minefields the player owns or knows, packets (its own and those seen), wormholes seen (a wormhole whose other end
  is not seen leads nowhere known), traders seen;
- of other players: their race's name, plural and logo, whether they are computer players, eliminated, rank, and
  their score records only with public scores; nothing else (no traits, tech, research, relations, plans, queues,
  knowledge);
- the battles the player took part in; random streams set to a fixed start, so nothing in the file foretells the
  year.

**Integrity**: turn files and order files carry `checksum`, the SHA-256 of the canonical JSON (keys sorted, no
whitespace) of every other field. A file whose checksum does not match is refused as damaged. This guards against
accidents in transit, not against a player who edits a file and recomputes the checksum.

**The player** opens the turn file (main menu, Open Turn File). The game is theirs alone (no hand-off). Ending the
turn, or saving, writes their orders beside the turn file (`.orders` for `.turn`), to send to the host; opening the
turn file again goes on with the orders written for it.

## Randomness

None.

## Edge cases

- Every human eliminated: the last player at the controls stays there and years go on.
- A save from before hotseat (one human, one orders file): loads as before.

## Worked examples

- Play by email: three humans and a computer player through 20 years, nothing passing between players and host but
  turn files and order files (`tests/unit/game/test_pbem.gd`).

- Two humans and a computer player: the first gives orders and ends the turn (no year); the second does the same;
  the year is generated with both humans' orders and the computer player's, and the first human is up again
  (`tests/unit/ui/test_hotseat.gd`).

## Mod hooks

None.

## Open questions

- A host that marks a player inactive (played by the computer, S22) or drops one: not offered yet.
