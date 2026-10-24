class_name HudMeter
extends Control
## A labelled horizontal meter: segmented bar, optional threshold marker, right-aligned value.

var label := ""
var value_text := ""
var fraction := 0.0
var color := Blueprint.LINE
## 0..1 position of a marker line (e.g. where the enemy starts firing back); negative hides it.
var marker := -1.0
var marker_label := ""
var segments := 20


func _draw() -> void:
	Blueprint.draw_text(self, Vector2(0, 10), label, Blueprint.TEXT_DIM, 10)
	Blueprint.draw_text(self, Vector2(size.x, 11), value_text, color, 12, HORIZONTAL_ALIGNMENT_RIGHT,
		Blueprint.FONT_MONO_BOLD)
	var bar := Rect2(0, 16, size.x, minf(size.y - 17, 13.0))
	draw_rect(bar, Color(Blueprint.PAPER_DARK, 0.9))
	var seg_w := bar.size.x / segments
	var lit := clampf(fraction, 0.0, 1.0) * segments
	for i in segments:
		var r := Rect2(bar.position.x + i * seg_w + 1, bar.position.y + 2, seg_w - 2, bar.size.y - 4)
		if i + 1 <= lit:
			draw_rect(r, color)
		elif i < lit:
			draw_rect(Rect2(r.position, Vector2(r.size.x * (lit - i), r.size.y)), Color(color, 0.7))
		else:
			draw_rect(r, Color(Blueprint.LINE, 0.08))
	draw_rect(bar, Color(Blueprint.LINE, 0.5), false, 1.0)
	if marker >= 0.0:
		var x := bar.position.x + bar.size.x * marker
		draw_line(Vector2(x, bar.position.y - 3), Vector2(x, bar.end.y + 3), Blueprint.RED, 1.5)
		if not marker_label.is_empty():
			Blueprint.draw_text(self, Vector2(x - 3, bar.end.y + 11), "▲ " + marker_label, Color(Blueprint.RED, 0.8), 9)
