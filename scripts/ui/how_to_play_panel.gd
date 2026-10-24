class_name HowToPlayPanel
extends PanelContainer
## Full-screen overlay showing res://HOW_TO_PLAY.md, so the in-game help and the file never drift.
## Renders a small Markdown subset (headings, bold, inline code, bullets, tables) as BBCode.

const GUIDE_PATH := "res://HOW_TO_PLAY.md"


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := StyleBoxFlat.new()
	shade.bg_color = Color(Blueprint.PAPER_DARK, 0.92)
	add_theme_stylebox_override("panel", shade)

	var margin := MarginContainer.new()
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	add_child(margin)
	var row := HBoxContainer.new()
	margin.add_child(row)
	row.add_child(_spacer())
	var sheet := PanelContainer.new()
	sheet.theme_type_variation = &"SheetPanel"
	sheet.custom_minimum_size = Vector2(920, 0)
	row.add_child(sheet)
	row.add_child(_spacer())

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	sheet.add_child(root)
	var top := HBoxContainer.new()
	root.add_child(top)
	var heading := VBoxContainer.new()
	heading.add_theme_constant_override("separation", 0)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(heading)
	var kicker := Label.new()
	kicker.theme_type_variation = &"SectionLabel"
	kicker.text = "FIELD MANUAL · FM-01"
	heading.add_child(kicker)
	var title := Label.new()
	title.theme_type_variation = &"HeaderLabel"
	title.add_theme_font_size_override("font_size", 24)
	title.text = "OPERATOR'S GUIDE"
	heading.add_child(title)
	var close := Button.new()
	close.text = "Close  [Esc]"
	close.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(queue_free)
	top.add_child(close)
	root.add_child(HSeparator.new())

	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text.add_theme_font_size_override("normal_font_size", 15)
	text.add_theme_font_size_override("bold_font_size", 15)
	text.add_theme_font_size_override("mono_font_size", 14)
	text.text = to_bbcode(FileAccess.get_file_as_string(GUIDE_PATH))
	root.add_child(text)
	text.grab_focus.call_deferred()


static func _spacer() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		queue_free()


static func to_bbcode(md: String) -> String:
	if md.is_empty():
		return "Guide not found at %s" % GUIDE_PATH
	var out := PackedStringArray()
	var in_code := false
	var table: Array[PackedStringArray] = []
	for line in md.split("\n"):
		if not line.begins_with("|") and not table.is_empty():
			out.append(_table(table))
			table.clear()
		if line.begins_with("```"):
			in_code = not in_code
			continue
		if in_code:
			out.append("[indent][code][color=#%s]%s[/color][/code][/indent]" % [Blueprint.LINE.to_html(false),
				line.replace("[", "[lb]")])
			continue
		line = line.replace("[", "[lb]")
		if line.strip_edges() == "---":
			out.append("[hr color=#%s]" % Color(Blueprint.LINE, 0.35).to_html())
			continue
		if line.begins_with("|"):
			if not line.contains("---"):
				var cells := PackedStringArray()
				for c in line.trim_prefix("|").trim_suffix("|").split("|"):
					cells.append(c.strip_edges())
				table.append(cells)
			continue
		elif line.begins_with("### "):
			line = _heading(line.substr(4), 17, Blueprint.AMBER)
		elif line.begins_with("## "):
			line = "\n" + _heading(line.substr(3).to_upper(), 21, Blueprint.LINE)
		elif line.begins_with("# "):
			line = _heading(line.substr(2).to_upper(), 28, Blueprint.INK)
		elif line.strip_edges().begins_with("- "):
			var indent := line.length() - line.lstrip(" ").length()
			line = "  ".repeat(indent / 2 + 1) + "[color=#%s]▸[/color] " % Blueprint.LINE.to_html(false) \
				+ line.strip_edges().substr(2)
		out.append(_inline(line))
	if not table.is_empty():
		out.append(_table(table))
	return "\n".join(out)


static func _heading(text: String, font_size: int, col: Color) -> String:
	return "[font=%s][font_size=%d][color=#%s]%s[/color][/font_size][/font]" % [
		Blueprint.FONT_MONO_BOLD.resource_path, font_size, col.to_html(false), text]


## Markdown table rows (first row is the header) as a BBCode table.
static func _table(rows: Array[PackedStringArray]) -> String:
	var cols := 0
	for r in rows:
		cols = maxi(cols, r.size())
	var out := "[table=%d]" % cols
	for i in rows.size():
		for c in cols:
			var cell := _inline(rows[i][c] if c < rows[i].size() else "")
			if i == 0:
				cell = "[color=#%s][b]%s[/b][/color]" % [Blueprint.TEXT_DIM.to_html(false), cell]
			out += "[cell padding=6,3,14,3]%s[/cell]" % cell
	return out + "[/table]"


static func _inline(line: String) -> String:
	var bold := RegEx.create_from_string("\\*\\*(.+?)\\*\\*")
	line = bold.sub(line, "[b]$1[/b]", true)
	var code := RegEx.create_from_string("`([^`]+)`")
	return code.sub(line, "[code][color=#%s]$1[/color][/code]" % Blueprint.AMBER.to_html(false), true)
