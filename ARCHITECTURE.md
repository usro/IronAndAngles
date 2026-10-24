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

- **Ballistics** (final, `scripts/ballistics/`, pure `RefCounted`, no nodes):
  - `Ballistics.simulate(weapon, ammo, elevation_deg, charge, origin_m, facing, weather, rng, hit_test) -> Trajectory` runs a whole shot (fragments included). `Ballistics.simulate_shot(params: ShotParams, hit_test)` is the same with the optional settings below.
  - `ShotParams.create(weapon, ammo, elevation_deg, charge, origin_m, facing, weather, rng)`, then optionally: `guidance_target_m` (laser designation for `guided` ammo; `Vector2.INF` = none), `world_bounds_m` (left/right/bottom edges end the flight; empty = unbounded), `reference_y_m` (y where `weather.air_density` applies, defaults to `origin_m.y`; density falls off above it with an 8.5 km scale height), `max_time`.
  - **Live shots:** `var flight := Ballistics.launch(params, hit_test)`, then every frame `for ev in flight.advance(delta): ...`, draw at `flight.get_render_position()` (interpolated between fixed steps), stop when `flight.is_settled()`. `advance()` also advances shrapnel fragments (`flight.fragments`). Events are dictionaries with `type` (`&"bounce"`, `&"impact"`, `&"airburst"`, `&"burst"`, `&"out_of_bounds"`, `&"timeout"`), `flight`, `position`, `velocity`, `time`, plus `normal` (bounce, impact) or `fragments: Array[ShellFlight]` (burst). Same seed and inputs → identical result to `simulate()`, whatever the frame deltas.
  - `Trajectory`: `points`/`times` (one per 1/120 s step plus exact contact points), `launch_elevation_deg` (after spread), `launch_velocity_m`, `end_reason` (`IMPACT`, `AIRBURST`, `OUT_OF_BOUNDS`, `TIMEOUT`), `end_point_m`, `end_velocity_m`, `impact_normal`, `time_of_flight`, `bounces` (`{position, normal, time, velocity_in, velocity_out}`), `fragments: Array[Trajectory]`, helpers `has_impact()`, `impact_point_m()`, `apex_m()`, `position_at(t)`.
  - **hit_test contract:** `hit_test(from_m, to_m) -> Dictionary` returns `{}` for no hit, or `{"position": Vector2, "normal": Vector2}` for the first solid point on the segment (same keys as Godot's `intersect_ray`; `normal` defaults to up). Called once per step. `Ballistics.flat_ground(y)` and `Ballistics.no_ground()` exist for tests and previews.
  - **Model:** RK4 at `PHYSICS_STEP` in 64-bit floats. Gravity from `weather.gravity`; quadratic drag `0.5·ρ·Cd·A·|v−wind|²` (wind = (`wind_speed` + seeded gust) × `wind_sensitivity`, so `wind_sensitivity = 0` is railgun-style zero drift); spread is a bounded triangular draw within ±`spread_deg` added to the clamped elevation; rockets push `thrust_n` along their heading for `burn_time`; guided ammo turns its velocity toward the target at up to `guidance_turn_rate_deg`/s after `guidance_arm_time`; bounces keep `bounce_restitution` of the normal speed (tangential 0.7..1 with restitution) and deflect by a seeded ±`bounce_randomness_deg`, up to `max_bounces`; shrapnel bursts `fragment_count` fragments at `fuse_time` (airburst) or on impact. RNG draw order: spread, gusts, then each bounce/burst as it happens.
  - `Ballistics.predict(params, hit_test)` is the nominal shot (no randomness, does not touch the rng) for aim previews. `AimSolver.solve(weapon, ammo, origin_m, target_m, weather, AimSolver.Arc.LOW|HIGH) -> {ok, elevation_deg, charge, facing, predicted_m, miss_m}` finds a nominal hit (terrain ignored); `AimSolver.solve_charge(..., elevation_deg)` fixes the elevation.
  - Not modelled yet: the `ORBITAL` launcher type (a strike from above is battle/AI logic, not a ballistic arc).
- **Terrain:** a node that builds the ground from a `PlotData`, with `carve(center_m: Vector2, radius_m: float)` (emits `EventBus.terrain_carved`), `is_solid(point_m) -> bool`, `raycast(from_m, to_m) -> Dictionary` and `surface_height_at(x_m) -> float`.
- **Economy:** auction logic as pure classes (`Auction`, bid resolution, rival bidding hook for AI), a shop that buys weapons, ammo and repairs through `PlayerState`, and settlement of the result.
- **Progression:** a `TechTree` that answers `can_unlock(id)` and `unlock(id)` (spends money, emits `tech_unlocked`) and lists purchasable weapons and ammo.

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
