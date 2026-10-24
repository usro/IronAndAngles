class_name FiringTablePanel
extends PanelContainer
## Battle overlay toggled with T: the range card (FiringTable) for the selected weapon and ammo,
## and, once Fire Control Computers is researched, the fire-control computer's solutions with
## Apply buttons (F applies the nearest standing target). Solutions are computed on demand,
## not every frame: an AimSolver run costs a few hundred trajectory simulations.

const FCC_ROWS := 3
## Cells within this share of the zone's edges are highlighted too (the grid is coarse).
const NEAR_ZONE := 0.05

var sim: BattleSim
var _box: VBoxContainer
var _table_key := ""
var _table: FiringTable
## Cache of computer solutions: key -> {"label", "point", "solution"}.
var _solutions: Array[Dictionary] = []
var _solutions_key := ""


func _ready() -> void:
	theme_type_variation = &"HudPanel"
	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	position = Vector2(14, 92)
	custom_minimum_size = Vector2(430, 0)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 4)
	add_child(_box)
	visible = false


func toggle() -> void:
	visible = not visible
	_table_key = ""
	_solutions_key = ""
	refresh()


## Rebuilds when the selected weapon, ammo or the standing targets change. Cheap otherwise.
func refresh() -> void:
	if not visible or sim == null:
		return
	var m := sim.selected_mount()
	if m == null:
		return
	var key := "%s/%s" % [m.weapon.id, m.ammo_id]
	var targets_key := key + "/" + _standing_key()
	if key == _table_key and targets_key == _solutions_key:
		return
	if key != _table_key:
		_table_key = key
		_table = _build_table(m)
	if FireControl.is_unlocked(sim.player) and targets_key != _solutions_key:
		_solutions_key = targets_key
		_solutions = _compute_solutions(m)
	_render(m)


## Applies the first (nearest standing target) solution. Returns false if the computer is locked.
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
	var muzzle := m.muzzle_m()
	var zone := sim.target_zone_center_m()
	return FiringTable.build(m.weapon, ammo, sim.weather, zone.y - muzzle.y, zone.x - muzzle.x)


func _compute_solutions(m: WeaponMount) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for p in _standing_points().slice(0, FCC_ROWS):
		out.append({"label": p.label, "point": p.point, "solution": FireControl.solve(sim, m, p.point)})
	return out


## Standing targets nearest first, then the enemy gun if it has been spotted.
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


func _render(m: WeaponMount) -> void:
	for c in _box.get_children():
		_box.remove_child(c)
		c.queue_free()
	var muzzle := m.muzzle_m()
	var zone_lo := sim.map.target_zone_min_x_m - muzzle.x
	var zone_hi := sim.map.target_zone_max_x_m - muzzle.x
	var drop := sim.target_zone_center_m().y - muzzle.y
	var ammo: AmmoData = sim.ammo_table.get(m.ammo_id)
	_text("FIRING TABLE  ·  %s  ·  %s" % [m.weapon.display_name.to_upper(), ammo.display_name if ammo else "—"],
		&"SectionLabel")
	_text("Still air, no spread. Target zone %.0f–%.0f m, ground %.0f m %s you. [T] close" % [zone_lo, zone_hi,
		absf(drop), "below" if drop >= 0.0 else "above"], &"CaptionLabel")
	if m.is_orbital():
		_text("Orbital strikes don't need a table: designate the target's x.", &"BodyLabel")
	elif _table and _table.direct_fire:
		_direct_grid(zone_lo, zone_hi)
	elif _table:
		_arc_grid(zone_lo, zone_hi)
	_box.add_child(HSeparator.new())
	_fire_control(m)


func _arc_grid(zone_lo: float, zone_hi: float) -> void:
	var grid := GridContainer.new()
	grid.columns = FiringTable.CHARGES.size() + 1
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 0)
	_box.add_child(grid)
	_cell(grid, "ELEV \\ CHG", Blueprint.TEXT_DIM)
	for c in FiringTable.CHARGES:
		_cell(grid, "%d%%" % roundi(c * 100.0), Blueprint.TEXT_DIM)
	for r in _table.elevations.size():
		_cell(grid, "%.0f°" % _table.elevations[r], Blueprint.LINE)
		for d in _table.distances[r]:
			var in_zone := not is_nan(d) and d >= zone_lo * (1.0 - NEAR_ZONE) and d <= zone_hi * (1.0 + NEAR_ZONE)
			var col := Blueprint.AMBER if in_zone else (Blueprint.INK if not is_nan(d) else Blueprint.TEXT_DIM)
			_cell(grid, "—" if is_nan(d) else "%.0f" % d, col)
	_text("Amber: lands in or near the target zone.", &"CaptionLabel")


func _direct_grid(zone_lo: float, zone_hi: float) -> void:
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 0)
	_box.add_child(grid)
	for h in ["RANGE", "ELEV", "RANGE", "ELEV"]:
		_cell(grid, h, Blueprint.TEXT_DIM)
	for i in _table.direct_distances.size():
		var d := _table.direct_distances[i]
		var in_zone := d >= zone_lo and d <= zone_hi
		_cell(grid, "%.0f m" % d, Blueprint.AMBER if in_zone else Blueprint.LINE)
		_cell(grid, "%.2f°" % _table.direct_elevations[i], Blueprint.AMBER if in_zone else Blueprint.INK)
	_text("At %d%% charge. Railguns don't drift with the wind." % roundi(FiringTable.DIRECT_CHARGE * 100.0),
		&"CaptionLabel")


func _fire_control(m: WeaponMount) -> void:
	if not FireControl.is_unlocked(sim.player):
		_text("FIRE-CONTROL COMPUTER: locked. Research Fire Control Computers (Modern era).", &"CaptionLabel")
		return
	_text("FIRE-CONTROL COMPUTER  ·  mean wind, not gusts  ·  [F] nearest", &"SectionLabel")
	for s in _solutions:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		_box.add_child(row)
		var sol: Dictionary = s.solution
		var text: String
		if sol.is_empty():
			text = "%s: can't fire" % s.label
		elif sol.has("designate_x_m"):
			text = "%s  %.0f m  →  strike x %.0f" % [s.label, sol.distance_m, sol.designate_x_m]
		else:
			var fmt := "%s  %.0f m  →  %.2f°  ·  %.1f%%" if m.weapon.is_direct_fire() else "%s  %.0f m  →  %.1f°  ·  %.1f%%"
			text = fmt % [s.label, sol.distance_m, sol.elevation_deg, sol.charge * 100.0]
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


func _text(text: String, variation: StringName) -> void:
	var l := Label.new()
	l.theme_type_variation = variation
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(400, 0)
	_box.add_child(l)


func _cell(grid: GridContainer, text: String, col: Color) -> void:
	var l := Label.new()
	l.theme_type_variation = &"MonoLabel"
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", col)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.text = text
	grid.add_child(l)
