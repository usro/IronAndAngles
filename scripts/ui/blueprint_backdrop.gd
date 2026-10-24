class_name BlueprintBackdrop
extends Control
## Full-screen drawing sheet behind a management screen: paper, grid, an inset frame with
## registration ticks and a small title block in the bottom-right corner.

const FRAME_INSET := 8.0

## Text in the title block, e.g. "SHEET 02 — REGION MAP". Empty hides the block.
var sheet_title := ""


static func add_to(parent: Control, title := "") -> BlueprintBackdrop:
	var b := BlueprintBackdrop.new()
	b.sheet_title = title
	parent.add_child(b)
	parent.move_child(b, 0)
	return b


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, Blueprint.PAPER)
	Blueprint.draw_grid(self, r)
	var frame := r.grow(-FRAME_INSET)
	draw_rect(frame, Color(Blueprint.LINE, 0.25), false, 1.0)
	Blueprint.draw_corner_ticks(self, frame, Color(Blueprint.LINE, 0.6), 18.0, 6.0)
	if sheet_title.is_empty():
		return
	var text_w := Blueprint.FONT_MONO.get_string_size(sheet_title, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
	var block := Rect2(frame.end - Vector2(text_w + 20, 18), Vector2(text_w + 20, 18))
	draw_rect(block, Blueprint.PAPER_DARK)
	draw_rect(block, Color(Blueprint.LINE, 0.4), false, 1.0)
	Blueprint.draw_text(self, block.position + Vector2(10, 13), sheet_title, Color(Blueprint.TEXT_DIM, 0.8), 10)
