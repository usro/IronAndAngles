class_name TechTreePanel
extends PanelContainer
## Research overlay opened from the region map: the tech tree drawn from each node's
## `tree_position` and prerequisites, grouped into era bands, with a detail card for the selected
## node. All rules live in TechTree: this only shows nodes and forwards clicks.

const STATUS_TEXT := {
	TechTree.Status.UNLOCKABLE: "Available",
	TechTree.Status.ALREADY_UNLOCKED: "Researched",
	TechTree.Status.MISSING_PREREQUISITES: "Needs prerequisites",
	TechTree.Status.ERA_LOCKED: "Later era",
	TechTree.Status.INSUFFICIENT_FUNDS: "Can't afford",
	TechTree.Status.UNKNOWN: "?",
}
const STATUS_VARIATION := {
	TechTree.Status.UNLOCKABLE: &"TechAvailable",
	TechTree.Status.ALREADY_UNLOCKED: &"TechResearched",
	TechTree.Status.INSUFFICIENT_FUNDS: &"TechUnaffordable",
}
const ROW_PITCH := 96.0
const MIN_COL_PITCH := 112.0
const HEADER_H := 34.0
const NODE_GAP := Vector2(20, 22)

var _tree := TechTree.for_game()
var _era_label: Label
var _funds_label: Label
var _graph: Control
var _scroll: ScrollContainer
var _node_buttons: Dictionary = {}  # id -> Button
var _selected: StringName = &""
var _detail_title: Label
var _detail_meta: Label
var _detail_desc: Label
var _detail_unlocks: HBoxContainer
var _detail_requires: Label
var _research_button: Button
var _col_pitch := MIN_COL_PITCH


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := StyleBoxFlat.new()
	shade.bg_color = Color(Blueprint.PAPER_DARK, 0.9)
	add_theme_stylebox_override("panel", shade)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	add_child(margin)
	var sheet := PanelContainer.new()
	sheet.theme_type_variation = &"SheetPanel"
	margin.add_child(sheet)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	sheet.add_child(root)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 14)
	root.add_child(top)
	var heading := VBoxContainer.new()
	heading.add_theme_constant_override("separation", 0)
	top.add_child(heading)
	_label(heading, "R&D DIVISION · SHEET 03", &"SectionLabel")
	var title := _label(heading, "RESEARCH", &"HeaderLabel")
	title.add_theme_font_size_override("font_size", 24)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)
	_label(top, "ERA", &"SectionLabel")
	_era_label = _label(top, "", &"ValueLabel")
	_era_label.add_theme_color_override("font_color", Blueprint.LINE)
	_label(top, "FUNDS", &"SectionLabel")
	_funds_label = _label(top, "", &"MoneyLabel")
	var close := Button.new()
	close.text = "Close  [Esc]"
	close.pressed.connect(queue_free)
	top.add_child(close)
	for c in top.get_children():
		if c is Label:
			c.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.resized.connect(_layout)
	root.add_child(_scroll)
	_graph = Control.new()
	_graph.draw.connect(_draw_graph)
	_scroll.add_child(_graph)
	for id in _tree.sorted_ids():
		var b := Button.new()
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.clip_text = true
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(_select.bind(id))
		_graph.add_child(b)
		_node_buttons[id] = b

	root.add_child(_build_detail())
	EventBus.money_changed.connect(_on_money_changed)
	var first := _tree.unlockable_ids()
	_selected = first[0] if not first.is_empty() else _tree.sorted_ids()[0]
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		queue_free()


func _on_money_changed(_balance: int, _delta: int, _reason: String) -> void:
	_refresh()


func _select(id: StringName) -> void:
	_selected = id
	_refresh()


func _unlock(id: StringName) -> void:
	# Money change triggers _refresh through EventBus.
	_tree.unlock(id)


# --- Refresh ---

func _refresh() -> void:
	var player := GameState.player
	_era_label.text = GameConstants.era_name(player.current_era).to_upper()
	_funds_label.text = Blueprint.money(player.money)
	for id in _node_buttons:
		var node: TechNodeData = _tree.nodes[id]
		var status := _tree.status(id)
		var b: Button = _node_buttons[id]
		b.theme_type_variation = STATUS_VARIATION.get(status, &"TechLocked")
		var second := "✓ RESEARCHED" if status == TechTree.Status.ALREADY_UNLOCKED else Blueprint.money(node.research_cost)
		if node.era_gate:
			second = "◆ GATE  " + second
		b.text = "%s\n%s" % [node.display_name.to_upper(), second]
		b.tooltip_text = STATUS_TEXT[status]
		if id == _selected:
			b.add_theme_stylebox_override("normal", _selected_style(b))
		else:
			b.remove_theme_stylebox_override("normal")
	_refresh_detail()
	_graph.queue_redraw()


func _selected_style(b: Button) -> StyleBox:
	var s := (b.get_theme_stylebox("normal") as StyleBoxFlat).duplicate()
	s.set_border_width_all(2)
	s.border_color = Blueprint.AMBER
	return s


func _refresh_detail() -> void:
	var node: TechNodeData = _tree.nodes.get(_selected)
	if node == null:
		return
	var status := _tree.status(_selected)
	_detail_title.text = node.display_name.to_upper()
	_detail_meta.text = "%s%s · %s · %s" % [GameConstants.era_name(node.era).to_upper(),
		" · ERA GATE" if node.era_gate else "", Blueprint.money(node.research_cost), STATUS_TEXT[status].to_upper()]
	_detail_meta.add_theme_color_override("font_color", {
		TechTree.Status.UNLOCKABLE: Blueprint.AMBER, TechTree.Status.ALREADY_UNLOCKED: Blueprint.LINE,
		TechTree.Status.INSUFFICIENT_FUNDS: Blueprint.RED}.get(status, Blueprint.TEXT_DIM))
	_detail_desc.text = node.description
	for c in _detail_unlocks.get_children():
		_detail_unlocks.remove_child(c)
		c.queue_free()
	for wid in node.unlocks_weapons:
		var w := DataRegistry.get_weapon(wid)
		if w:
			_detail_unlocks.add_child(WeaponIcon.create(w, Vector2(56, 36)))
	var unlocks := _names(node.unlocks_weapons, DataRegistry.weapons) + _names(node.unlocks_ammo, DataRegistry.ammo)
	if not unlocks.is_empty():
		_label(_detail_unlocks, "UNLOCKS  " + ", ".join(unlocks), &"MonoLabel").size_flags_vertical = \
			Control.SIZE_SHRINK_CENTER
	_detail_unlocks.visible = not unlocks.is_empty()
	_detail_requires.text = "REQUIRES  " + ", ".join(_names(node.prerequisites, DataRegistry.tech)) \
		if not node.prerequisites.is_empty() else "NO PREREQUISITES"
	_research_button.text = "Research  %s" % Blueprint.money(node.research_cost) \
		if status == TechTree.Status.UNLOCKABLE else STATUS_TEXT[status]
	_research_button.disabled = status != TechTree.Status.UNLOCKABLE


# --- Layout and drawing ---

func _layout() -> void:
	var cols := 1
	var rows := 1
	for id in _tree.nodes:
		var p: Vector2i = _tree.nodes[id].tree_position
		cols = maxi(cols, p.x + 1)
		rows = maxi(rows, p.y + 1)
	_col_pitch = maxf(MIN_COL_PITCH, _scroll.size.x / cols)
	var row_pitch := maxf(ROW_PITCH, floorf((_scroll.size.y - HEADER_H - 16.0) / rows))
	_graph.custom_minimum_size = Vector2(_col_pitch * cols, HEADER_H + row_pitch * rows)
	for id in _node_buttons:
		var p: Vector2i = _tree.nodes[id].tree_position
		var b: Button = _node_buttons[id]
		b.size = Vector2(_col_pitch - NODE_GAP.x, minf(row_pitch - NODE_GAP.y, 62.0))
		b.position = Vector2(p.x * _col_pitch + NODE_GAP.x * 0.5,
			HEADER_H + p.y * row_pitch + (row_pitch - b.size.y) * 0.5)
	_graph.queue_redraw()


func _draw_graph() -> void:
	# Era bands: one per era, spanning its nodes' columns.
	var spans := {}
	for id in _tree.nodes:
		var n: TechNodeData = _tree.nodes[id]
		var s: Vector2i = spans.get(n.era, Vector2i(n.tree_position.x, n.tree_position.x))
		spans[n.era] = Vector2i(mini(s.x, n.tree_position.x), maxi(s.y, n.tree_position.x))
	var h := _graph.size.y
	var current := GameState.player.current_era
	for era in spans:
		var s: Vector2i = spans[era]
		var r := Rect2(s.x * _col_pitch + 4, 0, (s.y - s.x + 1) * _col_pitch - 8, h)
		var reached: bool = era <= current
		_graph.draw_rect(r, Color(Blueprint.LINE, 0.06 if reached else 0.02))
		_graph.draw_line(r.position, Vector2(r.position.x, r.end.y), Color(Blueprint.LINE, 0.2), 1.0)
		_graph.draw_line(r.position + Vector2(0, HEADER_H - 6), Vector2(r.end.x, HEADER_H - 6),
			Color(Blueprint.LINE, 0.35 if reached else 0.15), 1.0)
		var label := "%s%s" % [GameConstants.era_name(era).to_upper(), "" if reached else "  · LOCKED"]
		Blueprint.draw_text(_graph, r.position + Vector2(10, 18), label,
			Blueprint.LINE if era == current else (Blueprint.TEXT_DIM if reached else Color(Blueprint.TEXT_DIM, 0.5)),
			12, HORIZONTAL_ALIGNMENT_LEFT, Blueprint.FONT_MONO_BOLD)
	# Connectors: prerequisite's right edge to the node's left edge, elbowed.
	for id in _node_buttons:
		var node: TechNodeData = _tree.nodes[id]
		var to: Button = _node_buttons[id]
		for pre in node.prerequisites:
			var from: Button = _node_buttons.get(pre)
			if from == null:
				continue
			var a := from.position + Vector2(from.size.x, from.size.y * 0.5)
			var b := to.position + Vector2(0, to.size.y * 0.5)
			var mid_x := b.x - NODE_GAP.x * 0.5
			var done := _tree.is_unlocked(pre)
			var col := Color(Blueprint.LINE, 0.85) if done else Color(Blueprint.LINE, 0.3)
			if id == _selected or pre == _selected:
				col = Blueprint.AMBER
			var pts := PackedVector2Array([a, Vector2(mid_x, a.y), Vector2(mid_x, b.y), b])
			_graph.draw_polyline(pts, col, 1.5)
			_graph.draw_colored_polygon(PackedVector2Array([b, b + Vector2(-7, -4), b + Vector2(-7, 4)]), col)
			_graph.draw_circle(a, 2.5, col)


func _build_detail() -> Control:
	var card := PanelContainer.new()
	card.theme_type_variation = &"SelectedCardPanel"
	card.custom_minimum_size = Vector2(0, 150)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	card.add_child(row)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 4)
	row.add_child(info)
	_detail_title = _label(info, "", &"HeaderLabel")
	_detail_meta = _label(info, "", &"CaptionLabel")
	_detail_desc = _label(info, "", &"BodyLabel")
	_detail_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_unlocks = HBoxContainer.new()
	info.add_child(_detail_unlocks)
	_detail_requires = _label(info, "", &"CaptionLabel")
	_research_button = Button.new()
	_research_button.theme_type_variation = &"PrimaryButton"
	_research_button.custom_minimum_size = Vector2(220, 48)
	_research_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_research_button.pressed.connect(func() -> void: _unlock(_selected))
	row.add_child(_research_button)
	return card


static func _label(parent: Node, text: String, variation: StringName) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = variation
	parent.add_child(l)
	return l


static func _names(ids: Array[StringName], table: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for id in ids:
		var res: Resource = table.get(id)
		out.append(res.display_name if res else String(id))
	return out
