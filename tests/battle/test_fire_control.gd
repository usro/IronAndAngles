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


## Every in-range card entry agrees with Ballistics.predict (still air) to within 3%.
func test_firing_table_matches_ballistics() -> void:
	for pair in [[&"trebuchet", &"stone_ball"], [&"sp_howitzer", &"he_155"], [&"mlrs_launcher", &"rocket_he"]]:
		var w := DataRegistry.get_weapon(pair[0])
		var a := DataRegistry.get_ammo(pair[1])
		var calm := WeatherState.new()
		var table := FiringTable.build(w, a, calm, 0.0, 300.0)
		var checked := 0
		for r in range(0, table.elevations.size(), 3):
			for c in [1, 3]:
				var d: float = table.distances[r][c]
				if is_nan(d):
					continue
				var p := ShotParams.create(w, a, table.elevations[r], FiringTable.CHARGES[c], Vector2.ZERO, 1, calm, null)
				p.stop_at_first_contact = true  # the card gives first contact, not where a bouncing ball stops
				var t := Ballistics.predict(p, Ballistics.flat_ground(0.0))
				assert_near(d, t.impact_point_m().x, maxf(2.0, t.impact_point_m().x * 0.03),
					"%s %.0f° %.0f%%" % [w.id, table.elevations[r], FiringTable.CHARGES[c] * 100.0])
				checked += 1
		assert_true(checked >= 4, "%s: checked %d entries" % [w.id, checked])


func test_direct_fire_card_lists_elevations_around_the_zone() -> void:
	var w := DataRegistry.get_weapon(&"railgun")
	var table := FiringTable.build(w, DataRegistry.get_ammo(&"tungsten_slug"), WeatherState.new(), 0.0, 2200.0)
	assert_true(table.direct_fire)
	assert_eq(table.direct_distances.size(), FiringTable.DIRECT_ROWS)
	for i in range(1, table.direct_elevations.size()):
		assert_true(table.direct_elevations[i] > table.direct_elevations[i - 1], "farther needs higher elevation")


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
