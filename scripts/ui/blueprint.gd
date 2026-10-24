class_name Blueprint
extends RefCounted
## The blueprint look shared by every screen: palette, fonts and small drafting helpers
## (grid paper, corner ticks, dimension lines). Views draw with these; they hold no game logic.
##
## Ink conventions: our side and neutral line work in white/cyan ink, the enemy and warnings in
## "red pencil" markup, money and the current selection in amber.

# --- Palette ---
const PAPER := Color("0d2748")
const PAPER_DARK := Color("081a33")
const PAPER_LIGHT := Color("143661")
const GRID_MINOR := Color(0.45, 0.70, 0.95, 0.05)
const GRID_MAJOR := Color(0.45, 0.70, 0.95, 0.12)
const INK := Color("eaf4ff")
const LINE := Color("7fd3ff")
const LINE_DIM := Color(0.50, 0.83, 1.0, 0.45)
const TEXT_DIM := Color("8fb2d6")
const AMBER := Color("ffc857")
const RED := Color("ff6f5e")
const GREEN := Color("7cf2b0")

const FONT_BODY := preload("res://themes/fonts/Inter-Regular.otf")
const FONT_BODY_BOLD := preload("res://themes/fonts/Inter-SemiBold.otf")
const FONT_MONO := preload("res://themes/fonts/JetBrainsMono-Regular.ttf")
const FONT_MONO_BOLD := preload("res://themes/fonts/JetBrainsMono-Bold.ttf")

const GRID_MINOR_PX := 20.0
const GRID_MAJOR_PX := 100.0


## Graph-paper grid over `rect`, aligned to `origin` so it can scroll with a view.
static func draw_grid(ci: CanvasItem, rect: Rect2, origin := Vector2.ZERO,
		minor := GRID_MINOR_PX, major := GRID_MAJOR_PX) -> void:
	for step_col in [[minor, GRID_MINOR], [major, GRID_MAJOR]]:
		var step: float = step_col[0]
		var col: Color = step_col[1]
		var x := rect.position.x + fposmod(origin.x - rect.position.x, step)
		while x <= rect.end.x:
			ci.draw_line(Vector2(x, rect.position.y), Vector2(x, rect.end.y), col, 1.0)
			x += step
		var y := rect.position.y + fposmod(origin.y - rect.position.y, step)
		while y <= rect.end.y:
			ci.draw_line(Vector2(rect.position.x, y), Vector2(rect.end.x, y), col, 1.0)
			y += step


## Registration ticks at the four corners of `rect`, overshooting it a little, as on a drawing.
static func draw_corner_ticks(ci: CanvasItem, rect: Rect2, col := LINE, length := 12.0,
		overshoot := 4.0, width := 1.0) -> void:
	var corners := [rect.position, Vector2(rect.end.x, rect.position.y), rect.end,
		Vector2(rect.position.x, rect.end.y)]
	var dirs := [Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1), Vector2(1, -1)]
	for i in 4:
		var c: Vector2 = corners[i]
		var d: Vector2 = dirs[i]
		ci.draw_line(c - Vector2(d.x * overshoot, 0), c + Vector2(d.x * length, 0), col, width)
		ci.draw_line(c - Vector2(0, d.y * overshoot), c + Vector2(0, d.y * length), col, width)


## A horizontal dimension line with end ticks and a centred label.
static func draw_dimension(ci: CanvasItem, from: Vector2, to: Vector2, text: String,
		col := LINE_DIM, font_size := 11) -> void:
	ci.draw_line(from, to, col, 1.0)
	var n := (to - from).orthogonal().normalized() * 5.0
	ci.draw_line(from - n, from + n, col, 1.0)
	ci.draw_line(to - n, to + n, col, 1.0)
	if text.is_empty():
		return
	var w := FONT_MONO.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var mid := (from + to) * 0.5
	ci.draw_rect(Rect2(mid - Vector2(w * 0.5 + 4, font_size * 0.6), Vector2(w + 8, font_size * 1.2)), PAPER)
	ci.draw_string(FONT_MONO, mid + Vector2(-w * 0.5, font_size * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT,
		-1, font_size, col)


## Mono text helper; `align` uses the anchor point as left, centre or right of the text.
static func draw_text(ci: CanvasItem, pos: Vector2, text: String, col := INK, font_size := 12,
		align := HORIZONTAL_ALIGNMENT_LEFT, font: Font = FONT_MONO) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var x := pos.x
	if align == HORIZONTAL_ALIGNMENT_CENTER:
		x -= w * 0.5
	elif align == HORIZONTAL_ALIGNMENT_RIGHT:
		x -= w
	ci.draw_string(font, Vector2(x, pos.y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)


## Diagonal 45° hatching clipped to `rect` (section fill on a drawing).
static func draw_hatch(ci: CanvasItem, rect: Rect2, col: Color, spacing := 6.0, width := 1.0) -> void:
	var h := rect.size.y
	var x := rect.position.x - h
	while x < rect.end.x:
		var a := Vector2(x, rect.end.y)
		var b := Vector2(x + h, rect.position.y)
		# Clip the segment to the rect's horizontal span.
		if a.x < rect.position.x:
			a = Vector2(rect.position.x, rect.end.y - (rect.position.x - a.x))
		if b.x > rect.end.x:
			b = Vector2(rect.end.x, rect.position.y + (b.x - rect.end.x))
		if a.x <= b.x:
			ci.draw_line(a, b, col, width)
		x += spacing


## "1,234" style thousands separators; negative numbers keep their sign.
static func money(amount: int, signed := false) -> String:
	var s := str(absi(amount))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	out = s + out
	if amount < 0:
		return "−" + out
	return ("+" + out) if signed and amount > 0 else out
