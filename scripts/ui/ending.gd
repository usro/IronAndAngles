extends Control
## Campaign complete: a closing report sheet with the campaign's numbers and the credits.
## The player can keep playing (back to the region map) or return to the main menu.


func _ready() -> void:
	BlueprintBackdrop.add_to(self, "SHEET 07 — CAMPAIGN COMPLETE")
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var sheet := PanelContainer.new()
	sheet.theme_type_variation = &"SheetPanel"
	sheet.custom_minimum_size = Vector2(980, 0)
	center.add_child(sheet)
	var root := HBoxContainer.new()
	root.add_theme_constant_override("separation", 32)
	sheet.add_child(root)

	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(left)
	var stamp := Stamp.new()
	stamp.text = "CONTRACT FULFILLED"
	stamp.color = Blueprint.AMBER
	stamp.custom_minimum_size = Vector2(380, 120)
	left.add_child(stamp)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 12)
	left.add_child(gap)
	_label(left, "The battery's work is done. Its guns are spoken of from the trebuchet yards to the orbital rails.",
		&"BodyLabel")
	left.add_child(HSeparator.new())
	var p := GameState.player
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18)
	left.add_child(grid)
	_pair(grid, "WEEKS IN THE FIELD", str(int(GameState.economy_state.get(StrategyController.KEY_WEEK, 0))))
	_pair(grid, "CONTRACTS WON", str(CampaignGoal.total_victories(p)))
	for era in GameConstants.Era.values():
		_pair(grid, "  %s" % GameConstants.era_name(era).to_upper(), str(int(p.era_victories.get(str(era), 0))))
	_pair(grid, "RESEARCH COMPLETED", "%d / %d" % [p.unlocked_tech.size(), DataRegistry.tech.size()])
	_pair(grid, "FUNDS", Blueprint.money(p.money))
	left.add_child(HSeparator.new())
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	left.add_child(buttons)
	var keep := Button.new()
	keep.text = "Keep playing"
	keep.theme_type_variation = &"PrimaryButton"
	keep.custom_minimum_size = Vector2(200, 44)
	keep.pressed.connect(SceneRouter.goto.bind(SceneRouter.Screen.REGION_MAP))
	buttons.add_child(keep)
	var menu := Button.new()
	menu.text = "Main menu"
	menu.custom_minimum_size = Vector2(160, 44)
	menu.pressed.connect(SceneRouter.goto.bind(SceneRouter.Screen.MAIN_MENU))
	buttons.add_child(menu)
	keep.grab_focus.call_deferred()

	root.add_child(VSeparator.new())
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 8)
	right.custom_minimum_size = Vector2(380, 0)
	root.add_child(right)
	Credits.add_to(right)


func _pair(grid: GridContainer, key: String, value: String) -> void:
	_label(grid, key, &"CaptionLabel")
	_label(grid, value, &"MonoLabel")


func _label(parent: Node, text: String, variation: StringName) -> Label:
	var l := Label.new()
	l.theme_type_variation = variation
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if variation == &"BodyLabel" else TextServer.AUTOWRAP_OFF
	if variation == &"BodyLabel":
		l.custom_minimum_size = Vector2(500, 0)
	parent.add_child(l)
	return l
