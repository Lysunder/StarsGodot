# S01 Random number generator

Status: draft (2026-09-30); implemented in `core/rng/` (2026-10-01). Generator, seeding and table checked against
the disassembly; the generator and the seed table, including the entry-55 quirk, confirmed against real files from
the original (see "Verification notes").
References: `Random@1038:8730`, `SeedRandom@1038:86cc`, `SeedRandomFromGameSeed@1038:8672`,
`PushRandomState@1038:0000`, `PopRandomState@1038:8654`, `GenerateTurn@10a8:0000`, `WinMain@1010:0000`,
`NewGameFromDefFile@1070:39d4`. Algorithm: P. L'Ecuyer, "Efficient and portable combined random number
generators", Communications of the ACM 31(6), 1988.

## Summary

The original uses L'Ecuyer's 1988 combined generator: two multiplicative linear congruential generators with
prime moduli, whose outputs are subtracted. Every random decision in the rules (event rolls, battle order, hit
rolls, random player order, AI choices, universe generation) draws from this one generator, so reproducing the
original's results needs the same generator, the same seeding and the same sequence of calls.

## Data used

The generator state is two signed 32-bit integers:

| Name | Range | Modulus | Multiplier |
|---|---|---|---|
| `s1` | 1 .. 2147483562 | m1 = 2147483563 | a1 = 40014 |
| `s2` | 1 .. 2147483398 | m2 = 2147483399 | a2 = 40692 |

Neither part ever becomes 0: both moduli are prime and every seed is non-zero.

## Algorithm

### Next value

1. `s1 ← (40014 × s1) mod 2147483563`
2. `s2 ← (40692 × s2) mod 2147483399`
3. `z ← s1 − s2`. If `z < 1`, add `2147483562` (that is, m1 − 1).
4. The raw value is `z`, in 1 .. 2147483562.

Steps 1 and 2 are exact modular products. The original computes them with Schrage's method in 32-bit arithmetic
(`k = s div q`, then `a × (s − k × q) − r × k`, adding the modulus if negative, with q = 53668, r = 12211 for the
first part and q = 52774, r = 3791 for the second). For positive state values this gives exactly the modular
product. A 64-bit implementation may compute `(a × s) mod m` directly.

### Random integer below a bound

`random(range)` returns an integer in `0 .. range − 1`:

1. Always advance the generator first (steps 1–4 above), **even when `range < 1`**.
2. If `range < 1`, return 0.
3. Otherwise return `z mod range`.

In the original, `range` is a signed 16-bit value, so the largest bound any rule uses is 32767. The classic stream
must assert `range <= 32767`; other streams may allow larger bounds.

The result is a plain remainder, so it carries the small modulo bias of the original. That bias is part of the
faithful behavior: do not "fix" it with rejection sampling.

### Seed table

Both seeding methods pick the two state values from a table `P[0..127]`: the 128 smallest odd primes in
increasing order (3, 5, 7, ... 727), **except that `P[55]` is 279 rather than 269.** 279 is not prime (9 × 31).
This quirk has no gameplay effect beyond which starting states exist, and we keep it so seeds give the same
sequences as the original.

### Game-seed method

Used when a game seed is given explicitly (see "When the original seeds" below). For a seed value `v` (an unsigned
32-bit integer):

1. `i ← v & 63`
2. `j ← (v >> 6) & 63`
3. If `j = i`, then `j ← (j + 1) & 63`.
4. `s1 ← P[i]`, `s2 ← P[j]`

Only bits 0–11 of the seed matter, and only the first 64 table entries are used, so this method has 64 × 63 = 4032
distinct starting states.

### Clock method

Used once at program start, with the system tick count as `v`:

1. `i ← (v XOR 0x35) & 127`
2. `j ← ((v >> 7) XOR 0x5C) & 127`
3. If `j = i`, then `j ← (j + 1) & 127`.
4. `s1 ← P[i]`, `s2 ← P[j]`

Only bits 0–13 of `v` matter: 128 × 127 = 16256 distinct starting states. Our game never seeds from a clock (that
would break determinism). The method is specified only because the verification harness needs it (see
"Verification notes").

### Save and restore

The original can push the current state on a small stack, switch to another state, and pop it back later. It
uses this only outside the game rules: for cosmetic drawing, and in code we do not reimplement. That way those uses
don't disturb the main sequence. We get the same effect from independent named streams instead (below), so there is
no push/pop in our API.

## When the original seeds

| Moment | What happens |
|---|---|
| Program start | Clock method, from the system tick count. |
| New game from a definition file that includes a seed | Game-seed method, before the universe is generated. Without a seed, the universe is generated from whatever state the generator is in. |
| Each turn generation, tutorial game | Game-seed method with a fixed constant (1234567890), at the start of turn generation. Tutorial turns are therefore reproducible. |
| Each turn generation, normal game | **No reseeding.** The sequence continues from the current state of the running program. Computer players, which run in the same program just before turn generation, draw from the same sequence. |

**The generator state is not stored in any game file.** In a normal game, the state at the start of a turn
depends on everything the hosting program did since it started.

## Randomness

This spec defines the generator itself. Each rule spec lists its own calls, in order, with their ranges.

## Draws outside the rules

Writing a game file draws from the generator: each file header takes one `random(2000)`, mixed with the clock, for
the file's cipher salt (`WriteFileHeader@1068:53f8`). Turn generation writes the host file and one file per
player, so these draws sit in the classic sequence between one turn's rules and the next. Our engine writes no such
files, so to stay aligned it must make the same draws (one per file the original would write, in the same order)
on the `classic` stream at that point. The exact count and order belong to the turn-order spec (S02).

## Our design: streams

- **Streams.** Gameplay code draws only from named streams passed in through its context: `classic` (the
  original's sequence; every call listed in a rule spec uses it), `fixes` (extra rolls needed by bug fixes, see
  the known-bugs policy), and one stream per mod (`mod.<mod_id>`, or `mod.<mod_id>.<name>`). Every stream uses the
  generator above.
- **State is saved.** Each stream's `(s1, s2)` is part of the game state and saved with it, so a turn continues
  each stream where the previous turn left off, as the original does.
- **Initial state of the `classic` stream.** With an explicit seed (from a definition file, or a fixture), the
  game-seed method above. Otherwise it is derived like the other streams, from the full game seed and the stream
  name `classic`. That allows about 4.6 × 10^18 starting states instead of the original's 16256 clock states. No
  rule changes: in the original, the starting state is effectively random too.
- **Initial state of the other streams.** Derived from the game seed and the stream name, so adding a mod or
  a fix never shifts the classic sequence:
  1. Let `text` be the game seed in decimal, a colon, and the stream name, encoded as UTF-8 (for example
     `"1234567890:fixes"`).
  2. `h1 ← FNV-1a-32("1:" + text)`, `h2 ← FNV-1a-32("2:" + text)`. FNV-1a-32 starts from 2166136261 and, for
     each byte, XORs the byte in and then multiplies by 16777619, keeping the low 32 bits.
  3. `s1 ← 1 + h1 mod 2147483562`, `s2 ← 1 + h2 mod 2147483398`.

  These derivations are ours, not the original's. They must not use Godot's `String.hash()`, which is not stable
  across engine versions.

## Edge cases

- `random(0)` and negative bounds return 0 but still advance the generator. Such a call counts as a draw, so a
  port must make it wherever the original does, even when the result is unused.
- The game-seed method ignores seed bits above bit 11: seeds 0 and 64 give the same sequence.
- When the two table indices collide, the second one moves up by one (wrapping within the table): game seed 0 gives
  `(P[0], P[1])` = (3, 5).

## Verification notes

Golden-turn tests need the `classic` state at the start of each original turn, which no file stores. Ways to get it:

1. **Tutorial games** reseed with a known constant every turn.
2. **Universe generation** from a definition file with a seed is reproducible.
3. **Fresh host process.** If the harness starts the original fresh for each turn, the state at start-up is one of
   16256 clock-method states. Any computer players then draw from it before turn generation. The harness can
   search those states for the one that reproduces the turn's random results. It is a small search, and the first
   random-dependent results narrow it quickly.
4. **Controlled clock.** If the harness can fix the tick count the original reads at start-up (for example, in the
   emulator), the start state is known directly.

Harness experiments (2026-09-30) showed:

- Two runs of the same turn from identical files differ, even with no computer players and random events turned
  off. Mining rounds fractional output up at random (`Planet_Mine@1020:3a72`), so every turn with a colony draws
  from the generator. No fixture avoids randomness.
- Universe creation from a definition file with a seed is reproducible.
- The original's file cipher uses this generator, seeded from the same table. A real host file whose cipher key
  goes through table entry 55 decodes correctly with 279 and gives garbage with 269, which confirms the generator
  and the quirk.
- Option 4 works: in a harness-only copy of the original with the start-up seed fixed, two runs of the same turns
  (up to 20 turns, with random events and computer players) give identical game data. Only file ids and checksums
  differ, because the file salt mixes in the clock (see "Draws outside the rules").

## Worked examples

Computed from this spec by an independent script; they are the unit tests of `core/rng/`.

| Game seed | `(s1, s2)` | First five raw values | First five `random(100)` |
|---|---|---|---|
| 0 | (3, 5) | 2147400144, 819132901, 2112045575, 549227523, 1079672687 | 44, 1, 75, 23, 87 |
| 1 | (5, 3) | 77994, 890600497, 421707707, 878171086, 1702513118 | 94, 97, 7, 86, 18 |
| 64 | (3, 5) | same as seed 0 | same as seed 0 |
| 1234567890 | (71, 41) | 1172622, 692980585, 763769720, 1721447872, 1598024419 | 22, 85, 20, 72, 19 |

The first raw value for seed 0, by hand: `s1 = 40014 × 3 = 120042`, `s2 = 40692 × 5 = 203460`,
`z = 120042 − 203460 = −83418`, so `z = −83418 + 2147483562 = 2147400144`.

`random(0)` still advances: from game seed 0, `random(0)` returns 0, and a following `random(1000)` returns 901,
which is the second raw value mod 1000 (819132901 mod 1000). The state after those two draws is
`(508393462, 1836744123)`.

Clock method: tick count 0 gives `(257, 491)`, tick count 0x1234 gives `(5, 673)`.

## Mod hooks

- `ctx.rng(stream_id)` returns a stream with `random(range)` and `next_raw()`. Mods get only their own
  `mod.<mod_id>…` streams. The `classic` and `fixes` streams are reserved for core rules.
- No formula ids: the generator itself is not replaceable, since every other rule depends on its exact sequence.

## Open questions

1. How many draws happen between program start and turn generation in a host-mode run of the original, with and
   without computer players. To be answered by the harness spike.
