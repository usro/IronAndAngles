class_name TerrainMap
extends RefCounted
## Pure model of destructible ground: a solidity bitmap in world meters (+y down). No nodes.
## Each cell is SOLID (255) or AIR (0), so a block of cells doubles as an L8 image for rendering.
## Outside the grid: anything at or below the bottom edge is solid (bedrock), everything else is air.

const SOLID := 255
const AIR := 0
## Chunks are CHUNK_CELLS x CHUNK_CELLS cells. They are the unit of redraw and collision rebuild.
const CHUNK_CELLS := 64
## Radius (in cells) of the neighbourhood sampled to estimate a surface normal.
const NORMAL_SAMPLE_RADIUS := 4

## Marching-squares segments per case (tl*8 + tr*4 + br*2 + bl). Edges: 0 top, 1 right, 2 bottom, 3 left.
## Saddles (5, 10) are resolved as two separate corners.
const _MS_CASES: Array = [
	[], [3, 2], [2, 1], [3, 1], [0, 1], [0, 1, 3, 2], [0, 2], [3, 0],
	[3, 0], [0, 2], [3, 0, 2, 1], [0, 1], [3, 1], [2, 1], [3, 2], [],
]
## Edge midpoints relative to the square's top-left cell index, in cell units.
const _MS_EDGE_POINTS: Array[Vector2] = [
	Vector2(1.0, 0.5), Vector2(1.5, 1.0), Vector2(1.0, 1.5), Vector2(0.5, 1.0),
]

var cell_size_m: float
## World position (meters) of the top-left corner of cell (0, 0).
var origin_m: Vector2
## Grid size in cells. Always a multiple of CHUNK_CELLS.
var width: int
var height: int
## Rows at or below this index are bedrock and are never carved.
var bedrock_row: int

## Layout spots, in meters. The battery fires toward +x (facing 1) at the target zone.
var battery_x_m: float = 0.0
var target_zone_min_x_m: float = 0.0
var target_zone_max_x_m: float = 0.0

var _cells := PackedByteArray()
## Topmost solid row per column (height if the column is empty).
var _surface_rows := PackedInt32Array()
var _dirty_chunks: Dictionary = {}  # Vector2i -> true


func _init(p_origin_m: Vector2, p_width: int, p_height: int, p_cell_size_m: float) -> void:
	assert(p_width % CHUNK_CELLS == 0 and p_height % CHUNK_CELLS == 0, "grid must be whole chunks")
	origin_m = p_origin_m
	width = p_width
	height = p_height
	cell_size_m = p_cell_size_m
	bedrock_row = height
	_cells.resize(width * height)
	_surface_rows.resize(width)
	_surface_rows.fill(height)


## Replaces all cells with a heightfield: column x is solid from surface_rows[x] down.
## Uses Image.fill_rect so generation stays native-speed.
func fill_from_surface_rows(surface_rows: PackedInt32Array) -> void:
	assert(surface_rows.size() == width)
	var img := Image.create_empty(width, height, false, Image.FORMAT_L8)
	for x in width:
		var top := clampi(surface_rows[x], 0, height)
		if top < height:
			img.fill_rect(Rect2i(x, top, 1, height - top), Color.WHITE)
	_cells = img.get_data()
	for x in width:
		_surface_rows[x] = clampi(surface_rows[x], 0, height)
	_mark_all_dirty()


# --- Coordinates ---

func world_to_cell(point_m: Vector2) -> Vector2i:
	var c := (point_m - origin_m) / cell_size_m
	return Vector2i(floori(c.x), floori(c.y))


func cell_center_m(cell: Vector2i) -> Vector2:
	return origin_m + (Vector2(cell) + Vector2(0.5, 0.5)) * cell_size_m


func size_m() -> Vector2:
	return Vector2(width, height) * cell_size_m


func chunk_grid_size() -> Vector2i:
	return Vector2i(width / CHUNK_CELLS, height / CHUNK_CELLS)


func chunk_origin_m(chunk: Vector2i) -> Vector2:
	return origin_m + Vector2(chunk * CHUNK_CELLS) * cell_size_m


# --- Queries ---

func is_solid(point_m: Vector2) -> bool:
	var c := world_to_cell(point_m)
	return _cell_solid(c.x, c.y)


## Surface y (meters, +y down, so smaller is higher) at x: the top of the highest solid cell,
## linearly interpolated between column centres. Off the map it is the bottom edge.
func surface_height_at(x_m: float) -> float:
	var fx := (x_m - origin_m.x) / cell_size_m - 0.5
	var x0 := floori(fx)
	var t := fx - x0
	return lerpf(_column_surface_m(x0), _column_surface_m(x0 + 1), t)


## Walks the segment cell by cell (Amanatides-Woo DDA) and returns the first solid contact:
## {hit: bool, position: Vector2, normal: Vector2}. Positions are accurate to one cell; the
## normal comes from the local solidity gradient, so it follows the visible slope and points to air.
func raycast(from_m: Vector2, to_m: Vector2) -> Dictionary:
	if is_solid(from_m):
		return _hit_result(from_m, to_m - from_m)
	var a := (from_m - origin_m) / cell_size_m
	var b := (to_m - origin_m) / cell_size_m
	var d := b - a
	var hit_t := _dda_first_solid(a, d)
	if hit_t < 0.0:
		# Off the grid sideways the ground is still the bedrock plane at the bottom edge.
		if a.y < height and b.y >= height:
			hit_t = (height - a.y) / d.y
		else:
			return {"hit": false, "position": to_m, "normal": Vector2.ZERO}
	return _hit_result(from_m + (to_m - from_m) * hit_t, d)


## Point on the surface above the battery spot (follows craters).
func battery_position_m() -> Vector2:
	return Vector2(battery_x_m, surface_height_at(battery_x_m))


func target_zone_center_m() -> Vector2:
	var x := (target_zone_min_x_m + target_zone_max_x_m) * 0.5
	return Vector2(x, surface_height_at(x))


## count evenly spaced surface points across the target zone, left to right.
func target_positions_m(count: int) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for i in count:
		var x := lerpf(target_zone_min_x_m, target_zone_max_x_m, (i + 0.5) / count)
		out.append(Vector2(x, surface_height_at(x)))
	return out


## Deterministic fingerprint of the cell data (for tests and replay checks).
func cells_hash() -> int:
	return hash(_cells)


func solid_cell_count() -> int:
	return _cells.count(SOLID)


# --- Destruction ---

## Removes every non-bedrock cell whose centre lies within radius_m of center_m.
## Returns how many cells were removed and marks the touched chunks dirty.
func carve(center_m: Vector2, radius_m: float) -> int:
	if radius_m <= 0.0:
		return 0
	var c := (center_m - origin_m) / cell_size_m
	var r := radius_m / cell_size_m
	var y0 := maxi(0, floori(c.y - r))
	var y1 := mini(bedrock_row - 1, ceili(c.y + r))
	var min_x := width
	var max_x := -1
	var removed := 0
	for y in range(y0, y1 + 1):
		var dy := y + 0.5 - c.y
		var hw2 := r * r - dy * dy
		if hw2 < 0.0:
			continue
		var hw := sqrt(hw2)
		var x0 := maxi(0, ceili(c.x - hw - 0.5))
		var x1 := mini(width - 1, floori(c.x + hw - 0.5))
		var row := y * width
		for x in range(x0, x1 + 1):
			if _cells[row + x] != AIR:
				_cells[row + x] = AIR
				removed += 1
				min_x = mini(min_x, x)
				max_x = maxi(max_x, x)
	if removed == 0:
		return 0
	for x in range(min_x, max_x + 1):
		if _surface_rows[x] >= y0 and _surface_rows[x] <= y1:
			_surface_rows[x] = _scan_surface_row(x, _surface_rows[x])
	# A cell change affects marching squares whose corners touch it, hence the -1.
	_mark_dirty_cells(Rect2i(min_x - 1, y0 - 1, max_x - min_x + 2, y1 - y0 + 2))
	return removed


# --- Chunk data for views ---

func has_dirty_chunks() -> bool:
	return not _dirty_chunks.is_empty()


## Returns and clears the chunks changed since the last call.
func take_dirty_chunks() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	out.assign(_dirty_chunks.keys())
	_dirty_chunks.clear()
	return out


## The chunk's cells plus a one-cell border, (CHUNK_CELLS + 2)^2 bytes, ready for an L8 image.
## The border lets linear filtering match across chunk seams.
func chunk_bytes_with_border(chunk: Vector2i) -> PackedByteArray:
	var x0 := chunk.x * CHUNK_CELLS - 1
	var y0 := chunk.y * CHUNK_CELLS - 1
	return _region_bytes(x0, y0, CHUNK_CELLS + 2, CHUNK_CELLS + 2)


## True when the chunk and its border are all solid or all air (nothing to outline).
static func is_uniform(bytes: PackedByteArray) -> bool:
	return not bytes.has(AIR) or not bytes.has(SOLID)


## Marching-squares outline of one chunk as segment pairs (a0, b0, a1, b1, ...) in meters.
## bytes must come from chunk_bytes_with_border(chunk).
func chunk_segments_m(chunk: Vector2i, bytes: PackedByteArray) -> PackedVector2Array:
	var out := PackedVector2Array()
	if is_uniform(bytes):
		return out
	var stride := CHUNK_CELLS + 2
	var base_cell := Vector2(chunk * CHUNK_CELLS)
	# Square (lx, ly) has its top-left corner at local cell (lx, ly); local 1 is the chunk's first cell.
	for ly in range(1, CHUNK_CELLS + 1):
		var row := ly * stride
		for lx in range(1, CHUNK_CELLS + 1):
			var i := row + lx
			var case_id := (8 if bytes[i] else 0) | (4 if bytes[i + 1] else 0) \
					| (2 if bytes[i + stride + 1] else 0) | (1 if bytes[i + stride] else 0)
			if case_id == 0 or case_id == 15:
				continue
			var cell := base_cell + Vector2(lx - 1, ly - 1)
			var edges: Array = _MS_CASES[case_id]
			for e in edges:
				out.append(origin_m + (cell + _MS_EDGE_POINTS[e]) * cell_size_m)
	return out


# --- Internals ---

func _cell_solid(x: int, y: int) -> bool:
	if y >= height:
		return true
	if x < 0 or x >= width or y < 0:
		return false
	return _cells[y * width + x] != AIR


func _column_surface_m(x: int) -> float:
	var row := height if x < 0 or x >= width else _surface_rows[x]
	return origin_m.y + row * cell_size_m


func _scan_surface_row(x: int, from_row: int) -> int:
	for y in range(maxi(from_row, 0), height):
		if _cells[y * width + x] != AIR:
			return y
	return height


## Returns the segment parameter t (0..1) where the ray in cell space first enters a solid
## cell, or -1. a is the start, d the full displacement.
func _dda_first_solid(a: Vector2, d: Vector2) -> float:
	# Clip to the grid box so the walk only covers cells that exist.
	var t0 := 0.0
	var t1 := 1.0
	for axis in 2:
		var lo := 0.0
		var hi := float(width if axis == 0 else height)
		if absf(d[axis]) < 1e-12:
			if a[axis] < lo or a[axis] >= hi:
				return -1.0
			continue
		var ta := (lo - a[axis]) / d[axis]
		var tb := (hi - a[axis]) / d[axis]
		t0 = maxf(t0, minf(ta, tb))
		t1 = minf(t1, maxf(ta, tb))
	if t0 > t1:
		return -1.0
	var p := a + d * t0
	var cx := clampi(floori(p.x), 0, width - 1)
	var cy := clampi(floori(p.y), 0, height - 1)
	var step_x := 1 if d.x > 0.0 else -1
	var step_y := 1 if d.y > 0.0 else -1
	var inf := INF
	var delta_x := absf(1.0 / d.x) if d.x != 0.0 else inf
	var delta_y := absf(1.0 / d.y) if d.y != 0.0 else inf
	var next_x := ((cx + (1 if step_x > 0 else 0)) - a.x) / d.x if d.x != 0.0 else inf
	var next_y := ((cy + (1 if step_y > 0 else 0)) - a.y) / d.y if d.y != 0.0 else inf
	var t_enter := t0
	for _i in width + height + 2:
		if _cells[cy * width + cx] != AIR:
			return t_enter
		if next_x < next_y:
			t_enter = next_x
			next_x += delta_x
			cx += step_x
		else:
			t_enter = next_y
			next_y += delta_y
			cy += step_y
		if t_enter > t1 or cx < 0 or cx >= width or cy < 0 or cy >= height:
			return -1.0
	return -1.0


func _hit_result(position_m: Vector2, ray_dir: Vector2) -> Dictionary:
	return {"hit": true, "position": position_m, "normal": _surface_normal(position_m, ray_dir)}


## Points from solid toward air: the sum of offsets to air cells in a disc around the point.
func _surface_normal(position_m: Vector2, ray_dir: Vector2) -> Vector2:
	var c := world_to_cell(position_m)
	var n := Vector2.ZERO
	var r := NORMAL_SAMPLE_RADIUS
	for oy in range(-r, r + 1):
		for ox in range(-r, r + 1):
			if ox * ox + oy * oy > r * r:
				continue
			if not _cell_solid(c.x + ox, c.y + oy):
				n += Vector2(ox, oy)
	if n.length_squared() < 1e-6:
		return -ray_dir.normalized() if ray_dir != Vector2.ZERO else Vector2.UP
	return n.normalized()


func _region_bytes(x0: int, y0: int, w: int, h: int) -> PackedByteArray:
	# Out of range rows/columns repeat the nearest edge, except below the grid (bedrock).
	var out := PackedByteArray()
	var xa := clampi(x0, 0, width)
	var xb := clampi(x0 + w, 0, width)
	var solid_row := PackedByteArray()
	for y in range(y0, y0 + h):
		if y >= height:
			if solid_row.is_empty():
				solid_row.resize(w)
				solid_row.fill(SOLID)
			out.append_array(solid_row)
			continue
		var row := clampi(y, 0, height - 1) * width
		for _i in xa - x0:
			out.append(_cells[row])
		out.append_array(_cells.slice(row + xa, row + xb))
		for _i in x0 + w - xb:
			out.append(_cells[row + width - 1])
	return out


func _mark_dirty_cells(rect: Rect2i) -> void:
	var grid := chunk_grid_size()
	var c0 := Vector2i(clampi(floori(rect.position.x / float(CHUNK_CELLS)), 0, grid.x - 1),
			clampi(floori(rect.position.y / float(CHUNK_CELLS)), 0, grid.y - 1))
	var end := rect.end - Vector2i.ONE
	var c1 := Vector2i(clampi(floori(end.x / float(CHUNK_CELLS)), 0, grid.x - 1),
			clampi(floori(end.y / float(CHUNK_CELLS)), 0, grid.y - 1))
	for cy in range(c0.y, c1.y + 1):
		for cx in range(c0.x, c1.x + 1):
			_dirty_chunks[Vector2i(cx, cy)] = true


func _mark_all_dirty() -> void:
	var grid := chunk_grid_size()
	for cy in grid.y:
		for cx in grid.x:
			_dirty_chunks[Vector2i(cx, cy)] = true
