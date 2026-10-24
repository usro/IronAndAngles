# Iron & Angles: Architecture

Godot 4.7, GDScript, 2D, GL Compatibility renderer. Design source: `game_design_document.md` (GDD).

## Layers

| Layer | Where | Rule |
|---|---|---|
| **Model** (data, rules) | `scripts/data/`, plus pure logic in each system folder | No nodes, no autoloads. Unit-testable. |
| **Services** (autoloads) | `scripts/core/` | Own the live game state and cross-cutting concerns. |
| **Views / controllers** | `scenes/`, and scene scripts in each system folder | Show state, forward input. Never write another system's data directly. |
| **Glue** | `EventBus` signals | Systems emit facts ("shot_fired"), never commands. |

### Autoloads (load order matters)

1. `EventBus`: all cross-system signals. **Add signals freely; never rename or remove one** without updating every listener.
2. `DataRegistry`: loads every `.tres` under `res://data/<kind>/` at startup. Look up by id: `DataRegistry.get_weapon(&"trebuchet")`. Dropping a new file in the folder registers it.
3. `GameState`: current `PlayerState`, campaign seed and RNG, `current_contract` / `current_plot` (set by the auction), `last_battle_result` (set by the battle).
4. `SaveSystem`: JSON saves in `user://saves/slot_N.json`. Never `.tres`, because a resource file can carry script code.
5. `SceneRouter`: the only thing that changes the top-level scene. `SceneRouter.goto(SceneRouter.Screen.BATTLE)`.

### Scene flow

```
MAIN_MENU -> REGION_MAP (auction, shop, tech tree) -> BATTLE -> RESULTS -> REGION_MAP
```

The contracts between screens:
- **Region map → Battle:** set `GameState.current_contract` and `GameState.current_plot`, then `goto(BATTLE)`.
- **Battle → Results:** fill a `BattleResult`, emit `EventBus.battle_ended(result)`, call `GameState.apply_battle_result(result)`, then `goto(RESULTS)`.
- **Shell costs** are charged when each shell is fired (`player.charge()`), so funds can go negative mid-battle. The payout is added in `apply_battle_result`.

All four screens are currently **placeholders** built with `PlaceholderUI`. Each owning session replaces its own screen but keeps the contract above.

## Conventions

- **Units:** simulation is in **meters, seconds, kilograms**. Convert for rendering with `GameConstants.meters_to_pixels()` (8 px = 1 m).
- **Axes:** Godot convention, **+y is down**, so gravity is a positive y. Elevation angles are in degrees above the horizontal, measured toward the target.
- **Determinism:** ballistics steps at a fixed `GameConstants.PHYSICS_STEP` (1/120 s), independent of frame rate. All randomness (spread, bounce, gusts, AI) uses a seeded `RandomNumberGenerator` derived from `GameState.rng`, never global `randf()`. The same seed and inputs must give the same shot.
- **Money** is an `int`. All changes go through `PlayerState.spend / earn / charge` so `money_changed` always fires.
- **Ids** are `StringName` (`&"stone_ball"`), unique per kind, and equal to the file name.
- **Content** lives in `.tres` files under `data/`. Code never hardcodes stats.
- Naming: `snake_case.gd` files, `class_name PascalCase` for reusable classes, `_private` members.

## Folder ownership (sub-sessions)

Each session owns its folders. Shared files (`scripts/core/`, `scripts/data/`, `project.godot`) may only receive **additive** changes (a new field, a new signal), and those changes are listed in the session's final report.

| Session | Owns |
|---|---|
| 0 Foundation | `scripts/core/`, `scripts/data/`, `tests/run_tests.gd`, `tests/test_case.gd` |
| 1 Ballistics | `scripts/ballistics/`, `tests/ballistics/` |
| 2 Terrain | `scripts/terrain/`, `tests/terrain/` |
| 3 Economy & auction | `scripts/economy/`, `scenes/strategy/`, `tests/economy/` |
| 4 Tech tree & content | `scripts/progression/`, `data/**` (all `.tres` content), `tests/progression/` |
| 5 Battle gameplay | `scripts/battle/`, `scenes/battle/`, input map in `project.godot` |
| 6 AI | `scripts/ai/` |
| 7 UI | `scripts/ui/`, `scenes/ui/`, `scenes/menu/`, `scenes/results/`, themes |
| 8 Audio & effects | `audio/`, `scripts/fx/`, `assets/` effects |

### Interfaces expected from wave 1

These signatures are proposals. The owning session may refine them and documents the final version here.

- **Ballistics** (pure `RefCounted`, no nodes): `Ballistics.simulate(weapon: WeaponData, ammo: AmmoData, elevation_deg: float, charge: float, origin_m: Vector2, facing: int, weather: WeatherState, rng: RandomNumberGenerator, hit_test: Callable) -> Trajectory`, where `Trajectory` holds the sampled points, impact point, time of flight and bounces. `hit_test(from_m, to_m) -> Dictionary` is provided by terrain, so ballistics needs no terrain dependency. It also has a step-wise API, so the battle can animate the shell live.
- **Terrain** (final, see *Terrain* below): `Terrain` node with `build(plot)`, `carve(center_m, radius_m) -> int` (emits `EventBus.terrain_carved` when anything was removed), `is_solid(point_m) -> bool`, `raycast(from_m, to_m) -> {hit, position, normal}` and `surface_height_at(x_m) -> float`. Ballistics' `hit_test` is simply `terrain.raycast`.
- **Economy:** auction logic as pure classes (`Auction`, bid resolution, rival bidding hook for AI), a shop that buys weapons, ammo and repairs through `PlayerState`, and settlement of the result.
- **Progression:** a `TechTree` that answers `can_unlock(id)` and `unlock(id)` (spends money, emits `tech_unlocked`) and lists purchasable weapons and ammo.

## Terrain

Code in `scripts/terrain/`, tests in `tests/terrain/`, manual check in `scenes/battle/terrain_demo.tscn` (click to carve).

| Piece | Role |
|---|---|
| `TerrainMap` (RefCounted, pure) | Solidity bitmap: 0.25 m cells, each `SOLID` (255) or `AIR` (0). Owns `carve`, `is_solid`, `raycast`, `surface_height_at`, layout spots and dirty-chunk tracking. No nodes, so tests and AI can use it headless. |
| `TerrainGenerator` | `generate(plot) -> TerrainMap`. Deterministic from `terrain_profile`, `terrain_seed` (FastNoiseLite + seeded RNG), `height_advantage_m`, `target_distance_m`. |
| `Terrain` (Node2D) | Battle-facing node: `build(plot)` / `set_map(map)`, same queries as the map, `carve` emits the signal. Rebuilds dirty chunks in `_process` (or call `rebuild_dirty()`). Keep it at the origin: children are in pixels. |
| `TerrainChunk` | One 64x64-cell chunk (16 m): an L8 texture drawn with `terrain_blueprint.gdshader`, plus a `StaticBody2D` with a `ConcavePolygonShape2D` from marching squares. |

**Layout** (meters, +y down): battery pad centred at `x = 80` with its ground at `y = -height_advantage_m`; target zone (40 m wide) centred `target_distance_m` to the right with its ground at `y = 0`. Both pads are exactly flat. The battery faces +x. Use `battery_position_m()`, `target_zone_center_m()` and `target_positions_m(count)`; they follow craters. `bounds_m()` gives the grid rectangle.

**Profiles:** FLAT (small noise), HILLS (rolling noise), RIDGE (a crest between battery and targets that forces high arcs), VALLEY (a dip), MOUNTAIN (a tall peak plus rough noise). Noise fades out over 15 m next to each pad.

**Edges:** below the grid's bottom edge is solid bedrock (the bottom 2 m are never carved, and a ray off the map's side still lands on that plane), everything else outside the grid is air. Ballistics should still cap flight time for shells that leave sideways and climb.

**Raycast:** grid DDA from `from_m` to `to_m`; `position` is where the ray enters the first solid cell (accurate to one cell, 0.25 m), `normal` is the solidity gradient over a 1 m disc, so it follows the visible slope and points toward air. A ray starting inside ground hits at its start.

**Why a bitmap, not polygon clipping:** `Geometry2D.clip_polygons` was the alternative. A bitmap was chosen because
- cost per crater is fixed (only cells in the circle change), while clipped polygons gain vertices with every crater and every query slows down with them;
- buried shells make caves; `clip_polygons` returns holes, which `Polygon2D` and collision polygons can't take directly, while a bitmap handles caves and overhangs with no special case;
- `is_solid` is one array read and `raycast` a cell walk, both exact on integer cells, so results are deterministic and don't drift with floating-point clipping;
- chunks make redraw and collision rebuilds local: one crater touches 1 to 4 chunks.

The cost is a 0.25 m staircase on edges, hidden by linear filtering plus the 0.5 contour in the shader. Measured on an M1 Pro (debug build, headless): 200 carves ~8 ms, rebuilding all touched chunks once afterwards ~25-60 ms, carve plus rebuild after every impact ~1.4 ms each, a 1000-ray burst ~50-160 ms.

**Not done yet:** loose debris islands stay floating (no collapse), and craters are not saved; if a mid-battle save is needed, store the `(center, radius)` list and replay it, since carving is deterministic.

## Running

```bash
GODOT=/Users/rizamukti/Downloads/Godot.app/Contents/MacOS/Godot
$GODOT --path .                                          # play
$GODOT --headless --path . -s res://tests/run_tests.gd   # all tests
$GODOT --headless --path . -s res://tests/run_tests.gd -- ballistics   # filter by path
```

Tests: put `test_*.gd` files under `tests/<area>/`, extending `TestCase`. Every `test_*` method runs, and autoloads are available.

## Design decisions (defaults chosen; change here if the design changes)

| Question | Decision |
|---|---|
| Turn-based or real-time? | **Real-time with reload timers.** This fits Tier 3 reload management, Tier 4 cooldowns and counter-battery pressure. |
| How you win a battle | Destroy all `target_count` targets. You lose if every battery weapon reaches 0 health, or the `time_limit` expires (when set). |
| Payout | Fixed payout on victory, nothing on defeat. Shells are paid when fired either way. |
| Campaign | A run of contracts that unlocks later eras through the tech tree. No fixed ending yet. |
| Rivals | About 3 AI commanders. They compete **only in the auction**. The enemy firing back in battle is the contract's defender. |
| Counter-battery | Every shot raises `reveal_level` (0..1), and misses raise it more. Enemy accuracy scales with reveal level and contract difficulty. |
| Bounce | **Seeded randomness**: learnable but not fixed (`AmmoData.bounce_randomness_deg`). |
| Physics backend | **GDScript**, not Go. C# or a GDExtension only if profiling shows a need. |
