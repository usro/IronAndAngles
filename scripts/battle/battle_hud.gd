class_name BattleHud
extends CanvasLayer
## Plain battle HUD: dials, wind, reload, ammo, running cost, reveal. The UI session restyles it.

var _info: Label
var _help: Label
var _banner: Label


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var panel := PanelContainer.new()
	panel.position = Vector2(12, 12)
	root.add_child(panel)
	_info = Label.new()
	_info.add_theme_font_size_override("font_size", 15)
	panel.add_child(_info)

	_help = Label.new()
	_help.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_help.offset_top = -30
	_help.offset_left = 12
	_help.add_theme_font_size_override("font_size", 13)
	_help.text = "[W/S or ↑/↓] elevation   [A/D or ←/→] charge (orbital: target x)   [Shift] fine   " \
		+ "[Wheel] elevation, [Shift+Wheel] charge   [Space] fire   [Tab] weapon   [R] ammo   " \
		+ "[V] overview   [Esc] retreat"
	root.add_child(_help)

	_banner = Label.new()
	_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.grow_vertical = Control.GROW_DIRECTION_BOTH
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_theme_font_size_override("font_size", 40)
	_banner.visible = false
	root.add_child(_banner)


func show_banner(text: String) -> void:
	_banner.text = text
	_banner.visible = true


func refresh(sim: BattleSim) -> void:
	var lines: PackedStringArray = []
	var c := sim.contract
	var time := _clock(sim.elapsed)
	if c.time_limit > 0.0:
		time += " / %s" % _clock(c.time_limit)
	lines.append("%s   Targets %d/%d   Time %s" % [c.client_name, sim.targets_left(), sim.targets.size(), time])

	var m := sim.selected_mount()
	if m == null:
		lines.append("No weapons in the battery")
	else:
		lines.append("Weapon [Tab] %d/%d: %s   HP %d/%d" % [sim.selected + 1, sim.mounts.size(),
			m.weapon.display_name, ceili(m.health), ceili(m.weapon.max_health)])
		var ammo: AmmoData = sim.ammo_table.get(m.ammo_id)
		if ammo:
			var cost := ammo.cost_per_shell + m.weapon.energy_cost_per_shot
			lines.append("Ammo [R]: %s  x%d   %d per shot%s" % [ammo.display_name,
				sim.player.ammo_count(ammo.id), cost,
				"  (incl. %d energy)" % m.weapon.energy_cost_per_shot if m.weapon.energy_cost_per_shot > 0 else ""])
		else:
			lines.append("Ammo: none")
		if m.is_orbital():
			lines.append("Strike x: %.1f m   (%.0f m from the battery)" % [m.designated_x_m,
				m.designated_x_m - m.position_m.x])
		else:
			lines.append("Elevation: %.1f°   Charge: %.1f%%  (%.1f m/s)" % [m.elevation_deg,
				m.charge * 100.0, m.muzzle_velocity()])
		lines.append("Status: %s" % _status(sim, m))

	var w := sim.weather
	var arrow := "→" if w.wind_speed > 0.0 else ("←" if w.wind_speed < 0.0 else "·")
	lines.append("Wind: %s %.1f m/s  (gusts ±%.1f)   Rain %d%%   Air %.3f kg/m³" % [arrow,
		absf(w.wind_speed), w.gust_strength, roundi(w.rain_intensity * 100.0), w.air_density])
	lines.append("Revealed: %s %d%%" % [_bar(sim.reveal_level), roundi(sim.reveal_level * 100.0)])
	lines.append("Shells %d (hit %d)   Spent %d   Funds %d" % [sim.result.shells_fired,
		sim.result.shells_hit, sim.result.ammo_spent, sim.player.money])
	_info.text = "\n".join(lines)


static func _status(sim: BattleSim, m: WeaponMount) -> String:
	if not m.is_alive():
		return "DESTROYED"
	if m.is_firing():
		return "FIRING (%d left in salvo)" % m.salvo_left
	if m.reload_left > 0.0:
		return "Reloading %.1f s  %s" % [m.reload_left, _bar(m.ready_fraction())]
	if sim.player.ammo_count(m.ammo_id) <= 0:
		return "No ammo of this type"
	return "READY [Space]"


static func _bar(fraction: float, width: int = 10) -> String:
	var n := clampi(roundi(fraction * width), 0, width)
	return "[" + "#".repeat(n) + "-".repeat(width - n) + "]"


static func _clock(seconds: float) -> String:
	var s := int(seconds)
	return "%02d:%02d" % [s / 60, s % 60]
