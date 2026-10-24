extends Control
## Main menu: a drawing sheet with the title, the menu buttons and a drafted firing diagram.

const MenuDiagram := preload("res://scripts/ui/menu_diagram.gd")


func _ready() -> void:
	BlueprintBackdrop.add_to(self, "SHEET 01 — GENERAL ARRANGEMENT   SCALE 1:100")

	var diagram := MenuDiagram.new()
	diagram.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	diagram.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(diagram)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 72)
	margin.add_theme_constant_override("margin_top", 64)
	margin.add_theme_constant_override("margin_bottom", 56)
	add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	col.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	margin.add_child(col)

	var kicker := Label.new()
	kicker.theme_type_variation = &"SectionLabel"
	kicker.text = "MERCENARY ARTILLERY CONTRACTORS"
	col.add_child(kicker)
	var title := Label.new()
	title.theme_type_variation = &"TitleLabel"
	title.add_theme_font_size_override("font_size", 64)
	title.text = "IRON & ANGLES"
	col.add_child(title)
	var tagline := Label.new()
	tagline.theme_type_variation = &"MonoLabel"
	tagline.add_theme_color_override("font_color", Blueprint.TEXT_DIM)
	tagline.text = "Bid for the contract.  Dial the angle.  Keep the change."
	col.add_child(tagline)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 36)
	col.add_child(spacer)

	_button(col, "New Campaign", _on_new, &"PrimaryButton")
	var cont := _button(col, "Continue", _on_continue)
	cont.disabled = not SaveSystem.has_save()
	_button(col, "How to Play", func() -> void: add_child(HowToPlayPanel.new()))
	_button(col, "Audio Settings", func() -> void: add_child(AudioSettingsPanel.new()))
	_button(col, "Quit", get_tree().quit)
	(col.get_child(4) as Button).grab_focus.call_deferred()


func _button(parent: Node, text: String, on_press: Callable, variation := &"MenuButtonLarge") -> Button:
	var b := Button.new()
	b.text = text
	b.theme_type_variation = variation
	if variation == &"PrimaryButton":
		b.add_theme_font_override("font", Blueprint.FONT_MONO_BOLD)
		b.add_theme_font_size_override("font_size", 17)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(300, 46)
	b.pressed.connect(on_press)
	parent.add_child(b)
	return b


func _on_new() -> void:
	GameState.new_game()
	SceneRouter.goto(SceneRouter.Screen.REGION_MAP)


func _on_continue() -> void:
	if SaveSystem.load_game() == OK:
		SceneRouter.goto(SceneRouter.Screen.REGION_MAP)
