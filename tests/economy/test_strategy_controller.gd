extends TestCase
## Integration over the autoloads with the shipped content.


class PassBidder extends RivalBidder:
	pass


func before_each() -> void:
	GameState.new_game(1234)


func _quiet(c: StrategyController) -> void:
	c.default_brain = PassBidder.new()


func test_round_offers_contracts_and_emits_events() -> void:
	var events := []
	var on_start := func(cs: Array[ContractData]) -> void: events.append("started")
	var on_won := func(w: StringName, _c: ContractData, _p: PlotData, _price: int) -> void: events.append(w)
	EventBus.auction_started.connect(on_start)
	EventBus.auction_won.connect(on_won)
	var c := StrategyController.new()
	_quiet(c)
	c.start_round()
	assert_false(c.offers.is_empty(), "shipped content offers something")
	var lot: Auction.Lot = c.auction.lots[0]
	var price := lot.contract.reserve_price
	var money := GameState.player.money
	assert_eq(c.place_player_bid(lot, price), Auction.BidError.OK)
	c.resolve()
	EventBus.auction_started.disconnect(on_start)
	EventBus.auction_won.disconnect(on_won)
	assert_eq(events, ["started", Auction.PLAYER_ID])
	assert_eq(GameState.player.money, money - price, "price paid up front")
	assert_eq(c.player_outcome().plot, lot.plot)


func test_player_cannot_bid_more_than_funds() -> void:
	var c := StrategyController.new()
	c.start_round()
	assert_eq(c.place_player_bid(c.auction.lots[0], GameState.player.money + 1), Auction.BidError.OVER_BUDGET)


func test_settlement_uses_paid_price() -> void:
	var c := StrategyController.new()
	_quiet(c)
	c.start_round()
	var lot: Auction.Lot = c.auction.lots[0]
	c.place_player_bid(lot, lot.contract.reserve_price + 50)
	c.resolve()
	var r := BattleResult.new()
	r.contract_id = lot.contract.id
	r.victory = true
	r.payout_earned = lot.contract.payout
	r.ammo_spent = 30
	GameState.apply_battle_result(r)
	var report := StrategyController.new().last_settlement()
	assert_eq(report.auction_price, lot.contract.reserve_price + 50)
	assert_eq(report.net_profit(), lot.contract.payout - lot.contract.reserve_price - 50 - 30)


func test_rival_funds_persist_in_economy_state() -> void:
	var c := StrategyController.new()
	c.start_round()
	c.resolve()
	var saved: Dictionary = GameState.economy_state.get(StrategyController.KEY_RIVAL_MONEY, {})
	assert_eq(saved.size(), DataRegistry.rivals.size())
	var again := StrategyController.new()
	for rival in again.rivals:
		assert_eq(again.ledger.money(rival.id), c.ledger.money(rival.id))
