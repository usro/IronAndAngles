class_name Terrain
extends Node2D
## Destructible battlefield ground. Builds a TerrainMap from a PlotData, draws it in chunks and
## keeps per-chunk collision in sync. All queries and carve() use meters (+y down); child nodes
## are positioned in pixels (GameConstants.meters_to_pixels), so keep this node at the origin.
##
## Ballistics hit test: pass `terrain.raycast` as the hit_test Callable.

const BLUEPRINT_SHADER := preload("res://scripts/terrain/terrain_blueprint.gdshader")

var map: TerrainMap
var _chunks: Dictionary = {}  # Vector2i -> TerrainChunk
var _material := ShaderMaterial.new()


func _init() -> void:
	_material.shader = BLUEPRINT_SHADER


## Generates the ground for plot and builds every chunk immediately.
func build(plot: PlotData, cell_size_m: float = TerrainGenerator.DEFAULT_CELL_SIZE_M) -> void:
	set_map(TerrainGenerator.generate(plot, cell_size_m))


## Uses an existing map (e.g. one restored from a save) and builds every chunk.
func set_map(new_map: TerrainMap) -> void:
	for chunk: TerrainChunk in _chunks.values():
		chunk.free()
	_chunks.clear()
	map = new_map
	rebuild_dirty()


## Removes ground within radius_m of center_m. Emits EventBus.terrain_carved when anything was
## removed. Views update on the next frame (or call rebuild_dirty()). Returns cells removed.
func carve(center_m: Vector2, radius_m: float) -> int:
	var removed := map.carve(center_m, radius_m)
	if removed > 0:
		EventBus.terrain_carved.emit(center_m, radius_m)
	return removed


func is_solid(point_m: Vector2) -> bool:
	return map.is_solid(point_m)


## {hit: bool, position: Vector2, normal: Vector2}, all in meters. See TerrainMap.raycast.
func raycast(from_m: Vector2, to_m: Vector2) -> Dictionary:
	return map.raycast(from_m, to_m)


## Surface y in meters (+y down: smaller is higher).
func surface_height_at(x_m: float) -> float:
	return map.surface_height_at(x_m)


func battery_position_m() -> Vector2:
	return map.battery_position_m()


func target_positions_m(count: int) -> Array[Vector2]:
	return map.target_positions_m(count)


## World bounds of the terrain grid in meters.
func bounds_m() -> Rect2:
	return Rect2(map.origin_m, map.size_m())


## Redraws and re-collides every chunk changed since the last rebuild.
func rebuild_dirty() -> void:
	if map == null:
		return
	for coord in map.take_dirty_chunks():
		var chunk: TerrainChunk = _chunks.get(coord)
		if chunk == null:
			chunk = TerrainChunk.new(coord, _material)
			_chunks[coord] = chunk
			add_child(chunk)
		chunk.refresh(map)


func chunk_count() -> int:
	return _chunks.size()


func get_chunk(coord: Vector2i) -> TerrainChunk:
	return _chunks.get(coord)


func _process(_delta: float) -> void:
	if map != null and map.has_dirty_chunks():
		rebuild_dirty()
