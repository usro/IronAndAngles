class_name AudioSettingsPanel
extends PanelContainer
## Full-screen overlay with the master / effects / music volume sliders. Changes apply live and
## are saved to AudioSettings.PATH when a slider is released and when the panel closes.

const ROWS := [
	[&"master", "MASTER", "Everything"],
	[&"sfx", "EFFECTS", "Guns, impacts, interface, weather"],
	[&"music", "MUSIC", "Theme and battle stings"],
]

## Slider key -> HSlider (tests drive these).
var sliders: Dictionary = {}
var _readouts: Dictionary = {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := StyleBoxFlat.new()
	shade.bg_color = Color(Blueprint.PAPER_DARK, 0.92)
	add_theme_stylebox_override("panel", shade)

	var center := CenterContainer.new()
	add_child(center)
	var sheet := PanelContainer.new()
	sheet.theme_type_variation = &"SheetPanel"
	sheet.custom_minimum_size = Vector2(560, 0)
	center.add_child(sheet)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	sheet.add_child(root)

	var top := HBoxContainer.new()
	root.add_child(top)
	var heading := VBoxContainer.new()
	heading.add_theme_constant_override("separation", 0)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(heading)
	var kicker := Label.new()
	kicker.theme_type_variation = &"SectionLabel"
	kicker.text = "SIGNAL ROOM · SR-02"
	heading.add_child(kicker)
	var title := Label.new()
	title.theme_type_variation = &"HeaderLabel"
	title.add_theme_font_size_override("font_size", 24)
	title.text = "AUDIO LEVELS"
	heading.add_child(title)
	var close := Button.new()
	close.text = "Close  [Esc]"
	close.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(_close)
	top.add_child(close)
	root.add_child(HSeparator.new())

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 14)
	root.add_child(grid)
	for row in ROWS:
		_add_row(grid, row[0], row[1], row[2])

	var note := Label.new()
	note.theme_type_variation = &"CaptionLabel"
	note.text = "Saved for this user. Far impacts arrive late: sound travels 343 m/s."
	root.add_child(note)
	(sliders[&"master"] as HSlider).grab_focus.call_deferred()


func _add_row(grid: GridContainer, key: StringName, label_text: String, hint: String) -> void:
	var names := VBoxContainer.new()
	names.add_theme_constant_override("separation", 0)
	names.custom_minimum_size = Vector2(170, 0)
	var label := Label.new()
	label.theme_type_variation = &"ValueLabel"
	label.text = label_text
	names.add_child(label)
	var caption := Label.new()
	caption.theme_type_variation = &"CaptionLabel"
	caption.text = hint
	names.add_child(caption)
	grid.add_child(names)

	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.custom_minimum_size = Vector2(240, 24)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.value = AudioDirector.settings.get_level(key)
	slider.value_changed.connect(_on_value_changed.bind(key))
	slider.drag_ended.connect(_on_drag_ended.bind(key))
	grid.add_child(slider)
	sliders[key] = slider

	var readout := Label.new()
	readout.theme_type_variation = &"MonoLabel"
	readout.custom_minimum_size = Vector2(48, 0)
	readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	grid.add_child(readout)
	_readouts[key] = readout
	_update_readout(key)


func _on_value_changed(value: float, key: StringName) -> void:
	AudioDirector.settings.set_level(key, value)
	AudioDirector.settings.apply()
	_update_readout(key)


func _on_drag_ended(_changed: bool, key: StringName) -> void:
	AudioDirector.save_settings()
	# A sample at the new level (the menu theme already plays on the music bus).
	if key != &"music":
		AudioDirector.play_ui(&"click")


func _update_readout(key: StringName) -> void:
	(_readouts[key] as Label).text = "%d%%" % roundi(AudioDirector.settings.get_level(key) * 100.0)


func _close() -> void:
	AudioDirector.save_settings()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_close()
