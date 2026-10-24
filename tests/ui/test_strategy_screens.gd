extends TestCase
## Smoke tests for the strategy-side screens: research overlay and results breakdown.


func test_research_panel_unlocks_a_node() -> void:
	GameState.new_game(5)
	GameState.player.money = 100000
	var tree := Engine.get_main_loop() as SceneTree
	var map: Control = load("res://scenes/strategy/region_map.tscn").instantiate()
	tree.root.add_child(map)
	await tree.process_frame
	map._open_research()
	await tree.process_frame
	var panels := map.get_children().filter(func(c): return c is TechTreePanel)
	assert_eq(panels.size(), 1, "research panel opened")
	if panels.size() == 1:
		var panel: TechTreePanel = panels[0]
		var ids := panel._tree.unlockable_ids()
		assert_false(ids.is_empty(), "something is researchable at the start")
		if not ids.is_empty():
			var before := GameState.player.money
			panel._unlock(ids[0])
			assert_true(GameState.player.unlocked_tech.has(ids[0]), "node unlocked")
			assert_true(GameState.player.money < before, "research cost paid")
		panel.queue_free()
	await tree.process_frame
	map.queue_free()
	await tree.process_frame


func test_results_screen_shows_settlement() -> void:
	GameState.new_game(6)
	var r := BattleResult.new()
	r.contract_id = &"siege_of_aldmoor"
	r.victory = true
	r.payout_earned = 1500
	r.shells_fired = 4
	r.shells_hit = 3
	GameState.apply_battle_result(r)
	var tree := Engine.get_main_loop() as SceneTree
	var screen: Control = load("res://scenes/results/results.tscn").instantiate()
	tree.root.add_child(screen)
	await tree.process_frame
	var texts := _label_texts(screen)
	assert_true(texts.has("Payout") and texts.has("+1,500"), "payout line")
	assert_true(texts.any(func(t): return t.contains("75% accuracy")), "accuracy line")
	screen.queue_free()
	await tree.process_frame


func _label_texts(node: Node) -> Array:
	var out := []
	for child in node.get_children():
		if child is Label:
			out.append(child.text)
		out.append_array(_label_texts(child))
	return out
