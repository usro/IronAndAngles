extends TestCase
## Pre-launch features: pause menu, settings, campaign goal and ending, tutorial tips.


func before_each() -> void:
	SaveSystem.stop_autosave()


func _battle(tree: SceneTree, seed_value: int) -> Node:
	GameState.new_game(seed_value)
	DebugMenu._quick_battle()
	for i in 8:
		await tree.process_frame
	return tree.current_scene


func test_esc_pauses_and_retreat_needs_confirmation() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var battle: Node = await _battle(tree, 2101)
	var esc := InputEventAction.new()
	esc.action = &"retreat"
	esc.pressed = true
	battle._unhandled_input(esc)
	await tree.process_frame
	assert_true(tree.paused, "Esc pauses the battle")
	assert_eq(battle.sim.outcome, BattleSim.Outcome.NONE, "no retreat without confirming")
	var menu: PauseMenu = battle.hud.find_children("*", "PauseMenu", true, false)[0]
	menu.close_sheet()
	await tree.process_frame
	assert_false(tree.paused, "Resume unpauses")
	tree.change_scene_to_file("res://scenes/menu/main_menu.tscn")
	await tree.process_frame


func test_rebind_and_reset_keys() -> void:
	var before := Settings.primary_key(&"fire")
	Settings.rebind(&"fire", KEY_K)
	assert_eq(Settings.primary_key(&"fire"), KEY_K)
	assert_true(Settings.key_name(&"fire").contains("K"))
	Settings.reset_bindings()
	assert_eq(Settings.primary_key(&"fire"), before, "defaults restored")


func test_campaign_goal_counts_experimental_wins_once() -> void:
	GameState.new_game(2102)
	var p := GameState.player
	assert_false(CampaignGoal.is_met(p))
	var exp_contract: ContractData = DataRegistry.contracts.values().filter(
		func(c: ContractData) -> bool: return c.era_required == CampaignGoal.GOAL_ERA)[0]
	for i in CampaignGoal.GOAL_WINS:
		var r := BattleResult.new()
		r.contract_id = exp_contract.id
		r.victory = true
		GameState.apply_battle_result(r)
	assert_eq(CampaignGoal.progress(p), CampaignGoal.GOAL_WINS)
	assert_true(CampaignGoal.claim_ending(p), "ending fires the first time")
	assert_false(CampaignGoal.claim_ending(p), "and only once")
	var q := PlayerState.from_dict(JSON.parse_string(JSON.stringify(p.to_dict())))
	assert_true(q.campaign_complete, "saved")
	assert_eq(CampaignGoal.progress(q), CampaignGoal.GOAL_WINS)


func test_tips_show_once_and_respect_the_setting() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	Settings.reset_tips()
	Settings.tips_enabled = true
	var battle: Node = await _battle(tree, 2103)
	var tips: TutorialTips = battle.hud.find_children("*", "TutorialTips", true, false)[0]
	await tree.process_frame
	assert_true(tips.visible, "welcome tip shows")
	assert_true(Settings.tips_seen.has("welcome"))
	Settings.tips_enabled = false
	await tree.process_frame
	assert_false(tips.visible, "tips can be switched off")
	Settings.tips_enabled = true
	tree.change_scene_to_file("res://scenes/menu/main_menu.tscn")
	await tree.process_frame


func test_ending_and_credits_build() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	GameState.new_game(2104)
	var ending: Control = load("res://scenes/ending/ending.tscn").instantiate()
	tree.root.add_child(ending)
	await tree.process_frame
	var sheet := Credits.Sheet.new()
	tree.root.add_child(sheet)
	await tree.process_frame
	assert_true(sheet.content.get_child_count() > 3, "credits listed")
	ending.queue_free()
	sheet.queue_free()
	await tree.process_frame
