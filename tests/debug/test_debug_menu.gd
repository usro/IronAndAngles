extends TestCase
## The debug menu's cheats change the campaign through the normal models.


func before_each() -> void:
	SaveSystem.stop_autosave()
	GameState.new_game(21)


func test_money_and_era_cheats() -> void:
	var start := GameState.player.money
	DebugMenu._add_money(10000)
	assert_eq(GameState.player.money, start + 10000)
	DebugMenu._advance_era()
	assert_eq(GameState.player.current_era, GameConstants.Era.INDUSTRIAL)
	assert_true(GameState.player.unlocked_tech.has(&"rifling"), "gate researched")
	for pre in DataRegistry.get_tech(&"rifling").prerequisites:
		assert_true(GameState.player.unlocked_tech.has(pre), "prerequisite %s researched" % pre)
	DebugMenu._unlock_all_tech()
	assert_eq(GameState.player.unlocked_tech.size(), DataRegistry.tech.size())
	assert_eq(GameState.player.current_era, GameConstants.Era.EXPERIMENTAL)


func test_weapon_and_ammo_cheats() -> void:
	DebugMenu._give_era_weapons(true)
	assert_eq(GameState.player.owned_weapons.size(), DataRegistry.weapons.size())
	assert_true(GameState.player.ammo_count(&"stone_ball") >= 50, "ammo refilled")


func test_quick_battle_and_win_now() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	DebugMenu._quick_battle()
	for i in 6:
		await tree.process_frame
	var sim: BattleSim = DebugMenu._sim()
	assert_not_null(sim, "in a battle")
	if sim == null:
		return
	assert_true(GameState.current_contract.template_id != &"", "on a generated contract")
	DebugMenu.god_mode = true
	await tree.process_frame
	assert_eq(sim.enemy_damage_scale, 0.0, "god mode applied")
	DebugMenu.god_mode = false
	DebugMenu._battle_win()
	await tree.process_frame
	await tree.process_frame
	assert_eq(sim.outcome, BattleSim.Outcome.VICTORY)
	assert_eq(sim.result.targets_destroyed, sim.targets.size(), "kills counted")
	tree.change_scene_to_file("res://scenes/menu/main_menu.tscn")
	for i in 3:
		await tree.process_frame
