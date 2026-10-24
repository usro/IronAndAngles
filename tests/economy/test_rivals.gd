extends TestCase

const F := preload("res://tests/economy/fixtures.gd")


class GreedyBidder extends RivalBidder:
	func choose_bid(_rival: RivalData, budget: int, lots: Array[Auction.Lot], _rng: RandomNumberGenerator) -> Dictionary:
		return {"lot": lots[0], "amount": budget * 10}


func _lots(contracts: Array[ContractData]) -> Array[Auction.Lot]:
	return Auction.new(contracts).lots


func test_rule_based_never_bids_over_budget() -> void:
	var brain := RuleBasedRivalBidder.new()
	var lots := _lots([F.contract(&"big", 100000, 50)] as Array[ContractData])
	for seed_value in 50:
		var choice := brain.choose_bid(F.rival(&"r", 0, 1.0), 900, lots, F.rng(seed_value))
		if not choice.is_empty():
			assert_true(choice.amount <= 900, "bid %d over budget 900" % choice.amount)


func test_rule_based_respects_reserve() -> void:
	var brain := RuleBasedRivalBidder.new()
	var lots := _lots([F.contract(&"c", 1000, 5000)] as Array[ContractData])
	for seed_value in 20:
		assert_eq(brain.choose_bid(F.rival(&"r", 0, 1.0), 10000, lots, F.rng(seed_value)), {})


func test_rule_based_prefers_its_terrain() -> void:
	var brain := RuleBasedRivalBidder.new()
	var hills: Array[GameConstants.TerrainProfile] = [GameConstants.TerrainProfile.HILLS]
	var c := F.contract(&"c", 1000, 100, [F.plot(&"flat"), F.plot(&"hills", GameConstants.TerrainProfile.HILLS)])
	var lots := _lots([c] as Array[ContractData])
	var choice := brain.choose_bid(F.rival(&"r", 0, 1.0, hills), 10000, lots, F.rng())
	assert_eq(choice.lot.plot.id, &"hills")


func test_rule_based_is_deterministic() -> void:
	var brain := RuleBasedRivalBidder.new()
	var lots := _lots([F.contract(&"c", 1500, 100)] as Array[ContractData])
	var a := brain.choose_bid(F.rival(&"r"), 4000, lots, F.rng(7))
	var b := brain.choose_bid(F.rival(&"r"), 4000, lots, F.rng(7))
	assert_eq(a.get("amount"), b.get("amount"))


func test_auction_refuses_greedy_brain() -> void:
	var auction := Auction.new([F.contract(&"c", 1000, 100)] as Array[ContractData])
	auction.open()
	auction.set_budget(&"r", 500)
	var choice := GreedyBidder.new().choose_bid(F.rival(&"r"), 500, auction.lots, F.rng())
	assert_eq(auction.place_bid(&"r", choice.lot, choice.amount), Auction.BidError.OVER_BUDGET)


func test_ledger_starts_from_rival_data_and_saved_state() -> void:
	var rivals := [F.rival(&"a", 3000), F.rival(&"b", 4000)]
	var ledger := RivalLedger.new(rivals, {"b": 1234.0})
	assert_eq(ledger.money(&"a"), 3000)
	assert_eq(ledger.money(&"b"), 1234, "saved funds win, JSON floats become ints")


func test_ledger_refuses_overspend() -> void:
	var ledger := RivalLedger.new([F.rival(&"a", 300)])
	assert_false(ledger.spend(&"a", 301))
	assert_eq(ledger.money(&"a"), 300)
	assert_true(ledger.spend(&"a", 300))
	assert_eq(ledger.money(&"a"), 0)
	assert_false(ledger.spend(&"ghost", 1), "unknown rival can't spend")


func test_ledger_round_trips() -> void:
	var rivals := [F.rival(&"a", 3000)]
	var ledger := RivalLedger.new(rivals)
	ledger.spend(&"a", 500)
	assert_eq(RivalLedger.new(rivals, ledger.to_dict()).money(&"a"), 2500)


func test_failed_rival_contract_never_goes_negative() -> void:
	var c := F.contract(&"c", 100000)
	c.difficulty = 5
	var ledger := RivalLedger.new([F.rival(&"a", 10)])
	for seed_value in 30:
		ledger.settle_contract(&"a", c, F.rng(seed_value))
		assert_true(ledger.money(&"a") >= 0)


func test_rival_pays_through_auction_and_ledger() -> void:
	var ledger := RivalLedger.new([F.rival(&"a", 800), F.rival(&"b", 800)])
	var auction := Auction.new([F.contract(&"c", 1000, 100)] as Array[ContractData])
	auction.open()
	for id in [&"a", &"b"]:
		auction.set_budget(id, ledger.money(id))
	auction.place_bid(&"a", auction.lots[0], 700)
	auction.place_bid(&"b", auction.lots[0], 400)
	ledger.spend(&"a", 600)  # a spent money elsewhere after bidding
	var outcome := auction.resolve(ledger.spend)[0]
	assert_eq(outcome.winner_id, &"b", "a can no longer pay 700")
	assert_eq(ledger.money(&"b"), 400)
	assert_eq(ledger.money(&"a"), 200)


func test_offers_filter_era_and_prefer_fresh() -> void:
	var contracts := [
		F.contract(&"a"), F.contract(&"b"), F.contract(&"c"),
		F.contract(&"modern", 1000, 100, [], GameConstants.Era.MODERN),
	]
	var done: Array[StringName] = [&"a"]
	var offers := ContractOffers.generate(contracts, GameConstants.Era.MEDIEVAL, done, F.rng(), 2)
	assert_eq(offers.size(), 2)
	for c in offers:
		assert_true(c.id in [&"b", &"c"], "got %s" % c.id)
	var all := ContractOffers.generate(contracts, GameConstants.Era.MEDIEVAL, done, F.rng(), 5)
	assert_eq(all.size(), 3, "modern contract filtered out")
	assert_eq(all[2].id, &"a", "completed contracts fill the remaining slots")


func test_offers_are_deterministic() -> void:
	var contracts := [F.contract(&"a"), F.contract(&"b"), F.contract(&"c"), F.contract(&"d")]
	var none: Array[StringName] = []
	var x := ContractOffers.generate(contracts, GameConstants.Era.MEDIEVAL, none, F.rng(9), 3)
	contracts.reverse()
	var y := ContractOffers.generate(contracts, GameConstants.Era.MEDIEVAL, none, F.rng(9), 3)
	assert_eq(x.map(func(c): return c.id), y.map(func(c): return c.id))
