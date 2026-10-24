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
3. `GameState`: current `PlayerState`, campaign seed and RNG, `current_contract` / `current_plot` (set by the auction), `last_battle_result` (set by the battle), `economy_state` (JSON-safe dictionary owned by the economy: rival funds, last contract price; saved as-is).
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
  - **hit_test contract:** `hit_test(from_m, to_m) -> Dictionary` returns `{}` (or `{"hit": false, ...}`, as `Terrain.raycast` does) for no hit, or `{"position": Vector2, "normal": Vector2}` for the first solid point on the segment (same keys as Godot's `intersect_ray`; `normal` defaults to up). Called once per step. `Ballistics.flat_ground(y)` and `Ballistics.no_ground()` exist for tests and previews.
  - **Model:** RK4 at `PHYSICS_STEP` in 64-bit floats. Gravity from `weather.gravity`; quadratic drag `0.5·ρ·Cd·A·|v−wind|²` (wind = (`wind_speed` + seeded gust) × `wind_sensitivity`, so `wind_sensitivity = 0` is railgun-style zero drift); spread is a bounded triangular draw within ±`spread_deg` added to the clamped elevation; rockets push `thrust_n` along their heading for `burn_time`; guided ammo turns its velocity toward the target at up to `guidance_turn_rate_deg`/s after `guidance_arm_time`; bounces keep `bounce_restitution` of the normal speed (tangential 0.7..1 with restitution) and deflect by a seeded ±`bounce_randomness_deg`, up to `max_bounces`; shrapnel bursts `fragment_count` fragments at `fuse_time` (airburst) or on impact. RNG draw order: spread, gusts, then each bounce/burst as it happens.
  - `Ballistics.predict(params, hit_test)` is the nominal shot (no randomness, does not touch the rng) for aim previews. `AimSolver.solve(weapon, ammo, origin_m, target_m, weather, AimSolver.Arc.LOW|HIGH) -> {ok, elevation_deg, charge, facing, predicted_m, miss_m}` finds a nominal hit (terrain ignored); `AimSolver.solve_charge(..., elevation_deg)` fixes the elevation.
  - Not modelled yet: the `ORBITAL` launcher type (a strike from above is battle/AI logic, not a ballistic arc).
- **Terrain** (final, see *Terrain* below): `Terrain` node with `build(plot)`, `carve(center_m, radius_m) -> int` (emits `EventBus.terrain_carved` when anything was removed), `is_solid(point_m) -> bool`, `raycast(from_m, to_m) -> {hit, position, normal}` and `surface_height_at(x_m) -> float`. Ballistics' `hit_test` is simply `terrain.raycast`.
- **Economy** (final, `scripts/economy/`):
  - `ContractOffers.generate(contracts, era, completed, rng, count) -> Array[ContractData]`: era-eligible contracts with plots, shuffled by a seeded RNG, uncompleted first.
  - `Auction` (pure): sealed-bid, first-price. Each (contract, plot) is an `Auction.Lot`; one bid per bidder (rebidding replaces it); bid must be `>= reserve_price` and `<= set_budget()`; highest bid per contract wins and pays its bid; **ties go to the earliest bid**; `resolve(collect_payment)` skips winners who can no longer pay. Emits `started / bid_placed / won`, relayed to `EventBus.auction_started / bid_placed / auction_won`. The player's bidder id is `Auction.PLAYER_ID` (`&"player"`).
  - `RivalBidder` (hook): override `choose_bid(rival, budget, lots, rng) -> {"lot", "amount"}` or `{}`. Default `RuleBasedRivalBidder` (aggression, preferred terrain). AI plugs in via `StrategyController.rival_brains[rival_id]` or `default_brain`.
  - `RivalLedger`: rival funds, never negative; won contracts are fought off-screen by `settle_contract`. Saved in `GameState.economy_state["rival_money"]`.
  - `Shop` (pure): `buy_weapon / buy_ammo / repair` return `Shop.Status`. An item is for sale if its era <= player era and no tech node lists it, or an unlocked tech node does (`unlocks_weapons / unlocks_ammo`). Repairs cost `ceil(hp) * repair_cost_per_hp`. Stocking ammo costs `AMMO_STOCK_FEE_RATE` (25%) of `cost_per_shell`; firing still charges the full `cost_per_shell`.
  - `Settlement`: the **auction price is paid up front** when the auction resolves (`PlayerState.spend`; you can't bid more than you have, and a lost battle still costs the price). The payout is not reduced. `Settlement.report(result, price, weapons)` gives payout, price, shells, repair cost, `net_profit()` and `margin()` for the results screen; `StrategyController.last_settlement()` builds it for the last battle.
  - `StrategyController`: glue used by the region map (offers, auction round, payments, `deploy()` to battle).
- **Progression** (final): `TechTree.for_game()` (or `TechTree.new(player, nodes)` in tests) gives `status(id) -> TechTree.Status`, `can_unlock(id)`, `unlock(id) -> bool` (spends via `PlayerState.spend`, appends to `unlocked_tech`, emits `tech_unlocked`; an `era_gate` node also advances `current_era` and emits `era_changed`), `unlockable_ids()`, `visible_ids()`, `purchasable_weapons(DataRegistry.weapons.keys())` / `purchasable_ammo(...)` (base kit, meaning items no node unlocks, plus unlocked items; owned weapons included), `is_weapon_unlocked` / `is_ammo_unlocked`, `unlocked_by(item_id)` and static `find_cycle(nodes)`. Non-gate nodes of a later era stay `ERA_LOCKED` until that era's gate is researched. `ContentValidator.validate(DataRegistry)` cross-checks all content. Balance rules are in `data/BALANCE.md`.

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
