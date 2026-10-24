extends TestCase
## Battle gameplay: fire control, costs, damage, counter-battery, orbital strikes, end conditions.

const SEED := 4242
const STEP := 1.0 / 60.0


func _weapon(id: StringName = &"test_gun", reload := 2.0, salvo := 1, interval := 0.0,
		cooldown := 0.0, energy := 0) -> WeaponData:
	var w := WeaponData.new()
	w.id = id
	w.display_name = "Test gun"
	w.max_health = 100.0
	w.elevation_min_deg = 20.0
	w.elevation_max_deg = 70.0
	w.muzzle_velocity_min = 20.0
	w.muzzle_velocity_max = 80.0
	w.spread_deg = 0.0
	w.reload_time = reload
	w.salvo_size = salvo
	w.salvo_interval = interval
	w.cooldown = cooldown
	w.energy_cost_per_shot = energy
	w.allowed_ammo = [&"test_shell"]
	return w


func _ammo(id: StringName = &"test_shell", cost := 30) -> AmmoData:
	var a := AmmoData.new()
	a.id = id
	a.display_name = "Test shell"
	a.cost_per_shell = cost
	a.mass_kg = 10.0
	a.drag_coefficient = 0.3
	a.cross_section_m2 = 0.01
	a.damage = 50.0
	a.explosion_radius_m = 2.0
	a.crater_radius_m = 1.0
	return a


func _plot() -> PlotData:
	var p := PlotData.new()
	p.id = &"test_plot"
	p.terrain_profile = GameConstants.TerrainProfile.FLAT
	p.terrain_seed = 7
	p.height_advantage_m = 10.0
	p.target_distance_m = 200.0
	return p


func _contract(plot: PlotData, targets := 2, health := 100.0, time_limit := 0.0) -> ContractData:
	var c := ContractData.new()
	c.id = &"test_contract"
	c.client_name = "Test client"
	c.payout = 1000
	c.plots = [plot]
	c.target_count = targets
	c.target_health = health
	c.time_limit = time_limit
	c.weather = WeatherState.new()
	return c


func _player(weapons: Array[WeaponData], shells := 10) -> PlayerState:
	var p := PlayerState.new()
	for w in weapons:
		p.add_weapon(w)
	p.add_ammo(&"test_shell", shells)
	return p


## A battle with one test gun (or the given weapons) and the enemy brain switched off.
func _sim(weapons: Array[WeaponData] = [], shells := 10, contract: ContractData = null) -> BattleSim:
	if weapons.is_empty():
		weapons = [_weapon()]
	var plot := _plot()
	if contract == null:
		contract = _contract(plot)
	var table := {}
	for w in weapons:
		table[w.id] = w
	var ammo := {&"test_shell": _ammo()}
	var sim := BattleSim.new(contract, plot, _player(weapons, shells), TerrainGenerator.generate(plot),
		SEED, table, ammo)
	sim.enemy_brain = null
	return sim


func _run(sim: BattleSim, seconds: float) -> void:
	var t := 0.0
	while t < seconds and sim.outcome == BattleSim.Outcome.NONE:
		sim.tick(STEP)
		t += STEP


func _run_until_settled(sim: BattleSim, max_s := 30.0) -> void:
	var t := 0.0
	while (sim.player_shots_pending()) and t < max_s and sim.outcome == BattleSim.Outcome.NONE:
		sim.tick(STEP)
		t += STEP


## Aims the selected weapon at a ground point with the solver (no spread, no wind in tests).
func _aim_at(sim: BattleSim, point: Vector2) -> void:
	var m := sim.selected_mount()
	var sol := AimSolver.solve(m.weapon, sim.ammo_table[m.ammo_id], m.muzzle_m(), point, sim.weather)
	assert_true(sol.ok, "solver reaches the target")
	m.elevation_deg = sol.elevation_deg
	m.charge = sol.charge


# --- Fire control ---

func test_reload_gating_on_mount() -> void:
	var m := WeaponMount.new(_weapon(&"g", 5.0, 1, 0.0, 2.0), Vector2.ZERO, 100.0)
	assert_true(m.is_ready(), "starts loaded")
	assert_true(m.pull_trigger(), "first pull")
	assert_eq(m.tick(0.0), 1, "first shell at once")
	assert_false(m.pull_trigger(), "no second pull while reloading")
	assert_near(m.reload_left, 7.0, 1e-6, "reload + cooldown")
	assert_eq(m.tick(6.9), 0, "nothing due while reloading")
	assert_false(m.is_ready(), "still locked at 6.9 s")
	m.tick(0.2)
	assert_true(m.is_ready(), "ready after reload + cooldown")


func test_salvo_spacing() -> void:
	var m := WeaponMount.new(_weapon(&"mlrs", 10.0, 3, 0.5), Vector2.ZERO, 100.0)
	assert_true(m.pull_trigger())
	assert_eq(m.tick(0.0), 1, "first rocket")
	assert_eq(m.tick(0.4), 0, "interval not over")
	assert_eq(m.tick(0.1), 1, "second rocket")
	assert_eq(m.tick(0.5), 1, "third rocket")
	assert_false(m.is_firing(), "salvo done")
	assert_near(m.reload_left, 10.0, 1e-6, "reload starts after the last rocket")


func test_destroyed_mount_cannot_fire() -> void:
	var m := WeaponMount.new(_weapon(), Vector2.ZERO, 0.0)
	assert_false(m.pull_trigger(), "0 hp weapon")


func test_sim_reload_gating() -> void:
	var sim := _sim()
	assert_true(sim.pull_trigger(), "first shot")
	assert_false(sim.pull_trigger(), "reloading")
	assert_eq(sim.result.shells_fired, 1)
	_run(sim, 1.0)
	assert_false(sim.pull_trigger(), "still reloading at 1 s")
	_run(sim, 1.1)
	assert_true(sim.pull_trigger(), "loaded after 2 s")
	assert_eq(sim.result.shells_fired, 2)


func test_salvo_stops_when_ammo_runs_out() -> void:
	var sim := _sim([_weapon(&"mlrs", 10.0, 6, 0.1)], 2)
	assert_true(sim.pull_trigger())
	_run(sim, 1.0)
	assert_eq(sim.result.shells_fired, 2, "only two shells in stock")
	assert_false(sim.selected_mount().is_firing(), "salvo aborted")
	assert_true(sim.selected_mount().reload_left > 0.0, "reload started")


# --- Costs ---

func test_cost_charged_per_shell_with_energy() -> void:
	var sim := _sim([_weapon(&"rail", 1.0, 1, 0.0, 0.0, 100)])
	var fired: Array = []
	var on_fired := func(w: StringName, a: StringName, cost: int) -> void: fired.append([w, a, cost])
	EventBus.shot_fired.connect(on_fired)
	var money := sim.player.money
	sim.pull_trigger()
	EventBus.shot_fired.disconnect(on_fired)
	assert_eq(money - sim.player.money, 130, "shell 30 + energy 100")
	assert_eq(sim.player.ammo_count(&"test_shell"), 9, "one shell consumed")
	assert_eq(sim.result.ammo_spent, 130, "result ammo_spent")
	assert_eq(sim.result.ammo_used.get(&"test_shell", 0), 1, "ammo_used")
	assert_eq(fired, [[&"rail", &"test_shell", 130]], "shot_fired emitted")


func test_each_salvo_shell_is_charged() -> void:
	var sim := _sim([_weapon(&"mlrs", 10.0, 3, 0.2)])
	var money := sim.player.money
	sim.pull_trigger()
	_run(sim, 1.0)
	assert_eq(sim.result.shells_fired, 3)
	assert_eq(money - sim.player.money, 90, "3 x 30")


func test_costs_can_push_funds_negative() -> void:
	var sim := _sim()
	sim.player.money = 10
	assert_true(sim.pull_trigger(), "firing is allowed in debt")
	assert_eq(sim.player.money, -20)


# --- Damage ---

func test_damage_falloff() -> void:
	var a := _ammo()
	var c := BattleRules.CONTACT_RADIUS_M
	assert_near(BattleRules.blast_damage(a, 0.0), 50.0, 1e-6, "direct hit")
	assert_near(BattleRules.blast_damage(a, c), 50.0, 1e-6, "contact")
	assert_near(BattleRules.blast_damage(a, c + 1.0), 25.0, 1e-6, "half way through the blast")
	assert_near(BattleRules.blast_damage(a, c + 2.0), 0.0, 1e-6, "edge of the blast")
	assert_near(BattleRules.blast_damage(a, 10.0), 0.0, 1e-6, "far away")
	assert_true(BattleRules.blast_damage(a, c + 0.5) > BattleRules.blast_damage(a, c + 1.5), "monotonic")
	a.explosion_radius_m = 0.0
	assert_near(BattleRules.blast_damage(a, 0.2), 50.0, 1e-6, "fragment contact")
	assert_near(BattleRules.blast_damage(a, 1.0), 0.0, 1e-6, "fragment miss")


func test_rain_reduces_incendiary_only() -> void:
	var a := _ammo()
	a.rain_penalty = 0.8
	assert_near(BattleRules.blast_damage(a, 0.0, 0.5), 50.0, 1e-6, "kinetic ignores rain")
	a.damage_type = GameConstants.DamageType.INCENDIARY
	assert_near(BattleRules.blast_damage(a, 0.0, 0.5), 30.0, 1e-6, "1 - 0.8 x 0.5")
	assert_near(BattleRules.blast_damage(a, 0.0, 0.0), 50.0, 1e-6, "dry")


func test_blast_damages_targets_with_falloff() -> void:
	var sim := _sim()
	var t0 := sim.targets[0]
	var t1 := sim.targets[1]
	var hits: Array = []
	var destroyed: Array = []
	var on_hit := func(id: StringName, dmg: float) -> void: hits.append([id, dmg])
	var on_destroyed := func(id: StringName) -> void: destroyed.append(id)
	EventBus.target_hit.connect(on_hit)
	EventBus.target_destroyed.connect(on_destroyed)
	var edge := t0.rect_m().position.x
	sim.apply_blast(_ammo(), Vector2(edge - BattleRules.CONTACT_RADIUS_M - 1.0, t0.position_m.y))
	sim.apply_blast(_ammo(), t1.position_m)
	sim.apply_blast(_ammo(), t1.position_m)
	EventBus.target_hit.disconnect(on_hit)
	EventBus.target_destroyed.disconnect(on_destroyed)
	assert_near(t0.health, 75.0, 1e-4, "half damage 1 m into the blast")
	assert_true(t1.is_destroyed(), "two direct hits")
	assert_eq(hits.size(), 3, "target_hit per damaged target")
	assert_eq(destroyed, [t1.id], "target_destroyed once")
	assert_eq(sim.result.targets_destroyed, 1)


func test_enemy_blast_damages_battery() -> void:
	var sim := _sim()
	var m := sim.selected_mount()
	var got: Array = []
	var on_dmg := func(id: StringName, dmg: float) -> void: got.append([id, dmg])
	EventBus.battery_damaged.connect(on_dmg)
	sim.apply_blast(_ammo(), m.position_m, 1.0, true)
	EventBus.battery_damaged.disconnect(on_dmg)
	var expected := 50.0 * BattleSim.ENEMY_DAMAGE_SCALE
	assert_near(m.health, 100.0 - expected, 1e-4, "mount health")
	assert_near(sim.result.damage_taken.get(m.weapon.id, 0.0), expected, 1e-4, "damage_taken")
	assert_eq(got.size(), 1, "battery_damaged emitted")
	assert_near(sim.targets[0].health, 100.0, 1e-6, "enemy blasts don't hurt targets")


func test_live_shot_hits_and_carves() -> void:
	var sim := _sim()
	var target := sim.targets[0]
	_aim_at(sim, target.position_m)
	sim.pull_trigger()
	_run_until_settled(sim)
	assert_true(target.health < target.max_health, "target damaged")
	assert_eq(sim.result.shells_hit, 1, "shell counted as a hit")
	# A shell into open ground digs a crater.
	_run(sim, 2.5)
	_aim_at(sim, sim.battery_position_m() + Vector2(60.0, 10.0))
	var solid_before := sim.map.solid_cell_count()
	sim.pull_trigger()
	_run_until_settled(sim)
	assert_true(sim.map.solid_cell_count() < solid_before, "crater carved")


# --- Counter-battery ---

func test_reveal_grows_more_on_misses() -> void:
	var sim := _sim()
	var revealed: Array = []
	var on_rev := func(level: float) -> void: revealed.append(level)
	EventBus.battery_revealed.connect(on_rev)
	# A hit: only the per-shot reveal.
	_aim_at(sim, sim.targets[0].position_m)
	sim.pull_trigger()
	_run_until_settled(sim)
	assert_near(sim.reveal_level, BattleRules.REVEAL_PER_SHOT, 1e-6, "hit")
	# A miss: lob it well short.
	_run(sim, 2.5)
	_aim_at(sim, sim.battery_position_m() + Vector2(60.0, 10.0))
	sim.pull_trigger()
	_run_until_settled(sim)
	EventBus.battery_revealed.disconnect(on_rev)
	assert_near(sim.reveal_level, BattleRules.REVEAL_PER_SHOT * 2.0 + BattleRules.REVEAL_PER_MISS, 1e-6, "miss")
	assert_eq(sim.result.shells_hit, 1)
	assert_eq(revealed.size(), 3, "battery_revealed on each change")


func test_reveal_is_capped() -> void:
	var level := 0.0
	for i in 40:
		level = BattleRules.reveal_after_miss(BattleRules.reveal_after_shot(level))
	assert_near(level, 1.0, 1e-6)


func test_enemy_error_shrinks_with_reveal_and_difficulty() -> void:
	var e0 := SimpleEnemyBrain.error_radius_m(0.0, 1)
	var e5 := SimpleEnemyBrain.error_radius_m(0.5, 1)
	var e1 := SimpleEnemyBrain.error_radius_m(1.0, 1)
	assert_true(e0 > e5 and e5 > e1, "reveal sharpens aim: %f %f %f" % [e0, e5, e1])
	assert_true(SimpleEnemyBrain.error_radius_m(0.5, 5) < e5, "difficulty sharpens aim")


func test_enemy_holds_fire_until_revealed_then_aims() -> void:
	var brain := SimpleEnemyBrain.new()
	var s := EnemyBrain.Situation.new()
	s.weapon = _weapon()
	s.ammo = _ammo()
	s.origin_m = Vector2(300.0, -2.0)
	s.battery_positions_m = [Vector2(80.0, -10.0)]
	s.weather = WeatherState.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	assert_true(brain.plan_shot(s, rng).is_empty(), "unrevealed battery")
	s.reveal_level = 1.0
	var plan := brain.plan_shot(s, rng)
	assert_false(plan.is_empty(), "fires once revealed")
	assert_eq(plan.get("facing"), -1, "toward the battery")
	var p := ShotParams.create(s.weapon, s.ammo, plan.elevation_deg, plan.charge, s.origin_m, -1, s.weather, null)
	var landing := Ballistics.simulate_shot(p, Ballistics.flat_ground(-10.0)).end_point_m
	assert_true(absf(landing.x - 80.0) <= SimpleEnemyBrain.error_radius_m(1.0, 1) + 1.0,
		"lands within the error radius: %s" % landing)


func test_enemy_fires_back_in_battle() -> void:
	var sim := _sim()
	sim.enemy_brain = SimpleEnemyBrain.new()
	sim.reveal_level = 1.0
	var launched: Array = []
	sim.shell_launched.connect(func(_f: ShellFlight, enemy: bool) -> void: launched.append(enemy))
	_run(sim, sim.enemy_reload_left + 0.1)
	assert_true(launched.has(true), "enemy shell launched")


# --- Orbital ---

func test_orbital_strike_is_delayed_and_lands_on_designation() -> void:
	var w := _weapon(&"orbital", 1.0)
	w.launcher_type = GameConstants.LauncherType.ORBITAL
	w.muzzle_velocity_min = 900.0
	w.muzzle_velocity_max = 900.0
	var sim := _sim([w])
	var m := sim.selected_mount()
	var target := sim.targets[1]
	m.designated_x_m = target.position_m.x
	assert_true(sim.pull_trigger())
	assert_eq(sim.strikes.size(), 1, "strike pending")
	assert_true(sim.flights.is_empty(), "nothing launched yet")
	assert_near(sim.reveal_level, 0.0, 1e-6, "orbital fire doesn't reveal the battery")
	_run(sim, BattleSim.ORBITAL_DELAY_S - 0.1)
	assert_true(sim.flights.is_empty(), "still waiting")
	_run(sim, 0.2)
	assert_eq(sim.flights.size(), 1, "rod dropped")
	_run_until_settled(sim)
	assert_true(target.health < target.max_health, "designated target hit")
	assert_near(sim.targets[0].health, sim.targets[0].max_health, 1e-6, "other target untouched")


# --- End conditions ---

func test_victory_when_all_targets_destroyed() -> void:
	var sim := _sim()
	for t in sim.targets:
		t.apply_damage(t.max_health)
	sim.tick(STEP)
	assert_eq(sim.outcome, BattleSim.Outcome.VICTORY)
	assert_true(sim.result.victory)
	assert_eq(sim.result.payout_earned, 1000)


func test_defeat_when_battery_destroyed() -> void:
	var sim := _sim()
	sim.selected_mount().health = 0.0
	sim.tick(STEP)
	assert_eq(sim.outcome, BattleSim.Outcome.DEFEAT)
	assert_eq(sim.end_reason, "Battery destroyed")
	assert_eq(sim.result.payout_earned, 0)


func test_defeat_when_time_runs_out() -> void:
	var plot := _plot()
	var sim := _sim([], 10, _contract(plot, 2, 100.0, 3.0))
	_run(sim, 2.9)
	assert_eq(sim.outcome, BattleSim.Outcome.NONE, "time left")
	_run(sim, 0.2)
	assert_eq(sim.outcome, BattleSim.Outcome.DEFEAT)
	assert_eq(sim.end_reason, "Time limit expired")
	assert_near(sim.result.duration_s, 3.0, 0.05, "duration")


func test_defeat_when_out_of_ammo_after_last_shell_lands() -> void:
	var sim := _sim([], 1)
	_aim_at(sim, sim.battery_position_m() + Vector2(60.0, 10.0))
	sim.pull_trigger()
	sim.tick(STEP)
	assert_eq(sim.outcome, BattleSim.Outcome.NONE, "shell still flying")
	_run(sim, 20.0)
	assert_eq(sim.outcome, BattleSim.Outcome.DEFEAT)
	assert_eq(sim.end_reason, "Out of ammunition")


func test_retreat_is_defeat() -> void:
	var sim := _sim()
	sim.retreat()
	assert_eq(sim.outcome, BattleSim.Outcome.DEFEAT)
	assert_false(sim.pull_trigger(), "no firing after the end")


# --- Setup ---

func test_layout_from_plot_and_contract() -> void:
	var sim := _sim([_weapon(&"a"), _weapon(&"b")])
	assert_eq(sim.targets.size(), 2, "target_count")
	assert_near(sim.targets[0].health, 100.0, 1e-6, "target_health")
	assert_eq(sim.mounts.size(), 2, "one mount per owned weapon")
	var battery := sim.battery_position_m()
	for m in sim.mounts:
		assert_true(absf(m.position_m.x - battery.x) <= TerrainGenerator.BATTERY_PAD_HALF_M, "on the pad")
		assert_near(m.position_m.y, battery.y, 0.3, "on the ground")


func test_weather_density_drops_with_altitude() -> void:
	var plot := _plot()
	plot.altitude_m = 2000.0
	var c := _contract(plot)
	c.weather.wind_speed = -4.0
	var w := BattleRules.battle_weather(c, plot)
	assert_near(w.air_density, GameConstants.SEA_LEVEL_AIR_DENSITY * exp(-2000.0 / 8500.0), 1e-4)
	assert_near(w.wind_speed, -4.0, 1e-6, "wind copied")
	assert_near(c.weather.air_density, GameConstants.SEA_LEVEL_AIR_DENSITY, 1e-6, "contract untouched")


func test_same_seed_same_battle() -> void:
	var healths: Array = []
	for run in 2:
		var sim := _sim()
		_aim_at(sim, sim.targets[0].position_m + Vector2(3.0, 0.0))
		sim.pull_trigger()
		_run(sim, 6.0)
		healths.append([sim.targets[0].health, sim.targets[1].health, sim.map.cells_hash(), sim.reveal_level])
	assert_eq(healths[0], healths[1], "deterministic")


func test_every_content_weapon_and_ammo_fires() -> void:
	var plot := _plot()
	plot.target_distance_m = 400.0
	for wid in DataRegistry.weapons:
		var w: WeaponData = DataRegistry.weapons[wid]
		for aid in w.allowed_ammo:
			var player := PlayerState.new()
			player.add_weapon(w)
			player.add_ammo(aid, 10)
			var c := _contract(plot)
			c.era_required = w.era
			var sim := BattleSim.new(c, plot, player, TerrainGenerator.generate(plot), SEED)
			sim.enemy_brain = null
			var m := sim.selected_mount()
			m.ammo_id = aid
			m.designated_x_m = sim.targets[0].position_m.x
			assert_true(sim.pull_trigger(), "%s fires %s" % [wid, aid])
			_run(sim, maxf(w.salvo_size * w.salvo_interval, 0.0) + BattleSim.ORBITAL_DELAY_S + 0.5)
			_run_until_settled(sim, 60.0)
			assert_eq(sim.result.shells_fired, maxi(w.salvo_size, 1), "%s/%s salvo" % [wid, aid])
			assert_false(sim.player_shots_pending(), "%s/%s settled" % [wid, aid])
			assert_eq(sim.result.ammo_spent, maxi(w.salvo_size, 1) * (DataRegistry.get_ammo(aid).cost_per_shell
				+ w.energy_cost_per_shot), "%s/%s cost" % [wid, aid])
