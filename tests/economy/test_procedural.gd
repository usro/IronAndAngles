extends TestCase
## Weekly procedural offers: generated plots stay inside each era's handcrafted bounds, are
## reachable by the era's reference weapon, and everything is reproducible from the seed.


func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func _templates(era: GameConstants.Era) -> Array[ContractData]:
	var out: Array[ContractData] = []
	for c: ContractData in DataRegistry.contracts.values():
		if c.era_required == era:
			out.append(c)
	out.sort_custom(func(a, b): return a.id < b.id)
	return out


func test_era_ranges_match_handcrafted_content() -> void:
	var r := PlotGenerator.EraRanges.for_era(GameConstants.Era.MEDIEVAL, DataRegistry.contracts.values())
	assert_true(r.is_valid())
	assert_near(r.distance_m.x, 220.0, 0.01, "nearest medieval plot")
	assert_near(r.distance_m.y, 300.0, 0.01, "farthest medieval plot")
	assert_true(r.profiles.has(GameConstants.TerrainProfile.FLAT), "gentle ground always allowed")


func test_generated_plots_stay_in_bounds_and_in_reach() -> void:
	for era in GameConstants.Era.values():
		var r := PlotGenerator.EraRanges.for_era(era, DataRegistry.contracts.values())
		var loadout := PlotGenerator.reference_loadout(era, DataRegistry.weapons, DataRegistry.ammo)
		assert_eq(loadout.size(), 2, "era %d has a reference weapon" % era)
		var rng := _rng(era + 1)
		for i in 40:
			var p := PlotGenerator.generate(r, loadout, rng, i)
			assert_true(p.target_distance_m >= r.distance_m.x - 0.01 and p.target_distance_m <= r.distance_m.y + 2.5,
				"era %d distance %.0f outside %s" % [era, p.target_distance_m, r.distance_m])
			# Direct-fire (railgun) eras fight from level or lower ground so the line of sight is clear.
			var heights := Vector2(-PlotGenerator.DIRECT_FIRE_MAX_DEPTH_M, 0.0) \
				if PlotGenerator.is_direct_fire(loadout[0]) else r.height_m
			assert_true(p.height_advantage_m >= heights.x - 0.5 and p.height_advantage_m <= heights.y + 0.5,
				"era %d height %.0f" % [era, p.height_advantage_m])
			assert_true(r.profiles.has(p.terrain_profile), "era %d profile allowed" % era)
			var reach := PlotGenerator.max_range_m(loadout[0], loadout[1], p)
			assert_true(p.target_distance_m <= reach, "era %d: %s %.0f m beyond reach %.0f m" % [
				era, p.display_name, p.target_distance_m, reach])
			assert_false(p.display_name.is_empty(), "named")


func test_week_is_deterministic_and_ids_unique() -> void:
	var templates := _templates(GameConstants.Era.MEDIEVAL)
	var a := ProceduralContracts.for_week(templates, 7, _rng(42), DataRegistry.contracts.values(),
		DataRegistry.weapons, DataRegistry.ammo)
	var b := ProceduralContracts.for_week(templates, 7, _rng(42), DataRegistry.contracts.values(),
		DataRegistry.weapons, DataRegistry.ammo)
	var ids := {}
	for i in a.size():
		assert_eq(a[i].id, b[i].id)
		assert_eq(a[i].plots.size(), b[i].plots.size())
		for j in a[i].plots.size():
			assert_eq(a[i].plots[j].display_name, b[i].plots[j].display_name, "same seed, same names")
			assert_eq(a[i].plots[j].target_distance_m, b[i].plots[j].target_distance_m)
			ids[a[i].plots[j].id] = true
		assert_eq(a[i].template_id, templates[i].id)
		var band := ProceduralContracts.PAYOUT_JITTER
		assert_true(a[i].payout >= templates[i].payout * band.x * 0.95 and a[i].payout <= templates[i].payout * band.y * 1.05,
			"%s payout %d" % [a[i].id, a[i].payout])
		assert_true(a[i].reserve_price < a[i].payout, "reserve below payout")
		assert_not_null(a[i].weather, "has weather")
	var plot_count: int = a.reduce(func(n, c): return n + c.plots.size(), 0)
	assert_eq(ids.size(), plot_count, "plot ids unique within the week")
	assert_true(templates[0].plots[0].id != a[0].plots[0].id, "template left untouched")


func test_controller_offers_new_land_every_week_and_registers_it() -> void:
	GameState.new_game(11)
	var c := StrategyController.new()
	c.start_round()
	var first := c.offers.map(func(x): return x.plots[0].display_name)
	for offer in c.offers:
		assert_true(offer.template_id != &"", "%s is generated" % offer.id)
		assert_eq(DataRegistry.get_contract(offer.id), offer, "findable by id")
		assert_eq(DataRegistry.get_plot(offer.plots[0].id), offer.plots[0])
	c.start_round()
	var second := c.offers.map(func(x): return x.plots[0].display_name)
	assert_eq(int(GameState.economy_state[StrategyController.KEY_WEEK]), 2)
	assert_true(first != second, "week 2 is different land")


func test_victory_on_generated_contract_completes_its_client() -> void:
	GameState.new_game(12)
	var c := StrategyController.new()
	c.start_round()
	var offer: ContractData = c.offers[0]
	var r := BattleResult.new()
	r.contract_id = offer.id
	r.victory = true
	r.payout_earned = offer.payout
	GameState.apply_battle_result(r)
	assert_true(GameState.player.completed_contracts.has(offer.template_id), "client marked done")
	assert_false(GameState.player.completed_contracts.has(offer.id), "not the weekly id")


func test_generating_a_week_is_fast() -> void:
	var t0 := Time.get_ticks_usec()
	for era in GameConstants.Era.values():
		ProceduralContracts.for_week(_templates(era).slice(0, 3), 1, _rng(era), DataRegistry.contracts.values(),
			DataRegistry.weapons, DataRegistry.ammo)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	print("     procedural: 4 eras x 3 offers in %.1f ms" % ms)
	assert_true(ms < 1500.0, "took %.1f ms" % ms)
