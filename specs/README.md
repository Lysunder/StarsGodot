# Rule specifications

Each file here specifies one subsystem of the Stars! 2.6i rules, in our own words. Code in `core/` is written from
these specs. See [CONTRIBUTING.md](../CONTRIBUTING.md) for the clean-room rules.

## Rules for specs

- **Our own words.** Describe the rule: formula, units, integer rounding, order of evaluation, random rolls and edge
  cases. Never paste decompiled code or the original's text.
- **Cite the source.** List the original functions a spec was derived from, as `FunctionName@seg:offset`. These are
  references for reviewers, not content.
- **The code wins.** Community write-ups (wiki pages, FAQs, spreadsheets) are test oracles. When one disagrees with
  the 2.6i code, follow the code and note the disagreement under "Open questions" or "Notes".
- **Bugs are fixed, not specified as behavior.** If the original has a known bug in this area, the spec describes
  the fixed behavior and, briefly, the original behavior it replaces (needed for the test-only compat mod), with
  the bug id from the known-bugs register.
- **Integer semantics are part of the rule.** State the integer width where it matters, whether division truncates
  or rounds, and any clamping.
- **Every spec has worked examples,** ideally from harness runs of the original.

## Status values

| Status | Meaning |
|---|---|
| `draft` | Written from the code; not yet checked against the original's output. |
| `verified` | Worked examples confirmed by harness runs of the original. |
| `locked` | Implemented and passing golden tests. Changes need a reason recorded in the spec. |

## Index

| Spec | Subsystem | Status |
|---|---|---|
| [S01](S01-rng.md) | Random number generator | draft |

New specs start from [TEMPLATE.md](TEMPLATE.md).
