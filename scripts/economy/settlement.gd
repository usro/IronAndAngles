class_name Settlement
extends RefCounted
## Money flow of one contract, and the profit report for the results screen.
##
## Decision: the auction price is paid UP FRONT, the moment the auction resolves
## (PlayerState.spend inside Auction.resolve). The payout is NOT reduced by it; it is still
## added in full by GameState.apply_battle_result on victory. Consequences:
## - You can't bid more than you have (no debt from bidding), the same rule rivals follow.
## - Losing the battle still costs the price: the bid is a real risk.
## Net profit of a contract = payout - auction price - shells fired (- repairs for damage taken).


class Report:
	var contract_id: StringName
	var victory: bool
	var payout: int
	var auction_price: int
	var ammo_spent: int
	## Cost to repair the damage taken in this battle at each weapon's repair_cost_per_hp.
	var repair_cost: int

	func net_profit() -> int:
		return payout - auction_price - ammo_spent

	func net_after_repairs() -> int:
		return net_profit() - repair_cost

	## Net profit as a share of the payout (0.25 = kept a quarter). 0 when there was no payout.
	func margin() -> float:
		return 0.0 if payout <= 0 else float(net_profit()) / payout

	func summary_lines() -> PackedStringArray:
		var lines := PackedStringArray()
		lines.append("Payout: %d" % payout)
		lines.append("Auction price: -%d" % auction_price)
		lines.append("Shells fired: -%d" % ammo_spent)
		lines.append("Net profit: %d (%s)" % [net_profit(),
			"%d%% margin" % roundi(margin() * 100.0) if payout > 0 else "no payout"])
		if repair_cost > 0:
			lines.append("Repairs needed: -%d  ->  %d after repairs" % [repair_cost, net_after_repairs()])
		return lines


## `weapons` is a weapon id -> WeaponData lookup (DataRegistry.weapons).
static func report(result: BattleResult, auction_price: int, weapons: Dictionary) -> Report:
	var r := Report.new()
	r.contract_id = result.contract_id
	r.victory = result.victory
	r.payout = result.payout_earned
	r.auction_price = auction_price
	r.ammo_spent = result.ammo_spent
	for weapon_id in result.damage_taken:
		var weapon: WeaponData = weapons.get(weapon_id)
		if weapon:
			r.repair_cost += ceili(result.damage_taken[weapon_id]) * weapon.repair_cost_per_hp
	return r
