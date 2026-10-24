class_name HudTargetPips
extends Control
## One small tower glyph per contract target: outlined while standing, struck out when destroyed.

var total := 0
var destroyed := 0


func _draw() -> void:
	var w := 14.0
	var gap := 6.0
	for i in total:
		var r := Rect2(i * (w + gap), 2, w, size.y - 4)
		var down := i < destroyed
		if down:
			draw_rect(r, Color(Blueprint.RED, 0.15))
			draw_line(r.position, r.end, Color(Blueprint.RED, 0.6), 1.5)
			draw_line(Vector2(r.position.x, r.end.y), Vector2(r.end.x, r.position.y), Color(Blueprint.RED, 0.6), 1.5)
			draw_rect(r, Color(Blueprint.RED, 0.4), false, 1.0)
		else:
			draw_rect(r, Color(BattleArt.ENEMY_FILL, 0.8))
			draw_rect(r, Blueprint.RED, false, 1.0)
			for m in [0, 2]:
				draw_rect(Rect2(r.position + Vector2(m * w / 3.0 + 1, -2), Vector2(w / 3.0 - 1, 3)), Blueprint.RED)
