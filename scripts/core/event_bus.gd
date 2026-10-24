extends Node
## Autoload "EventBus": game-wide signals between systems that don't know about each other.
## Rule: systems emit facts ("this happened"), never commands. Add signals; don't rename them.

# --- Economy ---
signal money_changed(balance: int, delta: int, reason: String)
signal inventory_changed

# --- Strategy / auction ---
signal auction_started(contracts: Array[ContractData])
signal bid_placed(bidder_id: StringName, contract_id: StringName, plot_id: StringName, amount: int)
signal auction_won(winner_id: StringName, contract: ContractData, plot: PlotData, price: int)

# --- Progression ---
signal tech_unlocked(tech_id: StringName)
signal era_changed(era: GameConstants.Era)

# --- Battle ---
signal battle_started(contract: ContractData, plot: PlotData)
signal weather_changed(weather: WeatherState)
signal shot_fired(weapon_id: StringName, ammo_id: StringName, cost: int)
## position is in world meters.
signal projectile_impacted(position: Vector2, ammo_id: StringName)
## A shell bounced off the ground (position in world meters). It keeps flying.
signal projectile_bounced(position: Vector2, ammo_id: StringName)
signal terrain_carved(position: Vector2, radius_m: float)
signal target_hit(target_id: StringName, damage: float)
signal target_destroyed(target_id: StringName)
## 0..1: how precisely enemy counter-battery knows the player's position.
signal battery_revealed(reveal_level: float)
signal battery_damaged(weapon_id: StringName, damage: float)
signal battle_ended(result: BattleResult)

# --- Meta ---
signal game_saved(slot: int)
signal game_loaded(slot: int)
