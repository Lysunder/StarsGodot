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
  so this mod swaps it through the normal ruleset and pipeline API instead of patching code. Its `ruleset.gd` has
  `build(ruleset)`, which the mod loader calls after loading its content (only test mods may have one for now).
- **Written from the specs.** Each subsystem spec describes both the fixed rule and the original behaviour; the
  code here follows the latter, in our own words.

## Contents

| Bug | Original behaviour reproduced | Replaces | Spec | State |
|---|---|---|---|---|
| B09 | Armor damage rounded up per hit, at least 1/500 of the armor per ship | formulas `battle.armor_damage`, `battle.starbase_damage` | S16 | done |
| B04 | Mine damage top-up applied to the first design stack only | formula `minefield.top_up` | S13 | done |
| B51, B52 | Macinti's scout cap by the miner design, rich by two minerals | formulas `ai.macinti_*` | S22 | done |
| B44, B45, B46, B48 | Cybertrons' packet and fleet marks as the original keeps them | formulas `ai.cybertrons_*` | S22 | done |
| B54 | An empty design slot's turn designed as the last computer player's file left it | formula `ai.empty_slot_turn` | S22 | done |

B08 (the 256-token battle limit) is not here: no fixture battle comes near it.

Tests load it with `tests/unit/compat_content.gd`.

Add a bug here only when fixtures cannot avoid it, and record the reason in `KNOWN_BUGS.md`.
