extends Control
## Decorative firing diagram on the main menu: a trebuchet, a ballistic arc with angle and range
## dimensions, and a target tower in red pencil. A shell loops along the arc.

const ELEVATION_DEG := 38.0
const LOOP_S := 4.0

var _t := 0.0


func _process(delta: float) -> void:
	_t = fmod(_t + delta, LOOP_S)
	queue_redraw()


func _draw() -> void:
	var s := size
	var scale := clampf(s.y / 34.0, 12.0, 32.0)  # px per meter (not to range scale: decorative)
	var ground_y := s.y * 0.8
	var gun := Vector2(s.x * 0.58, ground_y)
	var target := Vector2(s.x * 0.91, ground_y)

	_ground(ground_y, s.x * 0.48, s.x - 24.0)

	var w := 1.6
	LauncherArt.draw_weapon(self, &"trebuchet", GameConstants.LauncherType.MECHANICAL, gun, scale,
		ELEVATION_DEG, Blueprint.INK, Color(Blueprint.PAPER_DARK, 0.9), w)
	var tower := Rect2(target - Vector2(2.0, 3.0) * scale, Vector2(4.0, 3.0) * scale)
	BattleArt.draw_target(self, tower, w)

	# Arc from the throwing arm's tip to the tower top: a parabola through apex.
	var start := gun + Vector2(cos(deg_to_rad(ELEVATION_DEG)), -sin(deg_to_rad(ELEVATION_DEG))) * 2.9 * scale \
		+ Vector2(0, -2.6 * scale)
	var finish := Vector2(target.x, tower.position.y + 4.0)
	var pts := _arc(start, finish, deg_to_rad(ELEVATION_DEG))
	BattleArt.draw_dashed_polyline(self, pts, Color(Blueprint.LINE, 0.8), 1.4, 8.0, 6.0)
	var k := _t / LOOP_S
	var i := clampi(int(k * (pts.size() - 1)), 0, pts.size() - 2)
	var vel := pts[i + 1] - pts[i]
	BattleArt.draw_shell(self, pts[i], vel, 3.5, Blueprint.AMBER)

	# Angle: horizontal reference, arc, label.
	var ref_len := 70.0
	draw_line(start, start + Vector2(ref_len, 0), Blueprint.LINE_DIM, 1.0)
	draw_arc(start, ref_len * 0.75, -deg_to_rad(ELEVATION_DEG), 0.0, 24, Blueprint.LINE, 1.2)
	Blueprint.draw_text(self, start + Vector2(ref_len * 0.8, -12), "θ %.1f°" % ELEVATION_DEG, Blueprint.LINE, 13)

	# Apex callout.
	var apex := pts[0]
	for p in pts:
		if p.y < apex.y:
			apex = p
	draw_line(apex, Vector2(apex.x, ground_y), Color(Blueprint.LINE, 0.18), 1.0)
	BattleArt.draw_crosshair(self, apex, 5.0, Blueprint.LINE_DIM, 1.0)

	# Range dimension under the ground.
	var dim_y := ground_y + 34.0
	draw_line(Vector2(gun.x, ground_y + 6), Vector2(gun.x, dim_y + 6), Blueprint.LINE_DIM, 1.0)
	draw_line(Vector2(target.x, ground_y + 6), Vector2(target.x, dim_y + 6), Blueprint.LINE_DIM, 1.0)
	Blueprint.draw_dimension(self, Vector2(gun.x, dim_y), Vector2(target.x, dim_y), "R = 240 m", Blueprint.LINE, 12)

	# Callouts with leader lines.
	_callout(gun + Vector2(-1.9, -0.4) * scale, gun + Vector2(-1.9 * scale, -3.8 * scale), "COUNTERWEIGHT TREBUCHET")
	_callout(tower.end - Vector2(tower.size.x * 0.1, tower.size.y * 0.6), Vector2(tower.end.x + 8, apex.y - 24),
		"TARGET · SIEGE TOWER", Blueprint.RED)
	_wind(Vector2(s.x * 0.62, s.y * 0.14))


func _arc(a: Vector2, b: Vector2, elev: float) -> PackedVector2Array:
	# y = a.y - tan(e)·dx + c·dx², with c chosen to pass through b.
	var dx_total := b.x - a.x
	var c := (b.y - a.y + tan(elev) * dx_total) / (dx_total * dx_total)
	var pts := PackedVector2Array()
	for i in 61:
		var dx := dx_total * i / 60.0
		pts.append(Vector2(a.x + dx, a.y - tan(elev) * dx + c * dx * dx))
	return pts


func _ground(y: float, x0: float, x1: float) -> void:
	var pts := PackedVector2Array()
	var x := x0
	while x <= x1:
		var bump := sin(x * 0.013) * 6.0 + sin(x * 0.041) * 2.0
		var flat := absf(x - size.x * 0.58) < 60.0 or absf(x - size.x * 0.91) < 55.0
		pts.append(Vector2(x, y + (0.0 if flat else bump)))
		x += 6.0
	var fill := pts.duplicate()
	fill.append(Vector2(x1, y + 26.0))
	fill.append(Vector2(x0, y + 26.0))
	draw_colored_polygon(fill, Color(Blueprint.PAPER_DARK, 0.6))
	draw_polyline(pts, Blueprint.INK, 1.6)
	for p in pts:
		if int(p.x) % 12 < 6:
			draw_line(p + Vector2(0, 2), p + Vector2(-9, 11), Color(Blueprint.LINE, 0.35), 1.0)


## Leader line from `anchor` up to a shelf at `label_pos`; the label sits left of it, or right
## when `rightward`.
func _callout(anchor: Vector2, label_pos: Vector2, text: String, col := Blueprint.LINE, rightward := false) -> void:
	draw_circle(anchor, 2.5, col)
	var knee := Vector2(anchor.x, label_pos.y)
	draw_line(anchor, knee, Color(col, 0.6), 1.0)
	var w := Blueprint.FONT_MONO.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	draw_line(knee, label_pos, Color(col, 0.6), 1.0)
	var dir := 1.0 if rightward else -1.0
	draw_line(label_pos, label_pos + Vector2(dir * (w + 6), 0), Color(col, 0.6), 1.0)
	Blueprint.draw_text(self, label_pos + Vector2(4 if rightward else -w - 4, -5), text, col, 11)


func _wind(at: Vector2) -> void:
	Blueprint.draw_text(self, at, "WIND  → 4.0 m/s", Blueprint.TEXT_DIM, 11)
	for i in 3:
		var y := at.y + 10 + i * 7
		var x := at.x + i * 10
		draw_line(Vector2(x, y), Vector2(x + 60, y), Color(Blueprint.LINE, 0.35), 1.0)
		draw_line(Vector2(x + 60, y), Vector2(x + 54, y - 3), Color(Blueprint.LINE, 0.35), 1.0)
