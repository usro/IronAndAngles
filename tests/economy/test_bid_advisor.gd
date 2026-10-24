extends TestCase
## The bid advisor forecasts what RuleBasedRivalBidder actually does, and its suggestion wins.

const ROUNDS := 150


func _advise(c: StrategyController, lot: Auction.Lot) -> BidAdvisor.Advice:
	var funds := {}
	for r in c.rivals:
		funds[r.id] = c.ledger.money(r.id)
	return BidAdvisor.advise(lot, c.auction.lots, GameState.player, c.rivals, funds, DataRegistry.weapons, DataRegistry.ammo)


func test_rival_forecasts_match_real_bids() -> void:
	var picks_matched := 0
	var picks := 0
	var in_range := 0
	var bids := 0
	var brain := RuleBasedRivalBidder.new()
	for round_i in ROUNDS:
		GameState.new_game(5000 + round_i)
		var c := StrategyController.new()
		c.start_round()
		var rng := RandomNumberGenerator.new()
		rng.seed = round_i
		for rival in c.rivals:
			var funds := c.ledger.money(rival.id)
			var actual := brain.choose_bid(rival, funds, c.auction.lots, rng)
			if actual.is_empty():
				continue
			var lot: Auction.Lot = actual["lot"]
			var e: BidAdvisor.RivalEstimate
			for est in _advise(c, lot).rivals:
				if est.rival == rival:
					e = est
			picks += 1
			picks_matched += int(e.likely)
			bids += 1
			in_range += int(actual["amount"] >= e.low and actual["amount"] <= e.high)
	print("     advisor: picked contract forecast %d/%d, bid inside range %d/%d" % [picks_matched, picks, in_range, bids])
	assert_true(picks_matched >= picks * 0.75, "rival's contract forecast right %d/%d" % [picks_matched, picks])
	assert_true(in_range >= bids * 0.95, "actual bid inside forecast range %d/%d" % [in_range, bids])


func test_following_the_suggestion_wins_and_profits() -> void:
	var tried := 0
	var won := 0
	for round_i in ROUNDS:
		GameState.new_game(9000 + round_i)
		GameState.player.money = 50000
		var c := StrategyController.new()
		c.default_brain = RuleBasedRivalBidder.new()
		c.start_round()
		var best: Auction.Lot
		var best_advice: BidAdvisor.Advice
		for lot in c.auction.lots:
			var a := _advise(c, lot)
			if a.worth_it and (best_advice == null or a.expected_profit > best_advice.expected_profit):
				best = lot
				best_advice = a
		if best == null:
			continue
		tried += 1
		c.place_player_bid(best, best_advice.suggested)
		c.resolve()
		var out := c.player_outcome()
		won += int(out != null)
		if out:
			assert_true(best_advice.suggested < best.contract.payout, "never suggests bidding the whole payout")
	print("     advisor: suggested bid won %d/%d auctions" % [won, tried])
	assert_true(tried > ROUNDS * 0.5, "most weeks have a worthwhile lot (%d/%d)" % [tried, ROUNDS])
	assert_true(won >= tried * 0.85, "suggestion wins %d/%d" % [won, tried])


func test_shell_estimate_uses_the_deployed_battery() -> void:
	GameState.new_game(3)
	var c := StrategyController.new()
	c.start_round()
	var lot: Auction.Lot = c.auction.lots[0]
	var a := _advise(c, lot)
	assert_true(a.can_shoot(), "starting trebuchet reaches medieval plots")
	assert_true(a.shooter.begins_with("Trebuchet"), a.shooter)
	var stone := DataRegistry.get_ammo(&"stone_ball")
	var par := lot.contract.target_count * ceili(lot.contract.target_health / stone.damage) * stone.cost_per_shell
	assert_true(a.par_cost <= par, "par uses the cheapest option")
	assert_eq(a.break_even, lot.contract.payout - a.shell_cost)


func test_out_of_reach_plot_is_flagged() -> void:
	GameState.new_game(4)
	var c := StrategyController.new()
	c.start_round()
	var lot: Auction.Lot = c.auction.lots[0]
	lot.plot.target_distance_m = 5000.0
	var a := _advise(c, lot)
	assert_false(a.can_shoot())
	assert_false(a.worth_it)
	assert_true(a.verdict.contains("Battery"), a.verdict)
