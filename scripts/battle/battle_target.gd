class_name BattleTarget
extends RefCounted
## One contract target: a box standing on the ground with health. Pure model.

var id: StringName
## Ground point under the target (bottom centre), meters. Drops when the ground under it is carved.
var position_m: Vector2
var max_health: float
var health: float


func _init(p_id: StringName, p_position_m: Vector2, p_health: float) -> void:
	id = p_id
	position_m = p_position_m
	max_health = p_health
	health = p_health


func is_destroyed() -> bool:
	return health <= 0.0


func rect_m() -> Rect2:
	return BattleRules.standing_rect(position_m, BattleRules.TARGET_SIZE_M)


## Applies damage and returns how much health was actually lost.
func apply_damage(amount: float) -> float:
	if is_destroyed() or amount <= 0.0:
		return 0.0
	var lost := minf(amount, health)
	health -= lost
	return lost
