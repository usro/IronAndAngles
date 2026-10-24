class_name DraftedMap
extends Control
## The region map drawn as a survey sheet: contour lines, a river, a road, compass and scale bar,
## with each plot on offer marked as a hatched parcel. The region map screen adds the plot tags
## (buttons) as children and tells this control what to mark through `parcels`.

## One entry per lot: {"pos": Vector2 (0..1 of the map), "plot_id": StringName,
## "profile": GameConstants.TerrainProfile, "selected": bool, "bid": bool, "tag": Rect2 (px)}.
var parcels: Array[Dictionary] = []:
	set(value):
		parcels = value
		queue_redraw()

const CONTOUR_SEED := 4127
const CONTOUR_LEVELS := [-0.35, -0.15, 0.05, 0.25, 0.45]
const CELL_PX := 14.0

var _contours: Array[PackedVector2Array] = []  # pairs of points (segments) per level
var _contour_size := Vector2.ZERO


func _ready() -> void:
	clip_contents = true
	resized.connect(queue_redraw)


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, Color(Blueprint.PAPER_DARK, 0.92))
	Blueprint.draw_grid(self, r)
	if _contour_size != size:
		_build_contours()
	for i in _contours.size():
		var major := i == 2
		draw_multiline(_contours[i], Color(Blueprint.LINE, 0.28 if major else 0.14), 1.0)
	_river()
	_road()
	for p in parcels:
		_parcel(p)
	_compass(Vector2(size.x - 44, 48))
	_scale_bar(Vector2(18, size.y - 22))
	_cartouche()
	draw_rect(r.grow(-1), Color(Blueprint.LINE, 0.5), false, 1.0)
	Blueprint.draw_corner_ticks(self, r.grow(-6), Blueprint.LINE, 12.0, 0.0)


func marker_position(normalized: Vector2) -> Vector2:
	return normalized * size


# --- Terrain features ---

func _build_contours() -> void:
	_contour_size = size
	_contours.clear()
	var noise := FastNoiseLite.new()
	noise.seed = CONTOUR_SEED
	noise.frequency = 0.0045
	noise.fractal_octaves = 3
	var cols := int(size.x / CELL_PX) + 2
	var rows := int(size.y / CELL_PX) + 2
	var v := PackedFloat32Array()
	v.resize(cols * rows)
	for y in rows:
		for x in cols:
			v[y * cols + x] = noise.get_noise_2d(x * CELL_PX, y * CELL_PX)
	for level: float in CONTOUR_LEVELS:
		var segs := PackedVector2Array()
		for y in rows - 1:
			for x in cols - 1:
				_cell_segments(segs, v, cols, x, y, level)
		_contours.append(segs)


## Marching squares for one cell.
func _cell_segments(out: PackedVector2Array, v: PackedFloat32Array, cols: int, x: int, y: int, level: float) -> void:
	var c := [v[y * cols + x], v[y * cols + x + 1], v[(y + 1) * cols + x + 1], v[(y + 1) * cols + x]]
	var corners := [Vector2(x, y), Vector2(x + 1, y), Vector2(x + 1, y + 1), Vector2(x, y + 1)]
	var pts := PackedVector2Array()
	for e in 4:
		var a: float = c[e]
		var b: float = c[(e + 1) % 4]
		if (a < level) != (b < level):
			var t := (level - a) / (b - a)
			pts.append((corners[e] as Vector2).lerp(corners[(e + 1) % 4], t) * CELL_PX)
	if pts.size() >= 2:
		out.append(pts[0])
		out.append(pts[1])
	if pts.size() == 4:
		out.append(pts[2])
		out.append(pts[3])


func _river() -> void:
	var pts := PackedVector2Array()
	for i in 41:
		var t := i / 40.0
		pts.append(Vector2(size.x * (0.05 + 0.95 * t), size.y * (0.88 - 0.35 * t + 0.07 * sin(t * 9.0))))
	draw_polyline(pts, Color(Blueprint.LINE, 0.55), 3.0)
	draw_polyline(pts, Color(Blueprint.PAPER_DARK, 1.0), 1.2)
	var label_at := pts[30] + Vector2(-30, 18)
	Blueprint.draw_text(self, label_at, "R. GREYWATER", Color(Blueprint.LINE, 0.5), 10)


func _road() -> void:
	var sorted := parcels.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.pos.x < b.pos.x)
	var pts := PackedVector2Array([Vector2(0, size.y * 0.5)])
	for p in sorted:
		pts.append(marker_position(p.pos))
	pts.append(Vector2(size.x, size.y * 0.4))
	BattleArt.draw_dashed_polyline(self, pts, Color(Blueprint.INK, 0.22), 1.0, 6.0, 4.0)


# --- Parcels ---

func _parcel(p: Dictionary) -> void:
	var c := marker_position(p.pos)
	var selected: bool = p.get("selected", false)
	var bid: bool = p.get("bid", false)
	var col := Blueprint.AMBER if selected or bid else Blueprint.LINE
	# An irregular four-sided lot, stable per plot.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(p.plot_id)
	var poly := PackedVector2Array()
	for i in 4:
		var a := TAU * i / 4.0 + PI * 0.25 + rng.randf_range(-0.3, 0.3)
		poly.append(c + Vector2(cos(a), sin(a)) * rng.randf_range(16.0, 24.0))
	draw_colored_polygon(poly, Color(col, 0.16 if not bid else 0.3))
	var bounds := Rect2(poly[0], Vector2.ZERO)
	for q in poly:
		bounds = bounds.expand(q)
	_hatch_polygon(poly, bounds, Color(col, 0.35))
	var closed := poly.duplicate()
	closed.append(poly[0])
	draw_polyline(closed, col, 2.0 if selected else 1.2)
	_profile_glyph(c, p.get("profile", 0), col)
	if selected:
		BattleArt.draw_crosshair(self, c, 30.0, Color(Blueprint.AMBER, 0.8), 1.0)
	var tag: Rect2 = p.get("tag", Rect2())
	if tag.size != Vector2.ZERO:
		var end := Vector2(clampf(c.x, tag.position.x, tag.end.x), clampf(c.y, tag.position.y, tag.end.y))
		if end.distance_to(c) > 22.0:
			draw_line(c + (end - c).normalized() * 20.0, end, Color(col, 0.6), 1.0)


func _hatch_polygon(poly: PackedVector2Array, bounds: Rect2, col: Color) -> void:
	var x := bounds.position.x - bounds.size.y
	while x < bounds.end.x:
		var a := Vector2(x, bounds.end.y)
		var b := Vector2(x + bounds.size.y, bounds.position.y)
		var hits := Geometry2D.clip_polyline_with_polygon(PackedVector2Array([a, b]), poly)
		for seg in hits:
			draw_polyline(seg, col, 1.0)
		x += 5.0


## A tiny cross-section of the plot's terrain profile.
func _profile_glyph(c: Vector2, profile: int, col: Color) -> void:
	var w := 9.0
	var pts: PackedVector2Array
	match profile:
		GameConstants.TerrainProfile.FLAT:
			pts = [Vector2(-w, 0), Vector2(w, 0)]
		GameConstants.TerrainProfile.HILLS:
			pts = [Vector2(-w, 2), Vector2(-w * 0.5, -3), Vector2(0, 1), Vector2(w * 0.5, -3), Vector2(w, 2)]
		GameConstants.TerrainProfile.RIDGE:
			pts = [Vector2(-w, 3), Vector2(-2, 3), Vector2(0, -5), Vector2(2, 3), Vector2(w, 3)]
		GameConstants.TerrainProfile.VALLEY:
			pts = [Vector2(-w, -3), Vector2(-3, 3), Vector2(3, 3), Vector2(w, -3)]
		_:
			pts = [Vector2(-w, 4), Vector2(-2, -6), Vector2(1, -2), Vector2(4, -7), Vector2(w, 4)]
	for i in pts.size():
		pts[i] += c
	draw_polyline(pts, Blueprint.INK, 1.5)


# --- Map furniture ---

func _compass(c: Vector2) -> void:
	var col := Color(Blueprint.LINE, 0.7)
	draw_arc(c, 22.0, 0.0, TAU, 32, col, 1.0)
	draw_arc(c, 17.0, 0.0, TAU, 32, Color(col, 0.4), 1.0)
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -28), c + Vector2(5, 0), c + Vector2(-5, 0)]), col)
	draw_polyline(PackedVector2Array([c + Vector2(0, 28), c + Vector2(5, 0), c + Vector2(-5, 0), c + Vector2(0, 28)]),
		col, 1.0)
	draw_line(c + Vector2(-26, 0), c + Vector2(26, 0), Color(col, 0.6), 1.0)
	Blueprint.draw_text(self, c + Vector2(0, -32), "N", Blueprint.INK, 12, HORIZONTAL_ALIGNMENT_CENTER,
		Blueprint.FONT_MONO_BOLD)


func _scale_bar(at: Vector2) -> void:
	var seg := 30.0
	for i in 4:
		var r := Rect2(at + Vector2(i * seg, -5), Vector2(seg, 5))
		if i % 2 == 0:
			draw_rect(r, Color(Blueprint.INK, 0.7))
		draw_rect(r, Color(Blueprint.INK, 0.7), false, 1.0)
	Blueprint.draw_text(self, at + Vector2(0, -9), "0", Blueprint.TEXT_DIM, 10)
	Blueprint.draw_text(self, at + Vector2(4 * seg, -9), "10 km", Blueprint.TEXT_DIM, 10,
		HORIZONTAL_ALIGNMENT_CENTER)


func _cartouche() -> void:
	var text := "THEATRE OF OPERATIONS · CONTRACT PLOTS"
	var w := Blueprint.FONT_MONO_BOLD.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	var r := Rect2(Vector2(14, 14), Vector2(w + 20, 22))
	draw_rect(r, Blueprint.PAPER_DARK)
	draw_rect(r, Color(Blueprint.LINE, 0.6), false, 1.0)
	Blueprint.draw_text(self, r.position + Vector2(10, 15), text, Blueprint.INK, 11, HORIZONTAL_ALIGNMENT_LEFT,
		Blueprint.FONT_MONO_BOLD)
