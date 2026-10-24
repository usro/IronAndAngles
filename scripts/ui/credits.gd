class_name Credits
extends RefCounted
## The credits text, shared by the main menu's Credits sheet and the ending screen.

const LINES := [
	["IRON & ANGLES", ""],
	["Design and direction", "Riza Mukti"],
	["Built with", "Godot Engine 4.7 (MIT licence) · godotengine.org"],
	["Fonts", "Inter (SIL Open Font Licence) · JetBrains Mono (SIL Open Font Licence)"],
	["Sound", "Synthesized for this game"],
	["Development", "Made with Claude Code"],
	["", "Thank you for playing."],
]


static func add_to(parent: Control) -> void:
	for line in LINES:
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 0)
		parent.add_child(row)
		if line[0] != "":
			var k := Label.new()
			k.theme_type_variation = &"SectionLabel" if line[1] != "" else &"HeaderLabel"
			k.text = line[0]
			row.add_child(k)
		if line[1] != "":
			var v := Label.new()
			v.theme_type_variation = &"BodyLabel"
			v.text = line[1]
			v.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			row.add_child(v)


class Sheet extends OverlaySheet:
	func _init() -> void:
		super("SHEET 06", "CREDITS", 560.0)

	func build() -> void:
		Credits.add_to(content)
