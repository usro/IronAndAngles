extends TestCase
## Autosave follows the active campaign and never writes before one is started or loaded.

const SLOT := 98


func before_each() -> void:
	SaveSystem.delete_save(SLOT)
	SaveSystem.stop_autosave()


func _saved_money() -> int:
	var path := SaveSystem.SAVE_DIR.path_join("slot_%d.json" % SLOT)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return int(parsed["player"]["money"]) if parsed is Dictionary else -1


func test_no_autosave_without_active_campaign() -> void:
	GameState.new_game(1)
	GameState.player.earn(100, "test")
	await (Engine.get_main_loop() as SceneTree).process_frame
	assert_false(SaveSystem.has_save(SLOT), "nothing written while inactive")


func test_new_campaign_saves_immediately_and_follows_changes() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	SaveSystem.start_new_campaign(SLOT)
	assert_true(SaveSystem.has_save(SLOT), "saved on start")
	var start := GameState.player.money
	GameState.player.earn(777, "test")
	GameState.player.spend(77, "test")
	await tree.process_frame
	assert_eq(_saved_money(), start + 700, "money change autosaved")
	SaveSystem.delete_save(SLOT)
	assert_eq(SaveSystem.active_slot, -1, "deleting the active slot stops autosave")


func test_loaded_campaign_autosaves_to_its_slot() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	GameState.new_game(4)
	SaveSystem.save_game(SLOT)
	GameState.new_game(5)
	assert_eq(SaveSystem.load_game(SLOT), OK)
	assert_eq(SaveSystem.active_slot, SLOT)
	GameState.player.unlocked_tech.append(&"early_mortar")
	EventBus.tech_unlocked.emit(&"early_mortar")
	await tree.process_frame
	assert_eq(SaveSystem.load_game(SLOT), OK)
	assert_true(GameState.player.unlocked_tech.has(&"early_mortar"), "research autosaved")
	SaveSystem.delete_save(SLOT)


func test_save_is_written_atomically() -> void:
	GameState.new_game(6)
	assert_eq(SaveSystem.save_game(SLOT), OK)
	assert_false(FileAccess.file_exists(SaveSystem.SAVE_DIR.path_join("slot_%d.json.tmp" % SLOT)), "no temp left")
	SaveSystem.delete_save(SLOT)
