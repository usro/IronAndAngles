extends Control
## Region map: plots on a map, the auction, shop and repairs. Plain built-in controls for now;
## the UI session restyles it. All rules live in StrategyController and the economy model:
## this script only renders state and forwards clicks.

const MAP_PLOT_SIZE := Vector2(150, 44)

var _controller := StrategyController.new()
var _selected: Auction.Lot

var _funds_label: Label
var _map: Panel
var _plot_buttons: Dictionary = {}  # lot key -> Button
var _offers_box: VBoxContainer
var _report_label: Label
var _lot_label: Label
var _bid_spin: SpinBox
var _bid_button: Button
var _resolve_button: Button
var _status_label: Label
var _outcome_label: Label
var _deploy_button: Button
var _next_button: Button
var _rivals_label: Label
var _shop_box: VBoxContainer
var _repair_box: VBoxContainer


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
	_outcome_label.text = ""
	_build_offers()
	_build_map_plots()
	if not _controller.auction.lots.is_empty():
		_select(_controller.auction.lots[0])
	_refresh_auction()


func _select(lot: Auction.Lot) -> void:
	_selected = lot
	_refresh_auction()


func _place_bid() -> void:
	if _selected == null:
		return
	var err := _controller.place_player_bid(_selected, int(_bid_spin.value))
	_status_label.text = Auction.error_text(err)
	_refresh_auction()


func _resolve() -> void:
	var lines := PackedStringArray()
	for outcome in _controller.resolve():
		if outcome.sold():
			lines.append("%s: won by %s on %s for %d" % [outcome.contract.client_name,
				_controller.bidder_name(outcome.winner_id), outcome.plot.display_name, outcome.price])
		else:
			lines.append("%s: no bids met the reserve" % outcome.contract.client_name)
	var mine := _controller.player_outcome()
	lines.append("")
	lines.append("You won a contract! Deploy when ready." if mine else "You won nothing this week.")
	_outcome_label.text = "\n".join(lines)
	_status_label.text = ""
	_refresh_auction()


func _deploy() -> void:
	_controller.deploy()


func _buy_weapon(id: StringName) -> void:
	_status_label.text = Shop.status_text(_controller.shop.buy_weapon(GameState.player, id))


func _buy_ammo(id: StringName, count: int) -> void:
	_status_label.text = Shop.status_text(_controller.shop.buy_ammo(GameState.player, id, count))


func _repair(id: StringName, hp: float) -> void:
	_status_label.text = Shop.status_text(_controller.shop.repair(GameState.player, id, hp))


# --- Refresh ---

func _on_money_changed(balance: int, _delta: int, _reason: String) -> void:
	_funds_label.text = "Funds: %d    Era: %s" % [balance, GameConstants.era_name(GameState.player.current_era)]
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
		b.modulate = Color(1, 0.85, 0.4) if my_bid and my_bid.lot.key() == key else Color.WHITE

	if _selected:
		var c := _selected.contract
		var p := _selected.plot
		_lot_label.text = "%s\n%s\nPlot: %s (%s, %+.0f m height, %.0f m to target)\nPayout %d   Reserve %d   Difficulty %d" % [
			c.client_name, c.briefing, p.display_name,
			GameConstants.TerrainProfile.keys()[p.terrain_profile].capitalize(),
			p.height_advantage_m, p.target_distance_m, c.payout, c.reserve_price, c.difficulty]
		_bid_spin.min_value = c.reserve_price
		_bid_spin.max_value = maxi(c.reserve_price, GameState.player.money)
	else:
		_lot_label.text = "No contracts on offer." if auction.lots.is_empty() else "Select a plot on the map."
	if my_bid:
		_lot_label.text += "\nYour bid: %d on %s" % [my_bid.amount, my_bid.lot.plot.display_name]

	var can_bid := not resolved and _selected != null
	_bid_spin.editable = can_bid
	_bid_button.disabled = not can_bid
	_resolve_button.disabled = resolved or auction.lots.is_empty()
	_deploy_button.disabled = _controller.player_outcome() == null
	_next_button.disabled = not resolved

	var rival_lines := PackedStringArray(["Rivals:"])
	for rival in _controller.rivals:
		rival_lines.append("  %s: %d" % [rival.display_name, _controller.ledger.money(rival.id)])
	_rivals_label.text = "\n".join(rival_lines)


func _refresh_store() -> void:
	if _shop_box == null:
		return
	var shop := _controller.shop
	var player := GameState.player
	_clear(_shop_box)
	_section(_shop_box, "Weapons")
	for w in shop.weapon_catalog():
		var status := shop.check_weapon(player, w.id)
		var text := "%s  (%d)" % [w.display_name, w.purchase_cost]
		if status != Shop.Status.OK:
			text += "  - %s" % Shop.status_text(status)
		_row_button(_shop_box, text, _buy_weapon.bind(w.id), status != Shop.Status.OK)
	_section(_shop_box, "Ammo (fired shells are charged in battle; stocking costs a fee)")
	for a in shop.ammo_catalog():
		var row := HBoxContainer.new()
		_shop_box.add_child(row)
		var label := Label.new()
		label.text = "%s  x%d  (%d/shot)" % [a.display_name, player.ammo_count(a.id), a.cost_per_shell]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		if not shop.is_ammo_unlocked(player, a.id):
			_row_button(row, Shop.status_text(Shop.Status.LOCKED), Callable(), true)
			continue
		for count in [10, 50]:
			_row_button(row, "+%d (%d)" % [count, shop.ammo_price(a.id, count)], _buy_ammo.bind(a.id, count),
				shop.check_ammo(player, a.id, count) != Shop.Status.OK)

	_clear(_repair_box)
	_section(_repair_box, "Weapon repairs")
	if player.owned_weapons.is_empty():
		_section(_repair_box, "You own no weapons.")
	for id in player.owned_weapons:
		var w := DataRegistry.get_weapon(id)
		if w == null:
			continue
		var row := HBoxContainer.new()
		_repair_box.add_child(row)
		var label := Label.new()
		label.text = "%s  %.0f / %.0f hp  (%d per hp)" % [w.display_name, player.weapon_health.get(id, 0.0),
			w.max_health, w.repair_cost_per_hp]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		_row_button(row, "Full (%d)" % shop.repair_cost(player, id), _repair.bind(id, INF),
			shop.check_repair(player, id) != Shop.Status.OK)
		var affordable := shop.affordable_repair_hp(player, id)
		_row_button(row, "What I can afford (%d)" % shop.repair_cost(player, id, affordable),
			_repair.bind(id, affordable), affordable <= 0.0 or shop.check_repair(player, id, affordable) != Shop.Status.OK)


func _show_last_report() -> void:
	var report := _controller.last_settlement()
	if report == null:
		_report_label.visible = false
		return
	var contract := DataRegistry.get_contract(report.contract_id)
	_report_label.text = "Last contract%s (%s):\n%s" % [
		": " + contract.client_name if contract else "", "victory" if report.victory else "defeat",
		"\n".join(report.summary_lines())]


# --- Building ---

func _build() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	var top := HBoxContainer.new()
	root.add_child(top)
	var title := Label.new()
	title.text = "REGION MAP"
	title.add_theme_font_size_override("font_size", 28)
	top.add_child(title)
	_funds_label = Label.new()
	_funds_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_funds_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_funds_label.add_theme_font_size_override("font_size", 20)
	top.add_child(_funds_label)
	_row_button(top, "Save", func() -> void: _status_label.text = "Saved" if SaveSystem.save_game() == OK else "Save failed")
	_row_button(top, "Main Menu", SceneRouter.goto.bind(SceneRouter.Screen.MAIN_MENU))

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	root.add_child(body)

	_map = Panel.new()
	_map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map.clip_contents = true
	_map.resized.connect(_layout_plots)
	body.add_child(_map)

	var tabs := TabContainer.new()
	tabs.custom_minimum_size = Vector2(500, 0)
	body.add_child(tabs)
	tabs.add_child(_build_auction_tab())
	_shop_box = _scroll_tab(tabs, "Shop")
	_repair_box = _scroll_tab(tabs, "Repair")

	_status_label = Label.new()
	_status_label.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	root.add_child(_status_label)


func _build_auction_tab() -> Control:
	var scroll := ScrollContainer.new()
	scroll.name = "Auction"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 8)
	scroll.add_child(box)

	_report_label = _wrapped_label(box)
	_section(box, "Contracts this week (click a plot to select it)")
	_offers_box = VBoxContainer.new()
	box.add_child(_offers_box)
	box.add_child(HSeparator.new())
	_lot_label = _wrapped_label(box)

	var bid_row := HBoxContainer.new()
	box.add_child(bid_row)
	_bid_spin = SpinBox.new()
	_bid_spin.step = 10
	_bid_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bid_row.add_child(_bid_spin)
	_bid_button = _row_button(bid_row, "Place sealed bid", _place_bid)
	_resolve_button = _row_button(box, "Close bidding", _resolve)
	_outcome_label = _wrapped_label(box)
	var action_row := HBoxContainer.new()
	box.add_child(action_row)
	_deploy_button = _row_button(action_row, "Deploy to battle", _deploy)
	_next_button = _row_button(action_row, "Next week", _new_round)
	box.add_child(HSeparator.new())
	_rivals_label = _wrapped_label(box)
	return scroll


func _build_offers() -> void:
	_clear(_offers_box)
	for contract in _controller.offers:
		var row := HBoxContainer.new()
		_offers_box.add_child(row)
		var label := Label.new()
		label.text = "%s  - payout %d, reserve %d" % [contract.client_name, contract.payout, contract.reserve_price]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		for lot in _controller.auction.lots_for(contract):
			_row_button(row, lot.plot.display_name, _select.bind(lot))


func _build_map_plots() -> void:
	_clear(_map)
	_plot_buttons.clear()
	for lot in _controller.auction.lots:
		var b := Button.new()
		b.toggle_mode = true
		b.text = "%s\n%s" % [lot.plot.display_name, lot.contract.client_name]
		b.add_theme_font_size_override("font_size", 12)
		b.size = MAP_PLOT_SIZE
		b.pressed.connect(_select.bind(lot))
		_map.add_child(b)
		_plot_buttons[lot.key()] = b
	_layout_plots()


## Places plot buttons by PlotData.map_position; plots shared by several contracts stack downward.
func _layout_plots() -> void:
	var used := {}
	for lot in _controller.auction.lots if _controller.auction else []:
		var b: Button = _plot_buttons.get(lot.key())
		if b == null:
			continue
		var stack: int = used.get(lot.plot.id, 0)
		used[lot.plot.id] = stack + 1
		var pos := lot.plot.map_position * _map.size - MAP_PLOT_SIZE / 2.0 + Vector2(0, stack * (MAP_PLOT_SIZE.y + 4))
		b.position = pos.clamp(Vector2.ZERO, (_map.size - MAP_PLOT_SIZE).max(Vector2.ZERO))


# --- Widget helpers ---

func _scroll_tab(tabs: TabContainer, title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	return box


func _section(parent: Node, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", Color(0.7, 0.8, 1.0))
	parent.add_child(l)


func _wrapped_label(parent: Node) -> Label:
	var l := Label.new()
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(440, 0)
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


func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()
