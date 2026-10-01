# Sxx Subsystem name

Status: draft | verified | locked
References: `FunctionName@seg:offset`, ... (analysis references only)

## Summary

What the rule does and why, in plain words.

## Data used

Fields read and written, with units (for example, population in units of 100 colonists) and integer widths.

## Algorithm

Numbered steps with exact integer math: division and rounding, clamps, overflow behavior, order of iteration.

## Randomness

Each RNG call, in order: stream, range, and what the result is used for.

## Edge cases

Zero values, maximums, ownership changes during the turn, empty collections, and so on.

## Known bugs

Bugs from the known-bugs register that touch this subsystem: the fixed behavior we implement, the original behavior
(for the test-only compat mod, if the bug is in its set), and how the fix keeps the classic RNG stream aligned.

## Worked examples

Inputs and outputs, from harness runs of the original when possible.

## Mod hooks

Formula ids, trait parameters and hook names this spec exposes.

## Open questions
