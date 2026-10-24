class_name SettingsPanel
extends OverlaySheet
## Settings: display (fullscreen, window size), tutorial tips, key bindings, and a link to audio.
## Everything applies immediately and is saved by the Settings autoload.

## Action waiting for a key press, or &"" when not capturing.
var _capturing: StringName = &""
var _key_buttons: Dictionary = {}


func _init() -> void:
	super("CONFIGURATION · SHEET 05", "SETTINGS", 620.0)
	max_content_height = 470.0


func build() -> void:
	_section("DISPLAY")
	var fs := CheckButton.new()
	fs.text = "Fullscreen"
	fs.button_pressed = Settings.fullscreen
	fs.toggled.connect(Settings.set_fullscreen)
	content.add_child(fs)
	var row := HBoxContainer.new()
	content.add_child(row)
	var lab := Label.new()
	lab.theme_type_variation = &"BodyLabel"
	lab.text = "Window size"
	lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lab)
	var sizes := OptionButton.new()
	for i in Settings.WINDOW_SIZES.size():
		var s: Vector2i = Settings.WINDOW_SIZES[i]
		sizes.add_item("%d × %d" % [s.x, s.y], i)
		if s == Settings.window_size:
			sizes.select(i)
	sizes.item_selected.connect(func(i: int) -> void: Settings.set_window_size(Settings.WINDOW_SIZES[i]))
	row.add_child(sizes)

	_section("TUTORIAL")
	var tips := CheckButton.new()
	tips.text = "Show tips in battle"
	tips.button_pressed = Settings.tips_enabled
	tips.toggled.connect(func(on: bool) -> void:
		Settings.tips_enabled = on
		Settings.save_settings())
	content.add_child(tips)
	var reset_tips := Button.new()
	reset_tips.text = "Show all tips again"
	reset_tips.pressed.connect(func() -> void:
		Settings.reset_tips()
		reset_tips.text = "Tips reset")
	content.add_child(reset_tips)

	_section("CONTROLS  ·  click a key, then press the new one (Esc cancels)")
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 4)
	content.add_child(grid)
	for action in Settings.REBINDABLE:
		var name_label := Label.new()
		name_label.theme_type_variation = &"BodyLabel"
		name_label.text = Settings.ACTION_NAMES.get(action, String(action))
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(name_label)
		var key := Button.new()
		key.custom_minimum_size = Vector2(150, 0)
		key.text = Settings.key_name(action)
		key.pressed.connect(_start_capture.bind(action))
		grid.add_child(key)
		_key_buttons[action] = key
	var defaults := Button.new()
	defaults.text = "Reset keys to defaults"
	defaults.pressed.connect(func() -> void:
		Settings.reset_bindings()
		_refresh_keys())
	content.add_child(defaults)

	_section("AUDIO")
	add_button("Audio settings…", func() -> void: add_child(AudioSettingsPanel.new()), &"ChipButton")


func _start_capture(action: StringName) -> void:
	_capturing = action
	_refresh_keys()
	_key_buttons[action].text = "Press a key…"


func _input(event: InputEvent) -> void:
	if _capturing == &"" or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	get_viewport().set_input_as_handled()
	var key := event as InputEventKey
	if key.keycode != KEY_ESCAPE:
		Settings.rebind(_capturing, key.physical_keycode)
	_capturing = &""
	_refresh_keys()


func _unhandled_input(event: InputEvent) -> void:
	if _capturing != &"":
		return
	super(event)


func _refresh_keys() -> void:
	for action in _key_buttons:
		_key_buttons[action].text = Settings.key_name(action)


func _section(text: String) -> void:
	var l := Label.new()
	l.theme_type_variation = &"SectionLabel"
	l.text = text
	content.add_child(l)
