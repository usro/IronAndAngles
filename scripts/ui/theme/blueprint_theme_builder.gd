class_name BlueprintThemeBuilder
extends RefCounted
## Builds the game-wide blueprint Theme. The saved copy is res://themes/blueprint_theme.tres
## (the project's default theme). After changing this file, regenerate it:
##   godot --headless --path . -s res://scripts/ui/theme/build_theme.gd

const OUTPUT_PATH := "res://themes/blueprint_theme.tres"

const B = preload("res://scripts/ui/blueprint.gd")


static func build() -> Theme:
	var t := Theme.new()
	t.default_font = B.FONT_BODY
	t.default_font_size = 15
	_panels(t)
	_labels(t)
	_buttons(t)
	_inputs(t)
	_tabs(t)
	_scroll(t)
	_misc(t)
	return t


# --- Styleboxes ---

static func _flat(bg: Color, border := Color.TRANSPARENT, width := 0, margin := Vector4(10, 6, 10, 6)) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(width)
	s.content_margin_left = margin.x
	s.content_margin_top = margin.y
	s.content_margin_right = margin.z
	s.content_margin_bottom = margin.w
	s.anti_aliasing = false
	return s


static func _sheet(bg: Color, grid := false, ticks := 10.0, margin := 14.0) -> BlueprintPanelStyle:
	var s := BlueprintPanelStyle.new()
	s.bg_color = bg
	s.grid = grid
	s.tick_length = ticks
	s.content_margin_left = margin
	s.content_margin_right = margin
	s.content_margin_top = margin
	s.content_margin_bottom = margin
	return s


static func _line(col: Color, thickness := 1, vertical := false) -> StyleBoxLine:
	var s := StyleBoxLine.new()
	s.color = col
	s.thickness = thickness
	s.vertical = vertical
	return s


# --- Groups ---

static func _panels(t: Theme) -> void:
	t.set_stylebox("panel", "Panel", _sheet(B.PAPER_DARK))
	t.set_stylebox("panel", "PanelContainer", _sheet(B.PAPER_DARK))
	# A full drawing sheet with the grid printed on it.
	t.add_type("SheetPanel")
	t.set_type_variation("SheetPanel", "PanelContainer")
	t.set_stylebox("panel", "SheetPanel", _sheet(Color(B.PAPER_DARK, 0.97), true, 14.0, 20.0))
	# A card inside a sheet: lighter paper, thin border, no ticks.
	t.add_type("CardPanel")
	t.set_type_variation("CardPanel", "PanelContainer")
	t.set_stylebox("panel", "CardPanel", _flat(Color(B.PAPER_LIGHT, 0.55), Color(B.LINE, 0.25), 1,
		Vector4(10, 8, 10, 8)))
	t.add_type("SelectedCardPanel")
	t.set_type_variation("SelectedCardPanel", "PanelContainer")
	t.set_stylebox("panel", "SelectedCardPanel", _flat(Color(B.PAPER_LIGHT, 0.85), B.AMBER, 1,
		Vector4(10, 8, 10, 8)))
	# Battle HUD plates: see-through so the field shows behind them.
	t.add_type("HudPanel")
	t.set_type_variation("HudPanel", "PanelContainer")
	var hud := _sheet(Color(B.PAPER_DARK, 0.82), false, 8.0, 10.0)
	hud.border_color = Color(B.LINE, 0.35)
	t.set_stylebox("panel", "HudPanel", hud)
	# Top bar strip of the management screens.
	t.add_type("BarPanel")
	t.set_type_variation("BarPanel", "PanelContainer")
	var bar := _flat(Color(B.PAPER_DARK, 0.9), Color(B.LINE, 0.4), 0, Vector4(16, 8, 16, 8))
	bar.border_width_bottom = 1
	t.set_stylebox("panel", "BarPanel", bar)


static func _label_type(t: Theme, name: String, font: Font, size: int, col: Color) -> void:
	t.add_type(name)
	t.set_type_variation(name, "Label")
	t.set_font("font", name, font)
	t.set_font_size("font_size", name, size)
	t.set_color("font_color", name, col)


static func _labels(t: Theme) -> void:
	t.set_color("font_color", "Label", B.INK)
	t.set_font_size("font_size", "Label", 15)
	t.set_constant("line_spacing", "Label", 2)
	_label_type(t, "TitleLabel", B.FONT_MONO_BOLD, 30, B.INK)
	_label_type(t, "HeaderLabel", B.FONT_MONO_BOLD, 18, B.LINE)
	_label_type(t, "SectionLabel", B.FONT_MONO_BOLD, 12, B.TEXT_DIM)
	_label_type(t, "CaptionLabel", B.FONT_MONO, 11, B.TEXT_DIM)
	_label_type(t, "MonoLabel", B.FONT_MONO, 14, B.INK)
	_label_type(t, "ValueLabel", B.FONT_MONO_BOLD, 16, B.INK)
	_label_type(t, "MoneyLabel", B.FONT_MONO_BOLD, 18, B.AMBER)
	_label_type(t, "StatusLabel", B.FONT_MONO, 13, B.AMBER)
	_label_type(t, "BodyLabel", B.FONT_BODY, 14, Color(B.INK, 0.85))


static func _button_styles(t: Theme, type: String, base: Color, border: Color, accent: Color,
		margin: Vector4) -> void:
	t.set_stylebox("normal", type, _flat(base, border, 1, margin))
	t.set_stylebox("hover", type, _flat(base.lightened(0.12), accent, 1, margin))
	t.set_stylebox("pressed", type, _flat(Color(accent, 0.9), accent, 1, margin))
	t.set_stylebox("hover_pressed", type, _flat(accent.lightened(0.15), accent, 1, margin))
	t.set_stylebox("disabled", type, _flat(Color(base, base.a * 0.4), Color(border, 0.25), 1, margin))
	var focus := _flat(Color.TRANSPARENT, B.AMBER, 1, margin)
	focus.expand_margin_left = 2
	focus.expand_margin_right = 2
	focus.expand_margin_top = 2
	focus.expand_margin_bottom = 2
	t.set_stylebox("focus", type, focus)
	t.set_color("font_color", type, B.INK)
	t.set_color("font_hover_color", type, Color.WHITE)
	t.set_color("font_focus_color", type, B.INK)
	t.set_color("font_pressed_color", type, B.PAPER_DARK)
	t.set_color("font_hover_pressed_color", type, B.PAPER_DARK)
	t.set_color("font_disabled_color", type, Color(B.TEXT_DIM, 0.5))


static func _buttons(t: Theme) -> void:
	_button_styles(t, "Button", Color(B.PAPER_LIGHT, 0.6), Color(B.LINE, 0.55), B.LINE, Vector4(12, 6, 12, 6))
	t.set_font("font", "Button", B.FONT_BODY_BOLD)
	t.set_font_size("font_size", "Button", 14)

	t.add_type("PrimaryButton")
	t.set_type_variation("PrimaryButton", "Button")
	_button_styles(t, "PrimaryButton", Color(0.24, 0.2, 0.1, 0.85), B.AMBER, B.AMBER, Vector4(16, 8, 16, 8))
	t.set_color("font_color", "PrimaryButton", B.AMBER)
	t.set_color("font_focus_color", "PrimaryButton", B.AMBER)
	t.set_color("font_hover_color", "PrimaryButton", Color.WHITE)

	t.add_type("MenuButtonLarge")
	t.set_type_variation("MenuButtonLarge", "Button")
	_button_styles(t, "MenuButtonLarge", Color(B.PAPER_DARK, 0.7), Color(B.LINE, 0.45), B.LINE,
		Vector4(18, 10, 18, 10))
	t.set_font("font", "MenuButtonLarge", B.FONT_MONO_BOLD)
	t.set_font_size("font_size", "MenuButtonLarge", 17)
	t.set_constant("align_to_largest_stylebox", "MenuButtonLarge", 1)

	t.add_type("ChipButton")
	t.set_type_variation("ChipButton", "Button")
	_button_styles(t, "ChipButton", Color(B.PAPER_DARK, 0.6), Color(B.LINE, 0.4), B.LINE, Vector4(8, 3, 8, 3))
	t.set_font("font", "ChipButton", B.FONT_MONO)
	t.set_font_size("font_size", "ChipButton", 12)

	# Plot tags on the drafted map; "pressed" is the selected parcel.
	t.add_type("ParcelButton")
	t.set_type_variation("ParcelButton", "Button")
	_button_styles(t, "ParcelButton", Color(B.PAPER_DARK, 0.85), Color(B.LINE, 0.5), B.AMBER, Vector4(6, 2, 6, 2))
	t.set_font("font", "ParcelButton", B.FONT_MONO)
	t.set_font_size("font_size", "ParcelButton", 11)

	# Tech tree nodes, one variation per status.
	for v in [["TechResearched", Color(B.LINE, 0.22), B.LINE, B.LINE],
			["TechAvailable", Color(B.PAPER_LIGHT, 0.9), B.INK, B.AMBER],
			["TechUnaffordable", Color(B.PAPER_LIGHT, 0.6), Color(B.AMBER, 0.6), B.AMBER],
			["TechLocked", Color(B.PAPER_DARK, 0.8), Color(B.LINE, 0.25), B.LINE]]:
		t.add_type(v[0])
		t.set_type_variation(v[0], "Button")
		_button_styles(t, v[0], v[1], v[2], v[3], Vector4(8, 4, 8, 4))
		t.set_font("font", v[0], B.FONT_BODY_BOLD)
		t.set_font_size("font_size", v[0], 12)
		t.set_constant("h_separation", v[0], 4)
	t.set_color("font_color", "TechLocked", Color(B.TEXT_DIM, 0.7))
	t.set_color("font_color", "TechResearched", B.LINE)


static func _inputs(t: Theme) -> void:
	var edit := _flat(Color(B.PAPER_DARK, 0.9), Color(B.LINE, 0.25), 0, Vector4(8, 5, 8, 5))
	edit.border_width_bottom = 2
	edit.border_color = B.LINE
	t.set_stylebox("normal", "LineEdit", edit)
	var focus := edit.duplicate()
	focus.border_color = B.AMBER
	t.set_stylebox("focus", "LineEdit", focus)
	var ro := edit.duplicate()
	ro.border_color = Color(B.LINE, 0.3)
	t.set_stylebox("read_only", "LineEdit", ro)
	t.set_font("font", "LineEdit", B.FONT_MONO_BOLD)
	t.set_font_size("font_size", "LineEdit", 16)
	t.set_color("font_color", "LineEdit", B.AMBER)
	t.set_color("font_uneditable_color", "LineEdit", Color(B.TEXT_DIM, 0.7))
	t.set_color("caret_color", "LineEdit", B.AMBER)
	t.set_color("selection_color", "LineEdit", Color(B.LINE, 0.35))
	t.set_icon("updown", "SpinBox", load("res://themes/icons/spin_updown.svg"))
	t.set_icon("up", "SpinBox", load("res://themes/icons/spin_up.svg"))
	t.set_icon("down", "SpinBox", load("res://themes/icons/spin_down.svg"))
	for k in ["up_hover", "up_pressed", "up_disabled"]:
		t.set_icon(k, "SpinBox", load("res://themes/icons/spin_up.svg"))
	for k in ["down_hover", "down_pressed", "down_disabled"]:
		t.set_icon(k, "SpinBox", load("res://themes/icons/spin_down.svg"))
	for k in ["up_background", "down_background", "up_background_hovered", "down_background_hovered",
			"up_background_pressed", "down_background_pressed", "up_background_disabled",
			"down_background_disabled"]:
		t.set_stylebox(k, "SpinBox", _flat(Color(B.PAPER_LIGHT, 0.6), Color.TRANSPARENT, 0, Vector4(2, 0, 2, 0)))
	t.set_color("up_icon_modulate", "SpinBox", B.LINE)
	t.set_color("down_icon_modulate", "SpinBox", B.LINE)
	t.set_color("up_hover_icon_modulate", "SpinBox", B.AMBER)
	t.set_color("down_hover_icon_modulate", "SpinBox", B.AMBER)
	t.set_constant("buttons_width", "SpinBox", 20)


static func _tabs(t: Theme) -> void:
	var m := Vector4(14, 6, 14, 6)
	var sel := _flat(Color(B.PAPER_DARK, 1.0), B.LINE, 0, m)
	sel.border_width_top = 2
	t.set_stylebox("tab_selected", "TabContainer", sel)
	var unsel := _flat(Color(B.PAPER_LIGHT, 0.35), Color(B.LINE, 0.3), 0, m)
	unsel.border_width_bottom = 1
	t.set_stylebox("tab_unselected", "TabContainer", unsel)
	var hov := _flat(Color(B.PAPER_LIGHT, 0.6), B.LINE, 0, m)
	hov.border_width_bottom = 1
	t.set_stylebox("tab_hovered", "TabContainer", hov)
	t.set_stylebox("tab_focus", "TabContainer", StyleBoxEmpty.new())
	t.set_stylebox("tab_disabled", "TabContainer", unsel)
	t.set_stylebox("panel", "TabContainer", _sheet(Color(B.PAPER_DARK, 0.95), false, 0.0, 12.0))
	t.set_stylebox("tabbar_background", "TabContainer", StyleBoxEmpty.new())
	t.set_font("font", "TabContainer", B.FONT_MONO_BOLD)
	t.set_font_size("font_size", "TabContainer", 14)
	t.set_color("font_selected_color", "TabContainer", B.INK)
	t.set_color("font_unselected_color", "TabContainer", B.TEXT_DIM)
	t.set_color("font_hovered_color", "TabContainer", B.INK)


static func _scroll(t: Theme) -> void:
	for type in ["VScrollBar", "HScrollBar"]:
		var vertical: bool = type == "VScrollBar"
		var track := _line(Color(B.LINE, 0.18), 1, vertical)
		track.grow_begin = 0
		track.grow_end = 0
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color(B.LINE, 0.06)
		bg.content_margin_left = 3
		bg.content_margin_right = 3
		bg.content_margin_top = 3
		bg.content_margin_bottom = 3
		t.set_stylebox("scroll", type, bg)
		t.set_stylebox("scroll_focus", type, bg)
		for k in [["grabber", 0.45], ["grabber_highlight", 0.8], ["grabber_pressed", 1.0]]:
			var g := StyleBoxFlat.new()
			g.bg_color = Color(B.LINE, k[1])
			g.content_margin_left = 3
			g.content_margin_right = 3
			g.content_margin_top = 3
			g.content_margin_bottom = 3
			t.set_stylebox(k[0], type, g)


static func _misc(t: Theme) -> void:
	t.set_stylebox("separator", "HSeparator", _line(Color(B.LINE, 0.3)))
	t.set_constant("separation", "HSeparator", 12)
	t.set_stylebox("separator", "VSeparator", _line(Color(B.LINE, 0.3), 1, true))

	var pb_bg := _flat(Color(B.PAPER_DARK, 0.9), Color(B.LINE, 0.4), 1, Vector4.ZERO)
	t.set_stylebox("background", "ProgressBar", pb_bg)
	t.set_stylebox("fill", "ProgressBar", _flat(Color(B.LINE, 0.85), Color.TRANSPARENT, 0, Vector4.ZERO))
	t.set_font("font", "ProgressBar", B.FONT_MONO)
	t.set_font_size("font_size", "ProgressBar", 11)
	t.set_color("font_color", "ProgressBar", B.INK)
	t.set_color("font_outline_color", "ProgressBar", B.PAPER_DARK)
	t.set_constant("outline_size", "ProgressBar", 3)

	t.set_font("normal_font", "RichTextLabel", B.FONT_BODY)
	t.set_font("bold_font", "RichTextLabel", B.FONT_BODY_BOLD)
	t.set_font("mono_font", "RichTextLabel", B.FONT_MONO)
	t.set_color("default_color", "RichTextLabel", Color(B.INK, 0.9))
	t.set_color("table_border", "RichTextLabel", Color(B.LINE, 0.3))
	t.set_color("table_odd_row_bg", "RichTextLabel", Color(B.PAPER_LIGHT, 0.35))
	t.set_color("table_even_row_bg", "RichTextLabel", Color(B.PAPER_LIGHT, 0.15))
	t.set_constant("table_h_separation", "RichTextLabel", 14)
	t.set_constant("table_v_separation", "RichTextLabel", 4)
	t.set_constant("line_separation", "RichTextLabel", 3)

	var tip := _flat(B.PAPER_DARK, B.LINE, 1, Vector4(8, 5, 8, 5))
	t.set_stylebox("panel", "TooltipPanel", tip)
	t.set_color("font_color", "TooltipLabel", B.INK)
	t.set_font("font", "TooltipLabel", B.FONT_MONO)
	t.set_font_size("font_size", "TooltipLabel", 12)

	t.set_constant("separation", "HBoxContainer", 8)
	t.set_constant("separation", "VBoxContainer", 6)
