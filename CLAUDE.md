# CLAUDE.md

This file provides guidance to Claude Code when working with this repository.

## Project

Godot 4.3 game project. GDScript source lives in `src/`, tests in `tests/`.

## Commands

### Lint a GDScript file
```bash
godot --headless --check-only --script <file>
```

### Run all tests
```bash
godot --headless --script tests/run_tests.gd
```

### Import / refresh project cache (run after adding new scenes or resources)
```bash
godot --headless --import
```

## Architecture

- `project.godot` — Godot project configuration
- `src/` — Game scripts; main entry point is `src/main.gd`
- `tests/` — Test suite; `run_tests.gd` discovers and runs all `test_*.gd` files

## Adding Tests

Create a file named `test_<topic>.gd` in `tests/`. It should `extend Object` and contain methods prefixed with `test_`. Use `assert()` for assertions:

```gdscript
extends Object

func test_my_thing() -> void:
    assert(1 + 1 == 2, "math is broken")
```

## Notes

- The `.godot/` directory is generated and git-ignored; run `godot --headless --import` to regenerate it.
- Godot headless is installed automatically by the session-start hook on Claude Code on the web.
