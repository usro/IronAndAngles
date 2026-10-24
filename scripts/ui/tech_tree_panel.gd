class_name TechTreePanel
extends PanelContainer
## Functional research overlay opened from the region map. Plain controls; the UI session
## restyles it. All rules live in TechTree: this only lists nodes and forwards clicks.

const STATUS_TEXT := {
	TechTree.Status.UNLOCKABLE: "",
	TechTree.Status.ALREADY_UNLOCKED: "Researched",
	TechTree.Status.MISSING_PREREQUISITES: "Needs prerequisites",
	TechTree.Status.ERA_LOCKED: "Later era",
	TechTree.Status.INSUFFICIENT_FUNDS: "Can't afford",
	TechTree.Status.UNKNOWN: "?",
}

var _tree := TechTree.for_game()
var _list: VBoxContainer
var _era_label: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	var top := HBoxContainer.new()
	root.add_child(top)
	var title := Label.new()
	title.text = "RESEARCH"
	title.add_theme_font_size_override("font_size", 28)
	top.add_child(title)
	_era_label = Label.new()
	_era_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_era_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_era_label.add_theme_font_size_override("font_size", 20)
	top.add_child(_era_label)
	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(queue_free)
	top.add_child(close)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_list)

	EventBus.money_changed.connect(_on_money_changed)
	_refresh()


func _on_money_changed(_balance: int, _delta: int, _reason: String) -> void:
	_refresh()


func _refresh() -> void:
	var player := GameState.player
	_era_label.text = "Era: %s    Funds: %d" % [GameConstants.era_name(player.current_era), player.money]
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()

	var last_era := -1
	for id in _tree.sorted_ids():
		var node: TechNodeData = _tree.nodes[id]
		if node.era != last_era:
			last_era = node.era
			var header := Label.new()
			header.text = "— %s —" % GameConstants.era_name(node.era)
			header.add_theme_font_size_override("font_size", 20)
			_list.add_child(header)
		_list.add_child(_row(node))


func _row(node: TechNodeData) -> Control:
	var status := _tree.status(node.id)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	var info := Label.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var lines := ["%s%s  (%d)" % [node.display_name, "  [era gate]" if node.era_gate else "", node.research_cost]]
	if not node.description.is_empty():
		lines.append(node.description)
	var unlocks := _names(node.unlocks_weapons, DataRegistry.weapons) + _names(node.unlocks_ammo, DataRegistry.ammo)
	if not unlocks.is_empty():
		lines.append("Unlocks: " + ", ".join(unlocks))
	if not node.prerequisites.is_empty():
		lines.append("Requires: " + ", ".join(_names(node.prerequisites, DataRegistry.tech)))
	info.text = "\n".join(lines)
	if status == TechTree.Status.ALREADY_UNLOCKED:
		info.modulate = Color(0.6, 1.0, 0.6)
	elif status != TechTree.Status.UNLOCKABLE and status != TechTree.Status.INSUFFICIENT_FUNDS:
		info.modulate = Color(1, 1, 1, 0.5)
	row.add_child(info)

	var button := Button.new()
	button.custom_minimum_size = Vector2(170, 0)
	button.text = "Research" if status == TechTree.Status.UNLOCKABLE else STATUS_TEXT[status]
	button.disabled = status != TechTree.Status.UNLOCKABLE
	button.pressed.connect(_unlock.bind(node.id))
	row.add_child(button)
	return row


func _unlock(id: StringName) -> void:
	# Money change triggers _refresh through EventBus.
	_tree.unlock(id)


static func _names(ids: Array[StringName], table: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for id in ids:
		var res: Resource = table.get(id)
		out.append(res.display_name if res else String(id))
	return out
