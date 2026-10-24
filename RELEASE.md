# Releasing Iron & Angles

## Build (once export templates are installed)

Godot needs its export templates for 4.7.2 (Editor → Manage Export Templates → Download, or the
`Godot_v4.7.2-stable_export_templates.tpz` file from the official Godot releases).

```bash
GODOT=/Users/rizamukti/Downloads/Godot.app/Contents/MacOS/Godot
mkdir -p build/macos build/windows build/linux
$GODOT --headless --path . --export-release "macOS" "build/macos/Iron and Angles.zip"
$GODOT --headless --path . --export-release "Windows Desktop" build/windows/IronAndAngles.exe
$GODOT --headless --path . --export-release "Linux" build/linux/IronAndAngles.x86_64
```

Presets live in `export_presets.cfg`: the in-game guide (`HOW_TO_PLAY.md`) is included, while tests,
screenshots and the audio generator scripts are left out. Version: `application/config/version` in
`project.godot` (shown on the main menu and written into saves).

## Before each release

- [ ] All tests pass: `$GODOT --headless --path . -s res://tests/run_tests.gd`
- [ ] Bump `application/config/version` and the preset versions in `export_presets.cfg`
- [ ] Play one battle per era from a fresh campaign in an exported build (not the editor)
- [ ] Check the How to Play guide opens in the exported build
- [ ] The debug menu (F1) must NOT open in a release export (it frees itself outside debug builds)

## Still to do (needs accounts or decisions)

- [ ] Private GitHub backup of this repo
- [ ] Playtests with 3–5 new players
- [ ] Store choice (itch.io / Steam), page text, capsule art, trailer or GIFs (`screenshots/` has stills)
- [ ] macOS signing + notarization (Apple Developer account) and optional Windows code signing.
      The macOS preset currently signs ad-hoc (`codesign/codesign=3`); set the bundle identifier
      (`com.ironandangles.game` is a placeholder) to your own.
- [ ] Check the name "Iron & Angles" isn't taken
- [ ] Pricing / demo (the Medieval era makes a natural demo)
