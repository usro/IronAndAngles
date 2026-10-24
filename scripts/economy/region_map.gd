extends Control
## Region map: plots on a drafted map, the auction, shop and repairs, in the blueprint theme.
## All rules live in StrategyController and the economy model: this script only renders state
## and forwards clicks.

const MAP_PLOT_SIZE := Vector2(150, 36)
const TAG_OFFSET := Vector2(26, -18)
const TAB_WIDTH := 500.0

var _controller := StrategyController.new()
var _selected: Auction.Lot

var _funds_label: Label
var _era_label: Label
var _map: DraftedMap
var _plot_buttons: Dictionary = {}  # lot key -> Button (map tag)
var _offer_buttons: Dictionary = {}  # lot key -> Button (chip in the offers list)
var _offers_box: VBoxContainer
var _report_card: PanelContainer
var _report_label: Label
var _lot_title: Label
var _lot_brief: Label
var _lot_specs: Dictionary = {}  # spec name -> value Label
var _my_bid_label: Label
var _bid_spin: SpinBox
var _bid_button: Button
var _resolve_button: Button
var _status_label: Label
var _outcome_card: PanelContainer
var _outcome_box: VBoxContainer
var _deploy_button: Button
var _deploy_hint: Label
var _next_button: Button
var _rivals_box: VBoxContainer
var _auction_scroll: ScrollContainer
var _shop_box: VBoxContainer
var _repair_box: VBoxContainer
var _saved_label: Label


func _ready() -> void:
	_build()
	EventBus.money_changed.connect(_on_money_changed)
	EventBus.inventory_changed.connect(_refresh_store)
	_on_money_changed(GameState.player.money, 0, "")
	_show_last_report()
	_new_round()


# --- Actions ---

func _new_round() -> void:
	_controller.start_round()
	_selected = null
	_status_label.text = ""
	_clear(_outcome_box)
	_outcome_card.visible = false
	_build_offers()
	_build_map_plots()
	if not _controller.auction.lots.is_empty():
		_select(_controller.auction.lots[0])
	_refresh_auction()


func _open_research() -> void:
	var panel := TechTreePanel.new()
	# Research changes what the shop sells.
	panel.tree_exited.connect(_refresh_store)
	add_child(panel)


func _select(lot: Auction.Lot) -> void:
	_selected = lot
	_refresh_auction()
	# The Battery tab shows each gun's reach against the selected plot.
	_refresh_store()


func _place_bid() -> void:
	if _selected == null:
		return
	var err := _controller.place_player_bid(_selected, int(_bid_spin.value))
	_status_label.text = Auction.error_text(err)
	_refresh_auction()


func _resolve() -> void:
	_clear(_outcome_box)
	for outcome in _controller.resolve():
		var row := HBoxContainer.new()
		_outcome_box.add_child(row)
		var who := _label(row, outcome.contract.client_name, &"BodyLabel", true)
		who.clip_text = true
		if outcome.sold():
			var is_mine := outcome.winner_id == Auction.PLAYER_ID
			var winner := _label(row, "%s · %s" % [_controller.bidder_name(outcome.winner_id), outcome.plot.display_name],
				&"CaptionLabel")
			winner.add_theme_color_override("font_color", Blueprint.AMBER if is_mine else Blueprint.TEXT_DIM)
			_label(row, Blueprint.money(outcome.price), &"MonoLabel")
		else:
			_label(row, "no bids met the reserve", &"CaptionLabel")
	var mine := _controller.player_outcome()
	var verdict := _label(_outcome_box, "CONTRACT WON — DEPLOY WHEN READY" if mine else "NOTHING WON THIS WEEK",
		&"HeaderLabel")
	verdict.add_theme_font_size_override("font_size", 14)
	verdict.add_theme_color_override("font_color", Blueprint.AMBER if mine else Blueprint.TEXT_DIM)
	_outcome_card.visible = true
	_status_label.text = ""
	_refresh_auction()
	_reveal_actions()


## Brings the outcome and Deploy / Next week into view once the tab has laid out again.
func _reveal_actions() -> void:
	await get_tree().process_frame
	if is_instance_valid(_deploy_button):
		_auction_scroll.ensure_control_visible(_deploy_button)


func _deploy() -> void:
	_controller.deploy()


func _buy_weapon(id: StringName) -> void:
	_status_label.text = Shop.status_text(_controller.shop.buy_weapon(GameState.player, id))


func _buy_ammo(id: StringName, count: int) -> void:
	_status_label.text = Shop.status_text(_controller.shop.buy_ammo(GameState.player, id, count))


func _repair(id: StringName, hp: float) -> void:
	_status_label.text = Shop.status_text(_controller.shop.repair(GameState.player, id, hp))


func _sell(id: StringName) -> void:
	_status_label.text = Shop.status_text(_controller.shop.sell_weapon(GameState.player, id))


func _toggle_deploy(id: StringName) -> void:
	_status_label.text = Loadout.status_text(Loadout.toggle(GameState.player, DataRegistry.weapons, id))


# --- Refresh ---

func _on_game_saved(_slot: int) -> void:
	_saved_label.text = "AUTOSAVED %s" % Time.get_time_string_from_system().left(5)



func _on_money_changed(balance: int, _delta: int, _reason: String) -> void:
	_funds_label.text = Blueprint.money(balance)
	_funds_label.add_theme_color_override("font_color", Blueprint.AMBER if balance >= 0 else Blueprint.RED)
	_era_label.text = GameConstants.era_name(GameState.player.current_era).to_upper()
	if _controller.auction:
		_refresh_auction()
	_refresh_store()


func _refresh_auction() -> void:
	var auction := _controller.auction
	var resolved := auction.is_resolved
	var my_bid := auction.bid_of(Auction.PLAYER_ID)
	for key in _plot_buttons:
		var b: Button = _plot_buttons[key]
		b.button_pressed = _selected != null and _selected.key() == key
		b.disabled = resolved
	for key in _offer_buttons:
		var chip: Button = _offer_buttons[key]
		chip.button_pressed = _selected != null and _selected.key() == key
		chip.disabled = resolved
		chip.add_theme_color_override("font_color", Blueprint.AMBER if my_bid and my_bid.lot.key() == key
			else Blueprint.INK)
	_update_parcels()

	if _selected:
		var c := _selected.contract
		var p := _selected.plot
		_lot_title.text = "%s — %s" % [c.client_name, p.display_name]
		_lot_brief.text = c.briefing
		_lot_specs["PAYOUT"].text = Blueprint.money(c.payout)
		_lot_specs["RESERVE"].text = Blueprint.money(c.reserve_price)
		_lot_specs["DIFFICULTY"].text = "■".repeat(c.difficulty) + "□".repeat(maxi(0, 5 - c.difficulty))
		_lot_specs["TERRAIN"].text = GameConstants.TerrainProfile.keys()[p.terrain_profile].capitalize()
		_lot_specs["HEIGHT"].text = "%+.0f m" % p.height_advantage_m
		_lot_specs["RANGE"].text = "%.0f m" % p.target_distance_m
		_bid_spin.min_value = c.reserve_price
		_bid_spin.max_value = maxi(c.reserve_price, GameState.player.money)
	else:
		_lot_title.text = "No contracts on offer." if auction.lots.is_empty() else "Select a plot on the map."
		_lot_brief.text = ""
		for k in _lot_specs:
			_lot_specs[k].text = "—"
	_my_bid_label.text = "YOUR SEALED BID: %s on %s" % [Blueprint.money(my_bid.amount), my_bid.lot.plot.display_name] \
		if my_bid else "NO BID PLACED"
	_my_bid_label.add_theme_color_override("font_color", Blueprint.AMBER if my_bid else Blueprint.TEXT_DIM)

	var can_bid := not resolved and _selected != null
	_bid_spin.editable = can_bid
	_bid_button.disabled = not can_bid
	_resolve_button.disabled = resolved or auction.lots.is_empty()
	_deploy_button.disabled = _controller.player_outcome() == null \
		or Loadout.deployed(GameState.player, DataRegistry.weapons).is_empty()
	_next_button.disabled = not resolved

	_clear(_rivals_box)
	var richest := 1
	for rival in _controller.rivals:
		richest = maxi(richest, _controller.ledger.money(rival.id))
	for rival in _controller.rivals:
		var funds := _controller.ledger.money(rival.id)
		var row := HBoxContainer.new()
		_rivals_box.add_child(row)
		var name_label := _label(row, rival.display_name, &"BodyLabel")
		name_label.custom_minimum_size = Vector2(190, 0)
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.max_value = richest
		bar.value = funds
		bar.custom_minimum_size = Vector2(0, 8)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(bar)
		var amount := _label(row, Blueprint.money(funds), &"MonoLabel")
		amount.custom_minimum_size = Vector2(64, 0)
		amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT


func _refresh_store() -> void:
	if _shop_box == null:
		return
	var shop := _controller.shop
	var player := GameState.player
	_clear(_shop_box)
	_section(_shop_box, "WEAPONS")
	for w in shop.weapon_catalog():
		var status := shop.check_weapon(player, w.id)
		var card := _card(_shop_box)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		card.add_child(row)
		row.add_child(WeaponIcon.create(w))
		var info := VBoxContainer.new()
		info.add_theme_constant_override("separation", 0)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		_label(info, w.display_name, &"ValueLabel")
		var line := "%s · %s" % [GameConstants.era_name(w.era).to_upper(),
			GameConstants.LauncherType.keys()[w.launcher_type]]
		if status != Shop.Status.OK:
			line += " · " + Shop.status_text(status)
		var caption := _label(info, line, &"CaptionLabel")
		if status == Shop.Status.ALREADY_OWNED:
			caption.add_theme_color_override("font_color", Blueprint.LINE)
		var buy := _row_button(row, "Buy  %s" % Blueprint.money(w.purchase_cost), _buy_weapon.bind(w.id),
			status != Shop.Status.OK)
		buy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		buy.custom_minimum_size = Vector2(110, 0)
	_section(_shop_box, "AMMUNITION  ·  stocking fee now, full shell price when fired")
	for a in shop.ammo_catalog():
		var card := _card(_shop_box)
		var row := HBoxContainer.new()
		card.add_child(row)
		var info := VBoxContainer.new()
		info.add_theme_constant_override("separation", 0)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		_label(info, a.display_name, &"ValueLabel")
		_label(info, "%s per shot" % Blueprint.money(a.cost_per_shell), &"CaptionLabel")
		var stock := _label(row, "×%d" % player.ammo_count(a.id), &"ValueLabel")
		stock.custom_minimum_size = Vector2(56, 0)
		stock.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		stock.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		if player.ammo_count(a.id) == 0:
			stock.add_theme_color_override("font_color", Blueprint.TEXT_DIM)
		if not shop.is_ammo_unlocked(player, a.id):
			_chip(row, Shop.status_text(Shop.Status.LOCKED), Callable(), true)
			continue
		for count in [10, 50]:
			_chip(row, "+%d  %s" % [count, Blueprint.money(shop.ammo_price(a.id, count))], _buy_ammo.bind(a.id, count),
				shop.check_ammo(player, a.id, count) != Shop.Status.OK)

	_clear(_repair_box)
	var deployed := Loadout.deployed(player, DataRegistry.weapons)
	_section(_repair_box, "BATTERY  ·  %d / %d SLOTS DEPLOYED  ·  more slots in later eras" % [deployed.size(),
		Loadout.slots(player.current_era)])
	if player.owned_weapons.is_empty():
		_label(_repair_box, "You own no weapons.", &"BodyLabel")
	var plot := _selected.plot if _selected else null
	for id in player.owned_weapons:
		var w := DataRegistry.get_weapon(id)
		if w == null:
			continue
		var is_deployed := deployed.has(w)
		var hp: float = player.weapon_health.get(id, 0.0)
		var card := _card(_repair_box)
		if not is_deployed:
			card.modulate = Color(1, 1, 1, 0.75)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		card.add_child(row)
		row.add_child(WeaponIcon.create(w))
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		var title := _label(info, "%s  ·  %s" % [w.display_name, "DEPLOYED" if is_deployed else "RESERVE"], &"ValueLabel")
		if is_deployed:
			title.add_theme_color_override("font_color", Blueprint.AMBER)
		var bar := ProgressBar.new()
		bar.max_value = w.max_health
		bar.value = hp
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0, 10)
		if hp < w.max_health * 0.5:
			var fill := (get_theme_stylebox("fill", "ProgressBar") as StyleBoxFlat).duplicate()
			fill.bg_color = Blueprint.AMBER if hp > 0.0 else Blueprint.RED
			bar.add_theme_stylebox_override("fill", fill)
		info.add_child(bar)
		_label(info, "%.0f / %.0f hp · %s per hp" % [hp, w.max_health, Blueprint.money(w.repair_cost_per_hp)],
			&"CaptionLabel")
		var reach := _reach_text(w, plot)
		if not reach.is_empty():
			var reach_label := _label(info, reach, &"CaptionLabel")
			reach_label.add_theme_color_override("font_color", Blueprint.RED if reach.begins_with("✗") else Blueprint.LINE)
		var buttons := VBoxContainer.new()
		row.add_child(buttons)
		var toggle_status := Loadout.check_toggle(player, DataRegistry.weapons, id)
		var toggle := _chip(buttons, "Stand down" if is_deployed else "Deploy", _toggle_deploy.bind(id),
			toggle_status != Loadout.Status.OK)
		toggle.tooltip_text = Loadout.status_text(toggle_status) if toggle_status != Loadout.Status.OK else ""
		_chip(buttons, "Repair  %s" % Blueprint.money(shop.repair_cost(player, id)), _repair.bind(id, INF),
			shop.check_repair(player, id) != Shop.Status.OK)
		var affordable := shop.affordable_repair_hp(player, id)
		if affordable > 0.0 and affordable < shop.missing_health(player, id):
			_chip(buttons, "Repair what I can  %s" % Blueprint.money(shop.repair_cost(player, id, affordable)),
				_repair.bind(id, affordable), shop.check_repair(player, id, affordable) != Shop.Status.OK)
		var sell_status := shop.check_sell(player, id)
		var sell := _chip(buttons, "Sell  +%s" % Blueprint.money(shop.sell_value(player, id)), _sell.bind(id),
			sell_status != Shop.Status.OK)
		sell.tooltip_text = "50%% of the price (%s) minus repair cost" % Blueprint.money(w.purchase_cost) \
			if sell_status == Shop.Status.OK else Shop.status_text(sell_status)
	_refresh_deploy_hint()


## One line above the Deploy button: which guns go, or why none can.
func _refresh_deploy_hint() -> void:
	if not is_instance_valid(_deploy_hint):
		return
	var deployed := Loadout.deployed(GameState.player, DataRegistry.weapons)
	if is_instance_valid(_deploy_button) and _controller.auction:
		_deploy_button.disabled = _controller.player_outcome() == null or deployed.is_empty()
	if deployed.is_empty():
		_deploy_hint.text = "NO SERVICEABLE GUN: repair one in the Battery tab"
		_deploy_hint.add_theme_color_override("font_color", Blueprint.RED)
		return
	_deploy_hint.remove_theme_color_override("font_color")
	_deploy_hint.text = "BATTERY (%d/%d): %s  ·  change in the Battery tab" % [deployed.size(),
		Loadout.slots(GameState.player.current_era), ", ".join(deployed.map(func(w: WeaponData) -> String: return w.display_name))]


## "Reaches ~310 m ✓" against the selected plot, using the weapon's cheapest owned-or-first ammo.
func _reach_text(w: WeaponData, plot: PlotData) -> String:
	if plot == null or w.launcher_type == GameConstants.LauncherType.ORBITAL or w.allowed_ammo.is_empty():
		return ""
	var ammo := DataRegistry.get_ammo(w.allowed_ammo[0])
	if ammo == null:
		return ""
	var reach := PlotGenerator.max_range_m(w, ammo, plot)
	var ok := plot.target_distance_m <= reach
	return "%s reaches ~%.0f m  (%s: %.0f m)" % ["✓" if ok else "✗", reach, plot.display_name, plot.target_distance_m]


func _show_last_report() -> void:
	var report := _controller.last_settlement()
	if report == null:
		_report_card.visible = false
		return
	var contract := DataRegistry.get_contract(report.contract_id)
	_report_label.text = "LAST CONTRACT%s — %s\nNet %s · margin %d%%%s" % [
		": " + contract.client_name.to_upper() if contract else "", "VICTORY" if report.victory else "DEFEAT",
		Blueprint.money(report.net_profit(), true), roundi(report.margin() * 100.0),
		" · repairs %s" % Blueprint.money(report.repair_cost) if report.repair_cost > 0 else ""]


## Map markers follow the lots; tags are placed by _layout_plots.
func _update_parcels() -> void:
	if _map == null or _controller.auction == null:
		return
	var my_bid := _controller.auction.bid_of(Auction.PLAYER_ID)
	var list: Array[Dictionary] = []
	for lot in _controller.auction.lots:
		var b: Button = _plot_buttons.get(lot.key())
		list.append({"pos": lot.plot.map_position, "plot_id": lot.plot.id, "profile": lot.plot.terrain_profile,
			"selected": _selected != null and _selected.key() == lot.key(),
			"bid": my_bid != null and my_bid.lot.key() == lot.key(),
			"tag": Rect2(b.position, b.size) if b else Rect2()})
	_map.parcels = list


# --- Building ---

func _build() -> void:
	BlueprintBackdrop.add_to(self, "SHEET 02 — REGION MAP")
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	margin.add_theme_constant_override("margin_bottom", 28)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	var bar := PanelContainer.new()
	bar.theme_type_variation = &"BarPanel"
	root.add_child(bar)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 14)
	bar.add_child(top)
	var title := _label(top, "REGION MAP", &"TitleLabel")
	title.add_theme_font_size_override("font_size", 22)
	top.add_child(VSeparator.new())
	_label(top, "FUNDS", &"SectionLabel")
	_funds_label = _label(top, "", &"MoneyLabel")
	_label(top, "ERA", &"SectionLabel")
	_era_label = _label(top, "", &"ValueLabel")
	_era_label.add_theme_color_override("font_color", Blueprint.LINE)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)
	_row_button(top, "Research", _open_research).theme_type_variation = &"PrimaryButton"
	_row_button(top, "How to Play", func() -> void: add_child(HowToPlayPanel.new()))
	_saved_label = _label(top, "", &"CaptionLabel")
	_saved_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	EventBus.game_saved.connect(_on_game_saved)
	_row_button(top, "Main Menu", SceneRouter.goto.bind(SceneRouter.Screen.MAIN_MENU))

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	root.add_child(body)

	_map = DraftedMap.new()
	_map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map.resized.connect(_layout_plots)
	body.add_child(_map)

	var tabs := TabContainer.new()
	tabs.custom_minimum_size = Vector2(TAB_WIDTH, 0)
	body.add_child(tabs)
	tabs.add_child(_build_auction_tab())
	_shop_box = _scroll_tab(tabs, "Shop")
	_repair_box = _scroll_tab(tabs, "Battery")

	_status_label = _label(root, "", &"StatusLabel")


func _build_auction_tab() -> Control:
	var scroll := ScrollContainer.new()
	_auction_scroll = scroll
	scroll.name = "Auction"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 8)
	scroll.add_child(box)

	_report_card = _card(box)
	_report_label = _label(_report_card, "", &"MonoLabel")
	_report_label.add_theme_font_size_override("font_size", 12)

	_section(box, "CONTRACTS THIS WEEK")
	_offers_box = VBoxContainer.new()
	_offers_box.add_theme_constant_override("separation", 6)
	box.add_child(_offers_box)

	_section(box, "SELECTED LOT")
	var lot := _card(box)
	lot.theme_type_variation = &"SelectedCardPanel"
	var lot_box := VBoxContainer.new()
	lot.add_child(lot_box)
	_lot_title = _label(lot_box, "", &"HeaderLabel")
	_lot_title.add_theme_font_size_override("font_size", 15)
	_lot_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lot_brief = _label(lot_box, "", &"BodyLabel")
	_lot_brief.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lot_brief.custom_minimum_size = Vector2(420, 0)
	var specs := GridContainer.new()
	specs.columns = 3
	specs.add_theme_constant_override("h_separation", 18)
	specs.add_theme_constant_override("v_separation", 4)
	lot_box.add_child(specs)
	for key in ["PAYOUT", "RESERVE", "DIFFICULTY", "TERRAIN", "HEIGHT", "RANGE"]:
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", -2)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		specs.add_child(cell)
		_label(cell, key, &"CaptionLabel")
		var value := _label(cell, "—", &"ValueLabel")
		if key == "PAYOUT":
			value.add_theme_color_override("font_color", Blueprint.AMBER)
		_lot_specs[key] = value
	_my_bid_label = _label(lot_box, "", &"StatusLabel")

	var bid_row := HBoxContainer.new()
	box.add_child(bid_row)
	_bid_spin = SpinBox.new()
	_bid_spin.step = 10
	_bid_spin.prefix = "BID"
	_bid_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bid_row.add_child(_bid_spin)
	_bid_button = _row_button(bid_row, "Place sealed bid", _place_bid)
	_bid_button.theme_type_variation = &"PrimaryButton"
	_resolve_button = _row_button(box, "Close bidding", _resolve)

	_outcome_card = _card(box)
	_outcome_box = VBoxContainer.new()
	_outcome_card.add_child(_outcome_box)
	var action_row := HBoxContainer.new()
	box.add_child(action_row)
	_deploy_hint = _label(box, "", &"CaptionLabel")
	_deploy_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.move_child(_deploy_hint, action_row.get_index())
	_deploy_button = _row_button(action_row, "Deploy to battle", _deploy)
	_deploy_button.theme_type_variation = &"PrimaryButton"
	_deploy_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_next_button = _row_button(action_row, "Next week", _new_round)
	_next_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_section(box, "RIVAL WAR CHESTS")
	_rivals_box = VBoxContainer.new()
	box.add_child(_rivals_box)
	return scroll


func _build_offers() -> void:
	_clear(_offers_box)
	_offer_buttons.clear()
	for contract in _controller.offers:
		var card := _card(_offers_box)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 4)
		card.add_child(col)
		var head := HBoxContainer.new()
		col.add_child(head)
		_label(head, contract.client_name, &"ValueLabel", true)
		var money := _label(head, "PAYOUT %s · RESERVE %s" % [Blueprint.money(contract.payout),
			Blueprint.money(contract.reserve_price)], &"CaptionLabel")
		money.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var chips := HBoxContainer.new()
		col.add_child(chips)
		for lot in _controller.auction.lots_for(contract):
			var chip := _chip(chips, "◇ " + lot.plot.display_name, _select.bind(lot))
			chip.toggle_mode = true
			_offer_buttons[lot.key()] = chip


func _build_map_plots() -> void:
	for b in _plot_buttons.values():
		_map.remove_child(b)
		b.queue_free()
	_plot_buttons.clear()
	for lot in _controller.auction.lots:
		var b := Button.new()
		b.theme_type_variation = &"ParcelButton"
		b.toggle_mode = true
		b.text = "%s\n%s" % [lot.plot.display_name.to_upper(), lot.contract.client_name]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.size = MAP_PLOT_SIZE
		b.pressed.connect(_select.bind(lot))
		_map.add_child(b)
		_plot_buttons[lot.key()] = b
	_layout_plots()


## Places plot tags beside their parcel (PlotData.map_position); plots shared by several contracts
## stack downward. Tags flip to the left of the parcel near the right edge.
func _layout_plots() -> void:
	var used := {}
	for lot in _controller.auction.lots if _controller.auction else []:
		var b: Button = _plot_buttons.get(lot.key())
		if b == null:
			continue
		var stack: int = used.get(lot.plot.id, 0)
		used[lot.plot.id] = stack + 1
		var marker := lot.plot.map_position * _map.size
		var pos := marker + TAG_OFFSET + Vector2(0, stack * (MAP_PLOT_SIZE.y + 4))
		if pos.x + MAP_PLOT_SIZE.x > _map.size.x - 8:
			pos.x = marker.x - TAG_OFFSET.x - MAP_PLOT_SIZE.x
		b.position = pos.clamp(Vector2(8, 8), (_map.size - MAP_PLOT_SIZE - Vector2(8, 8)).max(Vector2.ZERO))
	_update_parcels()


# --- Widget helpers ---

func _scroll_tab(tabs: TabContainer, title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6)
	scroll.add_child(box)
	return box


func _section(parent: Node, text: String) -> void:
	var l := _label(parent, text, &"SectionLabel")
	l.add_theme_color_override("font_color", Blueprint.LINE)


func _card(parent: Node) -> PanelContainer:
	var card := PanelContainer.new()
	card.theme_type_variation = &"CardPanel"
	parent.add_child(card)
	return card


func _label(parent: Node, text: String, variation: StringName, expand := false) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = variation
	if expand:
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(l)
	return l


func _row_button(parent: Node, text: String, on_press: Callable, disabled := false) -> Button:
	var b := Button.new()
	b.text = text
	b.disabled = disabled
	if on_press.is_valid():
		b.pressed.connect(on_press)
	parent.add_child(b)
	return b


func _chip(parent: Node, text: String, on_press: Callable, disabled := false) -> Button:
	var b := _row_button(parent, text, on_press, disabled)
	b.theme_type_variation = &"ChipButton"
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return b


func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()
