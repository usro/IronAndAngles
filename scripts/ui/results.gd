extends Control
## Results screen: an after-action report sheet with the money ledger, a profit waterfall and the
## engagement figures. Reads GameState.last_battle_result and the economy's settlement report.

const SHEET_WIDTH := 1040.0


func _ready() -> void:
	BlueprintBackdrop.add_to(self, "SHEET 04 — AFTER-ACTION REPORT")
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 36)
	add_child(margin)
	var row := HBoxContainer.new()
	margin.add_child(row)
	row.add_child(_spacer())
	var sheet := PanelContainer.new()
	sheet.theme_type_variation = &"SheetPanel"
	sheet.custom_minimum_size = Vector2(SHEET_WIDTH, 0)
	row.add_child(sheet)
	row.add_child(_spacer())
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	sheet.add_child(root)

	var r := GameState.last_battle_result
	if r == null:
		_label(root, "No battle result", &"HeaderLabel")
	else:
		_build_report(root, r)
	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_END
	root.add_child(footer)
	var cont := Button.new()
	cont.text = "Continue"
	cont.theme_type_variation = &"PrimaryButton"
	cont.custom_minimum_size = Vector2(220, 44)
	cont.pressed.connect(_continue)
	footer.add_child(cont)
	cont.grab_focus.call_deferred()


## Back to the map, or to the ending the first time the campaign goal is reached.
func _continue() -> void:
	if CampaignGoal.claim_ending(GameState.player):
		SceneRouter.goto(SceneRouter.Screen.ENDING)
	else:
		SceneRouter.goto(SceneRouter.Screen.REGION_MAP)


func _build_report(root: VBoxContainer, r: BattleResult) -> void:
	var contract := DataRegistry.get_contract(r.contract_id)
	var plot := DataRegistry.get_plot(r.plot_id) if r.plot_id != &"" else null

	var head := HBoxContainer.new()
	root.add_child(head)
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", 0)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(titles)
	_label(titles, "AFTER-ACTION REPORT", &"SectionLabel")
	var title := _label(titles, (contract.client_name if contract else String(r.contract_id)).to_upper(), &"TitleLabel")
	title.add_theme_font_size_override("font_size", 28)
	if plot:
		_label(titles, "%s · %.0f m to target" % [plot.display_name, plot.target_distance_m], &"CaptionLabel")
	var stamp := Stamp.new()
	stamp.text = "VICTORY" if r.victory else "DEFEAT"
	stamp.color = Blueprint.AMBER if r.victory else Blueprint.RED
	stamp.custom_minimum_size = Vector2(280, 90)
	head.add_child(stamp)
	root.add_child(HSeparator.new())

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 28)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)

	# Ledger column.
	var ledger := VBoxContainer.new()
	ledger.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ledger.size_flags_stretch_ratio = 1.4
	body.add_child(ledger)
	_section(ledger, "LEDGER")
	var report := StrategyController.new().last_settlement()
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("v_separation", 2)
	ledger.add_child(grid)
	var steps: Array[Dictionary] = []
	if report:
		_ledger_row(grid, "Payout", Blueprint.money(report.payout, true), Blueprint.LINE)
		if r.counter_battery_bonus > 0:
			_ledger_row(grid, "  incl. counter-battery bonus", Blueprint.money(r.counter_battery_bonus, true), Blueprint.AMBER)
		_ledger_row(grid, "Auction price", Blueprint.money(-report.auction_price), Blueprint.RED)
		_ledger_row(grid, "Shells fired", Blueprint.money(-report.ammo_spent), Blueprint.RED)
		var margin_text := "%d%% margin" % roundi(report.margin() * 100.0) if report.payout > 0 else "no payout"
		_ledger_row(grid, "Net profit", "%s  (%s)" % [Blueprint.money(report.net_profit(), true), margin_text],
			Blueprint.AMBER if report.net_profit() >= 0 else Blueprint.RED, true)
		if report.repair_cost > 0:
			_ledger_row(grid, "Repairs needed", "%s  →  %s after repairs" % [Blueprint.money(-report.repair_cost),
				Blueprint.money(report.net_after_repairs(), true)], Blueprint.TEXT_DIM)
		steps = [{"label": "Payout", "amount": report.payout, "kind": &"in"},
			{"label": "Auction price", "amount": report.auction_price, "kind": &"out"},
			{"label": "Shells", "amount": report.ammo_spent, "kind": &"out"},
			{"label": "Net profit", "amount": report.net_profit(), "kind": &"total"}]
		if report.repair_cost > 0:
			steps.append({"label": "Repairs", "amount": report.repair_cost, "kind": &"after"})
	else:
		_ledger_row(grid, "Payout", Blueprint.money(r.payout_earned, true), Blueprint.LINE)
		_ledger_row(grid, "Shells fired", Blueprint.money(-r.ammo_spent), Blueprint.RED)
		_ledger_row(grid, "Net profit", Blueprint.money(r.net_profit(), true), Blueprint.AMBER, true)
		steps = [{"label": "Payout", "amount": r.payout_earned, "kind": &"in"},
			{"label": "Shells", "amount": r.ammo_spent, "kind": &"out"},
			{"label": "Net profit", "amount": r.net_profit(), "kind": &"total"}]
	var chart := ProfitWaterfall.new()
	chart.steps = steps
	ledger.add_child(HSeparator.new())
	ledger.add_child(chart)

	body.add_child(VSeparator.new())

	# Engagement column.
	var eng := VBoxContainer.new()
	eng.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(eng)
	_section(eng, "ENGAGEMENT")
	var eng_row := HBoxContainer.new()
	eng_row.add_theme_constant_override("separation", 16)
	eng.add_child(eng_row)
	var gauge := ArcGauge.new()
	gauge.custom_minimum_size = Vector2(150, 150)
	gauge.fraction = r.accuracy()
	gauge.value_text = "%d%%" % roundi(r.accuracy() * 100.0)
	gauge.caption = "ACCURACY"
	gauge.color = Blueprint.LINE if r.accuracy() >= 0.5 else Blueprint.AMBER
	eng_row.add_child(gauge)
	var figures := GridContainer.new()
	figures.columns = 2
	figures.add_theme_constant_override("h_separation", 14)
	figures.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	eng_row.add_child(figures)
	_figure(figures, "Shells", "%d fired, %d hit (%d%% accuracy)" % [r.shells_fired, r.shells_hit,
		roundi(r.accuracy() * 100.0)])
	_figure(figures, "Targets", "%d destroyed" % r.targets_destroyed)
	_figure(figures, "Enemy gun", "destroyed" if r.enemy_gun_destroyed else "survived")
	_figure(figures, "Time", "%d:%02d" % [int(r.duration_s) / 60, int(r.duration_s) % 60])
	var damage := 0.0
	for id in r.damage_taken:
		damage += r.damage_taken[id]
	_figure(figures, "Damage taken", "%.0f hp" % damage if damage > 0.0 else "none")
	if not r.ammo_used.is_empty():
		var used := PackedStringArray()
		for id in r.ammo_used:
			var a := DataRegistry.get_ammo(id)
			used.append("%s ×%d" % [a.display_name if a else String(id), r.ammo_used[id]])
		_figure(figures, "Ammo used", ", ".join(used))

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	eng.add_child(spacer)
	var funds_card := PanelContainer.new()
	funds_card.theme_type_variation = &"CardPanel"
	eng.add_child(funds_card)
	var funds := HBoxContainer.new()
	funds_card.add_child(funds)
	var funds_caption := _label(funds, "FUNDS NOW", &"SectionLabel", true)
	funds_caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var money := _label(funds, Blueprint.money(GameState.player.money), &"MoneyLabel")
	money.add_theme_font_size_override("font_size", 26)
	if GameState.player.money < 0:
		money.add_theme_color_override("font_color", Blueprint.RED)


func _ledger_row(grid: GridContainer, key: String, value: String, col: Color, emphasis := false) -> void:
	var k := _label(grid, key, &"BodyLabel", true)
	var v := _label(grid, value, &"ValueLabel")
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.add_theme_color_override("font_color", col)
	if emphasis:
		k.add_theme_font_override("font", Blueprint.FONT_BODY_BOLD)
		v.add_theme_font_size_override("font_size", 20)


func _figure(grid: GridContainer, key: String, value: String) -> void:
	_label(grid, key.to_upper(), &"CaptionLabel")
	_label(grid, value, &"MonoLabel")


func _section(parent: Node, text: String) -> void:
	_label(parent, text, &"SectionLabel").add_theme_color_override("font_color", Blueprint.LINE)


func _label(parent: Node, text: String, variation: StringName, expand := false) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = variation
	if expand:
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(l)
	return l


static func _spacer() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c
