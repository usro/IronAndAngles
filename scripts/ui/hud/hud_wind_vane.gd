class_name HudWindVane
extends Control
## Wind readout: an arrow whose length follows the steady wind, a band for the gust range and the
## numbers underneath. Positive wind blows toward the targets (+x).

const FULL_SCALE_MS := 12.0

var wind_speed := 0.0
var gust := 0.0


func _draw() -> void:
	var mid := Vector2(size.x * 0.5, 22.0)
	var half := size.x * 0.5 - 10.0
	var k := half / FULL_SCALE_MS
	Blueprint.draw_text(self, Vector2(0, 10), "WIND", Blueprint.TEXT_DIM, 10)
	# Scale: centre line, ticks every 2 m/s.
	draw_line(mid - Vector2(half, 0), mid + Vector2(half, 0), Color(Blueprint.LINE, 0.3), 1.0)
	for i in range(-6, 7):
		var x := mid.x + i * 2.0 * k
		draw_line(Vector2(x, mid.y - (5 if i % 3 == 0 else 3)), Vector2(x, mid.y + (5 if i % 3 == 0 else 3)),
			Color(Blueprint.LINE, 0.45), 1.0)
	# Gust band.
	var lo := clampf(wind_speed - gust, -FULL_SCALE_MS, FULL_SCALE_MS)
	var hi := clampf(wind_speed + gust, -FULL_SCALE_MS, FULL_SCALE_MS)
	draw_rect(Rect2(mid.x + lo * k, mid.y - 6, (hi - lo) * k, 12), Color(Blueprint.LINE, 0.12))
	# Arrow.
	var tip := mid + Vector2(clampf(wind_speed, -FULL_SCALE_MS, FULL_SCALE_MS) * k, 0)
	if absf(wind_speed) > 0.05:
		var d := signf(wind_speed)
		draw_line(mid, tip, Blueprint.INK, 3.0)
		draw_colored_polygon(PackedVector2Array([tip + Vector2(d * 8, 0), tip + Vector2(-d * 2, -6),
			tip + Vector2(-d * 2, 6)]), Blueprint.INK)
	else:
		draw_circle(mid, 4.0, Blueprint.INK)
	var text := "%s %.1f m/s  ±%.1f" % ["→" if wind_speed > 0.05 else ("←" if wind_speed < -0.05 else "·"),
		absf(wind_speed), gust]
	Blueprint.draw_text(self, Vector2(size.x * 0.5, size.y - 2), text, Blueprint.INK, 13,
		HORIZONTAL_ALIGNMENT_CENTER, Blueprint.FONT_MONO_BOLD)
