class_name HudChargeGauge
extends Control
## Vertical charge column with 10 % graduations, the current charge filled in and the last shot's
## charge as a tick, plus the muzzle velocity readout.

var charge := 0.5
## NAN when there is no previous shot.
var last_charge := NAN
var velocity := 0.0
var alive := true
## The weapon's propellant increments (0..1), drawn as ticks; the readout shows "CHG n".
var increments := PackedFloat32Array()


func _draw() -> void:
	var col_w := 18.0
	var top := 16.0
	var bottom := size.y - 22.0
	var x := 4.0
	var h := bottom - top
	var ink := Blueprint.INK if alive else Blueprint.TEXT_DIM
	Blueprint.draw_text(self, Vector2(0, 10), "CHARGE", Blueprint.TEXT_DIM, 10)
	var frame := Rect2(x, top, col_w, h)
	draw_rect(frame, Color(Blueprint.PAPER_DARK, 0.9))
	var fill_h := h * clampf(charge, 0.0, 1.0)
	var fill := Rect2(x, bottom - fill_h, col_w, fill_h)
	draw_rect(fill, Color(Blueprint.LINE, 0.35))
	Blueprint.draw_hatch(self, fill, Color(Blueprint.LINE, 0.5), 5.0)
	draw_line(Vector2(x - 3, bottom - fill_h), Vector2(x + col_w + 3, bottom - fill_h), ink, 2.0)
	draw_rect(frame, Color(Blueprint.LINE, 0.7), false, 1.0)
	# One tick per propellant increment.
	for c in increments:
		var y := bottom - h * c
		draw_line(Vector2(x + col_w, y), Vector2(x + col_w + 7.0, y), Color(Blueprint.LINE, 0.6), 1.0)
	if not is_nan(last_charge):
		var ly := bottom - h * clampf(last_charge, 0.0, 1.0)
		draw_colored_polygon(PackedVector2Array([Vector2(x - 2, ly), Vector2(x - 8, ly - 4), Vector2(x - 8, ly + 4)]),
			Color(Blueprint.AMBER, 0.7))
	var tx := x + col_w + 12.0
	Blueprint.draw_text(self, Vector2(tx, bottom - fill_h * 0.5 + 6.0).clamp(Vector2(tx, top + 16), Vector2(tx, bottom)),
		"CHG %d" % (_nearest() + 1), ink, 18,
		HORIZONTAL_ALIGNMENT_LEFT, Blueprint.FONT_MONO_BOLD)
	Blueprint.draw_text(self, Vector2(0, size.y - 2), "%.1f m/s" % velocity, Blueprint.TEXT_DIM, 11)


func _nearest() -> int:
	var best := 0
	for i in increments.size():
		if absf(increments[i] - charge) < absf(increments[best] - charge):
			best = i
	return best
