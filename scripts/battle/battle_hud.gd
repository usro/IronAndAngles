class_name BattleHud
extends CanvasLayer
## Battle HUD in the blueprint style: mission plate (top left), conditions plate (top right),
## fire-control plate (bottom left) with elevation dial, charge column, ammo and reload bar,
## a key strip and the end-of-battle stamp. Only reads the sim; battle.gd forwards input.

const KEY_HINTS := [["W/S", "elevation"], ["A/D", "charge"], ["Shift", "fine"], ["Wheel", "elev · +Shift charge"],
	["Space", "fire"], ["Tab", "weapon"], ["R", "ammo"], ["T", "table"], ["F", "computer"], ["X", "split"], ["V", "overview"],
	["Esc", "retreat"]]

var _contract_label: Label
var _clock_label: Label
var _pips: HudTargetPips
var _wind: HudWindVane
var _weather_label: Label
var _reveal: HudMeter
var _enemy_label: Label
var _ledger_label: Label
var _weapon_label: Label
var _weapon_index: Label
var _hp: HudMeter
var _dial: HudElevationDial
var _charge: HudChargeGauge
var _ammo_label: Label
var _ammo_cost: Label
var _reload: HudMeter
var _banner: Stamp
## Dial settings of the player's previous shot, for the ghost ticks: {"mount": int, "elevation", "charge"}.
var _last_shot := {}


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Mission plate.
	var mission := _plate(root, Control.PRESET_TOP_LEFT, Vector2(14, 14))
	var mbox := VBoxContainer.new()
	mbox.add_theme_constant_override("separation", 4)
	mission.add_child(mbox)
	_contract_label = _label(mbox, &"HeaderLabel")
	_contract_label.add_theme_font_size_override("font_size", 15)
	var mrow := HBoxContainer.new()
	mrow.add_theme_constant_override("separation", 14)
	mbox.add_child(mrow)
	_pips = HudTargetPips.new()
	_pips.custom_minimum_size = Vector2(0, 16)
	_pips.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mrow.add_child(_pips)
	_clock_label = _label(mrow, &"MonoLabel")

	# Conditions plate.
	var cond := _plate(root, Control.PRESET_TOP_RIGHT, Vector2(-14, 14))
	cond.custom_minimum_size = Vector2(260, 0)
	var cbox := VBoxContainer.new()
	cbox.add_theme_constant_override("separation", 6)
	cond.add_child(cbox)
	_wind = HudWindVane.new()
	_wind.custom_minimum_size = Vector2(240, 54)
	cbox.add_child(_wind)
	_weather_label = _label(cbox, &"CaptionLabel")
	_weather_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_reveal = HudMeter.new()
	_reveal.label = "REVEALED"
	_reveal.custom_minimum_size = Vector2(240, 42)
	cbox.add_child(_reveal)
	_enemy_label = _label(cbox, &"MonoLabel")
	_enemy_label.add_theme_font_size_override("font_size", 12)
	_ledger_label = _label(cbox, &"MonoLabel")
	_ledger_label.add_theme_font_size_override("font_size", 12)

	# Fire-control plate: kept low and wide so it stays under the battery in the home view.
	var fc := _plate(root, Control.PRESET_BOTTOM_LEFT, Vector2(14, -38))
	var frow := HBoxContainer.new()
	frow.add_theme_constant_override("separation", 14)
	fc.add_child(frow)
	var fbox := VBoxContainer.new()
	fbox.add_theme_constant_override("separation", 4)
	fbox.custom_minimum_size = Vector2(270, 0)
	frow.add_child(fbox)
	var head := HBoxContainer.new()
	fbox.add_child(head)
	_weapon_label = _label(head, &"HeaderLabel")
	_weapon_label.add_theme_font_size_override("font_size", 15)
	_weapon_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_weapon_index = _label(head, &"CaptionLabel")
	_hp = HudMeter.new()
	_hp.label = "INTEGRITY"
	_hp.segments = 24
	_hp.custom_minimum_size = Vector2(0, 26)
	fbox.add_child(_hp)
	var ammo_row := HBoxContainer.new()
	fbox.add_child(ammo_row)
	_label(ammo_row, &"CaptionLabel").text = "AMMO [R]"
	_ammo_label = _label(ammo_row, &"ValueLabel")
	_ammo_label.add_theme_font_size_override("font_size", 14)
	_ammo_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ammo_cost = _label(ammo_row, &"MonoLabel")
	_ammo_cost.add_theme_color_override("font_color", Blueprint.AMBER)
	_ammo_cost.add_theme_font_size_override("font_size", 12)
	_reload = HudMeter.new()
	_reload.segments = 24
	_reload.custom_minimum_size = Vector2(0, 30)
	fbox.add_child(_reload)
	frow.add_child(VSeparator.new())
	_dial = HudElevationDial.new()
	_dial.custom_minimum_size = Vector2(140, 112)
	frow.add_child(_dial)
	_charge = HudChargeGauge.new()
	_charge.custom_minimum_size = Vector2(100, 112)
	frow.add_child(_charge)

	root.add_child(_key_strip())

	_banner = Stamp.new()
	_banner.font_size = 56
	_banner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.visible = false
	root.add_child(_banner)


## Remembers the dials of a shot the player just fired (drawn as ghost ticks on the gauges).
func note_shot(mount_index: int, elevation_deg: float, charge: float) -> void:
	_last_shot = {"mount": mount_index, "elevation": elevation_deg, "charge": charge}


## A short message above the key strip that fades out (e.g. "computer locked").
func flash_note(text: String) -> void:
	var l := Label.new()
	l.theme_type_variation = &"StatusLabel"
	l.text = text
	l.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	l.grow_horizontal = Control.GROW_DIRECTION_BOTH
	l.position.y -= 70
	add_child(l)
	var tw := l.create_tween()
	tw.tween_interval(1.8)
	tw.tween_property(l, "modulate:a", 0.0, 0.6)
	tw.tween_callback(l.queue_free)


func show_banner(text: String) -> void:
	var lines := text.split("\n")
	_banner.text = lines[0]
	_banner.color = Blueprint.AMBER if lines[0] == "VICTORY" else Blueprint.RED
	_banner.visible = true
	if lines.size() > 1:
		var reason := Label.new()
		reason.theme_type_variation = &"MonoLabel"
		reason.text = lines[1]
		reason.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		reason.grow_horizontal = Control.GROW_DIRECTION_BOTH
		reason.position.y += 70
		reason.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_banner.add_child(reason)


func refresh(sim: BattleSim) -> void:
	var c := sim.contract
	_contract_label.text = c.client_name.to_upper()
	_pips.total = sim.targets.size()
	_pips.destroyed = sim.targets.size() - sim.targets_left()
	_pips.custom_minimum_size.x = sim.targets.size() * 20.0
	_pips.queue_redraw()
	var time := _clock(sim.elapsed)
	if c.time_limit > 0.0:
		time += " / %s" % _clock(c.time_limit)
	_clock_label.text = "T " + time

	var w := sim.weather
	_wind.wind_speed = w.wind_speed
	_wind.gust = w.gust_strength
	_wind.queue_redraw()
	_weather_label.text = "RAIN %d%%   AIR %.3f kg/m³" % [roundi(w.rain_intensity * 100.0), w.air_density]
	_reveal.fraction = sim.reveal_level
	_reveal.value_text = "%d%%" % roundi(sim.reveal_level * 100.0)
	_reveal.color = Blueprint.RED if sim.reveal_level >= SimpleEnemyBrain.HOLD_BELOW_REVEAL else Blueprint.AMBER
	_reveal.marker = SimpleEnemyBrain.HOLD_BELOW_REVEAL if sim.enemy_brain is SimpleEnemyBrain else -1.0
	_reveal.marker_label = "RETURN FIRE"
	_reveal.queue_redraw()
	_enemy_label.text = _enemy_text(sim)
	_enemy_label.add_theme_color_override("font_color", Blueprint.TEXT_DIM if not sim.enemy_gun_alive()
		else (Blueprint.RED if sim.enemy_spotted else Blueprint.AMBER))
	_ledger_label.text = "SHELLS %d  HIT %d   SPENT %s\nFUNDS %s" % [sim.result.shells_fired, sim.result.shells_hit,
		Blueprint.money(sim.result.ammo_spent), Blueprint.money(sim.player.money)]

	var m := sim.selected_mount()
	if m == null:
		_weapon_label.text = "NO WEAPONS IN THE BATTERY"
		return
	_weapon_label.text = m.weapon.display_name.to_upper()
	_weapon_index.text = "[Tab] %d/%d" % [sim.selected + 1, sim.mounts.size()]
	_hp.fraction = m.health / m.weapon.max_health
	_hp.value_text = "%d / %d" % [ceili(m.health), ceili(m.weapon.max_health)]
	_hp.color = Blueprint.LINE if _hp.fraction > 0.5 else (Blueprint.AMBER if _hp.fraction > 0.0 else Blueprint.RED)
	_hp.queue_redraw()

	var last: Dictionary = _last_shot if _last_shot.get("mount", -1) == sim.selected else {}
	_dial.alive = m.is_alive()
	_dial.orbital = m.is_orbital()
	_dial.elevation_deg = m.elevation_deg
	_dial.decimals = 2 if m.weapon.is_direct_fire() else 1
	_dial.min_deg = m.weapon.elevation_min_deg
	_dial.max_deg = m.weapon.elevation_max_deg
	_dial.last_deg = last.get("elevation", NAN)
	_dial.strike_offset_m = m.designated_x_m - m.position_m.x
	_dial.queue_redraw()
	_charge.alive = m.is_alive()
	_charge.charge = m.charge
	_charge.increments = m.increments()
	_charge.velocity = m.muzzle_velocity()
	_charge.last_charge = last.get("charge", NAN)
	_charge.visible = not m.is_orbital()
	_charge.queue_redraw()

	var ammo: AmmoData = sim.ammo_table.get(m.ammo_id)
	if ammo:
		var cost := ammo.cost_per_shell + m.weapon.energy_cost_per_shot
		var count := sim.player.ammo_count(ammo.id)
		_ammo_label.text = "%s  ×%d" % [ammo.display_name, count]
		_ammo_label.add_theme_color_override("font_color", Blueprint.INK if count > 0 else Blueprint.RED)
		_ammo_cost.text = "%s/shot%s" % [Blueprint.money(cost),
			" (%s energy)" % Blueprint.money(m.weapon.energy_cost_per_shot) if m.weapon.energy_cost_per_shot > 0 else ""]
	else:
		_ammo_label.text = "none"
		_ammo_cost.text = ""
	_status(sim, m)


func _status(sim: BattleSim, m: WeaponMount) -> void:
	_reload.marker = -1.0
	if not m.is_alive():
		_reload.label = "STATUS"
		_reload.value_text = "DESTROYED"
		_reload.fraction = 0.0
		_reload.color = Blueprint.RED
	elif m.is_firing():
		_reload.label = "FIRING"
		_reload.value_text = "%d left in salvo" % m.salvo_left
		_reload.fraction = 1.0
		_reload.color = Blueprint.AMBER
	elif m.reload_left > 0.0:
		_reload.label = "RELOADING"
		_reload.value_text = "%.1f s" % m.reload_left
		_reload.fraction = m.ready_fraction()
		_reload.color = Color(Blueprint.LINE, 0.8)
	elif sim.player.ammo_count(m.ammo_id) <= 0:
		_reload.label = "STATUS"
		_reload.value_text = "NO AMMO OF THIS TYPE"
		_reload.fraction = 0.0
		_reload.color = Blueprint.RED
	else:
		_reload.label = "LOADED"
		_reload.value_text = "READY [Space]"
		_reload.fraction = 1.0
		_reload.color = Blueprint.GREEN
	_reload.queue_redraw()


func _key_strip() -> Control:
	var strip := HBoxContainer.new()
	strip.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	strip.offset_top = -28
	strip.offset_bottom = -8
	strip.offset_left = 14
	strip.add_theme_constant_override("separation", 12)
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for hint in KEY_HINTS:
		var key := PanelContainer.new()
		var style := StyleBoxFlat.new()
		style.bg_color = Color(Blueprint.PAPER_DARK, 0.85)
		style.border_color = Color(Blueprint.LINE, 0.6)
		style.set_border_width_all(1)
		style.border_width_bottom = 2
		style.content_margin_left = 5
		style.content_margin_right = 5
		key.add_theme_stylebox_override("panel", style)
		strip.add_child(key)
		var k := _label(key, &"MonoLabel")
		k.text = hint[0]
		k.add_theme_font_size_override("font_size", 11)
		var d := _label(strip, &"CaptionLabel")
		d.text = hint[1]
		d.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return strip


func _plate(root: Control, preset: Control.LayoutPreset, offset: Vector2) -> PanelContainer:
	var p := PanelContainer.new()
	p.theme_type_variation = &"HudPanel"
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(p)
	p.set_anchors_and_offsets_preset(preset)
	if preset == Control.PRESET_TOP_RIGHT:
		p.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	if preset == Control.PRESET_BOTTOM_LEFT:
		p.grow_vertical = Control.GROW_DIRECTION_BEGIN
	p.position += offset
	return p


static func _label(parent: Node, variation: StringName) -> Label:
	var l := Label.new()
	l.theme_type_variation = variation
	parent.add_child(l)
	return l


static func _clock(seconds: float) -> String:
	var s := int(seconds)
	return "%02d:%02d" % [s / 60, s % 60]


static func _enemy_text(sim: BattleSim) -> String:
	if sim.enemy_weapon == null:
		return "ENEMY GUN: NONE"
	if not sim.enemy_gun_alive():
		return "ENEMY GUN: DESTROYED  +%d%% BONUS ON VICTORY" % roundi(BattleSim.COUNTER_BATTERY_BONUS * 100.0)
	if not sim.enemy_spotted:
		return "ENEMY GUN: HIDDEN (fires → spotted)"
	var range_m := sim.enemy_origin_m.x - sim.battery_position_m().x
	return "ENEMY GUN: SPOTTED  %.0f m  ·  %d / %d HP" % [range_m, ceili(sim.enemy_health), ceili(sim.enemy_max_health)]
