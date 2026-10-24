extends TestCase
## Smoke test: the region map builds, bids, resolves and shops without script errors.


func test_region_map_round_trip() -> void:
	GameState.new_game(99)
	var tree := Engine.get_main_loop() as SceneTree
	var map: Control = load("res://scenes/strategy/region_map.tscn").instantiate()
	tree.root.add_child(map)
	await tree.process_frame
	var controller: StrategyController = map._controller
	assert_false(controller.auction.lots.is_empty(), "lots on the map")
	assert_eq(map._plot_buttons.size(), controller.auction.lots.size())
	map._bid_spin.value = map._selected.contract.reserve_price
	map._place_bid()
	assert_not_null(controller.auction.bid_of(Auction.PLAYER_ID), "bid placed from the view")
	map._resolve()
	assert_true(controller.auction.is_resolved)
	assert_false(map._next_button.disabled)
	map._buy_ammo(&"stone_ball", 10)
	map._new_round()
	assert_false(controller.auction.is_resolved, "next week opens a new auction")
	map.queue_free()
	await tree.process_frame
