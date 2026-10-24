class_name ArcGauge
extends Control
## A ring gauge with a big centred value and a caption, drawn like a protractor scale.

var fraction := 0.0:
	set(v):
		fraction = clampf(v, 0.0, 1.0)
		queue_redraw()
var value_text := ""
var caption := ""
var color := Blueprint.LINE


func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5 - 6.0
	var start := PI * 0.75
	var sweep := PI * 1.5
	draw_arc(c, r, start, start + sweep, 48, Color(Blueprint.LINE, 0.2), 6.0)
	if fraction > 0.0:
		draw_arc(c, r, start, start + sweep * fraction, 48, color, 6.0)
	for i in 11:
		var a := start + sweep * i / 10.0
		var d := Vector2(cos(a), sin(a))
		var inner := r - (10.0 if i % 5 == 0 else 6.0)
		draw_line(c + d * (r - 14.0), c + d * (inner - 8.0), Color(Blueprint.LINE, 0.5), 1.0)
	Blueprint.draw_text(self, c + Vector2(0, 8), value_text, Blueprint.INK, int(r * 0.42), HORIZONTAL_ALIGNMENT_CENTER,
		Blueprint.FONT_MONO_BOLD)
	Blueprint.draw_text(self, c + Vector2(0, r * 0.62), caption, Blueprint.TEXT_DIM, 10, HORIZONTAL_ALIGNMENT_CENTER)
