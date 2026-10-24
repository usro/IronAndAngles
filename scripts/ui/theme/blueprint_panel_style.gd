@tool
class_name BlueprintPanelStyle
extends StyleBox
## A drafting-sheet panel: flat paper fill, a thin ink border and registration ticks that
## overshoot the corners. Used by the theme for PanelContainer and the sheet variations.

@export var bg_color := Blueprint.PAPER_DARK
@export var border_color := Blueprint.LINE_DIM
@export var tick_color := Blueprint.LINE
@export var border_width := 1.0
@export var tick_length := 10.0
## Draw the paper grid inside the panel.
@export var grid := false


func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	RenderingServer.canvas_item_add_rect(to_canvas_item, rect, bg_color)
	if grid:
		_grid(to_canvas_item, rect)
	if border_width > 0.0:
		var pts := PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end,
			Vector2(rect.position.x, rect.end.y), rect.position])
		RenderingServer.canvas_item_add_polyline(to_canvas_item, pts, PackedColorArray([border_color]),
			border_width)
	if tick_length > 0.0:
		var corners := [rect.position, Vector2(rect.end.x, rect.position.y), rect.end,
			Vector2(rect.position.x, rect.end.y)]
		var dirs := [Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1), Vector2(1, -1)]
		for i in 4:
			var c: Vector2 = corners[i]
			var d: Vector2 = dirs[i]
			_line(to_canvas_item, c + Vector2(0, -d.y * 3.0), c + Vector2(0, d.y * tick_length))
			_line(to_canvas_item, c + Vector2(-d.x * 3.0, 0), c + Vector2(d.x * tick_length, 0))


func _line(ci: RID, a: Vector2, b: Vector2) -> void:
	RenderingServer.canvas_item_add_line(ci, a, b, tick_color, 1.5)


func _grid(ci: RID, rect: Rect2) -> void:
	var step := Blueprint.GRID_MINOR_PX
	var i := 0
	var x := rect.position.x + step
	while x < rect.end.x:
		var col := Blueprint.GRID_MAJOR if i % 5 == 4 else Blueprint.GRID_MINOR
		RenderingServer.canvas_item_add_line(ci, Vector2(x, rect.position.y), Vector2(x, rect.end.y), col)
		x += step
		i += 1
	i = 0
	var y := rect.position.y + step
	while y < rect.end.y:
		var col := Blueprint.GRID_MAJOR if i % 5 == 4 else Blueprint.GRID_MINOR
		RenderingServer.canvas_item_add_line(ci, Vector2(rect.position.x, y), Vector2(rect.end.x, y), col)
		y += step
		i += 1
