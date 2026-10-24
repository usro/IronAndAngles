# Iron & Angles (Godot 4.7 project)

Read `ARCHITECTURE.md` before changing anything: layers, units (meters, +y down), determinism rules, folder ownership and the screen-to-screen contracts all live there. The game design is in `game_design_document.md`.

- Godot is not on PATH: `/Users/rizamukti/Downloads/Godot.app/Contents/MacOS/Godot`
- Run tests: `<godot> --headless --path . -s res://tests/run_tests.gd` (append `-- <path filter>` to filter). They must pass before you finish.
- After adding a new `class_name` script, run `<godot> --headless --path . --import` once so the class cache knows it.
- Stay inside your session's folders (see ARCHITECTURE.md). Changes to `scripts/core/`, `scripts/data/` or `project.godot` must be additive, and you must mention them in your report.
