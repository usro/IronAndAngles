extends TestCase
## Experimental-era fixes: railguns need line of sight, defenders lob, railgun dials are finer.


func _exp_ranges() -> PlotGenerator.EraRanges:
	return PlotGenerator.EraRanges.for_era(GameConstants.Era.EXPERIMENTAL, DataRegistry.contracts.values())


func test_downhill_s_curve_blocks_a_flat_shot() -> void:
	var downhill := PlotData.new()
	downhill.target_distance_m = 2200.0
	downhill.height_advantage_m = 50.0
	assert_false(TerrainGenerator.has_line_of_sight(downhill), "rounded shoulder below the pad blocks it")
	var level := PlotData.new()
	level.target_distance_m = 2200.0
	assert_true(TerrainGenerator.has_line_of_sight(level), "level flat ground is clear")


func test_generated_railgun_plots_have_line_of_sight() -> void:
	var lo := PlotGenerator.reference_loadout(GameConstants.Era.EXPERIMENTAL, DataRegistry.weapons, DataRegistry.ammo)
	assert_true(PlotGenerator.is_direct_fire(lo[0]), "experimental reference weapon is a railgun")
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for i in 40:
		var p := PlotGenerator.generate(_exp_ranges(), lo, rng, i)
		assert_true(TerrainGenerator.has_line_of_sight(p), "%s (%s, %+.0f m) blocked" % [p.display_name,
			GameConstants.TerrainProfile.keys()[p.terrain_profile], p.height_advantage_m])


func test_railgun_actually_hits_on_a_generated_plot() -> void:
	var lo := PlotGenerator.reference_loadout(GameConstants.Era.EXPERIMENTAL, DataRegistry.weapons, DataRegistry.ammo)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var plot := PlotGenerator.generate(_exp_ranges(), lo, rng, 1)
	var contract: ContractData = DataRegistry.get_contract(&"citadel_zero").duplicate()
	contract.plots = [plot]
	var p := PlayerState.new()
	p.current_era = GameConstants.Era.EXPERIMENTAL
	p.add_weapon(lo[0])
	p.add_ammo(lo[1].id, 20)
	var sim := BattleSim.new(contract, plot, p, TerrainGenerator.generate(plot), 5)
	sim.enemy_brain = null
	for shot in 6:
		var m := sim.selected_mount()
		var tg: Vector2 = Vector2.INF
		for t in sim.targets:
			if not t.is_destroyed():
				tg = t.rect_m().get_center()
				break
		var aim := AimSolver.solve(m.weapon, sim.ammo_table[m.ammo_id], m.muzzle_m(), tg, sim.weather)
		m.elevation_deg = aim.elevation_deg
		m.charge = aim.charge
		m.reload_left = 0.0
		m.salvo_left = 0
		sim.pull_trigger()
		for i in 120:
			sim.tick(1.0 / 60.0)
	assert_true(sim.result.shells_hit >= 4, "railgun hit %d of 6 with nominal aim" % sim.result.shells_hit)


func test_defender_lobs_and_reaches() -> void:
	var lo := PlotGenerator.reference_loadout(GameConstants.Era.EXPERIMENTAL, DataRegistry.weapons, DataRegistry.ammo)
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	for i in 8:
		var plot := PlotGenerator.generate(_exp_ranges(), lo, rng, i)
		var contract: ContractData = DataRegistry.get_contract(&"citadel_zero").duplicate()
		contract.plots = [plot]
		var p := PlayerState.new()
		p.add_weapon(lo[0])
		var sim := BattleSim.new(contract, plot, p, TerrainGenerator.generate(plot), i)
		assert_not_null(sim.enemy_weapon, "a defender gun")
		assert_false(sim.enemy_weapon.is_direct_fire(), "defender lobs")
		assert_true(sim.enemy_weapon.launcher_type != GameConstants.LauncherType.ORBITAL)


func test_railgun_dial_is_ten_times_finer() -> void:
	var m := WeaponMount.new(DataRegistry.get_weapon(&"railgun"), Vector2.ZERO, 400.0)
	assert_near(m.elevation_scale(), 0.1)
	var h := WeaponMount.new(DataRegistry.get_weapon(&"sp_howitzer"), Vector2.ZERO, 450.0)
	assert_near(h.elevation_scale(), 1.0)
