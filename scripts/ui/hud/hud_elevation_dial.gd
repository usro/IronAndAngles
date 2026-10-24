class_name HudElevationDial
extends Control
## Quarter-circle protractor: the weapon's allowed elevation band, a needle at the current
## elevation and a ghost tick at the last shot's. Orbital weapons show a strike offset instead.

var elevation_deg := 45.0
## Decimal places on the readout (2 for railguns).
var decimals := 1
var min_deg := 0.0
var max_deg := 90.0
## NAN when there is no previous shot.
var last_deg := NAN
var orbital := false
var strike_offset_m := 0.0
var alive := true


func _draw() -> void:
	var r := minf(size.x - 12.0, size.y - 22.0)
	var c := Vector2(6.0, size.y - 16.0)
	var ink := Blueprint.INK if alive else Blueprint.TEXT_DIM
	Blueprint.draw_text(self, Vector2(size.x - 8, 10), "ELEV", Blueprint.TEXT_DIM, 10, HORIZONTAL_ALIGNMENT_RIGHT)
	if orbital:
		BattleArt.draw_crosshair(self, c + Vector2(r * 0.5, -r * 0.5), r * 0.3, Blueprint.AMBER, 1.5)
		Blueprint.draw_text(self, Vector2(size.x * 0.5, size.y - 2), "STRIKE %+.0f m" % strike_offset_m,
			Blueprint.AMBER, 12, HORIZONTAL_ALIGNMENT_CENTER, Blueprint.FONT_MONO_BOLD)
		return
	# Scale arc and degree ticks.
	draw_arc(c, r, -PI * 0.5, 0.0, 40, Color(Blueprint.LINE, 0.35), 1.0)
	draw_arc(c, r, -deg_to_rad(max_deg), -deg_to_rad(min_deg), 40, Color(Blueprint.LINE, 0.9), 4.0)
	for d in range(0, 91, 5):
		var a := -deg_to_rad(d)
		var dir := Vector2(cos(a), sin(a))
		var len := 9.0 if d % 15 == 0 else 4.0
		draw_line(c + dir * (r - len), c + dir * r, Color(Blueprint.LINE, 0.6), 1.0)
		if d % 30 == 0:
			Blueprint.draw_text(self, c + dir * (r - 20.0) + Vector2(0, 4), str(d), Blueprint.TEXT_DIM, 9,
				HORIZONTAL_ALIGNMENT_CENTER)
	draw_line(c, c + Vector2(r, 0), Color(Blueprint.LINE, 0.4), 1.0)
	draw_line(c, c + Vector2(0, -r), Color(Blueprint.LINE, 0.4), 1.0)
	if not is_nan(last_deg):
		var la := -deg_to_rad(last_deg)
		var ld := Vector2(cos(la), sin(la))
		draw_line(c + ld * (r * 0.55), c + ld * (r + 4.0), Color(Blueprint.AMBER, 0.55), 2.0)
	var a := -deg_to_rad(elevation_deg)
	var dir := Vector2(cos(a), sin(a))
	draw_line(c, c + dir * (r + 2.0), ink, 2.0)
	draw_circle(c, 3.0, ink)
	Blueprint.draw_text(self, Vector2(size.x, size.y - 2), ("%." + str(decimals) + "f°") % elevation_deg, ink, 18,
		HORIZONTAL_ALIGNMENT_RIGHT, Blueprint.FONT_MONO_BOLD)
