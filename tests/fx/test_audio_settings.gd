extends TestCase
## Volume settings: saved per user, robust to missing or bad files, applied to the buses.

const PATH := "user://test_audio_settings.cfg"


func before_each() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))


func test_round_trip() -> void:
	var s := AudioSettings.new()
	s.set_level(&"master", 0.35)
	s.set_level(&"sfx", 1.0)
	s.set_level(&"music", 0.0)
	assert_eq(s.save(PATH), OK, "saved")
	var back := AudioSettings.load_from(PATH)
	assert_near(back.get_level(&"master"), 0.35, 1e-6, "master")
	assert_near(back.get_level(&"sfx"), 1.0, 1e-6, "sfx")
	assert_near(back.get_level(&"music"), 0.0, 1e-6, "music")


func test_missing_file_gives_defaults() -> void:
	var s := AudioSettings.load_from(PATH)
	for key in AudioSettings.DEFAULTS:
		assert_near(s.get_level(key), AudioSettings.DEFAULTS[key], 1e-6, String(key))


func test_bad_values_are_clamped_or_ignored() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(AudioSettings.SECTION, "master", 7.5)
	cfg.set_value(AudioSettings.SECTION, "sfx", "loud")
	cfg.set_value(AudioSettings.SECTION, "music", -2)
	cfg.save(PATH)
	var s := AudioSettings.load_from(PATH)
	assert_near(s.get_level(&"master"), 1.0, 1e-6, "clamped high")
	assert_near(s.get_level(&"sfx"), AudioSettings.DEFAULTS[&"sfx"], 1e-6, "junk ignored")
	assert_near(s.get_level(&"music"), 0.0, 1e-6, "clamped low")
	s.set_level(&"bogus", 0.5)
	assert_false(s.levels.has(&"bogus"), "unknown key ignored")


func test_apply_sets_bus_volumes() -> void:
	var before := AudioDirector.settings
	var s := AudioSettings.new()
	s.set_level(&"master", 0.5)
	s.set_level(&"sfx", 1.0)
	s.set_level(&"music", 0.0)
	s.apply()
	var master := AudioServer.get_bus_index(&"Master")
	var sfx := AudioServer.get_bus_index(&"SFX")
	var music := AudioServer.get_bus_index(&"Music")
	assert_true(sfx > 0 and music > 0, "bus layout loaded")
	assert_near(AudioServer.get_bus_volume_db(master), linear_to_db(0.5), 1e-3, "master")
	assert_near(AudioServer.get_bus_volume_db(sfx), 0.0, 1e-3, "sfx")
	assert_true(AudioServer.is_bus_mute(music), "music muted at 0")
	assert_false(AudioServer.is_bus_mute(sfx), "sfx audible")
	before.apply()


func test_bus_layout_routes_through_master_limiter() -> void:
	for bus_name in [&"SFX", &"UI", &"Ambience", &"Music"]:
		assert_true(AudioServer.get_bus_index(bus_name) > 0, "bus %s" % bus_name)
	assert_eq(AudioServer.get_bus_send(AudioServer.get_bus_index(&"UI")), &"SFX", "UI feeds SFX")
	assert_eq(AudioServer.get_bus_send(AudioServer.get_bus_index(&"Ambience")), &"SFX", "ambience feeds SFX")
	assert_eq(AudioServer.get_bus_send(AudioServer.get_bus_index(&"Music")), &"Master", "music to master")
	var kinds := []
	for i in AudioServer.get_bus_effect_count(0):
		kinds.append(AudioServer.get_bus_effect(0, i).get_class())
	assert_true(kinds.has("AudioEffectCompressor"), "master compressor")
	assert_true(kinds.has("AudioEffectHardLimiter"), "master limiter")


func test_settings_panel_drives_levels() -> void:
	var before: Dictionary = AudioDirector.settings.levels.duplicate()
	var tree := Engine.get_main_loop() as SceneTree
	var panel := AudioSettingsPanel.new()
	tree.root.add_child(panel)
	assert_eq(panel.sliders.size(), 3, "three sliders")
	(panel.sliders[&"sfx"] as HSlider).value = 0.25
	assert_near(AudioDirector.settings.get_level(&"sfx"), 0.25, 1e-6, "slider sets the level")
	assert_near(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"SFX")), linear_to_db(0.25), 1e-3, "applied")
	panel.free()
	AudioDirector.settings.levels = before
	AudioDirector.settings.apply()
