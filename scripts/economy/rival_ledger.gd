class_name RivalLedger
extends RefCounted
## Rival commanders' funds across the campaign. Rivals never go into debt.
## Persisted through to_dict() in GameState.economy_state["rival_money"].

## Rivals fight their won contracts off-screen. Chance of success at difficulty 1, minus
## the penalty for each difficulty step above 1.
const BASE_SUCCESS_CHANCE := 0.9
const SUCCESS_PENALTY_PER_DIFFICULTY := 0.1
## Share of the payout a rival spends on shells, rolled per contract.
const SHELL_COST_SHARE_MIN := 0.15
const SHELL_COST_SHARE_MAX := 0.35

var _money: Dictionary = {}  # StringName -> int


## `saved` is a previous to_dict(); rivals missing from it start with RivalData.starting_money.
func _init(rivals: Array = [], saved: Dictionary = {}) -> void:
	for r: RivalData in rivals:
		_money[r.id] = int(saved.get(String(r.id), r.starting_money))


func has_rival(rival_id: StringName) -> bool:
	return _money.has(rival_id)


func money(rival_id: StringName) -> int:
	return _money.get(rival_id, 0)


func can_afford(rival_id: StringName, amount: int) -> bool:
	return has_rival(rival_id) and amount >= 0 and amount <= money(rival_id)


## Returns false (and changes nothing) if the rival can't afford it.
func spend(rival_id: StringName, amount: int) -> bool:
	if not can_afford(rival_id, amount):
		return false
	_money[rival_id] -= amount
	return true


func earn(rival_id: StringName, amount: int) -> void:
	if has_rival(rival_id) and amount > 0:
		_money[rival_id] += amount


## Simulates a rival fighting a contract it won (the price was already paid). Returns the net
## change in its funds: payout minus shells on success, shells only on failure (capped at funds).
func settle_contract(rival_id: StringName, contract: ContractData, rng: RandomNumberGenerator) -> int:
	var chance := BASE_SUCCESS_CHANCE - SUCCESS_PENALTY_PER_DIFFICULTY * (contract.difficulty - 1)
	var success := rng.randf() < chance
	var shells := int(contract.payout * rng.randf_range(SHELL_COST_SHARE_MIN, SHELL_COST_SHARE_MAX))
	if success:
		earn(rival_id, contract.payout - shells)
		return contract.payout - shells
	shells = mini(shells, money(rival_id))
	spend(rival_id, shells)
	return -shells


func to_dict() -> Dictionary:
	var out := {}
	for id in _money:
		out[String(id)] = _money[id]
	return out
