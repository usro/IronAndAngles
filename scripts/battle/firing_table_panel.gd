class_name FiringTablePanel
extends PanelContainer
## Battle overlay toggled with T, laid out like a gunner's firing table:
## the player enters the RANGE and HEIGHT of the target (typed, or measured with the rangefinder:
## right-click the battlefield), the table for the selected gun, ammo and CHARGE gives elevation
## per range (low and high angle), time of flight and wind drift, and a solution line reads off
## the entered range. Wind is never applied: that's the crew's job.
## Once Fire Control Computers is researched, the computer section adds wind-corrected solutions
## with Apply buttons (F applies the nearest standing target).

const FCC_ROWS := 3

var sim: BattleSim
## The player's inputs (meters). Height: target ground above (+) or below (-) the battery.
var input_range_m := 0.0
var input_height_m := 0.0

var _box: VBoxContainer
var _range_box: SpinBox
var _height_box: SpinBox
var _content: VBoxContainer
var _table_key := ""
var _table: FiringTable
var _solutions: Array[Dictionary] = []
var _solutions_key := ""
var _render_key := ""


func _ready() -> void:
	theme_type_variation = &"HudPanel"
	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	position = Vector2(14, 92)
	custom_minimum_size = Vector2(440, 0)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 4)
	add_child(_box)
	var title := _text(_box, "FIRING TABLE   [T] close", &"SectionLabel")
	title.custom_minimum_size = Vector2(0, 0)
	var inputs := HBoxContainer.new()
	inputs.add_theme_constant_override("separation", 8)
	_box.add_child(inputs)
	_range_box = _spin(inputs, "RANGE m", 0.0, 5000.0, 5.0)
	_height_box = _spin(inputs, "HEIGHT m", -300.0, 300.0, 1.0)
	_range_box.value_changed.connect(func(v: float) -> void: input_range_m = v; _render_key = "")
	_height_box.value_changed.connect(func(v: float) -> void: input_height_m = v; _table_key = ""; _render_key = "")
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 3)
	_box.add_child(_content)
	visible = false
	if sim and GameState.player.current_era == GameConstants.Era.MEDIEVAL:
		# Training wheels for the first era: the target zone is pre-measured.
		var zone := sim.target_zone_center_m()
		var battery := sim.battery_position_m()
		set_measurement(zone.x - battery.x, battery.y - zone.y)


func toggle() -> void:
	visible = not visible
	_render_key = ""
	refresh()


## Fills RANGE and HEIGHT (the rangefinder calls this).
func set_measurement(range_m: float, height_m: float) -> void:
	_range_box.set_value_no_signal(roundf(range_m))
	_height_box.set_value_no_signal(roundf(height_m))
	input_range_m = _range_box.value
	input_height_m = _height_box.value
	_table_key = ""
	_render_key = ""


func refresh() -> void:
	if not visible or sim == null:
		return
	var m := sim.selected_mount()
	if m == null:
		return
	var key := "%s/%s/%d/%.0f" % [m.weapon.id, m.ammo_id, m.charge_increment(), input_height_m]
	if key != _table_key:
		_table_key = key
		_table = _build_table(m)
		_render_key = ""
	var targets_key := "%s/%s/%s" % [m.weapon.id, m.ammo_id, _standing_key()]
	if FireControl.is_unlocked(sim.player) and targets_key != _solutions_key:
		_solutions_key = targets_key
		_solutions = _compute_solutions(m)
		_render_key = ""
	var render_key := "%s/%.0f/%s" % [key, input_range_m, targets_key]
	if render_key != _render_key:
		_render_key = render_key
		_render(m)


func apply_nearest() -> bool:
	if sim == null or not FireControl.is_unlocked(sim.player):
		return false
	var m := sim.selected_mount()
	if m == null:
		return false
	var standing := _standing_points()
	if standing.is_empty():
		return false
	FireControl.apply(m, FireControl.solve(sim, m, standing[0].point))
	return true


func _build_table(m: WeaponMount) -> FiringTable:
	var ammo: AmmoData = sim.ammo_table.get(m.ammo_id)
	if ammo == null or m.is_orbital():
		return null
	return FiringTable.build(m.weapon, ammo, sim.weather, m.charge, input_height_m)


func _render(m: WeaponMount) -> void:
	for c in _content.get_children():
		_content.remove_child(c)
		c.queue_free()
	var ammo: AmmoData = sim.ammo_table.get(m.ammo_id)
	_text(_content, "%s · %s · CHARGE %d of %d [A/D]" % [m.weapon.display_name.to_upper(),
		ammo.display_name if ammo else "—", m.charge_increment() + 1, m.increments().size()], &"ValueLabel")
	if m.is_orbital():
		_text(_content, "Orbital strikes don't need a table: designate the target's x.", &"BodyLabel")
	elif _table == null or _table.ranges.is_empty():
		_text(_content, "No reach at this charge.", &"BodyLabel")
	else:
		_text(_content, "Still air. Reach %.0f–%.0f m at this charge. Right-click the field to measure." % [
			_table.min_range, _table.max_range], &"CaptionLabel")
		_solution_line()
		_grid()
	_content.add_child(HSeparator.new())
	_fire_control(m)


## The entered range read off the table: what to dial.
func _solution_line() -> void:
	if input_range_m <= 0.0:
		_text(_content, "Enter the target's RANGE (or right-click it) to read a solution.", &"CaptionLabel")
		return
	var low := _table.solve(input_range_m, false)
	var high := _table.solve(input_range_m, true)
	var line: String
	if is_nan(low.x) and is_nan(high.x):
		line = "%.0f m: out of reach at this charge, try %s." % [input_range_m,
			"a higher charge" if input_range_m > _table.max_range else "a lower charge"]
	else:
		var fmt := "%.2f°" if _table.direct_fire else "%.1f°"
		line = "%.0f m  →  LOW %s" % [input_range_m, fmt % low.x if not is_nan(low.x) else "—"]
		if not _table.direct_fire:
			line += "   HIGH %s" % (fmt % high.x if not is_nan(high.x) else "—")
		var use := low if not is_nan(low.x) else high
		line += "   TOF %.1f s   WIND %+.1f m per m/s" % [use.y, use.z]
	var l := _text(_content, line, &"MonoLabel")
	l.add_theme_color_override("font_color", Blueprint.AMBER)


func _grid() -> void:
	var grid := GridContainer.new()
	grid.columns = 7 if not _table.direct_fire else 4
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 0)
	_content.add_child(grid)
	var heads := ["RANGE", "LOW", "TOF", "WIND"] + ([] if _table.direct_fire else ["HIGH", "TOF", "WIND"])
	for h in heads:
		_cell(grid, h, Blueprint.TEXT_DIM)
	var nearest := -1
	if input_range_m > 0.0:
		var best := INF
		for i in _table.ranges.size():
			if absf(_table.ranges[i] - input_range_m) < best:
				best = absf(_table.ranges[i] - input_range_m)
				nearest = i
	var fmt := "%.2f°" if _table.direct_fire else "%.1f°"
	for i in _table.ranges.size():
		var col := Blueprint.AMBER if i == nearest else Blueprint.INK
		_cell(grid, "%.0f" % _table.ranges[i], Blueprint.AMBER if i == nearest else Blueprint.LINE)
		_angle_cells(grid, _table.low_elevations[i], _table.low_tof[i], _table.low_wind_drift[i], fmt, col)
		if not _table.direct_fire:
			_angle_cells(grid, _table.high_elevations[i], _table.high_tof[i], _table.high_wind_drift[i], fmt, col)
	_text(_content, "TOF: seconds in the air. WIND: meters the shot moves per 1 m/s of tailwind (−: headwind shortens).",
		&"CaptionLabel")


func _angle_cells(grid: GridContainer, elev: float, tof: float, drift: float, fmt: String, col: Color) -> void:
	_cell(grid, "—" if is_nan(elev) else fmt % elev, col)
	_cell(grid, "—" if is_nan(tof) else "%.1f" % tof, col)
	_cell(grid, "—" if is_nan(drift) else "%+.1f" % drift, col)


func _compute_solutions(m: WeaponMount) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for p in _standing_points().slice(0, FCC_ROWS):
		out.append({"label": p.label, "point": p.point, "solution": FireControl.solve(sim, m, p.point)})
	return out


func _standing_points() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var i := 0
	for t in sim.targets:
		i += 1
		if not t.is_destroyed():
			out.append({"label": "TARGET %d" % i, "point": t.rect_m().get_center()})
	if sim.enemy_spotted and sim.enemy_gun_alive():
		out.append({"label": "ENEMY GUN", "point": sim.enemy_gun_rect().get_center()})
	return out


func _standing_key() -> String:
	var bits := ""
	for t in sim.targets:
		bits += "0" if t.is_destroyed() else "1"
	return bits + ("g" if sim.enemy_spotted and sim.enemy_gun_alive() else "")


func _fire_control(m: WeaponMount) -> void:
	if not FireControl.is_unlocked(sim.player):
		_text(_content, "FIRE-CONTROL COMPUTER: locked. Research Fire Control Computers (Modern era).", &"CaptionLabel")
		return
	_text(_content, "FIRE-CONTROL COMPUTER  ·  mean wind, not gusts  ·  [F] nearest", &"SectionLabel")
	for s in _solutions:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		_content.add_child(row)
		var sol: Dictionary = s.solution
		var text: String
		if sol.is_empty():
			text = "%s: can't fire" % s.label
		elif sol.has("designate_x_m"):
			text = "%s  %.0f m  →  strike x %.0f" % [s.label, sol.distance_m, sol.designate_x_m]
		else:
			var fmt := "%s  %.0f m  →  CHG %d  %.2f°" if m.weapon.is_direct_fire() else "%s  %.0f m  →  CHG %d  %.1f°"
			text = fmt % [s.label, sol.distance_m, ChargeIncrements.nearest(m.weapon, sol.charge) + 1,
				sol.elevation_deg]
			if not sol.ok:
				text += "  (out of reach)"
		var l := Label.new()
		l.theme_type_variation = &"MonoLabel"
		l.add_theme_font_size_override("font_size", 12)
		l.text = text
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		var b := Button.new()
		b.text = "Apply"
		b.theme_type_variation = &"ChipButton"
		b.focus_mode = Control.FOCUS_NONE
		b.disabled = sol.is_empty()
		b.pressed.connect(func() -> void: FireControl.apply(sim.selected_mount(), sol))
		row.add_child(b)


func _spin(parent: Node, label: String, lo: float, hi: float, step: float) -> SpinBox:
	var cap := Label.new()
	cap.theme_type_variation = &"CaptionLabel"
	cap.text = label
	parent.add_child(cap)
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.allow_greater = true
	s.allow_lesser = true
	s.custom_minimum_size = Vector2(110, 0)
	# Enter hands the keyboard back to the guns.
	s.get_line_edit().text_submitted.connect(func(_t: String) -> void: s.get_line_edit().release_focus())
	parent.add_child(s)
	return s


func _text(parent: Node, text: String, variation: StringName) -> Label:
	var l := Label.new()
	l.theme_type_variation = variation
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(410, 0)
	parent.add_child(l)
	return l


func _cell(grid: GridContainer, text: String, col: Color) -> void:
	var l := Label.new()
	l.theme_type_variation = &"MonoLabel"
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", col)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.text = text
	grid.add_child(l)
