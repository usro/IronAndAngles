extends TestCase
## AudioDirector: EventBus facts become sounds, delayed and shaped by distance. Headless, so the
## director runs on the dummy driver and only logs what it would play (`played`).


func before_each() -> void:
	AudioDirector.reset()


func _ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for p in AudioDirector.played:
		out.append(p.id)
	return out


func _last(id: StringName) -> Dictionary:
	for i in range(AudioDirector.played.size() - 1, -1, -1):
		if AudioDirector.played[i].id == id:
			return AudioDirector.played[i]
	return {}


func test_far_impact_arrives_after_sound_travel_time() -> void:
	AudioDirector.listener_override = Vector2(80, -20)
	EventBus.projectile_impacted.emit(Vector2(80 + 686, -20), &"he_155")
	assert_eq(AudioDirector.pending.size(), 1, "travelling")
	assert_near(AudioDirector.pending[0].at - AudioDirector.clock, 2.0, 1e-6, "686 m / 343 m/s")
	AudioDirector.advance(1.95)
	assert_false(_ids().has(&"impact_explosive"), "not heard yet at 1.95 s")
	AudioDirector.advance(0.1)
	var p := _last(&"impact_explosive")
	assert_false(p.is_empty(), "heard by 2.05 s")
	assert_near(p.distance_m, 686.0, 1e-3, "distance")
	assert_near(p.cutoff_hz, AudioMath.distance_cutoff_hz(686.0), 1e-3, "air absorption")
	var size := SoundBank.blast_size(DataRegistry.get_ammo(&"he_155"))
	var expected: float = SoundBank.base_db(&"impact_explosive") + size.db + AudioMath.distance_gain_db(686.0)
	assert_near(p.gain_db, expected, 1.5 + 1e-6, "distance gain (± variation)")
	assert_true(p.pan > 0.0, "to the right of the listener")


func test_impact_at_the_listener_is_immediate() -> void:
	AudioDirector.listener_override = Vector2.ZERO
	EventBus.projectile_impacted.emit(Vector2.ZERO, &"stone_ball")
	assert_true(AudioDirector.pending.is_empty(), "nothing travelling")
	assert_true(_ids().has(&"impact_kinetic"), "stone ball thuds now")


func test_farther_is_quieter_and_duller() -> void:
	AudioDirector.listener_override = Vector2.ZERO
	EventBus.terrain_carved.emit(Vector2(200, 0), 2.0)
	AudioDirector.advance(1.0)
	var near := _last(&"debris")
	AudioDirector.reset()
	AudioDirector.listener_override = Vector2.ZERO
	EventBus.terrain_carved.emit(Vector2(-2000, 0), 2.0)
	AudioDirector.advance(5.0)
	assert_true(_last(&"debris").is_empty(), "2 km of air takes 5.8 s")
	AudioDirector.advance(1.0)
	var far := _last(&"debris")
	assert_false(far.is_empty(), "arrived")
	assert_true(far.gain_db < near.gain_db, "quieter")
	assert_true(far.cutoff_hz < near.cutoff_hz, "duller")
	assert_true(far.pan < 0.0 and near.pan > 0.0, "panned by side")


func test_without_a_listener_sounds_play_unplaced() -> void:
	EventBus.projectile_bounced.emit(Vector2(900, 0), &"stone_ball")
	assert_true(AudioDirector.pending.is_empty(), "no delay outside a battle")
	assert_near(_last(&"bounce_thud").pan, 0.0, 1e-9, "centred")


func test_every_event_has_a_sound() -> void:
	var contract := ContractData.new()
	var plot := PlotData.new()
	var cases := [
		[func() -> void: EventBus.battle_started.emit(contract, plot), &"battle_start"],
		[func() -> void: EventBus.shot_fired.emit(&"trebuchet", &"stone_ball", 25), &"launch_trebuchet"],
		[func() -> void: EventBus.shot_fired.emit(&"rifled_cannon", &"common_shell", 60), &"launch_gunpowder"],
		[func() -> void: EventBus.shot_fired.emit(&"mlrs_launcher", &"rocket_he", 90), &"launch_rocket"],
		[func() -> void: EventBus.shot_fired.emit(&"railgun", &"tungsten_slug", 90), &"launch_railgun"],
		[func() -> void: EventBus.shot_fired.emit(&"orbital_platform", &"kinetic_rod", 90), &"orbital_uplink"],
		[func() -> void: EventBus.projectile_impacted.emit(Vector2.ZERO, &"he_155"), &"impact_explosive"],
		[func() -> void: EventBus.projectile_impacted.emit(Vector2.ZERO, &"fire_pot"), &"impact_incendiary"],
		[func() -> void: EventBus.projectile_impacted.emit(Vector2.ZERO, &"shrapnel_shell"), &"impact_shrapnel"],
		[func() -> void: EventBus.projectile_impacted.emit(Vector2.ZERO, &"ap_shell"), &"impact_ap"],
		[func() -> void: EventBus.projectile_impacted.emit(Vector2.ZERO, &"kinetic_rod"), &"impact_massive"],
		[func() -> void: EventBus.projectile_bounced.emit(Vector2.ZERO, &"stone_ball"), &"bounce_thud"],
		[func() -> void: EventBus.terrain_carved.emit(Vector2.ZERO, 1.5), &"debris"],
		[func() -> void: EventBus.target_hit.emit(&"t0", 60.0), &"target_hit"],
		[func() -> void: EventBus.target_destroyed.emit(&"t0"), &"target_collapse"],
		[func() -> void: EventBus.battery_damaged.emit(&"trebuchet", 30.0), &"battery_hit"],
		[func() -> void: EventBus.battery_revealed.emit(0.3), &"alert"],
		[func() -> void: EventBus.money_changed.emit(100, -50, "Bought 2 x Stone Ball"), &"purchase"],
		[func() -> void: EventBus.money_changed.emit(900, 800, "Contract payout"), &"payout"],
		[func() -> void: EventBus.bid_placed.emit(Auction.PLAYER_ID, &"c", &"p", 100), &"stamp"],
		[func() -> void: EventBus.auction_won.emit(Auction.PLAYER_ID, contract, plot, 100), &"gavel"],
		[func() -> void: EventBus.era_changed.emit(GameConstants.Era.INDUSTRIAL), &"era"],
		[func() -> void: EventBus.game_saved.emit(0), &"stamp"],
	]
	for c in cases:
		AudioDirector.played.clear()
		(c[0] as Callable).call()
		assert_true(_ids().has(c[1]), "%s plays" % c[1])
	AudioDirector.played.clear()
	EventBus.tech_unlocked.emit(&"rifling")
	AudioDirector.advance(0.0)
	assert_true(_ids().has(&"research"), "research chime")
	AudioDirector.played.clear()
	EventBus.tech_unlocked.emit(&"heavy_howitzer")
	EventBus.era_changed.emit(GameConstants.Era.MODERN)
	AudioDirector.advance(0.0)
	assert_true(_ids().has(&"era") and not _ids().has(&"research"), "an era gate plays the fanfare only")


func test_reveal_alert_only_on_rising_steps() -> void:
	EventBus.battery_revealed.emit(0.0)
	EventBus.battery_revealed.emit(0.1)
	assert_false(_ids().has(&"alert"), "below the first step")
	EventBus.battery_revealed.emit(0.26)
	assert_eq(_ids().count(&"alert"), 1, "first step")
	EventBus.battery_revealed.emit(0.3)
	assert_eq(_ids().count(&"alert"), 1, "same step")


func test_time_to_fall() -> void:
	assert_near(AudioDirector.time_to_fall(0.0, 0.0, 19.62, 9.81), 2.0, 1e-6, "dropped from rest")
	assert_near(AudioDirector.time_to_fall(0.0, 10.0, 10.0, 0.0), 1.0, 1e-6, "no gravity")
	assert_near(AudioDirector.time_to_fall(0.0, -9.81, 0.0, 9.81), 0.0, 1e-6, "at the ground")
	assert_near(AudioDirector.time_to_fall(-10.0, -9.81, 0.0, 9.81), 1.0 + sqrt(1.0 + 2.0 * 10.0 / 9.81), 1e-6, "still climbing")


func test_sound_files_are_imported() -> void:
	for id: StringName in SoundBank.SOUNDS:
		var path := SoundBank.path(id)
		assert_true(ResourceLoader.exists(path), "%s exists" % path)
		var stream := load(path) as AudioStreamWAV
		assert_not_null(stream, "%s loads" % path)
		if stream and id in [&"menu_theme", &"wind", &"rain"]:
			assert_eq(stream.loop_mode, AudioStreamWAV.LOOP_FORWARD, "%s loops" % id)


func test_follows_the_battle_scene() -> void:
	GameState.new_game(5)
	var contract := DataRegistry.get_contract(&"siege_of_aldmoor")
	GameState.current_contract = contract
	GameState.current_plot = contract.plots[0]
	var tree := Engine.get_main_loop() as SceneTree
	var scene: Node = load("res://scenes/battle/battle.tscn").instantiate()
	tree.root.add_child(scene)
	for i in 3:
		await tree.process_frame
	var sim: BattleSim = scene.get("sim")
	var listener := AudioDirector.listener_position_m()
	assert_eq(listener, sim.battery_position_m() + Vector2(0, -AudioDirector.EAR_HEIGHT_M), "battery is the listener")
	AudioDirector.played.clear()
	sim.pull_trigger()
	sim.tick(0.0)
	AudioDirector.advance(0.05)
	assert_true(_ids().has(&"launch_trebuchet"), "launch heard at the battery")
	var target: BattleTarget = sim.targets[0]
	EventBus.target_destroyed.emit(target.id)
	var d := AudioMath.arrival_delay(target.position_m + Vector2(0, -1.5), listener)
	assert_true(d > 0.5, "targets are far")
	var due: Dictionary = AudioDirector.pending.back()
	assert_eq(due.id, &"target_collapse", "collapse travelling")
	assert_near(due.at - AudioDirector.clock, d, 0.05, "delayed by the distance to the target")
	scene.free()
	assert_eq(AudioDirector.listener_position_m(), Vector2.INF, "listener gone with the scene")
	assert_true(AudioDirector.pending.is_empty(), "nothing left travelling")
	GameState.new_game()
