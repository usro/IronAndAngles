class_name RivalBidder
extends RefCounted
## Hook for a rival commander's bidding brain. Subclass it and override choose_bid();
## StrategyController asks one brain per rival (see StrategyController.rival_brains).
## The auction still enforces reserve and budget, so a brain can't cheat by overbidding.


## Returns {"lot": Auction.Lot, "amount": int}, or {} to pass this round.
## `budget` is the rival's current funds. Draw all randomness from `rng` (it is seeded).
func choose_bid(_rival: RivalData, _budget: int, _lots: Array[Auction.Lot],
		_rng: RandomNumberGenerator) -> Dictionary:
	return {}
