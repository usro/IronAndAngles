extends TestCase
## The battle scene itself, headless: builds from GameState's contract and plot, fires, ends.


func test_scene_builds_and_fires_with_real_content() -> void:
	GameState.new_game(11)
	var contract := DataRegistry.get_contract(&"siege_of_aldmoor")
	assert_not_null(contract, "content contract")
	if contract == null:
		return
	GameState.current_contract = contract
	GameState.current_plot = contract.plots[0]
	var tree := Engine.get_main_loop() as SceneTree
	var scene: Node = load("res://scenes/battle/battle.tscn").instantiate()
	tree.root.add_child(scene)
	for i in 3:
		await tree.process_frame
	var sim: BattleSim = scene.get("sim")
	assert_not_null(sim, "sim created")
	assert_eq(sim.targets.size(), contract.target_count, "targets from contract")
	assert_near(sim.targets[0].health, contract.target_health, 1e-6, "target health")
	assert_eq(sim.mounts[0].weapon.id, &"trebuchet", "starting kit on the pad")
	assert_eq(sim.mounts[0].ammo_id, &"stone_ball", "stocked ammo selected")
	assert_not_null(sim.enemy_weapon, "defender has a gun")
	var money := GameState.player.money
	assert_true(sim.pull_trigger(), "fires")
	assert_eq(GameState.player.money, money - 25, "stone ball charged")
	for i in 10:
		await tree.process_frame
	assert_true(sim.elapsed > 0.0, "battle clock runs")
	for k in ["aim_up", "aim_down", "charge_up", "charge_down", "fire", "next_weapon", "next_ammo",
			"fine_adjust", "toggle_overview", "retreat"]:
		assert_true(InputMap.has_action(k), "input action %s" % k)
	scene.free()
	GameState.new_game()
