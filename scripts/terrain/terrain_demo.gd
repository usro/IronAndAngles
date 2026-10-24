extends Node2D
## Manual check for destructible terrain (scenes/battle/terrain_demo.tscn).
## Left click: carve. Wheel: crater size. Right click: raycast from the battery to the mouse.
## 1-5: terrain profile. R: new seed. Space: 50 random impacts.

const BACKGROUND := Color(0.05, 0.13, 0.26)
const MARK_COLOR := Color(1.0, 0.85, 0.3)

var _plot := PlotData.new()
var _terrain := Terrain.new()
var _camera := Camera2D.new()
var _info := Label.new()
var _radius_m := 3.0
var _last_ray: Dictionary = {}
var _last_ray_end_m := Vector2.ZERO
var _last_action := ""


func _ready() -> void:
	RenderingServer.set_default_clear_color(BACKGROUND)
	var source := DataRegistry.get_plot(&"river_ridge")
	if source:
		_plot = source.duplicate()
	add_child(_terrain)
	add_child(_camera)
	var layer := CanvasLayer.new()
	add_child(layer)
	_info.position = Vector2(12, 8)
	layer.add_child(_info)
	_rebuild()


func _rebuild() -> void:
	var t0 := Time.get_ticks_usec()
	_terrain.build(_plot)
	_last_action = "built in %.1f ms" % ((Time.get_ticks_usec() - t0) / 1000.0)
	_last_ray = {}
	_fit_camera()
	_refresh()


func _fit_camera() -> void:
	var b := _terrain.bounds_m()
	var rect := Rect2(GameConstants.meters_to_pixels(b.position), GameConstants.meters_to_pixels(b.size))
	rect = rect.grow_individual(0, 200, 0, 0)  # some sky
	var view := get_viewport_rect().size
	var z := minf(view.x / rect.size.x, view.y / rect.size.y)
	_camera.zoom = Vector2(z, z)
	_camera.position = rect.get_center()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var mouse_m := GameConstants.pixels_to_meters(get_global_mouse_position())
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				var t0 := Time.get_ticks_usec()
				var removed := _terrain.carve(mouse_m, _radius_m)
				_terrain.rebuild_dirty()
				_last_action = "carve %d cells, %.2f ms incl. rebuild" % [removed, (Time.get_ticks_usec() - t0) / 1000.0]
			MOUSE_BUTTON_RIGHT:
				_last_ray_end_m = mouse_m
				_last_ray = _terrain.raycast(_terrain.battery_position_m() + Vector2(0, -1.0), mouse_m)
				_last_action = "ray %s" % (str(_last_ray.position) if _last_ray.hit else "miss")
			MOUSE_BUTTON_WHEEL_UP:
				_radius_m = minf(_radius_m + 0.5, 15.0)
			MOUSE_BUTTON_WHEEL_DOWN:
				_radius_m = maxf(_radius_m - 0.5, 0.5)
		_refresh()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode >= KEY_1 and event.keycode <= KEY_5:
			_plot.terrain_profile = event.keycode - KEY_1 as GameConstants.TerrainProfile
			_rebuild()
		elif event.keycode == KEY_R:
			_plot.terrain_seed += 1
			_rebuild()
		elif event.keycode == KEY_SPACE:
			_barrage(50)


func _barrage(count: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = Time.get_ticks_usec()
	var map := _terrain.map
	var t0 := Time.get_ticks_usec()
	for i in count:
		var x := rng.randf_range(map.battery_x_m + 20.0, map.target_zone_max_x_m)
		_terrain.carve(Vector2(x, map.surface_height_at(x)), rng.randf_range(1.5, 5.0))
	_terrain.rebuild_dirty()
	_last_action = "%d impacts in %.1f ms" % [count, (Time.get_ticks_usec() - t0) / 1000.0]
	_refresh()


func _refresh() -> void:
	_info.text = "%s  seed %d  |  crater r=%.1f m  |  %s\n%s" % [
		GameConstants.TerrainProfile.keys()[_plot.terrain_profile], _plot.terrain_seed, _radius_m, _last_action,
		"LMB carve   wheel size   RMB raycast from battery   1-5 profile   R reseed   Space barrage"]
	queue_redraw()


func _draw() -> void:
	if _terrain.map == null:
		return
	var px := GameConstants.PIXELS_PER_METER
	var width := 2.0 / _camera.zoom.x
	var battery := _terrain.battery_position_m() * px
	draw_rect(Rect2(battery + Vector2(-12, -16), Vector2(24, 16)), MARK_COLOR, false, width)
	for p in _terrain.target_positions_m(3):
		draw_circle(p * px + Vector2(0, -6), 6, MARK_COLOR, false, width)
	var map := _terrain.map
	var zone_y := map.target_zone_center_m().y * px + 4.0
	draw_line(Vector2(map.target_zone_min_x_m * px, zone_y), Vector2(map.target_zone_max_x_m * px, zone_y), MARK_COLOR, width)
	if not _last_ray.is_empty():
		var start := (_terrain.battery_position_m() + Vector2(0, -1.0)) * px
		var end: Vector2 = _last_ray.position * px if _last_ray.hit else _last_ray_end_m * px
		draw_line(start, end, Color.WHITE, width)
		if _last_ray.hit:
			draw_circle(end, 4, Color.RED)
			draw_line(end, end + _last_ray.normal * 40.0, Color.RED, width)


func _process(_delta: float) -> void:
	# Battery and target markers follow craters.
	queue_redraw()
