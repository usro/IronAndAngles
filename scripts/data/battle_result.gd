class_name BattleResult
extends RefCounted
## Outcome of one battle, produced by the battle scene and consumed by economy and results UI.

var contract_id: StringName
var plot_id: StringName
var victory: bool = false
var shells_fired: int = 0
var shells_hit: int = 0
var targets_destroyed: int = 0
var ammo_spent: int = 0        ## Money spent on shells and energy.
var payout_earned: int = 0     ## 0 on defeat. Includes counter_battery_bonus.
## The player destroyed the enemy gun; on victory the client adds counter_battery_bonus.
var enemy_gun_destroyed: bool = false
var counter_battery_bonus: int = 0
## weapon id -> health lost during the battle.
var damage_taken: Dictionary = {}
var duration_s: float = 0.0
## Ammo usage by id -> count, for the results breakdown.
var ammo_used: Dictionary = {}


func net_profit() -> int:
	return payout_earned - ammo_spent


func accuracy() -> float:
	return 0.0 if shells_fired == 0 else float(shells_hit) / shells_fired
