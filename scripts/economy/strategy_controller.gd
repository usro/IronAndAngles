class_name StrategyController
extends RefCounted
## Glue between the region map view and the economy model: reads and writes the autoloads so
## the view only renders and forwards clicks. One instance per visit to the region map.

const OFFER_COUNT := 3
## Keys in GameState.economy_state.
const KEY_RIVAL_MONEY := "rival_money"
const KEY_LAST_CONTRACT := "last_contract"

var offers: Array[ContractData] = []
var auction: Auction
var outcomes: Array[Auction.Outcome] = []
var ledger: RivalLedger
var shop: Shop
var rivals: Array[RivalData] = []
## Per-rival brains (rival id -> RivalBidder). Rivals not listed use default_brain.
## The AI session plugs in here.
var rival_brains: Dictionary = {}
var default_brain: RivalBidder = RuleBasedRivalBidder.new()


func _init() -> void:
	rivals.assign(DataRegistry.rivals.values())
	rivals.sort_custom(func(a: RivalData, b: RivalData) -> bool: return a.id < b.id)
	ledger = RivalLedger.new(rivals, GameState.economy_state.get(KEY_RIVAL_MONEY, {}))
	shop = Shop.new(DataRegistry.weapons, DataRegistry.ammo, DataRegistry.tech)


var player: PlayerState:
	get: return GameState.player


## Generates this round's offers and opens a new auction.
func start_round() -> void:
	offers = ContractOffers.generate(DataRegistry.contracts.values(), player.current_era,
		player.completed_contracts, _derive_rng(), OFFER_COUNT)
	outcomes = []
	auction = Auction.new(offers)
	auction.started.connect(EventBus.auction_started.emit)
	auction.bid_placed.connect(EventBus.bid_placed.emit)
	auction.won.connect(EventBus.auction_won.emit)
	auction.open()


func place_player_bid(lot: Auction.Lot, amount: int) -> Auction.BidError:
	auction.set_budget(Auction.PLAYER_ID, player.money)
	return auction.place_bid(Auction.PLAYER_ID, lot, amount)


## Rivals place their sealed bids, then the auction resolves and everyone pays.
## Rivals who win fight their contract off-screen right away (RivalLedger.settle_contract).
func resolve() -> Array[Auction.Outcome]:
	var rng := _derive_rng()
	for rival in rivals:
		auction.set_budget(rival.id, ledger.money(rival.id))
		var brain: RivalBidder = rival_brains.get(rival.id, default_brain)
		var choice := brain.choose_bid(rival, ledger.money(rival.id), auction.lots, rng)
		if not choice.is_empty():
			auction.place_bid(rival.id, choice.get("lot"), int(choice.get("amount", 0)))
	outcomes = auction.resolve(_collect_payment)
	for outcome in outcomes:
		if outcome.winner_id == Auction.PLAYER_ID:
			GameState.economy_state[KEY_LAST_CONTRACT] = {
				"contract_id": String(outcome.contract.id), "price": outcome.price}
		elif ledger.has_rival(outcome.winner_id):
			ledger.settle_contract(outcome.winner_id, outcome.contract, rng)
	GameState.economy_state[KEY_RIVAL_MONEY] = ledger.to_dict()
	return outcomes


func player_outcome() -> Auction.Outcome:
	for outcome in outcomes:
		if outcome.winner_id == Auction.PLAYER_ID:
			return outcome
	return null


## Region map -> Battle contract.
func deploy() -> bool:
	var won := player_outcome()
	if won == null:
		return false
	GameState.current_contract = won.contract
	GameState.current_plot = won.plot
	SceneRouter.goto(SceneRouter.Screen.BATTLE)
	return true


func bidder_name(bidder_id: StringName) -> String:
	if bidder_id == Auction.PLAYER_ID:
		return "You"
	var rival := DataRegistry.get_rival(bidder_id)
	return rival.display_name if rival else String(bidder_id)


## Profit report for the last battle the player fought, or null if there is none.
func last_settlement() -> Settlement.Report:
	var result := GameState.last_battle_result
	if result == null:
		return null
	var last: Dictionary = GameState.economy_state.get(KEY_LAST_CONTRACT, {})
	var price := int(last.get("price", 0)) if StringName(last.get("contract_id", "")) == result.contract_id else 0
	return Settlement.report(result, price, DataRegistry.weapons)


func _collect_payment(bidder_id: StringName, amount: int) -> bool:
	if bidder_id == Auction.PLAYER_ID:
		return player.spend(amount, "Auction price")
	return ledger.spend(bidder_id, amount)


## A child RNG seeded from the campaign RNG, so each step is reproducible from the campaign seed.
func _derive_rng() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = GameState.rng.randi()
	return rng
