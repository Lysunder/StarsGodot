# Contributing to StarsGodot

StarsGodot reimplements the game mechanics of the 1990s 4X game Stars! (version 2.6i) in Godot 4.7. It is a
clean-room project: the original game is still under copyright, and nothing from it may end up in this repository.

## Clean-room rules

**Never commit:**

- decompiled or disassembled code, or output from reverse-engineering tools;
- the original executable, help file, DLLs, graphics, sounds or other resources;
- the original's UI, message, help or tutorial text, copied verbatim or closely paraphrased;
- anything describing how the original's registration or serial-number checks work.

**Spec first, then code.** Every rule is first written down as a spec in `specs/`, in our own words: the formula,
integer rounding, order of evaluation and edge cases. Code is then written from the spec, not from the original. A
spec may name the original function it was derived from (for example `SomeFunction@1040:1234`) as a reference.

The original names of parts, hulls and race traits are kept. Descriptions, help and messages are our own wording.

## Layout

| Folder | Contents |
|---|---|
| `core/` | Pure game logic: model, content, rules, turn pipeline, RNG, visibility, battle, universe, I/O, AI, mod loader. |
| `content/core/` | The base game, packaged as a content pack (the base game is itself a mod). |
| `ui/` | Scenes. |
| `tests/` | Unit tests (gdUnit4) and golden-turn tests. Never exported. |
| `tests/harness_compat/` | Test-only mod that reproduces a few original bugs so golden runs can match the original exactly. Never exported, never loaded outside tests. |
| `specs/` | Rule specifications. |
| `tools/` | Helper scripts (test runner, checks, dev-only harness). |

## Rules for `core/`

These are checked by `tests/unit/test_core_purity.gd` where a text scan can check them.

- **No scene types and no globals.** `core/` scripts extend `RefCounted` or `Resource`. No Nodes, no SceneTree, no
  autoloads, no `static var`. Content, ruleset, RNG streams and hooks arrive through context objects
  (`GameContext`, `TurnContext`, `FormulaContext`).
- **Deterministic.** Randomness comes only from the engine's named RNG streams: never `randi()`, `randf()`,
  `RandomNumberGenerator`, `Time`, `OS` or `Engine`. Only `core/io` touches files.
- **Integer math.** Gameplay math uses integers or fixed point, and gameplay content holds integers only
  (percentages or `[numerator, denominator]` pairs, never floats). GDScript integers are 64-bit, `/` on two
  integers truncates toward zero and `%` takes the sign of the dividend, as in C. Where the original's 16-bit
  rounding matters, use the shared integer helpers (added with the first spec that needs them) and cite the spec.
- **Defined order.** Iterate collections in id order through the provided helpers, never in the incidental order of
  a Dictionary.
- **Moddable by construction.** Read constants from content and call formulas by id through the `Ruleset`. Race
  traits are trait parameters, modifiers or hook scripts, never `if trait` checks scattered through the code. Every
  turn step is a `Phase` with an id. Content is referenced by string ids (`part.beam.laser`).

## GDScript style

- Follow the [Godot GDScript style guide](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_styleguide.html).
  `gdformat` settles layout questions.
- **Static typing everywhere:** typed variables, parameters and return types. Use `:=` only when the type is
  obvious from the right-hand side.
- `class_name` in PascalCase for reusable classes; files in snake_case; functions and variables in snake_case;
  constants in CONSTANT_CASE; private members start with `_`.
- Tabs for indentation, lines of at most 100 characters, LF line endings.
- Document public classes and functions with `##` comments. Say what a rule does and why, and cite the spec
  (`# S08 step 4`).

## Tests and checks

Set `GODOT_BIN` to a Godot 4.7.2 binary (on Windows, the `*_console.exe` build), then:

```bash
bash tools/run_tests.sh
```

This imports the project, compiles every script (`tools/check_scripts.gd`) and runs all gdUnit4 suites under
`tests/`. CI runs the same script on every push.

Lint and format with [gdtoolkit](https://github.com/Scony/godot-gdscript-toolkit) 4.5:

```bash
gdlint core tests tools
```

```bash
gdformat --check core tests tools
```

On Windows, `gdformat` writes CRLF line endings. Git normalizes them on commit (`.gitattributes`), but convert
them back to LF if you want a clean working copy.

## Commits

- One logical change per commit, with a message that says why.
- Every rule change comes with tests; every spec change says what changed in its status line.

## License

The project is licensed under the [GNU General Public License v3.0](LICENSE). By contributing, you agree that your
contribution is licensed under the same terms.
