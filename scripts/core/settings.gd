extends Node
## Autoload "Settings": per-player preferences in user://settings.cfg (not part of a campaign save):
## window mode and size, tutorial tips, and key bindings. Applied at startup and on change.
## (Volume lives in AudioSettings.)

const PATH := "user://settings.cfg"
const WINDOW_SIZES: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080),
	Vector2i(2560, 1440)]
## Actions the player may rebind (shown in Settings > Controls), in display order.
const REBINDABLE: Array[StringName] = [&"aim_up", &"aim_down", &"charge_up", &"charge_down", &"fine_adjust",
	&"fire", &"next_weapon", &"next_ammo", &"toggle_firing_table", &"apply_solution", &"relocate",
	&"toggle_split", &"toggle_overview"]
const ACTION_NAMES := {
	&"aim_up": "Elevation up", &"aim_down": "Elevation down", &"charge_up": "Next charge",
	&"charge_down": "Previous charge", &"fine_adjust": "Fine adjust (hold)", &"fire": "Fire",
	&"next_weapon": "Next weapon", &"next_ammo": "Next ammo", &"toggle_firing_table": "Firing table",
	&"apply_solution": "Fire-control computer", &"relocate": "Relocate (shoot and scoot)",
	&"toggle_split": "Split screen", &"toggle_overview": "Overview camera",
}

## Off in automated tests, so test battles don't mark the player's tips as seen or change keys.
var persist := true
var fullscreen := false
var window_size := Vector2i(1280, 720)
var tips_enabled := true
## Tutorial tip ids already shown.
var tips_seen: Array[String] = []
## Action -> physical keycode the player chose (replaces the action's first key).
var bindings: Dictionary = {}
## Project defaults captured at startup, so "Reset" can restore them.
var _default_keys: Dictionary = {}


func _ready() -> void:
	for action in REBINDABLE:
		_default_keys[action] = primary_key(action)
	load_settings()
	apply()


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	fullscreen = cfg.get_value("display", "fullscreen", false)
	window_size = cfg.get_value("display", "window_size", Vector2i(1280, 720))
	tips_enabled = cfg.get_value("tips", "enabled", true)
	tips_seen.assign(cfg.get_value("tips", "seen", []))
	for action in REBINDABLE:
		var code: int = cfg.get_value("keys", String(action), 0)
		if code != 0:
			bindings[action] = code


func save_settings() -> void:
	if not persist:
		return
	var cfg := ConfigFile.new()
	cfg.set_value("display", "fullscreen", fullscreen)
	cfg.set_value("display", "window_size", window_size)
	cfg.set_value("tips", "enabled", tips_enabled)
	cfg.set_value("tips", "seen", tips_seen)
	for action in bindings:
		cfg.set_value("keys", String(action), bindings[action])
	cfg.save(PATH)


func apply() -> void:
	for action in bindings:
		_set_primary_key(action, bindings[action])
	if DisplayServer.get_name() == "headless":
		return
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		var screen := DisplayServer.screen_get_size()
		var size := Vector2i(mini(window_size.x, screen.x), mini(window_size.y, screen.y))
		DisplayServer.window_set_size(size)
		DisplayServer.window_set_position(DisplayServer.screen_get_position() + (screen - size) / 2)


func set_fullscreen(on: bool) -> void:
	fullscreen = on
	apply()
	save_settings()


func set_window_size(size: Vector2i) -> void:
	window_size = size
	apply()
	save_settings()


func rebind(action: StringName, physical_keycode: int) -> void:
	bindings[action] = physical_keycode
	_set_primary_key(action, physical_keycode)
	save_settings()


func reset_bindings() -> void:
	for action in REBINDABLE:
		_set_primary_key(action, _default_keys.get(action, 0))
	bindings.clear()
	save_settings()


## Marks a tutorial tip as shown. Returns true the first time.
func mark_tip(id: String) -> bool:
	if tips_seen.has(id):
		return false
	tips_seen.append(id)
	save_settings()
	return true


func reset_tips() -> void:
	tips_seen.clear()
	save_settings()


## The action's first keyboard key (physical keycode), 0 if none.
func primary_key(action: StringName) -> int:
	if not InputMap.has_action(action):
		return 0
	for e in InputMap.action_get_events(action):
		if e is InputEventKey:
			return (e as InputEventKey).physical_keycode
	return 0


func key_name(action: StringName) -> String:
	var code := primary_key(action)
	return OS.get_keycode_string(code as Key) if code != 0 else "—"


## Replaces the action's first key event (other keys, like arrow alternatives, stay).
func _set_primary_key(action: StringName, physical_keycode: int) -> void:
	if not InputMap.has_action(action) or physical_keycode == 0:
		return
	for e in InputMap.action_get_events(action):
		if e is InputEventKey:
			InputMap.action_erase_event(action, e)
			break
	var ev := InputEventKey.new()
	ev.physical_keycode = physical_keycode as Key
	var events := InputMap.action_get_events(action)
	for e in events:
		InputMap.action_erase_event(action, e)
	InputMap.action_add_event(action, ev)
	for e in events:
		InputMap.action_add_event(action, e)
