class_name Stamp
extends Control
## A rubber-stamp mark ("VICTORY", "DEFEAT") tilted on the sheet.

var text := ""
var color := Blueprint.AMBER
var angle_deg := -8.0
var font_size := 40


func _draw() -> void:
	var font := Blueprint.FONT_MONO_BOLD
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var box := Vector2(w + 36.0, font_size * 1.5)
	draw_set_transform(size * 0.5, deg_to_rad(angle_deg))
	var r := Rect2(-box * 0.5, box)
	draw_rect(r, Color(color, 0.08))
	draw_rect(r, color, false, 3.0)
	draw_rect(r.grow(-6.0), Color(color, 0.7), false, 1.0)
	draw_string(font, Vector2(-w * 0.5, font_size * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
	draw_set_transform_matrix(Transform2D.IDENTITY)
