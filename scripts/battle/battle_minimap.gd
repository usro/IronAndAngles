class_name BattleMinimap
extends Control
## Profile strip of the whole engagement for the HUD: ground line, our battery, the targets, the
## enemy gun once spotted, and every shell in the air with its trail, so a flight can be followed
## from launch to impact even when both ends are off screen. Horizontal scale is uniform; the
## vertical scale stretches to fit the tallest arc in flight (a profile view, not to scale).

const GROUND_SAMPLES := 160
const GROUND_REFRESH_S := 0.5
const PAD := 6.0

var sim: BattleSim
## ShellFlight -> PackedVector2Array (meters), shared with the battle scene.
var trails: Dictionary = {}

var _ground := PackedVector2Array()
var _ground_age := INF


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	if sim == null:
		return
	_ground_age += delta
	if _ground_age >= GROUND_REFRESH_S:
		_ground_age = 0.0
		_sample_ground()
	queue_redraw()


func _sample_ground() -> void:
	var b := _x_range()
	_ground.resize(GROUND_SAMPLES)
	for i in GROUND_SAMPLES:
		var x := lerpf(b.x, b.y, i / float(GROUND_SAMPLES - 1))
		_ground[i] = Vector2(x, sim.map.surface_height_at(x))


## Horizontal extent shown: a margin behind the battery to a margin past the enemy gun.
func _x_range() -> Vector2:
	var battery := sim.battery_position_m().x
	var far := sim.map.target_zone_max_x_m
	if sim.enemy_origin_m != Vector2.INF:
		far = maxf(far, sim.enemy_origin_m.x)
	var margin := (far - battery) * 0.05 + 10.0
	return Vector2(battery - margin, far + margin)


func _draw() -> void:
	if sim == null or _ground.is_empty():
		return
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, Color(Blueprint.PAPER_DARK, 0.85))
	draw_rect(r, Color(Blueprint.LINE, 0.5), false, 1.0)
	var xr := _x_range()
	# Vertical fit: ground plus the highest point of anything in the air.
	var top := INF
	var bottom := -INF
	for g in _ground:
		top = minf(top, g.y)
		bottom = maxf(bottom, g.y)
	for trail: PackedVector2Array in trails.values():
		for p in trail:
			top = minf(top, p.y)
	top -= 10.0
	bottom += 4.0
	var inner := r.grow(-PAD)
	var to_px := func(p: Vector2) -> Vector2:
		return Vector2(inner.position.x + (p.x - xr.x) / (xr.y - xr.x) * inner.size.x,
			inner.position.y + (p.y - top) / maxf(bottom - top, 1.0) * inner.size.y)

	# Ground.
	var line := PackedVector2Array()
	var fill := PackedVector2Array()
	for g in _ground:
		var q: Vector2 = to_px.call(g)
		line.append(q)
		fill.append(q)
	fill.append(Vector2(inner.end.x, inner.end.y))
	fill.append(Vector2(inner.position.x, inner.end.y))
	draw_colored_polygon(fill, Color(Blueprint.LINE, 0.12))
	draw_polyline(line, Color(Blueprint.LINE, 0.8), 1.0)

	# Target zone, targets, enemy gun, battery.
	var zone_a: Vector2 = to_px.call(Vector2(sim.map.target_zone_min_x_m, sim.target_zone_center_m().y))
	var zone_b: Vector2 = to_px.call(Vector2(sim.map.target_zone_max_x_m, sim.target_zone_center_m().y))
	draw_line(zone_a + Vector2(0, 3), zone_b + Vector2(0, 3), Color(Blueprint.RED, 0.5), 2.0)
	for t in sim.targets:
		var q: Vector2 = to_px.call(t.rect_m().get_center())
		if t.is_destroyed():
			draw_line(q + Vector2(-2, -2), q + Vector2(2, 2), Blueprint.TEXT_DIM, 1.0)
		else:
			draw_rect(Rect2(q - Vector2(2, 3), Vector2(4, 4)), Blueprint.RED)
	if sim.enemy_spotted and sim.enemy_origin_m != Vector2.INF:
		var q: Vector2 = to_px.call(sim.enemy_origin_m)
		var col := Blueprint.RED if sim.enemy_gun_alive() else Blueprint.TEXT_DIM
		draw_arc(q, 4.0, 0.0, TAU, 12, col, 1.5)
	for m in sim.mounts:
		var q: Vector2 = to_px.call(m.muzzle_m())
		var col := Blueprint.AMBER if m.is_alive() else Blueprint.TEXT_DIM
		draw_colored_polygon(PackedVector2Array([q + Vector2(0, -4), q + Vector2(-3, 2), q + Vector2(3, 2)]), col)

	# Shells and their trails.
	for f: ShellFlight in trails:
		var trail: PackedVector2Array = trails[f]
		var enemy := sim.is_enemy_flight(f)
		var col := Blueprint.RED if enemy else Blueprint.INK
		if trail.size() >= 2:
			var pts := PackedVector2Array()
			for p in trail:
				pts.append(to_px.call(p))
			draw_polyline(pts, Color(col, 0.55), 1.0)
		if not f.is_finished:
			draw_circle(to_px.call(f.get_render_position()), 2.0, col)

	# Scale: distance labels at both ends.
	Blueprint.draw_text(self, Vector2(PAD, 11), "MAP", Blueprint.TEXT_DIM, 9)
	Blueprint.draw_text(self, Vector2(size.x - PAD, 11), "%.0f m" % (xr.y - sim.battery_position_m().x),
		Blueprint.TEXT_DIM, 9, HORIZONTAL_ALIGNMENT_RIGHT)
