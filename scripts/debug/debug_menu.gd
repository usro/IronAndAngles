extends CanvasLayer
## Autoload "DebugMenu": a cheat/test panel toggled with F1 (or `). Debug builds only (editor runs
## and debug exports); release exports remove it at startup.
##
## Shows campaign cheats everywhere, plus region-map or battle actions for the current screen.
## Battle toggles (god mode, instant reload, enemy off) persist across battles until switched off.
## Everything goes through the same models the game uses, so autosave records the results.

const TOGGLE_KEYS: Array[Key] = [KEY_F1, KEY_QUOTELEFT]
const PANEL_WIDTH := 340.0

var god_mode := false
var instant_reload := false
var enemy_off := false

var _panel: PanelContainer
var _list: VBoxContainer
var _status: Label
var _context := ""


func _ready() -> void:
	if not OS.is_debug_build():
		queue_free()
		return
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_panel.visible = false
	SceneRouter.screen_changed.connect(func(_s: int) -> void: _rebuild.call_deferred())


func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key and key.pressed and not key.echo and TOGGLE_KEYS.has(key.keycode):
		_panel.visible = not _panel.visible
		if _panel.visible:
			_rebuild()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	var sim := _sim()
	if sim:
		_apply_battle_toggles(sim)
	if _panel.visible:
		if _screen_kind() != _context:
			_rebuild()
		_status.text = _status_text()


# --- Context ---

func _screen_kind() -> String:
	var scene := get_tree().current_scene
	if scene == null:
		return ""
	if "sim" in scene and scene.sim is BattleSim:
		return "battle"
	if scene.has_method("_new_round"):
		return "map"
	return "other"


func _sim() -> BattleSim:
	var scene := get_tree().current_scene
	return scene.sim if scene and "sim" in scene and scene.sim is BattleSim else null


func _status_text() -> String:
	var p := GameState.player
	return "Seed %d · week %d · %s\nFunds %s · %d tech · %d fps · time ×%.0f" % [
		GameState.campaign_seed, int(GameState.economy_state.get(StrategyController.KEY_WEEK, 0)),
		GameConstants.era_name(p.current_era), p.money, p.unlocked_tech.size(),
		Engine.get_frames_per_second(), Engine.time_scale]


# --- Campaign cheats ---

func _add_money(amount: int) -> void:
	GameState.player.earn(amount, "Debug")


func _zero_money() -> void:
	GameState.player.charge(GameState.player.money, "Debug")


func _refill_ammo() -> void:
	var p := GameState.player
	for weapon_id in p.owned_weapons:
		var w := DataRegistry.get_weapon(weapon_id)
		if w:
			for ammo_id in w.allowed_ammo:
				p.add_ammo(ammo_id, 50)


func _give_era_weapons(all_eras: bool) -> void:
	var p := GameState.player
	for w: WeaponData in DataRegistry.weapons.values():
		if all_eras or w.era <= p.current_era:
			p.add_weapon(w)
	_refill_ammo()


func _repair_all() -> void:
	var p := GameState.player
	for weapon_id in p.owned_weapons:
		var w := DataRegistry.get_weapon(weapon_id)
		if w:
			p.weapon_health[weapon_id] = w.max_health
	p.inventory_changed.emit()


## Unlocks the next era's gate node and everything it needs, as if researched for free.
func _advance_era() -> void:
	var p := GameState.player
	if p.current_era >= GameConstants.Era.EXPERIMENTAL:
		return
	var next := p.current_era + 1
	for node: TechNodeData in DataRegistry.tech.values():
		if node.era_gate and node.era == next:
			_unlock_with_ancestors(node.id)
	p.current_era = next as GameConstants.Era
	EventBus.era_changed.emit(p.current_era)


func _unlock_all_tech() -> void:
	for id in DataRegistry.tech:
		_unlock_with_ancestors(id)
	GameState.player.current_era = GameConstants.Era.EXPERIMENTAL
	EventBus.era_changed.emit(GameState.player.current_era)


func _unlock_with_ancestors(id: StringName) -> void:
	var p := GameState.player
	var node := DataRegistry.get_tech(id)
	if node == null or p.unlocked_tech.has(id):
		return
	for pre in node.prerequisites:
		_unlock_with_ancestors(pre)
	p.unlocked_tech.append(id)
	EventBus.tech_unlocked.emit(id)


## Straight into a battle on a freshly generated contract of the current era.
func _quick_battle() -> void:
	var c := StrategyController.new()
	c.start_round()
	if c.offers.is_empty():
		return
	GameState.current_contract = c.offers[0]
	GameState.current_plot = c.offers[0].plots[0]
	SceneRouter.goto(SceneRouter.Screen.BATTLE)


# --- Region map ---

func _map_new_week() -> void:
	get_tree().current_scene._new_round()


## Bids all funds on the selected lot, closes bidding and deploys if the player won.
func _map_win_and_deploy() -> void:
	var map := get_tree().current_scene
	if map._selected == null:
		return
	if GameState.player.money < map._selected.contract.reserve_price * 3:
		_add_money(map._selected.contract.reserve_price * 3)
	map._bid_spin.max_value = GameState.player.money
	map._bid_spin.value = GameState.player.money
	map._place_bid()
	map._resolve()
	if map._controller.player_outcome():
		map._deploy()


# --- Battle ---

func _apply_battle_toggles(sim: BattleSim) -> void:
	if god_mode:
		sim.enemy_damage_scale = 0.0
	if enemy_off:
		sim.enemy_brain = null
	if instant_reload:
		for m in sim.mounts:
			if m.is_alive() and not m.is_firing():
				m.reload_left = 0.0


func _battle_win() -> void:
	for t in _sim().targets:
		_destroy(t)


func _battle_kill_one() -> void:
	for t in _sim().targets:
		if not t.is_destroyed():
			_destroy(t)
			return


## Destroys a target with the same bookkeeping a real hit does (result count, events).
func _destroy(t: BattleTarget) -> void:
	if t.is_destroyed():
		return
	var lost := t.apply_damage(t.health + 1.0)
	EventBus.target_hit.emit(t.id, lost)
	_sim().result.targets_destroyed += 1
	EventBus.target_destroyed.emit(t.id)


func _battle_kill_enemy_gun() -> void:
	_sim().damage_enemy_gun(_sim().enemy_health + 1.0)


func _battle_lose() -> void:
	for m in _sim().mounts:
		m.health = 0.0


func _battle_heal() -> void:
	for m in _sim().mounts:
		m.health = m.weapon.max_health
	_sim().reveal_level = 0.0


## Dials the selected weapon onto the first standing target (nominal solution: wind gusts,
## spread and terrain can still make it miss).
func _battle_auto_aim() -> void:
	var sim := _sim()
	var m := sim.selected_mount()
	if m == null:
		return
	for t in sim.targets:
		if t.is_destroyed():
			continue
		if m.is_orbital():
			m.designated_x_m = t.rect_m().get_center().x
			return
		var aim := AimSolver.solve(m.weapon, sim.ammo_table[m.ammo_id], m.muzzle_m(), t.rect_m().get_center(), sim.weather)
		m.elevation_deg = aim.elevation_deg
		m.charge = aim.charge
		return


## Dials the selected weapon onto the enemy gun once it is spotted.
func _battle_auto_aim_gun() -> void:
	var sim := _sim()
	var m := sim.selected_mount()
	if m == null or not sim.enemy_spotted or not sim.enemy_gun_alive():
		return
	var at := sim.enemy_gun_rect().get_center()
	if m.is_orbital():
		m.designated_x_m = at.x
		return
	var aim := AimSolver.solve(m.weapon, sim.ammo_table[m.ammo_id], m.muzzle_m(), at, sim.weather)
	m.elevation_deg = aim.elevation_deg
	m.charge = aim.charge


func _set_time_scale(s: float) -> void:
	Engine.time_scale = s


# --- UI ---

func _build() -> void:
	_panel = PanelContainer.new()
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = -PANEL_WIDTH - 8.0
	_panel.offset_right = -8.0
	_panel.offset_top = 8.0
	_panel.offset_bottom = -8.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.05, 0.09, 0.94)
	style.border_color = Color(1.0, 0.45, 0.35)
	style.set_border_width_all(1)
	style.set_content_margin_all(10)
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)
	var root := VBoxContainer.new()
	_panel.add_child(root)
	var title := Label.new()
	title.text = "DEBUG  ·  F1 to close"
	title.add_theme_color_override("font_color", Color(1.0, 0.55, 0.45))
	root.add_child(title)
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 12)
	root.add_child(_status)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)


func _rebuild() -> void:
	if _list == null:
		return
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	_context = _screen_kind()

	_section("CAMPAIGN")
	_row([["+1k", _add_money.bind(1000)], ["+10k", _add_money.bind(10000)],
		["+100k", _add_money.bind(100000)], ["+1M", _add_money.bind(1000000)]])
	_row([["Funds → 0", _zero_money], ["Refill ammo", _refill_ammo], ["Repair all", _repair_all]])
	_row([["Advance era", _advance_era], ["Unlock all tech", _unlock_all_tech]])
	_row([["Weapons ≤ era", _give_era_weapons.bind(false)], ["All weapons", _give_era_weapons.bind(true)]])
	_row([["Quick battle (current era)", _quick_battle]])

	if _context == "map":
		_section("REGION MAP")
		_row([["New week (reroll offers)", _map_new_week]])
		_row([["Win selected lot + deploy", _map_win_and_deploy]])

	if _context == "battle":
		_section("BATTLE")
		_row([["Auto-aim target", _battle_auto_aim], ["Auto-aim gun", _battle_auto_aim_gun]])
		_row([["Kill 1 target", _battle_kill_one], ["Kill enemy gun", _battle_kill_enemy_gun]])
		_row([["Win now", _battle_win], ["Lose now", _battle_lose], ["Heal + hide", _battle_heal]])
		_toggle("God mode (no battery damage)", "god_mode")
		_toggle("Instant reload", "instant_reload")
		_toggle("Enemy holds fire", "enemy_off")

	_section("TIME")
	_row([["×0.25", _set_time_scale.bind(0.25)], ["×1", _set_time_scale.bind(1.0)],
		["×4", _set_time_scale.bind(4.0)], ["×10", _set_time_scale.bind(10.0)]])
	_status.text = _status_text()


func _section(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", Color(0.55, 0.8, 1.0))
	_list.add_child(l)


func _row(buttons: Array) -> void:
	var row := HBoxContainer.new()
	_list.add_child(row)
	for spec in buttons:
		var b := Button.new()
		b.text = spec[0]
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# No keyboard focus: Space must keep firing the gun, not re-press the last debug button.
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 13)
		b.pressed.connect(spec[1])
		row.add_child(b)


func _toggle(text: String, property: String) -> void:
	var c := CheckButton.new()
	c.text = text
	c.focus_mode = Control.FOCUS_NONE
	c.button_pressed = get(property)
	c.add_theme_font_size_override("font_size", 13)
	c.toggled.connect(func(on: bool) -> void:
		set(property, on)
		if not on and property == "god_mode" and _sim():
			_sim().enemy_damage_scale = BattleSim.ENEMY_DAMAGE_SCALE)
	_list.add_child(c)
