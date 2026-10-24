extends TestCase
## Checks the shared foundation that every sub-session builds on.


func test_registry_loads_sample_content() -> void:
	assert_not_null(DataRegistry.get_weapon(&"trebuchet"), "trebuchet")
	assert_not_null(DataRegistry.get_ammo(&"stone_ball"), "stone_ball")
	assert_not_null(DataRegistry.get_tech(&"early_mortar"), "early_mortar")
	assert_not_null(DataRegistry.get_plot(&"river_ridge"), "river_ridge")
	assert_not_null(DataRegistry.get_rival(&"marshal_voss"), "marshal_voss")
	var contract := DataRegistry.get_contract(&"siege_of_aldmoor")
	assert_not_null(contract, "siege_of_aldmoor")
	if contract:
		assert_eq(contract.plots.size(), 1, "contract plots")
		assert_near(contract.weather.wind_speed, -3.0, 1e-4, "contract wind")


func test_weapon_ammo_references_resolve() -> void:
	for weapon: WeaponData in DataRegistry.weapons.values():
		for ammo_id in weapon.allowed_ammo:
			assert_not_null(DataRegistry.get_ammo(ammo_id), "%s allows unknown ammo %s" % [weapon.id, ammo_id])


func test_tech_prerequisites_resolve() -> void:
	for node: TechNodeData in DataRegistry.tech.values():
		for p in node.prerequisites:
			assert_not_null(DataRegistry.get_tech(p), "%s requires unknown tech %s" % [node.id, p])


func test_charge_maps_to_velocity() -> void:
	var w := DataRegistry.get_weapon(&"trebuchet")
	assert_near(w.velocity_for_charge(0.0), w.muzzle_velocity_min)
	assert_near(w.velocity_for_charge(1.0), w.muzzle_velocity_max)
	assert_near(w.velocity_for_charge(2.0), w.muzzle_velocity_max, 1e-4, "clamped")


func test_spend_refuses_when_broke() -> void:
	var p := PlayerState.new()
	p.money = 100
	assert_false(p.spend(150, "too much"))
	assert_eq(p.money, 100)
	assert_true(p.spend(60, "ok"))
	assert_eq(p.money, 40)


func test_money_changed_relays_to_event_bus() -> void:
	GameState.new_game(42)
	var seen := []
	var cb := func(balance, delta, _reason): seen.append([balance, delta])
	EventBus.money_changed.connect(cb)
	GameState.player.earn(250, "test")
	EventBus.money_changed.disconnect(cb)
	assert_eq(seen.size(), 1)
	assert_eq(seen[0], [GameConstants.STARTING_MONEY + 250, 250])


func test_battle_result_applies_payout_and_damage() -> void:
	GameState.new_game(1)
	var start := GameState.player.money
	var r := BattleResult.new()
	r.contract_id = &"siege_of_aldmoor"
	r.victory = true
	r.payout_earned = 1500
	r.damage_taken = {&"trebuchet": 20.0}
	GameState.apply_battle_result(r)
	assert_eq(GameState.player.money, start + 1500)
	assert_near(GameState.player.weapon_health[&"trebuchet"], 100.0)
	assert_true(GameState.player.completed_contracts.has(&"siege_of_aldmoor"))


func test_player_state_round_trips_through_dict() -> void:
	var p := PlayerState.new()
	p.money = 1234
	p.add_ammo(&"stone_ball", 7)
	p.unlocked_tech.append(&"early_mortar")
	p.current_era = GameConstants.Era.INDUSTRIAL
	var json := JSON.stringify(p.to_dict())
	var q := PlayerState.from_dict(JSON.parse_string(json))
	assert_eq(q.money, 1234)
	assert_eq(q.ammo_count(&"stone_ball"), 7)
	assert_true(q.unlocked_tech.has(&"early_mortar"))
	assert_eq(q.current_era, GameConstants.Era.INDUSTRIAL)


func test_save_and_load_game() -> void:
	const SLOT := 99
	GameState.new_game(7)
	GameState.player.money = 4321
	assert_eq(SaveSystem.save_game(SLOT), OK)
	GameState.new_game(8)
	assert_eq(SaveSystem.load_game(SLOT), OK)
	assert_eq(GameState.player.money, 4321)
	assert_eq(GameState.campaign_seed, 7)
	SaveSystem.delete_save(SLOT)


func test_every_routed_scene_instantiates() -> void:
	GameState.new_game(3)
	GameState.current_contract = DataRegistry.get_contract(&"siege_of_aldmoor")
	GameState.current_plot = GameState.current_contract.plots[0]
	GameState.last_battle_result = BattleResult.new()
	var tree := Engine.get_main_loop() as SceneTree
	for screen in SceneRouter.SCENES:
		var packed: PackedScene = load(SceneRouter.SCENES[screen])
		assert_not_null(packed, "scene %s" % SceneRouter.SCENES[screen])
		var node := packed.instantiate()
		tree.root.add_child(node)
		await tree.process_frame
		node.queue_free()
	await tree.process_frame
