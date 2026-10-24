class_name BidAdvisor
extends RefCounted
## Advice for one auction lot: the shell bill to expect with the player's deployed battery, the
## break-even bid, how each rival is likely to bid, and a suggested bid. Pure: pass the data in.
##
## Rival forecasts mirror RuleBasedRivalBidder without its random noise (the ±BID_NOISE spread is
## shown as a range). They forecast the rule the rivals follow; they never read sealed bids.
## If the AI session gives rivals different brains, update _estimate_rival() to match.

## Share of shots assumed to hit when estimating the shell bill (the balance sheet's "typical"
## shooter lands 1 in 3; a careful one, about 1 in 2).
const EXPECTED_HIT_RATE := 0.4
## The suggested bid must leave at least this share of the payout as profit to be "worth it".
const MIN_PROFIT_SHARE := 0.2
## How far above the strongest likely rival's top estimate to bid.
const OUTBID_MARGIN := 50


class RivalEstimate:
	var rival: RivalData
	## Expected bid range on this contract; 0 / 0 if the rival can't meet the reserve.
	var low: int
	var high: int
	## This contract is the rival's best pick this week (it bids on one contract only).
	var likely: bool
	var prefers_terrain: bool
	## Chance the rival sits the whole week out.
	var pass_chance: float

	func can_bid() -> bool:
		return high > 0


class Advice:
	## Expected shell bill (0 if no deployed gun can reach the plot).
	var shell_cost: int
	## Shell bill if every shot hits.
	var par_cost: int
	## "Great Trebuchet · Stone Ball", or "" if nothing can shoot this plot.
	var shooter: String
	var break_even: int
	var suggested: int
	var expected_profit: int
	var worth_it: bool
	var contested: bool
	var rivals: Array[RivalEstimate] = []
	var verdict: String

	func can_shoot() -> bool:
		return not shooter.is_empty()


## `lots`: every lot in this week's auction (rivals compare them all). `rival_funds`: rival id -> money.
static func advise(lot: Auction.Lot, lots: Array[Auction.Lot], player: PlayerState, rivals: Array[RivalData],
		rival_funds: Dictionary, weapons: Dictionary, ammo: Dictionary) -> Advice:
	var a := Advice.new()
	var c := lot.contract
	_estimate_shells(a, lot, player, weapons, ammo)
	a.break_even = c.payout - a.shell_cost

	var top_likely := 0
	for rival in rivals:
		var e := _estimate_rival(rival, int(rival_funds.get(rival.id, 0)), c, lots)
		a.rivals.append(e)
		if e.likely and e.can_bid():
			a.contested = true
			top_likely = maxi(top_likely, e.high)
	a.suggested = maxi(c.reserve_price, top_likely + OUTBID_MARGIN if a.contested else c.reserve_price + OUTBID_MARGIN)
	a.suggested = ceili(a.suggested / 10.0) * 10
	a.expected_profit = c.payout - a.suggested - a.shell_cost
	a.worth_it = a.can_shoot() and a.expected_profit >= c.payout * MIN_PROFIT_SHARE
	a.verdict = _verdict(a, c, player)
	return a


## Cheapest way the deployed battery can level every target on this plot.
static func _estimate_shells(a: Advice, lot: Auction.Lot, player: PlayerState, weapons: Dictionary,
		ammo: Dictionary) -> void:
	var c := lot.contract
	var best := -1
	for w in Loadout.deployed(player, weapons):
		var orbital := w.launcher_type == GameConstants.LauncherType.ORBITAL
		for ammo_id in w.allowed_ammo:
			var shell: AmmoData = ammo.get(ammo_id)
			if shell == null or shell.damage <= 0.0:
				continue
			if not orbital and PlotGenerator.max_range_m(w, shell, lot.plot) < lot.plot.target_distance_m:
				continue
			var hits := c.target_count * ceili(c.target_health / shell.damage)
			var cost := hits * (shell.cost_per_shell + w.energy_cost_per_shot)
			if best < 0 or cost < best:
				best = cost
				a.shooter = "%s · %s" % [w.display_name, shell.display_name]
	a.par_cost = maxi(best, 0)
	a.shell_cost = ceili(a.par_cost / EXPECTED_HIT_RATE)


static func _estimate_rival(rival: RivalData, funds: int, contract: ContractData, lots: Array[Auction.Lot]) -> RivalEstimate:
	var e := RivalEstimate.new()
	e.rival = rival
	e.pass_chance = (1.0 - rival.aggression) * RuleBasedRivalBidder.PASS_CHANCE
	var cap := int(funds * lerpf(RuleBasedRivalBidder.BUDGET_SHARE_CAUTIOUS, RuleBasedRivalBidder.BUDGET_SHARE_AGGRESSIVE, rival.aggression))
	var share := lerpf(RuleBasedRivalBidder.PAYOUT_SHARE_CAUTIOUS, RuleBasedRivalBidder.PAYOUT_SHARE_AGGRESSIVE, rival.aggression)
	# Score every lot the way the bidder does, at the middle of its noise band.
	var best_score := -INF
	var best_contract: ContractData
	for l in lots:
		var prefers := rival.preferred_terrain.has(l.plot.terrain_profile)
		var amount := mini(int(l.contract.payout * share * (RuleBasedRivalBidder.PREFERRED_TERRAIN_BONUS if prefers else 1.0)), cap)
		if amount < l.contract.reserve_price:
			continue
		var score := l.contract.payout * (RuleBasedRivalBidder.PREFERRED_TERRAIN_BONUS if prefers else 1.0) - amount
		if score > best_score:
			best_score = score
			best_contract = l.contract
		if l.contract == contract and amount * (1.0 + RuleBasedRivalBidder.BID_NOISE) > e.high:
			e.prefers_terrain = prefers
			e.low = maxi(contract.reserve_price, mini(int(amount * (1.0 - RuleBasedRivalBidder.BID_NOISE)), cap))
			e.high = mini(int(amount * (1.0 + RuleBasedRivalBidder.BID_NOISE)), cap)
	e.likely = best_contract == contract
	return e


static func _verdict(a: Advice, c: ContractData, player: PlayerState) -> String:
	if not a.can_shoot():
		return "None of your deployed guns reaches this plot. Check the Battery tab, or pick another plot."
	if a.suggested > player.money:
		return "You can't afford the suggested bid (%s)." % _money(a.suggested)
	var rivals := PackedStringArray()
	for e in a.rivals:
		if e.likely and e.can_bid():
			rivals.append(e.rival.display_name)
	if not a.worth_it:
		return "Not worth it: winning%s costs about %s, leaving only %s after shells." % [
			" against " + ", ".join(rivals) if a.contested else "", _money(a.suggested),
			_money(a.expected_profit)]
	if a.contested:
		return "Contested by %s. Bid about %s to win; expect about %s profit." % [", ".join(rivals),
			_money(a.suggested), _money(a.expected_profit)]
	return "No rival is likely to bid here: the reserve plus a little should win. Expect about %s profit." % \
		_money(a.expected_profit)


## 12,345 (the model formats its own sentences, without the UI's helpers).
static func _money(amount: int) -> String:
	var digits := str(absi(amount))
	var out := ""
	while digits.length() > 3:
		out = "," + digits.right(3) + out
		digits = digits.left(digits.length() - 3)
	return ("-" if amount < 0 else "") + digits + out
