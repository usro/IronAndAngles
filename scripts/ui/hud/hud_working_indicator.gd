class_name HudWorkingIndicator
extends Control
## "CALCULATING FIRE SOLUTION" in the blueprint style: a spinning protractor arc with a sweeping
## needle and animated dots, shown while background ballistics work runs.

var text := "CALCULATING FIRE SOLUTION"
var color := Blueprint.AMBER
var _t := 0.0


func _init(p_text := "CALCULATING FIRE SOLUTION") -> void:
	text = p_text
	custom_minimum_size = Vector2(300, 22)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var c := Vector2(10, size.y * 0.5)
	var r := 8.0
	# Protractor: a quarter arc that rotates, and a needle sweeping across it.
	var a0 := _t * 3.0
	draw_arc(c, r, a0, a0 + PI * 0.5, 12, color, 1.5)
	draw_arc(c, r, a0 + PI, a0 + PI * 1.5, 12, Color(color, 0.35), 1.5)
	var needle := -PI * 0.25 + sin(_t * 4.0) * PI * 0.25
	draw_line(c, c + Vector2(cos(needle), sin(needle)) * (r - 1.0), Blueprint.INK, 1.0)
	var dots := ".".repeat(int(_t * 3.0) % 4)
	Blueprint.draw_text(self, Vector2(26, size.y * 0.5 + 4.0), text + dots, color, 11)
