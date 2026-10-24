class_name ProfitWaterfall
extends Control
## Horizontal waterfall of one contract's money: payout in, then each cost out, ending at the net.
## Feed it `steps`: [{"label": String, "amount": int, "kind": &"in"|&"out"|&"total"|&"after"}].

const ROW_H := 26.0
const LABEL_W := 120.0

var steps: Array[Dictionary] = []:
	set(value):
		steps = value
		custom_minimum_size.y = ROW_H * steps.size() + 18.0
		queue_redraw()


func _draw() -> void:
	if steps.is_empty():
		return
	# Scale covers every running total and the zero line.
	var lo := 0
	var hi := 0
	var running := 0
	for s in steps:
		match s.kind:
			&"in":
				running += s.amount
			&"out":
				running -= s.amount
			_:
				pass
		lo = mini(lo, running)
		hi = maxi(hi, maxi(running, s.amount if s.kind == &"in" else 0))
	var span := maxf(float(hi - lo), 1.0)
	var x0 := LABEL_W
	var x1 := size.x - 70.0
	var to_x := func(v: float) -> float: return x0 + (v - lo) / span * (x1 - x0)
	var zero_x: float = to_x.call(0.0)
	draw_line(Vector2(zero_x, 0), Vector2(zero_x, size.y - 14), Color(Blueprint.LINE, 0.5), 1.0)
	Blueprint.draw_text(self, Vector2(zero_x, size.y - 2), "0", Blueprint.TEXT_DIM, 10, HORIZONTAL_ALIGNMENT_CENTER)

	running = 0
	var prev_end := zero_x
	for i in steps.size():
		var s: Dictionary = steps[i]
		var y := i * ROW_H + 4.0
		var from := running
		var col := Blueprint.LINE
		match s.kind:
			&"in":
				running += s.amount
			&"out":
				running -= s.amount
				col = Blueprint.RED
			&"total":
				from = 0
				col = Blueprint.AMBER if running >= 0 else Blueprint.RED
			&"after":
				from = running
				running -= s.amount
				col = Color(Blueprint.TEXT_DIM, 0.8)
		var a: float = to_x.call(float(from))
		var b: float = to_x.call(float(running))
		var r := Rect2(minf(a, b), y, maxf(absf(b - a), 2.0), ROW_H - 10.0)
		draw_rect(r, Color(col, 0.25))
		if s.kind == &"after":
			Blueprint.draw_hatch(self, r, Color(col, 0.6), 5.0)
		draw_rect(r, col, false, 1.0)
		# Connector from the previous bar's end.
		if i > 0:
			draw_dashed_line(Vector2(prev_end, y - 10.0), Vector2(prev_end, y), Color(Blueprint.LINE, 0.4), 1.0, 2.0)
		prev_end = b
		Blueprint.draw_text(self, Vector2(0, y + 12), String(s.label).to_upper(), Blueprint.TEXT_DIM, 11)
		var sign := "+" if s.kind == &"in" else ("−" if s.kind == &"out" or s.kind == &"after" else "")
		var value := sign + Blueprint.money(absi(s.amount)) if s.kind != &"total" else Blueprint.money(running)
		Blueprint.draw_text(self, Vector2(size.x, y + 12), value, col, 12, HORIZONTAL_ALIGNMENT_RIGHT,
			Blueprint.FONT_MONO_BOLD)
