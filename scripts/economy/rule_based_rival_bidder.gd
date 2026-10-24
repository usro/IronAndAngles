class_name RuleBasedRivalBidder
extends RivalBidder
## Default rival brain: bids a share of the payout that grows with aggression, bids more on
## preferred terrain, and never risks more than part of its funds. The AI session replaces this.

## Share of the payout bid at aggression 0 and 1.
const PAYOUT_SHARE_CAUTIOUS := 0.2
const PAYOUT_SHARE_AGGRESSIVE := 0.55
## Most of its funds a rival will put on one contract, at aggression 0 and 1.
const BUDGET_SHARE_CAUTIOUS := 0.3
const BUDGET_SHARE_AGGRESSIVE := 0.8
## Multiplier on the bid for plots with a preferred terrain profile.
const PREFERRED_TERRAIN_BONUS := 1.25
## +/- random variation on each bid.
const BID_NOISE := 0.1
## Chance to sit the round out, scaled by (1 - aggression).
const PASS_CHANCE := 0.3


func choose_bid(rival: RivalData, budget: int, lots: Array[Auction.Lot],
		rng: RandomNumberGenerator) -> Dictionary:
	# Draw the pass roll first so the RNG sequence doesn't depend on the lots offered.
	var passes := rng.randf() < (1.0 - rival.aggression) * PASS_CHANCE
	var cap := int(budget * lerpf(BUDGET_SHARE_CAUTIOUS, BUDGET_SHARE_AGGRESSIVE, rival.aggression))
	var best := {}
	var best_score := -INF
	for lot in lots:
		var prefers := rival.preferred_terrain.has(lot.plot.terrain_profile)
		var share := lerpf(PAYOUT_SHARE_CAUTIOUS, PAYOUT_SHARE_AGGRESSIVE, rival.aggression)
		if prefers:
			share *= PREFERRED_TERRAIN_BONUS
		share *= rng.randf_range(1.0 - BID_NOISE, 1.0 + BID_NOISE)
		var amount := mini(int(lot.contract.payout * share), cap)
		if amount < lot.contract.reserve_price:
			continue
		# Expected surplus: a preferred plot is worth more to this rival than its payout alone.
		var value := lot.contract.payout * (PREFERRED_TERRAIN_BONUS if prefers else 1.0)
		var score := value - amount
		if score > best_score:
			best_score = score
			best = {"lot": lot, "amount": amount}
	return {} if passes else best
