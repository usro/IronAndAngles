class_name AudioSettings
extends RefCounted
## The player's volume sliders (0..1 each), saved per user in a small ConfigFile.
## apply() pushes them onto the Master / SFX / Music buses (UI and Ambience feed SFX).

const PATH := "user://audio_settings.cfg"
const SECTION := "audio"
## Slider key -> bus it drives.
const BUSES := {&"master": &"Master", &"sfx": &"SFX", &"music": &"Music"}
const DEFAULTS := {&"master": 0.8, &"sfx": 0.8, &"music": 0.6}

var levels: Dictionary = DEFAULTS.duplicate()


func get_level(key: StringName) -> float:
	return levels.get(key, 0.0)


func set_level(key: StringName, value: float) -> void:
	if BUSES.has(key):
		levels[key] = clampf(value, 0.0, 1.0)


func save(path: String = PATH) -> Error:
	var cfg := ConfigFile.new()
	for key in levels:
		cfg.set_value(SECTION, String(key), levels[key])
	return cfg.save(path)


## Missing file, missing keys or junk values fall back to the defaults.
static func load_from(path: String = PATH) -> AudioSettings:
	var s := AudioSettings.new()
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return s
	for key: StringName in DEFAULTS:
		var v: Variant = cfg.get_value(SECTION, String(key), DEFAULTS[key])
		if v is float or v is int:
			s.set_level(key, float(v))
	return s


func apply() -> void:
	for key: StringName in BUSES:
		var idx := AudioServer.get_bus_index(BUSES[key])
		if idx < 0:
			continue
		AudioServer.set_bus_volume_db(idx, AudioMath.slider_to_db(get_level(key)))
		AudioServer.set_bus_mute(idx, get_level(key) <= AudioMath.SILENT_LINEAR)
