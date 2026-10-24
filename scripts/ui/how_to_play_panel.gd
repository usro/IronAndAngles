class_name HowToPlayPanel
extends PanelContainer
## Full-screen overlay showing res://HOW_TO_PLAY.md, so the in-game help and the file never drift.
## Renders a small Markdown subset (headings, bold, inline code, bullets, tables) as BBCode.

const GUIDE_PATH := "res://HOW_TO_PLAY.md"


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.09, 0.14, 0.97)
	add_theme_stylebox_override("panel", style)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)
	var root := VBoxContainer.new()
	margin.add_child(root)

	var close := Button.new()
	close.text = "Close"
	close.size_flags_horizontal = Control.SIZE_SHRINK_END
	close.pressed.connect(queue_free)
	root.add_child(close)

	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text.add_theme_font_size_override("normal_font_size", 16)
	text.add_theme_font_size_override("bold_font_size", 16)
	text.text = to_bbcode(FileAccess.get_file_as_string(GUIDE_PATH))
	root.add_child(text)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		queue_free()


static func to_bbcode(md: String) -> String:
	if md.is_empty():
		return "Guide not found at %s" % GUIDE_PATH
	var out := PackedStringArray()
	var in_code := false
	for line in md.split("\n"):
		if line.begins_with("```"):
			in_code = not in_code
			continue
		if in_code:
			out.append("[code]%s[/code]" % line.replace("[", "[lb]"))
			continue
		line = line.replace("[", "[lb]")
		if line.strip_edges() == "---":
			out.append("")
			continue
		if line.begins_with("|"):
			if line.contains("---"):
				continue
			var cells := PackedStringArray()
			for c in line.trim_prefix("|").trim_suffix("|").split("|"):
				cells.append(c.strip_edges())
			line = "    " + "   —   ".join(cells)
		elif line.begins_with("### "):
			line = "[font_size=20][b]%s[/b][/font_size]" % line.substr(4)
		elif line.begins_with("## "):
			line = "\n[font_size=26][b]%s[/b][/font_size]" % line.substr(3)
		elif line.begins_with("# "):
			line = "[font_size=34][b]%s[/b][/font_size]" % line.substr(2)
		elif line.strip_edges().begins_with("- "):
			var indent := line.length() - line.lstrip(" ").length()
			line = "  ".repeat(indent / 2 + 1) + "• " + line.strip_edges().substr(2)
		out.append(_inline(line))
	return "\n".join(out)


static func _inline(line: String) -> String:
	var bold := RegEx.create_from_string("\\*\\*(.+?)\\*\\*")
	line = bold.sub(line, "[b]$1[/b]", true)
	var code := RegEx.create_from_string("`([^`]+)`")
	return code.sub(line, "[code]$1[/code]", true)
