class_name Auction
extends RefCounted
## One round of bidding on contract plots. Pure model: emits its own signals, which
## StrategyController relays to EventBus.
##
## Rules (sealed-bid, first-price):
## - Every (contract, plot) pair is a lot. The winner of a contract fights from the plot they bid on.
## - A bidder holds at most one bid per auction (one battery, one battle). Bidding again replaces it.
## - A bid must be at least the contract's reserve_price and at most the bidder's budget.
## - Each contract sells once: the highest bid across all of its plots wins and pays its own bid.
## - Ties go to the bid placed first.
## - If the winner can't pay at resolution, their bid is dropped and the next-best bid wins.

signal started(contracts: Array[ContractData])
signal bid_placed(bidder_id: StringName, contract_id: StringName, plot_id: StringName, amount: int)
signal won(winner_id: StringName, contract: ContractData, plot: PlotData, price: int)

enum BidError { OK, CLOSED, UNKNOWN_LOT, BELOW_RESERVE, OVER_BUDGET }

const PLAYER_ID := &"player"


class Lot:
	var contract: ContractData
	var plot: PlotData

	func _init(c: ContractData, p: PlotData) -> void:
		contract = c
		plot = p

	func key() -> String:
		return Auction.lot_key(contract.id, plot.id)


class Bid:
	var bidder_id: StringName
	var lot: Lot
	var amount: int
	## Placement order, for tie-breaking.
	var order: int


class Outcome:
	var contract: ContractData
	## null when nobody met the reserve.
	var plot: PlotData
	var winner_id: StringName = &""
	var price: int = 0

	func sold() -> bool:
		return winner_id != &""


var contracts: Array[ContractData] = []
var lots: Array[Lot] = []
var is_open := false
var is_resolved := false

var _lots_by_key: Dictionary = {}  # String -> Lot
var _bids: Dictionary = {}         # bidder id -> Bid
var _budgets: Dictionary = {}      # bidder id -> int
var _next_order := 0


func _init(offered: Array[ContractData]) -> void:
	contracts = offered
	for c in contracts:
		for p in c.plots:
			var lot := Lot.new(c, p)
			lots.append(lot)
			_lots_by_key[lot.key()] = lot


static func lot_key(contract_id: StringName, plot_id: StringName) -> String:
	return "%s/%s" % [contract_id, plot_id]


static func error_text(err: BidError) -> String:
	match err:
		BidError.OK: return "Bid placed"
		BidError.CLOSED: return "The auction is closed"
		BidError.UNKNOWN_LOT: return "That plot is not up for auction"
		BidError.BELOW_RESERVE: return "Bid is below the reserve price"
		BidError.OVER_BUDGET: return "Not enough funds for that bid"
	return "Unknown error"


func open() -> void:
	is_open = true
	started.emit(contracts)


func get_lot(contract_id: StringName, plot_id: StringName) -> Lot:
	return _lots_by_key.get(lot_key(contract_id, plot_id))


func lots_for(contract: ContractData) -> Array[Lot]:
	var out: Array[Lot] = []
	for lot in lots:
		if lot.contract == contract:
			out.append(lot)
	return out


## The most a bidder may bid. Set it before they bid (player money, rival ledger funds).
func set_budget(bidder_id: StringName, amount: int) -> void:
	_budgets[bidder_id] = amount


func budget(bidder_id: StringName) -> int:
	return _budgets.get(bidder_id, 0)


func place_bid(bidder_id: StringName, lot: Lot, amount: int) -> BidError:
	if not is_open:
		return BidError.CLOSED
	if lot == null or _lots_by_key.get(lot.key()) != lot:
		return BidError.UNKNOWN_LOT
	if amount < lot.contract.reserve_price:
		return BidError.BELOW_RESERVE
	if amount > budget(bidder_id):
		return BidError.OVER_BUDGET
	var bid := Bid.new()
	bid.bidder_id = bidder_id
	bid.lot = lot
	bid.amount = amount
	bid.order = _next_order
	_next_order += 1
	_bids[bidder_id] = bid
	bid_placed.emit(bidder_id, lot.contract.id, lot.plot.id, amount)
	return BidError.OK


func withdraw(bidder_id: StringName) -> void:
	if is_open:
		_bids.erase(bidder_id)


func bid_of(bidder_id: StringName) -> Bid:
	return _bids.get(bidder_id)


func bids() -> Array[Bid]:
	var out: Array[Bid] = []
	out.assign(_bids.values())
	return out


## Closes the auction and picks a winner per contract, in offer order.
## `collect_payment(bidder_id, amount) -> bool` charges the winner; returning false drops that
## bid and moves on to the next-best. Leave it empty to accept every winner (tests, previews).
func resolve(collect_payment: Callable = Callable()) -> Array[Outcome]:
	is_open = false
	is_resolved = true
	var out: Array[Outcome] = []
	for c in contracts:
		var outcome := Outcome.new()
		outcome.contract = c
		for bid in _ranked_bids(c):
			if collect_payment.is_valid() and not collect_payment.call(bid.bidder_id, bid.amount):
				continue
			outcome.winner_id = bid.bidder_id
			outcome.plot = bid.lot.plot
			outcome.price = bid.amount
			break
		out.append(outcome)
	for outcome in out:
		if outcome.sold():
			won.emit(outcome.winner_id, outcome.contract, outcome.plot, outcome.price)
	return out


func _ranked_bids(contract: ContractData) -> Array[Bid]:
	var ranked: Array[Bid] = []
	for bid: Bid in _bids.values():
		if bid.lot.contract == contract:
			ranked.append(bid)
	ranked.sort_custom(func(a: Bid, b: Bid) -> bool:
		return a.amount > b.amount or (a.amount == b.amount and a.order < b.order))
	return ranked
