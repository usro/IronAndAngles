extends TestCase

const F := preload("res://tests/economy/fixtures.gd")

var _contract: ContractData
var _auction: Auction


func before_each() -> void:
	_contract = F.contract(&"siege", 1000, 200, [F.plot(&"ridge"), F.plot(&"hill")])
	var offered: Array[ContractData] = [_contract]
	_auction = Auction.new(offered)
	_auction.open()
	for id in [Auction.PLAYER_ID, &"a", &"b"]:
		_auction.set_budget(id, 1000)


func _lot(plot_id: StringName) -> Auction.Lot:
	return _auction.get_lot(&"siege", plot_id)


func test_lots_cover_every_plot() -> void:
	assert_eq(_auction.lots.size(), 2)
	assert_not_null(_lot(&"ridge"))
	assert_not_null(_lot(&"hill"))


func test_bid_below_reserve_is_refused() -> void:
	assert_eq(_auction.place_bid(Auction.PLAYER_ID, _lot(&"ridge"), 199), Auction.BidError.BELOW_RESERVE)
	assert_eq(_auction.bid_of(Auction.PLAYER_ID), null)


func test_bid_at_reserve_is_accepted() -> void:
	assert_eq(_auction.place_bid(Auction.PLAYER_ID, _lot(&"ridge"), 200), Auction.BidError.OK)


func test_no_valid_bids_means_no_sale() -> void:
	_auction.place_bid(&"a", _lot(&"ridge"), 150)
	var outcomes := _auction.resolve()
	assert_eq(outcomes.size(), 1)
	assert_false(outcomes[0].sold(), "nothing sold under reserve")


func test_bid_over_budget_is_refused() -> void:
	_auction.set_budget(&"a", 300)
	assert_eq(_auction.place_bid(&"a", _lot(&"ridge"), 301), Auction.BidError.OVER_BUDGET)
	assert_eq(_auction.place_bid(&"a", _lot(&"ridge"), 300), Auction.BidError.OK)


func test_unknown_bidder_has_no_budget() -> void:
	assert_eq(_auction.place_bid(&"stranger", _lot(&"ridge"), 250), Auction.BidError.OVER_BUDGET)


func test_lot_from_other_auction_is_refused() -> void:
	var other := Auction.new([_contract] as Array[ContractData])
	assert_eq(_auction.place_bid(Auction.PLAYER_ID, other.lots[0], 300), Auction.BidError.UNKNOWN_LOT)


func test_highest_bid_wins_across_plots() -> void:
	_auction.place_bid(Auction.PLAYER_ID, _lot(&"ridge"), 400)
	_auction.place_bid(&"a", _lot(&"hill"), 650)
	_auction.place_bid(&"b", _lot(&"ridge"), 500)
	var outcome := _auction.resolve()[0]
	assert_eq(outcome.winner_id, &"a")
	assert_eq(outcome.price, 650, "first-price: winner pays own bid")
	assert_eq(outcome.plot.id, &"hill", "winner fights from the plot they bid on")


func test_tie_goes_to_earliest_bid() -> void:
	_auction.place_bid(&"b", _lot(&"hill"), 500)
	_auction.place_bid(Auction.PLAYER_ID, _lot(&"ridge"), 500)
	_auction.place_bid(&"a", _lot(&"ridge"), 500)
	assert_eq(_auction.resolve()[0].winner_id, &"b")


func test_rebidding_replaces_and_loses_tie_priority() -> void:
	_auction.place_bid(&"a", _lot(&"ridge"), 500)
	_auction.place_bid(&"b", _lot(&"ridge"), 500)
	_auction.place_bid(&"a", _lot(&"ridge"), 500)
	assert_eq(_auction.bids().size(), 2, "one bid per bidder")
	assert_eq(_auction.resolve()[0].winner_id, &"b")


func test_winner_who_cannot_pay_falls_through_to_next_bid() -> void:
	_auction.place_bid(&"a", _lot(&"ridge"), 900)
	_auction.place_bid(&"b", _lot(&"hill"), 300)
	var outcome := _auction.resolve(func(id: StringName, _amount: int) -> bool: return id != &"a")[0]
	assert_eq(outcome.winner_id, &"b")
	assert_eq(outcome.price, 300)


func test_closed_auction_refuses_bids() -> void:
	_auction.resolve()
	assert_eq(_auction.place_bid(Auction.PLAYER_ID, _lot(&"ridge"), 300), Auction.BidError.CLOSED)


func test_each_contract_sells_separately() -> void:
	var c2 := F.contract(&"relief", 800, 100)
	var auction := Auction.new([_contract, c2] as Array[ContractData])
	auction.open()
	auction.set_budget(&"a", 1000)
	auction.set_budget(&"b", 1000)
	auction.place_bid(&"a", auction.get_lot(&"siege", &"ridge"), 300)
	auction.place_bid(&"b", auction.lots_for(c2)[0], 150)
	var outcomes := auction.resolve()
	assert_eq(outcomes[0].winner_id, &"a")
	assert_eq(outcomes[1].winner_id, &"b")


func test_signals_fire() -> void:
	var log := []
	var auction := Auction.new([_contract] as Array[ContractData])
	auction.started.connect(func(cs: Array[ContractData]) -> void: log.append(["started", cs.size()]))
	auction.bid_placed.connect(func(b: StringName, c: StringName, p: StringName, amt: int) -> void:
		log.append(["bid", b, c, p, amt]))
	auction.won.connect(func(w: StringName, c: ContractData, p: PlotData, price: int) -> void:
		log.append(["won", w, c.id, p.id, price]))
	auction.open()
	auction.set_budget(&"a", 1000)
	auction.place_bid(&"a", auction.get_lot(&"siege", &"hill"), 250)
	auction.resolve()
	assert_eq(log, [["started", 1], ["bid", &"a", &"siege", &"hill", 250], ["won", &"a", &"siege", &"hill", 250]])
