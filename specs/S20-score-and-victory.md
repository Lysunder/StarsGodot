# S20 Score and victory

Status: draft (2026-10-12). Read from the code (the ship rating's 32-bit arithmetic from the disassembly); built
(`core/rules/score.gd`, phase `score.update`). Verified: every score record in the fixtures' turn files (393 in
mine1, terra1, long1, follow1, gate1 and prod1) and in big1's 80 turns (480 records, six computer players), with
ranks: scores, resources, planets, starbases, ship classes, tech, and the tech, production, highest-score and
exceeds-second conditions. Not yet seen in a game: capital ships, the planets and score conditions, an elimination,
a winner (unit tests only).
References: `UpdateScoresAndVictory@10b0:3b78`, `ComputePlayerScore@1030:3832`, `Design_Evaluate@1030:079e`,
`Design_BattleMovement@10e8:216e`, `Planet_GetResources@1040:4de8`, `GetVictoryCondition@1070:6a04`,
`IsVictoryConditionOn@1070:698a`, `PackLongToWord@1030:2ffe`, `AddMessageFirst`.

## Summary

Every turn, right after the year advances (S02 phase 24, `score.update`), each player gets a score and a score record
(population, resources, starbases, ships by class, tech), a rank among all players, and the victory conditions the
player meets this turn. A player left with no planets and no ships is eliminated. When enough conditions are met by
someone (after a minimum number of years), or only one player is left, the game has a winner: everyone is told every
turn from then on, but play can go on.

## Data used

- Planets: owner, population (hundreds), starbase and its design's hull (`dock`), the planet's resources (S08).
- Players: tech levels, ship designs, `eliminated`.
- Fleets: owner, ships per design.
- Parts (ship rating): beam `range`, `power`, tag `sapper`; torpedo `range`, `power`; bomb `kill_rate`,
  `installations`; electrical parts tagged `capacitor` and their `beam_damage_pct`; engines and battle movement (S16).
- Game settings `victory` (below) and the turn number (after the year advanced).

Written:

- Player `score`: the record below; `rank`; `eliminated`.
- Messages (S21, all goto the score report): see "Messages".

### Victory settings

`settings.victory` holds the ten values of the New Game dialog's victory conditions, each a whole number; the first
seven can be switched on:

| Id | Meaning | Values | Original byte |
|---|---|---|---|
| `owns_planets` | owns at least this percent of all planets | 20, 25 … 100 (×5) | 0: `(v + 4) × 5` |
| `tech_level` | reaches this tech level … | 8 … | 1: `v + 8` |
| `tech_fields` | … in this many fields (no switch of its own) | 2 … 6 | 2: `v + 2` |
| `score` | reaches this score | 1,000 … (×1,000) | 3: `(v + 1) × 1000` |
| `exceeds_second` | exceeds the second-ranked player's score by this percent | 20 … (×10) | 4: `(v + 2) × 10` |
| `production` | has this many thousand resources a year | 10 … (×10) | 5: `(v + 1) × 10` |
| `capital_ships` | has this many capital ships | 10 … (×10) | 6: `(v + 1) × 10` |
| `highest_score` | has the highest score after this many years | 30 … (×10) | 7: `(v + 3) × 10` |
| `criteria` | conditions a winner must meet | 0 … 7 | 8: `v`, at most the number switched on |
| `min_years` | years before a winner can be declared | 30 … (×10) | 9: `(v + 3) × 10` |

The original keeps each as a byte (low 7 bits `v`, bit 7 on) at offset 20 of the game settings block (S23); the
harness converts them to the values above. A condition counts only when switched on; `criteria` counts the switched
on conditions among the seven (`tech_fields` has no switch).

## Algorithm

### Ship rating (`Design_Evaluate`)

For a ship design, over its slots (32-bit arithmetic, each division truncating):

1. **Beams:** a = Σ (range + 3) × power × count div 4, divided by 3 (truncating) for a sapper.
2. **Torpedoes:** t = Σ (range − 2) × power × count div 2.
3. **Bombs:** b = Σ (kill_rate + installations) × count × 2.
4. **Capacitors:** c = 1000, then for each capacitor (count times) c = (beam_damage_pct + 100) × c div 100. When c is
   not 1000: c = min(c div 10, 255) and a = c × a div 100.
5. **Movement:** m = the design's battle movement without a fleet (S16 `Design_BattleMovement`: no race bonus, no
   cargo, no draw): the engine speed plus movement parts minus 4, minus mass div 70 div engines, at most 8, at least
   0 (a design without engines: 0).
6. rating = a + (m − 4) × a div 10 + t + b.

Its **class**: unarmed when the rating is 0 or less, escort below 2,000, capital from 2,000.

### Score (`ComputePlayerScore`)

For player p, all sums 32-bit:

1. Over the planets p owns, in planet order: P counts them; population points += min(ceil(population div 1000),
   6) (population in hundreds: one point per 100,000 colonists, rounded up, at most 6); K counts those with a
   starbase whose hull has a dock (any starbase but the Orbital Fort); R += the planet's resources (S08).
2. score = population points + R div 30 + 3 × K.
3. **Tech** (none for an eliminated player): for each field's level L, score += L when L ≤ 3; 2L − 3 for 4 … 6;
   3(L − 3) for 7 … 9; 4L − 18 from 10. The record's tech total is the sum of the levels (0 when eliminated).
4. **Ships:** over p's fleets with ships, the ships per design are added to U (unarmed), E (escorts) or C (capitals)
   by the design's class. score += min(U, P) div 2 + 2 × min(E, P), plus P × C × 8 div (P + C) when C > 0.

The **record**: score, resources R, planets P, starbases K, U, E and C, tech total. (The original stores U, E and C
packed into 16 bits, S16 "Damage" `PackLongToWord`: exact up to 8,191; the capital ships condition reads the packed
value back.)

### The turn's update (`UpdateScoresAndVictory`)

1. For each player p in order:
   1. Compute p's record.
   2. **Elimination:** when p has no planets and no ships (P, U, E, C all 0) and is not eliminated yet, p is
      eliminated; every other player gets **`game.player_eliminated`** `[p]`, put **first** in their messages.
   3. **Conditions** p meets this turn (noted in p's record whether switched on or not; each switched-on one adds 1
      to p's count):
      - `owns_planets`: P ≥ MulDiv(all planets in the universe, percent, 100) (rounded to nearest, halves away
        from zero);
      - `capital_ships`: C (as packed) ≥ the value;
      - `score`: score ≥ the value;
      - `tech_level`: the number of fields at level ≥ `tech_level` is at least `tech_fields`;
      - `production`: R div 1000 ≥ the value.
2. With a single player in the game, that player's rank is 1 and nothing else happens.
3. **Ranks:** each player's rank is 1 + the number of players (eliminated ones included) with a higher score. The
   leader is the last player in order with rank 1; "second" is the score of the last player with rank 2 (0 when
   none), or the leader's score when several share rank 1.
4. `highest_score`: when the turn ≥ the value and exactly one player has rank 1, the leader meets it.
5. When at least two players are not eliminated:
   - `exceeds_second`: when (percent + 100) × second div 100 ≤ the leader's score, the leader meets it;
   - when the turn ≥ `min_years` and `criteria` n > 0: every player whose count is at least n is a **winner**
     (noted in the record). With at least one winner, every player gets, put first: an eliminated player
     **`game.dead`**; a player not among the winners **`game.won_by_other`** `[winners]`; the only winner
     **`game.won`**; a winner among several **`game.won_shared`** `[the other winners]`.
6. Otherwise (at most one player not eliminated): the leader gets **`game.last_standing`** when not eliminated, and
   every other player **`game.dead`**, put first.

The messages come again every turn the conditions still hold; the game goes on.

### History

After the update, the turn's records are added to the game's `history`: {turn, records}, one record per player with
its planets, starbases, unarmed, escort and capital ships, tech total, resources, score and rank. The original keeps
these in each player's history file (`.h`, `WriteHistoryFile@1040:80da`) from the score records in the player's turn
files, so the golden fixtures don't hold them (the golden turns ignore `history`).

### What a player sees (score report)

A player's turn file has the player's own score record, and every player's when the game has public scores and the
turn is above 19 (`WriteGameFile@1068:35b0`, block 45; the original also writes the record of a player whose player
flag bit 0 is set, open item). The score report (`SCOREXDLG@10f8:0a66`) shows those records only, in three views
the Switch button goes round: the table (planets, starbases, unarmed, escort and capital ships, tech levels,
resources, score and rank per player), the victory conditions (the conditions switched on, the number a winner
must meet and the years before a winner, with the conditions each player met this turn), and the history graph of
one of the first eight figures over the years (`Score_DrawHistoryGraph@10f8:1a0e`, the figure picked by clicking it).

## Randomness

None.

## Edge cases

- Eliminated players keep their place in the ranking (with no tech points, usually 0 or little score).
- A player with no planets gets nothing for unarmed or escort ships, and nothing for capital ships (P = 0).
- Ties for first: no one meets `highest_score` or `exceeds_second`.
- `criteria` 0 (or nothing switched on): no winner by conditions, only by being the last one left.
- A starbase without a dock (Orbital Fort) adds no score.

## Known bugs

None known. (The community notes that capital ships score less once a player has more of them than planets; that is
the formula, not a bug.)

## Worked examples

mine1 turn 120, player 2: one planet with 1,150,300 colonists (6 points), resources 1,680 (56), a Space Station
(3), tech levels 13, 11, 10, 10, 10, 10 (34 + 26 + 22 × 4 = 148), 4 unarmed ships (min(4, 1) div 2 = 0) and 4
escorts (2 × min(4, 1) = 2): score 215, rank 1. Its record also notes the tech and highest-score conditions.

## Mod hooks

Formula ids: `score.player` (the score and record), `score.ship_rating`. Victory conditions and messages are content
(settings and message types).

## Open questions

1. Player flag bit 0 also puts a player's score record in every turn file (see "What a player sees"); what sets it
   is not known yet.
2. A harness game that ends is still needed: capital ships, an elimination, then a win by conditions.
