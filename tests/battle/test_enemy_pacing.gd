extends TestCase
## The defender must fire slower than the player's own gun, or a perfect player still loses.


func _sim(difficulty: int) -> BattleSim:
	var contract: ContractData = DataRegistry.get_contract(&"siege_of_aldmoor").duplicate()
	contract.difficulty = difficulty
	var plot: PlotData = contract.plots[0]
	var player := PlayerState.new()
	player.add_weapon(DataRegistry.get_weapon(&"trebuchet"))
	return BattleSim.new(contract, plot, player, TerrainGenerator.generate(plot), 1)


func test_enemy_reloads_slower_than_rated_and_speeds_up_with_difficulty() -> void:
	var easy := _sim(1)
	var hard := _sim(5)
	var rated := easy.enemy_weapon.reload_time + easy.enemy_weapon.cooldown
	assert_near(easy.enemy_reload_time(), rated * BattleSim.ENEMY_RELOAD_FACTOR, 1e-3, "difficulty 1")
	assert_true(hard.enemy_reload_time() < easy.enemy_reload_time(), "harder contracts fire faster")
	assert_true(hard.enemy_reload_time() >= rated, "never faster than the weapon's rating")
