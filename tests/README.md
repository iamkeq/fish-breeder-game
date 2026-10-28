# Tests

Unit tests for the pure game logic in `scripts/core/`. They use a small
built-in runner (`run_tests.gd`), so there are no add-ons to install.

## Running

From the project folder (where `project.godot` is):

```bash
godot --headless --path . -s res://tests/run_tests.gd
```

Only run files whose name contains some text:

```bash
godot --headless --path . -s res://tests/run_tests.gd -- --filter=genetics
```

`godot` is the Godot 4.7 console executable. On this machine:
`G:/2026 Downloads/GODOT/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe`

If you add a new `class_name` script and the tests can't find it, run
`godot --headless --path . --import` once (or open the project in the editor).

## Writing tests

- Put files in `tests/unit/` named `test_*.gd`, starting with
  `extends "res://tests/test_case.gd"`.
- Every method named `test_*` runs on a fresh instance. `before_each()` runs first if present.
- Assertions: `assert_eq`, `assert_ne`, `assert_true`, `assert_false`,
  `assert_between`, `assert_almost`, `assert_has`.
- A test that makes no assertions counts as a failure. This catches tests that
  stopped early because of a script error.
- Use `tests/fixtures.gd` for small hand-made data and seeded RNGs, so tests
  don't break when the real balance numbers in `data/` change.
