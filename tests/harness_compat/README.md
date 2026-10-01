# harness_compat: test-only compatibility mod (D12)

Our rules fix the original's known bugs (spec S25, `KNOWN_BUGS.md`). A few of those bugs fire so often that
golden-turn fixtures can't avoid them, and fixing them changes later state (which ships survive, which targets
are chosen, how many random draws follow). For those, this mod puts the **original behaviour** back, so the
golden-turn runner can check that everything around the fix matches the original exactly.

The runner has two modes:

| Mode | Mods | Expects |
|---|---|---|
| compat | `core` + `harness_compat` | an exact match with the original's next turn |
| standard | `core` only (the shipped rules) | a match except for differences explained by fixes logged as triggered that turn |

## Rules for this mod

- **Test runs only.** The mod loader refuses it unless test mods are allowed (`ModLoader.allow_test_mods`), and
  refuses the id `harness_compat` anywhere outside `res://tests/`, so a copy in `user://mods` never loads. Every
  export preset excludes `tests/`. It is never a host, player or mod option.
- **Replaces whole formulas or phases.** Each fix lives in its own replaceable formula or phase in the core rules,
  so this mod swaps it through the normal ruleset and pipeline API (M6) instead of patching code.
- **Written from the specs.** Each subsystem spec describes both the fixed rule and the original behaviour; the
  code here follows the latter, in our own words.

## Contents (planned)

Nothing is replaced yet: the formulas and phases these entries target arrive with the rules engine (M6, M7, M9).

| Bug | Original behaviour reproduced | Replaces | Spec |
|---|---|---|---|
| B04 | Mine damage top-up applied to the first design stack only | formula `minefield.damage` | S13 |
| B08 | Battle board limited to 256 tokens, extras left out by fleet number | battle token selection | S16 |
| B09 | Armor damage rounded to 1/512 of the stack per salvo | battle damage resolution | S16 |

Add a bug here only when fixtures cannot avoid it, and record the reason in `KNOWN_BUGS.md`.
