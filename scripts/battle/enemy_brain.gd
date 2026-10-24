class_name EnemyBrain
extends RefCounted
## Decides the contract defender's counter-battery fire. The battle owns the enemy gun (weapon,
## ammo, position, reload timing) and asks the brain where to aim each time the gun is loaded.
##
## The AI session replaces the default (SimpleEnemyBrain) by subclassing this and setting
## `BattleSim.brain_factory = func() -> EnemyBrain: return MyBrain.new()` before the battle
## scene loads, or by assigning `sim.enemy_brain` directly.


## What the defender knows when the gun is loaded.
class Situation:
	extends RefCounted
	var weapon: WeaponData
	var ammo: AmmoData
	## Where the enemy shell leaves the barrel, meters.
	var origin_m: Vector2
	## Ground points of the player's weapons that still work.
	var battery_positions_m: Array[Vector2] = []
	## 0..1, see BattleSim.reveal_level.
	var reveal_level: float = 0.0
	## ContractData.difficulty, 1..5.
	var difficulty: int = 1
	var weather: WeatherState
	## Seconds since the battle started.
	var time_s: float = 0.0
	## Where the enemy's previous shell came down (Vector2.INF if none yet).
	var last_impact_m: Vector2 = Vector2.INF


## Return {} to hold fire this time, or {"elevation_deg": float, "charge": float} with an optional
## "facing" (+1/-1, default toward the battery). rng is the brain's own seeded generator.
func plan_shot(_situation: Situation, _rng: RandomNumberGenerator) -> Dictionary:
	return {}
