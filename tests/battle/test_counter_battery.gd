extends TestCase
## Counter-battery duel: hidden enemy gun, spotted by its muzzle flash or a hit, shootable,
## silenced when destroyed, worth a bonus on victory, never required for victory.


func _sim(seed_value := 5) -> BattleSim:
	var contract: ContractData = DataRegistry.get_contract(&"siege_of_aldmoor")
	var plot: PlotData = contract.plots[0]
	var p := PlayerState.new()
	p.add_weapon(DataRegistry.get_weapon(&"trebuchet"))
	p.add_ammo(&"stone_ball", 30)
	return BattleSim.new(contract, plot, p, TerrainGenerator.generate(plot), seed_value)


func test_gun_starts_hidden_with_its_weapons_health() -> void:
	var sim := _sim()
	assert_false(sim.enemy_spotted, "hidden at start")
	assert_true(sim.enemy_gun_alive())
	assert_near(sim.enemy_max_health, sim.enemy_weapon.max_health * BattleSim.ENEMY_GUN_HEALTH_SCALE)


func test_first_enemy_shot_reveals_the_gun() -> void:
	var sim := _sim()
	var spotted := [false]
	var cb := func(_p: Vector2) -> void: spotted[0] = true
	EventBus.enemy_gun_spotted.connect(cb)
	sim.reveal_level = 1.0
	sim.enemy_reload_left = 0.0
	sim.tick(1.0 / 30.0)
	EventBus.enemy_gun_spotted.disconnect(cb)
	assert_true(sim.enemy_spotted, "muzzle flash gives it away")
	assert_true(spotted[0], "event emitted")


func test_a_hit_damages_and_spots_the_hidden_gun() -> void:
	var sim := _sim()
	var stone := DataRegistry.get_ammo(&"stone_ball")
	var dealt := sim.apply_blast(stone, sim.enemy_gun_rect().get_center(), 1.0, false)
	assert_near(dealt, stone.damage, 0.01, "full damage on contact")
	assert_true(sim.enemy_spotted, "a hit also spots it")
	assert_near(sim.enemy_health, sim.enemy_max_health - stone.damage, 0.01)


func test_destroyed_gun_falls_silent() -> void:
	var sim := _sim()
	sim.damage_enemy_gun(sim.enemy_health + 1.0)
	assert_false(sim.enemy_gun_alive())
	assert_true(sim.result.enemy_gun_destroyed)
	sim.reveal_level = 1.0
	sim.enemy_reload_left = 0.0
	var launched := [0]
	sim.shell_launched.connect(func(_f: ShellFlight, enemy: bool) -> void: launched[0] += int(enemy))
	for i in 600:
		sim.tick(1.0 / 30.0)
	assert_eq(launched[0], 0, "no return fire after it is destroyed")
	var probe := sim._player_hit_test(sim.enemy_gun_rect().get_center() + Vector2(-20, -1), sim.enemy_gun_rect().get_center() + Vector2(20, -1))
	assert_true(probe.is_empty() or probe.get("position", Vector2.ZERO).distance_to(sim.enemy_gun_rect().get_center()) > 1.0,
		"wreck no longer stops shells")


func test_victory_pays_bonus_only_when_gun_destroyed() -> void:
	var plain := _sim()
	for t in plain.targets:
		t.apply_damage(t.health + 1.0)
	plain.tick(1.0 / 30.0)
	assert_eq(plain.outcome, BattleSim.Outcome.VICTORY, "gun not required for victory")
	assert_eq(plain.result.payout_earned, plain.contract.payout)
	assert_eq(plain.result.counter_battery_bonus, 0)

	var duel := _sim()
	duel.damage_enemy_gun(duel.enemy_health + 1.0)
	for t in duel.targets:
		t.apply_damage(t.health + 1.0)
	duel.tick(1.0 / 30.0)
	var bonus := roundi(duel.contract.payout * BattleSim.COUNTER_BATTERY_BONUS)
	assert_eq(duel.result.counter_battery_bonus, bonus)
	assert_eq(duel.result.payout_earned, duel.contract.payout + bonus)


func test_no_bonus_on_defeat() -> void:
	var sim := _sim()
	sim.damage_enemy_gun(sim.enemy_health + 1.0)
	sim.retreat()
	assert_eq(sim.result.payout_earned, 0)
	assert_eq(sim.result.counter_battery_bonus, 0)
