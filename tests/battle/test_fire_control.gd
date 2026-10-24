extends TestCase
## Firing table matches the real ballistics; the fire-control computer is locked until researched
## and its solution lands.


func _sim(weapon_id: StringName, ammo_id: StringName, contract_id := &"siege_of_aldmoor") -> BattleSim:
	var contract: ContractData = DataRegistry.get_contract(contract_id)
	var p := PlayerState.new()
	p.add_weapon(DataRegistry.get_weapon(weapon_id))
	p.add_ammo(ammo_id, 20)
	var sim := BattleSim.new(contract, contract.plots[0], p, TerrainGenerator.generate(contract.plots[0]), 2)
	sim.enemy_brain = null
	return sim


## Table rows agree with Ballistics.predict (still air, first contact) at both angles, to 3%.
func test_firing_table_matches_ballistics() -> void:
	var calm := WeatherState.new()
	for pair in [[&"trebuchet", &"stone_ball", 3], [&"sp_howitzer", &"he_155", 2], [&"mlrs_launcher", &"rocket_he", 4]]:
		var w := DataRegistry.get_weapon(pair[0])
		var a := DataRegistry.get_ammo(pair[1])
		var inc := ChargeIncrements.for_weapon(w)
		var charge := inc[mini(pair[2], inc.size() - 1)]
		var table := FiringTable.build(w, a, calm, charge, 0.0)
		assert_true(table.ranges.size() >= 4, "%s: %d rows" % [w.id, table.ranges.size()])
		var checked := 0
		for i in range(0, table.ranges.size(), 2):
			for elev in [table.low_elevations[i], table.high_elevations[i]]:
				if is_nan(elev):
					continue
				var p := ShotParams.create(w, a, elev, charge, Vector2.ZERO, 1, calm, null)
				p.stop_at_first_contact = true  # the table gives first contact, not where a bouncing ball stops
				var t := Ballistics.predict(p, Ballistics.flat_ground(0.0))
				assert_near(t.impact_point_m().x, table.ranges[i], maxf(2.0, table.ranges[i] * 0.03),
					"%s charge %.2f %.1f°" % [w.id, charge, elev])
				checked += 1
		assert_true(checked >= 4, "%s: checked %d entries" % [w.id, checked])


func test_table_tof_and_wind_drift_make_sense() -> void:
	var w := DataRegistry.get_weapon(&"trebuchet")
	var table := FiringTable.build(w, DataRegistry.get_ammo(&"stone_ball"), WeatherState.new(), 1.0, 0.0)
	for i in range(1, table.ranges.size()):
		if not is_nan(table.low_tof[i]) and not is_nan(table.low_tof[i - 1]):
			assert_true(table.low_tof[i] >= table.low_tof[i - 1] - 0.05, "farther takes longer at low angle")
	var last := table.ranges.size() - 1
	assert_true(table.low_wind_drift[last] > 0.0, "a tailwind carries the shot farther")
	assert_true(table.high_wind_drift[0] > 0.0, "at the high angle too")
	var s := table.solve(table.ranges[last], false)
	assert_near(s.x, table.low_elevations[last], 0.01, "solve() reads the same row")


func test_direct_fire_table_lists_low_angle_only() -> void:
	var w := DataRegistry.get_weapon(&"railgun")
	var table := FiringTable.build(w, DataRegistry.get_ammo(&"tungsten_slug"), WeatherState.new(), 0.5, 0.0)
	assert_true(table.direct_fire)
	assert_true(table.ranges.size() >= 6)
	for i in range(1, table.ranges.size()):
		if not is_nan(table.low_elevations[i]) and not is_nan(table.low_elevations[i - 1]):
			assert_true(table.low_elevations[i] > table.low_elevations[i - 1], "farther needs higher elevation")
		assert_true(is_nan(table.high_elevations[i]), "no high angle for a railgun")


func test_solver_at_fixed_charge_lands() -> void:
	var w := DataRegistry.get_weapon(&"sp_howitzer")
	var a := DataRegistry.get_ammo(&"he_155")
	for arc in [AimSolver.Arc.LOW, AimSolver.Arc.HIGH]:
		var r := AimSolver.solve_at_charge(w, a, Vector2(0, -10), Vector2(1100, 0), WeatherState.new(), 0.75, arc)
		assert_true(r.ok, "arc %d miss %.1f" % [arc, r.miss_m])
		assert_near(r.charge, 0.75)


func test_computer_is_locked_until_researched() -> void:
	var sim := _sim(&"trebuchet", &"stone_ball")
	var panel := FiringTablePanel.new()
	panel.sim = sim
	assert_false(FireControl.is_unlocked(sim.player))
	assert_false(panel.apply_nearest(), "locked")
	sim.player.unlocked_tech.append(FireControl.TECH_ID)
	assert_true(panel.apply_nearest(), "unlocked")
	panel.free()


func test_computer_solution_hits() -> void:
	var sim := _sim(&"trebuchet", &"stone_ball")
	sim.player.unlocked_tech.append(FireControl.TECH_ID)
	var m := sim.selected_mount()
	var hits := 0
	for shot in 4:
		var target := Vector2.INF
		for t in sim.targets:
			if not t.is_destroyed():
				target = t.rect_m().get_center()
				break
		FireControl.apply(m, FireControl.solve(sim, m, target))
		m.reload_left = 0.0
		sim.pull_trigger()
		for i in 600:
			sim.tick(1.0 / 60.0)
			if not sim.player_shots_pending():
				break
	hits = sim.result.shells_hit
	assert_true(hits >= 2, "computer-aimed trebuchet hit %d of 4 (spread and bounces remain)" % hits)
	assert_near(m.charge, m.increments()[m.charge_increment()], 1e-5, "the computer picks a real propellant increment")


## Every gun's charge bands overlap: no distance between its shortest and longest shot is unreachable.
func test_every_weapon_has_gapless_charges() -> void:
	for w: WeaponData in DataRegistry.weapons.values():
		var inc := ChargeIncrements.for_weapon(w)
		assert_true(inc.size() >= ChargeIncrements.MIN_COUNT, "%s: %d charges" % [w.id, inc.size()])
		for i in range(1, inc.size()):
			assert_true(inc[i] > inc[i - 1], "%s increments ascend" % w.id)
		if w.is_direct_fire() or w.launcher_type == GameConstants.LauncherType.ORBITAL:
			continue
		assert_true(ChargeIncrements._covers(w, DataRegistry.get_ammo(w.allowed_ammo[0]), inc),
			"%s has a range gap with %d charges" % [w.id, inc.size()])
		print("     charges: %s = %d" % [w.id, inc.size()])
