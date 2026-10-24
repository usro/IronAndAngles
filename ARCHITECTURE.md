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

Every screen uses the blueprint look described in *UI* below. Each owning session keeps the contract above when it changes its screen.

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
| 5 Battle gameplay | `scripts/battle/`, `scenes/battle/`, `tests/battle/`, input map in `project.godot` |
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
  - **Loadout** (`scripts/economy/loadout.gd`): `PlayerState.loadout` lists the deployed guns (empty = automatic: newest era, then priciest). `Loadout.slots(era)` = 2 / 3 / 3 / 4; only guns with health > 0 deploy; `Loadout.deployed()` is what `BattleSim` places on the pad. `Shop.buy_weapon` calls `Loadout.on_bought` (joins a free slot). `Shop.sell_weapon` pays `RESALE_RATE` (50%) of the price minus the full repair cost, refuses the last gun, and removes it from the loadout.
  - **Weekly offers are procedural** (see `data/BALANCE.md`, *Procedural offers*): `StrategyController.start_round()` bumps `economy_state["week"]`, picks clients with `ContractOffers`, and turns them into that week's contracts with `ProceduralContracts.for_week` / `PlotGenerator` (fresh plot, terrain seed, profile, distance, height, altitude, weather and name, bounded by the era's handcrafted content and checked for reach). Generated contracts carry `template_id` and are registered with `DataRegistry.register_generated()`, so `get_contract` / `get_plot` find them; `DataRegistry.contracts` / `plots` stay the on-disk content only.
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


## Battle

Code in `scripts/battle/`, tests in `tests/battle/`. Manual end-to-end run (windowed, presses the real buttons and input actions, aims with AimSolver): `$GODOT --path . -s res://tests/battle/play_through.gd -- <screenshot dir>`.

| Piece | Role |
|---|---|
| `BattleSim` (RefCounted) | The battle model. `BattleSim.new(contract, plot, player, field, seed)` where field is a built `Terrain` (scene) or a `TerrainMap` (tests). `tick(delta)`, `pull_trigger()`, `select_next_weapon()`, `cycle_ammo()`, `adjust_designator(mount, dx)`, `retreat()`, `commit()` (emits `battle_ended` + `GameState.apply_battle_result`). Local signals `shell_launched`, `blast`, `ended` for the view. |
| `WeaponMount` | One owned weapon on the pad: dials (`elevation_deg`, `charge`, `designated_x_m` for orbital), `health`, fire control (`pull_trigger`, `tick` → shells due, `abort_salvo`). |
| `BattleTarget` | A contract target: a 4×3 m box on the ground with health. Drops into craters dug under it. |
| `BattleRules` | Pure rules: `blast_damage` (full within 0.5 m of a box, linear to 0 over `explosion_radius_m`; incendiary × `1 − rain_penalty·rain`), reveal steps, `battle_weather` (contract weather as sea level, density × e^(−altitude/8.5 km)), segment-vs-box. |
| `EnemyBrain` / `SimpleEnemyBrain` | Counter-battery aiming hook (see below). |
| `battle.gd` + `BattleHud` | Scene: builds `Terrain`, runs the sim, input, camera, plain drawing, HUD. |

**Flow:** each mount starts loaded. A trigger pull fires `salvo_size` shells `salvo_interval` apart, then locks the weapon for `reload_time + cooldown`. Every shell consumes one ammo and `player.charge(cost_per_shell + energy_cost_per_shot)`, emits `shot_fired`, and is a live `ShellFlight` (hit test = terrain raycast plus the live target boxes; weather density referenced to y = 0). Impacts carve `crater_radius_m` and deal blast damage (`projectile_impacted`, `target_hit`, `target_destroyed`); bounces deal 50 % damage and dig 40 % of the crater (`projectile_bounced`); airbursts deal blast damage without a crater; fragments only damage what they touch. Guided ammo homes on the live target nearest its unguided landing point. **Orbital** weapons designate an x (the charge/elevation keys move it); the rod drops 3 s later from 400 m straight down at the charge's velocity, scattered by `spread_deg`. A shell counts as a hit (`shells_hit`) if it or its fragments damaged anything.

**Counter-battery:** every shot raises `reveal_level` by 0.05; a shell that damages nothing adds 0.08 more when it settles (`battery_revealed`). Orbital strikes don't reveal the battery. The defender fields the cheapest non-orbital weapon of the contract's era (first allowed ammo), from 12 m right of the target zone, once per `reload_time + cooldown`. It hits the battery for 50 % of its ammo's blast damage (`battery_damaged`, `BattleResult.damage_taken`). The first enemy shot comes after one reload. Each time the gun is loaded the sim asks `EnemyBrain.plan_shot(situation, rng) -> {elevation_deg, charge[, facing]}` or `{}` to hold. `SimpleEnemyBrain` holds below reveal 0.1, then picks a working weapon and aims at it with `AimSolver` (high arc) plus a seeded error of ±`lerp(60, 2, reveal) / (1 + 0.35·(difficulty − 1))` m. **AI hook:** set `BattleSim.brain_factory = func() -> EnemyBrain: return MyBrain.new()` before the battle scene loads.

**End:** victory when every target is destroyed. Defeat when every battery weapon is at 0 hp, `time_limit` runs out, the player retreats (Esc), or no working weapon has ammo left and no shell of ours is in the air. The banner shows for 2.5 s, then `commit()` and `goto(RESULTS)`.

**Randomness:** one RNG seeded from `GameState.rng.randi()` at battle start; every shell gets its own child RNG at launch, and the enemy brain has its own, so frame timing never changes a result.

**Controls** (input map): `aim_up/aim_down` W/S ↑/↓ (elevation), `charge_up/charge_down` D/A →/← (charge; orbital: target x), `fine_adjust` Shift (÷10), mouse wheel elevation (Shift+wheel charge), `fire` Space, `next_weapon` Tab/E, `next_ammo` R, `toggle_overview` V, `retreat` Esc.

## UI

Code in `scripts/ui/`, theme and fonts in `themes/`. Every screen draws with the same parts:

| Piece | Role |
|---|---|
| `themes/blueprint_theme.tres` | The project's default theme (`gui/theme/custom`). Generated by `BlueprintThemeBuilder`; after editing the builder run `$GODOT --headless --path . -s res://scripts/ui/theme/build_theme.gd`. |
| `Blueprint` | Palette (paper blue, white/cyan ink, amber for money and selection, red pencil for the enemy), fonts, drafting helpers (grid, corner ticks, dimension lines, hatching) and `money()` formatting. |
| Theme variations | Labels: `TitleLabel`, `HeaderLabel`, `SectionLabel`, `CaptionLabel`, `MonoLabel`, `ValueLabel`, `MoneyLabel`, `StatusLabel`, `BodyLabel`. Buttons: `PrimaryButton`, `MenuButtonLarge`, `ChipButton`, `ParcelButton`, `Tech*`. Panels: `SheetPanel` (gridded sheet), `CardPanel`, `SelectedCardPanel`, `HudPanel`, `BarPanel`. Set `theme_type_variation` instead of overriding colours. |
| `BlueprintBackdrop` | Full-screen sheet (paper, grid, frame, title block) behind a management screen. |
| `LauncherArt`, `BattleArt` | Procedural line art: one silhouette per launcher type (with variants by weapon id), target towers, shells, blasts, crosshairs. Used by the battlefield, the shop and the menu. |
| `DraftedMap`, `TechTreePanel`, `ProfitWaterfall`, `ArcGauge`, `Stamp`, `WeaponIcon`, `scripts/ui/hud/*` | Screen widgets. They only draw what they are given. |
| `blueprint_sky.gdshader` | Battle sky with a world-aligned grid (fed the camera each frame by `battle.gd`); the terrain keeps `terrain_blueprint.gdshader` (section hatching). |

Fonts are Inter and JetBrains Mono, bundled under the SIL OFL (`themes/fonts/`).

## Audio

Code in `scripts/fx/`, sounds in `audio/`, tests in `tests/fx/`. The `AudioDirector` autoload (registered last) only listens: it turns EventBus facts into sound and never changes game state.

| Piece | Role |
|---|---|
| `audio/tools/generate_sounds.py` | Synthesizes every `.wav` (44.1 kHz mono, standard-library Python, fixed seeds). Regenerate with `python3 audio/tools/generate_sounds.py`, then `$GODOT --headless --path . --import`. No downloaded samples. The three loops (`menu_theme`, `wind`, `rain`) have `edit/loop_mode=2` in their `.import`. |
| `default_bus_layout.tres` | `Master` (compressor + hard limiter) ← `SFX` ← `UI`, `Ambience`; `Master` ← `Music`. The director adds 16 `SFX Voice N` buses at runtime (low-pass + panner each) for placed sounds. |
| `AudioMath` | Pure propagation math: delay = distance / 343 m/s, gain −10·log10(1 + d/60 m), air low-pass 18 kHz·e^(−d/900 m), pan by screen x. |
| `SoundBank` | Sound id → file, bus, level and pitch variation; launch/reload sound per `LauncherType`, impact per `DamageType` (crater ≥ 8 m = massive), size from `explosion_radius_m`. |
| `AudioDirector` | Schedules placed sounds by distance from the listener (the battery, `BattleSim.battery_position_m()` + 2 m), on the wall clock. Reads the battle scene's `sim` and `camera` (never writes): reload sounds when a mount becomes ready, a click on weapon/ammo change, the enemy gun's far boom and an incoming whistle timed to land with the shell (`sim.shell_launched`), victory/defeat stings (`sim.ended`). UI clicks/hovers attach to every `BaseButton` via `SceneTree.node_added`. On the dummy driver (headless) it schedules and logs to `played` but plays nothing. |
| `AudioSettings`, `AudioSettingsPanel` | Master / effects / music sliders (0..1) saved in `user://audio_settings.cfg`; panel opened from the main menu. |

## Debug menu

`DebugMenu` autoload (`scripts/debug/debug_menu.gd`), **F1** or **`** to toggle, debug builds only (it frees itself in release exports). Campaign cheats everywhere (funds, refill ammo, repair, advance era / unlock all tech, give weapons, quick battle on a generated contract of the current era), region-map actions (reroll the week, win the selected lot and deploy), battle actions (auto-aim, kill one / all targets, lose, heal; god mode, instant reload and enemy-holds-fire toggles that persist across battles) and time scale. Cheats go through the normal models, so autosave records them; buttons take no keyboard focus so Space still fires.

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
| How you win a battle | Destroy all `target_count` targets. You lose if every battery weapon reaches 0 health, or the `time_limit` expires (when set). Also lost: retreating, or running out of usable ammo. |
| Payout | Fixed payout on victory, nothing on defeat. Shells are paid when fired either way. |
| Campaign | A run of contracts that unlocks later eras through the tech tree. No fixed ending yet. |
| Rivals | About 3 AI commanders. They compete **only in the auction**. The enemy firing back in battle is the contract's defender. |
| Counter-battery | Every shot raises `reveal_level` (0..1), and misses raise it more. Enemy accuracy scales with reveal level and contract difficulty. |
| Bounce | **Seeded randomness**: learnable but not fixed (`AmmoData.bounce_randomness_deg`). |
| Physics backend | **GDScript**, not Go. C# or a GDExtension only if profiling shows a need. |
