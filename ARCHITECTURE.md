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

- **Ballistics** (pure `RefCounted`, no nodes): `Ballistics.simulate(weapon: WeaponData, ammo: AmmoData, elevation_deg: float, charge: float, origin_m: Vector2, facing: int, weather: WeatherState, rng: RandomNumberGenerator, hit_test: Callable) -> Trajectory`, where `Trajectory` holds the sampled points, impact point, time of flight and bounces. `hit_test(from_m, to_m) -> Dictionary` is provided by terrain, so ballistics needs no terrain dependency. It also has a step-wise API, so the battle can animate the shell live.
- **Terrain:** a node that builds the ground from a `PlotData`, with `carve(center_m: Vector2, radius_m: float)` (emits `EventBus.terrain_carved`), `is_solid(point_m) -> bool`, `raycast(from_m, to_m) -> Dictionary` and `surface_height_at(x_m) -> float`.
- **Economy** (final, `scripts/economy/`):
  - `ContractOffers.generate(contracts, era, completed, rng, count) -> Array[ContractData]`: era-eligible contracts with plots, shuffled by a seeded RNG, uncompleted first.
  - `Auction` (pure): sealed-bid, first-price. Each (contract, plot) is an `Auction.Lot`; one bid per bidder (rebidding replaces it); bid must be `>= reserve_price` and `<= set_budget()`; highest bid per contract wins and pays its bid; **ties go to the earliest bid**; `resolve(collect_payment)` skips winners who can no longer pay. Emits `started / bid_placed / won`, relayed to `EventBus.auction_started / bid_placed / auction_won`. The player's bidder id is `Auction.PLAYER_ID` (`&"player"`).
  - `RivalBidder` (hook): override `choose_bid(rival, budget, lots, rng) -> {"lot", "amount"}` or `{}`. Default `RuleBasedRivalBidder` (aggression, preferred terrain). AI plugs in via `StrategyController.rival_brains[rival_id]` or `default_brain`.
  - `RivalLedger`: rival funds, never negative; won contracts are fought off-screen by `settle_contract`. Saved in `GameState.economy_state["rival_money"]`.
  - `Shop` (pure): `buy_weapon / buy_ammo / repair` return `Shop.Status`. An item is for sale if its era <= player era and no tech node lists it, or an unlocked tech node does (`unlocks_weapons / unlocks_ammo`). Repairs cost `ceil(hp) * repair_cost_per_hp`. Stocking ammo costs `AMMO_STOCK_FEE_RATE` (25%) of `cost_per_shell`; firing still charges the full `cost_per_shell`.
  - `Settlement`: the **auction price is paid up front** when the auction resolves (`PlayerState.spend`; you can't bid more than you have, and a lost battle still costs the price). The payout is not reduced. `Settlement.report(result, price, weapons)` gives payout, price, shells, repair cost, `net_profit()` and `margin()` for the results screen; `StrategyController.last_settlement()` builds it for the last battle.
  - `StrategyController`: glue used by the region map (offers, auction round, payments, `deploy()` to battle).
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
