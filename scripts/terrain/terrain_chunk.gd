class_name TerrainChunk
extends Node2D
## View of one TerrainMap chunk: a filtered L8 texture drawn with the blueprint shader, and a
## StaticBody2D whose segment shape follows the marching-squares outline. Positioned in pixels.

var coord: Vector2i
var _sprite := Sprite2D.new()
var _body := StaticBody2D.new()
var _shape := CollisionShape2D.new()
var _texture: ImageTexture


func _init(p_coord: Vector2i, material_: Material) -> void:
	coord = p_coord
	name = "Chunk_%d_%d" % [coord.x, coord.y]
	_sprite.centered = false
	_sprite.material = material_
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	# The texture carries a one-cell border; show only the interior but let filtering bleed into it.
	_sprite.region_enabled = true
	_sprite.region_rect = Rect2(1, 1, TerrainMap.CHUNK_CELLS, TerrainMap.CHUNK_CELLS)
	add_child(_sprite)
	_body.add_child(_shape)
	add_child(_body)


## Redraws and re-collides this chunk from the map.
func refresh(map: TerrainMap) -> void:
	var px_per_m := GameConstants.PIXELS_PER_METER
	var origin_px := map.chunk_origin_m(coord) * px_per_m
	position = origin_px
	_sprite.scale = Vector2.ONE * map.cell_size_m * px_per_m

	var bytes := map.chunk_bytes_with_border(coord)
	var side := TerrainMap.CHUNK_CELLS + 2
	var all_air := not bytes.has(TerrainMap.SOLID)
	_sprite.visible = not all_air
	if not all_air:
		var img := Image.create_from_data(side, side, false, Image.FORMAT_L8, bytes)
		if _texture == null:
			_texture = ImageTexture.create_from_image(img)
			_sprite.texture = _texture
		else:
			_texture.update(img)

	var segments := map.chunk_segments_m(coord, bytes)
	if segments.is_empty():
		_shape.shape = null
		_shape.disabled = true
		return
	for i in segments.size():
		segments[i] = segments[i] * px_per_m - origin_px
	var concave := ConcavePolygonShape2D.new()
	concave.segments = segments
	_shape.shape = concave
	_shape.disabled = false


func segment_count() -> int:
	var s := _shape.shape as ConcavePolygonShape2D
	return 0 if s == null else s.segments.size() / 2
