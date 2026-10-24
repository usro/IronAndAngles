extends TestCase
## Battery loadout slots and weapon resale.


func _player(ids: Array, era := GameConstants.Era.MEDIEVAL) -> PlayerState:
	var p := PlayerState.new()
	p.current_era = era
	for id in ids:
		p.add_weapon(DataRegistry.get_weapon(id))
	return p


func _ids(weapons: Array[WeaponData]) -> Array:
	return weapons.map(func(w: WeaponData) -> StringName: return w.id)


func test_automatic_pick_prefers_newest_and_respects_slots() -> void:
	var p := _player([&"trebuchet", &"bronze_mortar", &"great_trebuchet"])
	var d := Loadout.deployed(p, DataRegistry.weapons)
	assert_eq(d.size(), Loadout.slots(GameConstants.Era.MEDIEVAL), "medieval battery is full, not overfull")
	assert_false(_ids(d).has(&"trebuchet"), "cheapest medieval gun stays in reserve")
	p.current_era = GameConstants.Era.INDUSTRIAL
	p.add_weapon(DataRegistry.get_weapon(&"rifled_cannon"))
	d = Loadout.deployed(p, DataRegistry.weapons)
	assert_eq(_ids(d)[0], &"rifled_cannon", "newest era first")
	assert_eq(d.size(), 3, "industrial has three slots")


func test_toggle_stands_down_and_deploys() -> void:
	var p := _player([&"trebuchet", &"bronze_mortar", &"great_trebuchet"])
	var auto := _ids(Loadout.deployed(p, DataRegistry.weapons))
	assert_eq(Loadout.toggle(p, DataRegistry.weapons, &"trebuchet"), Loadout.Status.NO_FREE_SLOT, "battery full")
	assert_eq(Loadout.toggle(p, DataRegistry.weapons, auto[0]), Loadout.Status.OK, "stand one down")
	assert_eq(Loadout.toggle(p, DataRegistry.weapons, &"trebuchet"), Loadout.Status.OK, "now there's room")
	var d := _ids(Loadout.deployed(p, DataRegistry.weapons))
	assert_true(d.has(&"trebuchet") and not d.has(auto[0]), "swap stuck: %s" % [d])


func test_destroyed_gun_cannot_deploy_and_falls_back() -> void:
	var p := _player([&"trebuchet", &"great_trebuchet"])
	p.weapon_health[&"great_trebuchet"] = 0.0
	assert_eq(_ids(Loadout.deployed(p, DataRegistry.weapons)), [&"trebuchet"], "only the working gun")
	p.loadout.assign([&"great_trebuchet"])
	assert_eq(_ids(Loadout.deployed(p, DataRegistry.weapons)), [&"trebuchet"], "falls back when the choice is broken")
	p.weapon_health[&"trebuchet"] = 0.0
	assert_true(Loadout.deployed(p, DataRegistry.weapons).is_empty(), "nothing serviceable")


func test_bought_gun_joins_free_slot() -> void:
	var p := _player([&"trebuchet"])
	p.money = 10000
	p.unlocked_tech.append(&"great_trebuchet")
	var shop := Shop.new(DataRegistry.weapons, DataRegistry.ammo, DataRegistry.tech)
	assert_eq(shop.buy_weapon(p, &"great_trebuchet"), Shop.Status.OK)
	assert_true(Loadout.is_deployed(p, DataRegistry.weapons, &"great_trebuchet"), "new gun deployed")
	assert_true(Loadout.is_deployed(p, DataRegistry.weapons, &"trebuchet"), "old gun still fits")


func test_battle_deploys_only_the_loadout() -> void:
	var contract: ContractData = DataRegistry.get_contract(&"siege_of_aldmoor")
	var p := _player([&"trebuchet", &"bronze_mortar", &"great_trebuchet"])
	p.add_ammo(&"stone_ball", 5)
	Loadout.toggle(p, DataRegistry.weapons, Loadout.deployed(p, DataRegistry.weapons)[0].id)
	var sim := BattleSim.new(contract, contract.plots[0], p, TerrainGenerator.generate(contract.plots[0]), 3)
	assert_eq(sim.mounts.size(), 1, "one gun stood down, one deployed")


func test_sell_value_is_half_price_minus_damage() -> void:
	var shop := Shop.new(DataRegistry.weapons, DataRegistry.ammo, DataRegistry.tech)
	var p := _player([&"trebuchet", &"great_trebuchet"])
	var w := DataRegistry.get_weapon(&"great_trebuchet")
	assert_eq(shop.sell_value(p, w.id), w.purchase_cost / 2)
	p.weapon_health[w.id] = w.max_health - 10.0
	assert_eq(shop.sell_value(p, w.id), w.purchase_cost / 2 - 10 * w.repair_cost_per_hp, "damage deducted")
	var money := p.money
	assert_eq(shop.sell_weapon(p, w.id), Shop.Status.OK)
	assert_eq(p.money, money + w.purchase_cost / 2 - 10 * w.repair_cost_per_hp)
	assert_false(p.owned_weapons.has(w.id), "gone")
	assert_false(p.loadout.has(w.id), "left the battery")
	assert_eq(shop.sell_weapon(p, &"trebuchet"), Shop.Status.LAST_WEAPON, "keep at least one gun")


func test_loadout_survives_save() -> void:
	var p := _player([&"trebuchet", &"great_trebuchet"])
	Loadout.toggle(p, DataRegistry.weapons, &"trebuchet")
	var q := PlayerState.from_dict(JSON.parse_string(JSON.stringify(p.to_dict())))
	assert_eq(_ids(Loadout.deployed(q, DataRegistry.weapons)), _ids(Loadout.deployed(p, DataRegistry.weapons)))
