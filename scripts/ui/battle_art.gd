class_name BattleArt
extends RefCounted
## Battlefield line art other than the battery's weapons: targets, shells, blasts and markers.
## Everything is in the caller's pixels; `w` is a line width in those pixels.

const ENEMY_FILL := Color(0.35, 0.08, 0.08, 0.55)


## A target box as a fortified tower in red pencil. `rect` is the hit box in pixels.
static func draw_target(ci: CanvasItem, rect: Rect2, w: float, destroyed := false) -> void:
	var ink := Blueprint.RED
	if destroyed:
		_rubble(ci, rect, w)
		return
	var body := Rect2(rect.position + Vector2(rect.size.x * 0.08, rect.size.y * 0.22),
		Vector2(rect.size.x * 0.84, rect.size.y * 0.78))
	ci.draw_rect(body, ENEMY_FILL)
	Blueprint.draw_hatch(ci, body, Color(ink, 0.25), maxf(rect.size.x / 10.0, 2.0), w * 0.6)
	# Battlements: three merlons across the top.
	var mw := body.size.x / 5.0
	var pts := PackedVector2Array([Vector2(body.position.x, body.end.y), body.position])
	for i in 5:
		var x := body.position.x + i * mw
		if i % 2 == 0:
			ci.draw_rect(Rect2(x, rect.position.y, mw, body.position.y - rect.position.y), ENEMY_FILL)
			pts.append(Vector2(x, rect.position.y))
			pts.append(Vector2(x + mw, rect.position.y))
			pts.append(Vector2(x + mw, body.position.y))
		else:
			pts.append(Vector2(x + mw, body.position.y))
	pts.append(Vector2(body.end.x, body.end.y))
	ci.draw_polyline(pts, ink, w)
	ci.draw_line(Vector2(body.position.x, body.end.y), body.end, ink, w)
	# Arrow slit and door.
	var c := body.get_center()
	ci.draw_line(c + Vector2(0, -body.size.y * 0.3), c + Vector2(0, -body.size.y * 0.05), ink, w * 1.2)
	var door_r := body.size.x * 0.14
	var door_base := Vector2(c.x, body.end.y)
	ci.draw_arc(door_base + Vector2(0, -door_r * 1.4), door_r, PI, TAU, 10, ink, w)
	ci.draw_line(door_base + Vector2(-door_r, -door_r * 1.4), door_base + Vector2(-door_r, 0), ink, w)
	ci.draw_line(door_base + Vector2(door_r, -door_r * 1.4), door_base + Vector2(door_r, 0), ink, w)


static func _rubble(ci: CanvasItem, rect: Rect2, w: float) -> void:
	var ink := Color(Blueprint.RED, 0.6)
	var base := rect.end.y
	var x0 := rect.position.x - rect.size.x * 0.05
	var x1 := rect.end.x + rect.size.x * 0.05
	var h := rect.size.y
	var pts := PackedVector2Array([Vector2(x0, base)])
	var heights := [0.12, 0.3, 0.22, 0.42, 0.28, 0.36, 0.15, 0.2, 0.05]
	for i in heights.size():
		pts.append(Vector2(lerpf(x0, x1, (i + 0.5) / heights.size()), base - h * heights[i]))
	pts.append(Vector2(x1, base))
	ci.draw_colored_polygon(pts, Color(ENEMY_FILL, 0.4))
	ci.draw_polyline(pts, ink, w)
	# Struck through: this target is done.
	ci.draw_line(rect.position, rect.end, Color(ink, 0.5), w)
	ci.draw_line(Vector2(rect.position.x, rect.end.y), Vector2(rect.end.x, rect.position.y), Color(ink, 0.5), w)


## A thin health bar above `rect`.
static func draw_health(ci: CanvasItem, rect: Rect2, fraction: float, h: float, ink: Color) -> void:
	var bar := Rect2(rect.position - Vector2(0, h * 2.2), Vector2(rect.size.x, h))
	ci.draw_rect(bar, Color(Blueprint.PAPER_DARK, 0.85))
	var f := clampf(fraction, 0.0, 1.0)
	var col := ink if f > 0.35 else Blueprint.AMBER
	ci.draw_rect(Rect2(bar.position, Vector2(bar.size.x * f, h)), col)
	ci.draw_rect(bar, Color(ink, 0.6), false, maxf(h * 0.15, 0.5))


## A shell: a dot with a short streak behind it.
static func draw_shell(ci: CanvasItem, pos: Vector2, velocity: Vector2, r: float, col: Color) -> void:
	if velocity.length_squared() > 0.0:
		ci.draw_line(pos, pos - velocity.normalized() * r * 4.0, Color(col, 0.6), r * 0.9)
	ci.draw_circle(pos, r * 1.8, Color(col, 0.18))
	ci.draw_circle(pos, r, col)


## A blast at age fraction k (0..1): expanding rings plus radial ticks, fading out.
static func draw_blast(ci: CanvasItem, pos: Vector2, radius: float, k: float, kind: StringName, w: float) -> void:
	var a := 1.0 - k
	if kind == &"bounce":
		ci.draw_arc(pos, radius * (0.3 + 0.7 * k), 0.0, TAU, 24, Color(Blueprint.INK, 0.6 * a), w)
		return
	var hot := Blueprint.AMBER
	if k < 0.25:
		ci.draw_circle(pos, radius * (0.2 + 1.6 * k), Color(Color.WHITE, 0.8 * (1.0 - k * 4.0)))
	ci.draw_arc(pos, radius * (0.4 + 0.6 * k), 0.0, TAU, 40, Color(hot, a), w * 1.5)
	ci.draw_arc(pos, radius * (0.2 + 0.9 * k), 0.0, TAU, 40, Color(Blueprint.INK, a * 0.5), w)
	for i in 12:
		var ang := TAU * i / 12.0 + 0.13
		var d := Vector2(cos(ang), sin(ang))
		ci.draw_line(pos + d * radius * (0.5 + 0.7 * k), pos + d * radius * (0.7 + 0.9 * k), Color(hot, a * 0.8), w)


## Crosshair circle with four ticks.
static func draw_crosshair(ci: CanvasItem, pos: Vector2, r: float, col: Color, w: float) -> void:
	ci.draw_arc(pos, r, 0.0, TAU, 28, col, w)
	for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		ci.draw_line(pos + d * r * 0.5, pos + d * r * 1.5, col, w)


## A dashed polyline (the ghost of the last shot, the menu's firing arc).
static func draw_dashed_polyline(ci: CanvasItem, pts: PackedVector2Array, col: Color, w: float, dash: float,
		gap := -1.0) -> void:
	if gap < 0.0:
		gap = dash
	var on := true
	var left := dash
	for i in range(1, pts.size()):
		var a := pts[i - 1]
		var b := pts[i]
		var seg := a.distance_to(b)
		var t := 0.0
		while t < seg:
			var step := minf(left, seg - t)
			var p0 := a.lerp(b, t / seg)
			var p1 := a.lerp(b, (t + step) / seg)
			if on:
				ci.draw_line(p0, p1, col, w)
			t += step
			left -= step
			if left <= 0.0:
				on = not on
				left = dash if on else gap
