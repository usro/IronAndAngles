extends TestCase
## Forward-observer calls and shoot-and-scoot.

const Battle := preload("res://scripts/battle/battle.gd")


func _sim() -> BattleSim:
	var contract: ContractData = DataRegistry.get_contract(&"siege_of_aldmoor")
	var p := PlayerState.new()
	p.add_weapon(DataRegistry.get_weapon(&"trebuchet"))
	p.add_ammo(&"stone_ball", 30)
	var sim := BattleSim.new(contract, contract.plots[0], p, TerrainGenerator.generate(contract.plots[0]), 4)
	sim.enemy_brain = null
	return sim


func test_observer_calls_short_over_and_hits() -> void:
	var sim := _sim()
	var t := sim.targets[0].rect_m().get_center()
	assert_eq(Battle.observer_call(sim, t + Vector2(-41, 0), false), "SHORT 40 m")
	var last := sim.targets[sim.targets.size() - 1].rect_m().get_center()
	assert_eq(Battle.observer_call(sim, last + Vector2(23, 0), false), "OVER 25 m", "past the farthest target")
	assert_eq(Battle.observer_call(sim, t + Vector2(1, 0), false), "ON LINE, CLOSE")
	assert_eq(Battle.observer_call(sim, t, true), "TARGET HIT")


func test_each_shell_is_observed_once_at_first_contact() -> void:
	var sim := _sim()
	var seen: Array = []
	sim.shell_observed.connect(func(pos: Vector2, hit: bool) -> void: seen.append([pos, hit]))
	var m := sim.selected_mount()
	m.elevation_deg = 45.0
	m.charge = 1.0
	sim.pull_trigger()
	for i in 900:
		sim.tick(1.0 / 60.0)
		if not sim.player_shots_pending():
			break
	assert_eq(seen.size(), 1, "one report per shell, even though stone balls bounce")


func test_relocate_silences_hides_and_cools_down() -> void:
	var sim := _sim()
	sim.reveal_level = 0.8
	var before := sim.mounts[0].position_m.x
	assert_true(sim.relocate())
	assert_near(sim.reveal_level, 0.8 * BattleSim.RELOCATE_REVEAL_KEEP, 1e-5, "enemy loses most of its fix")
	assert_near(absf(sim.mounts[0].position_m.x - before), BattleSim.RELOCATE_SHIFT_M, 0.01, "guns moved")
	assert_false(sim.pull_trigger(), "no firing while moving")
	assert_false(sim.relocate(), "can't relocate again right away")
	for i in int(BattleSim.RELOCATE_S * 10) + 2:
		sim.tick(0.1)
	assert_true(sim.pull_trigger(), "back in action after relocating")
	assert_false(sim.can_relocate(), "still cooling down")
	for i in int(BattleSim.RELOCATE_COOLDOWN_S * 10):
		sim.tick(0.1)
	assert_true(sim.can_relocate(), "ready again after the cooldown")
