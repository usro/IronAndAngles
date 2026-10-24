extends TestCase
## Destructible terrain: generation, carving, queries and performance.

const PERF_CARVES := 200
## Generous budgets (debug build, headless) so slow CI machines don't flake.
const PERF_CARVE_BUDGET_MS := 150
const PERF_REBUILD_BUDGET_MS := 500
## Carving and rebuilding after every single crater (one impact per frame).
const PERF_PER_IMPACT_BUDGET_MS := 1500


func _plot(profile: GameConstants.TerrainProfile, seed_value: int = 1337) -> PlotData:
	var p := PlotData.new()
	p.id = &"test_plot"
	p.terrain_profile = profile
	p.terrain_seed = seed_value
	p.height_advantage_m = 25.0
	p.target_distance_m = 280.0
	return p


func test_same_seed_same_terrain() -> void:
	for profile in GameConstants.TerrainProfile.values():
		var a := TerrainGenerator.generate(_plot(profile, 99))
		var b := TerrainGenerator.generate(_plot(profile, 99))
		assert_eq(a.cells_hash(), b.cells_hash(), "profile %d cells" % profile)
		assert_eq(a.width, b.width, "width")
		assert_eq(a.height, b.height, "height")
		for x in [10.0, 150.0, 222.5, 300.0]:
			assert_eq(a.surface_height_at(x), b.surface_height_at(x), "profile %d surface at %f" % [profile, x])


func test_different_seed_different_terrain() -> void:
	var a := TerrainGenerator.generate(_plot(GameConstants.TerrainProfile.HILLS, 1))
	var b := TerrainGenerator.generate(_plot(GameConstants.TerrainProfile.HILLS, 2))
	assert_true(a.cells_hash() != b.cells_hash(), "seeds 1 and 2 should differ")


func test_layout_spots_follow_plot() -> void:
	for profile in GameConstants.TerrainProfile.values():
		var plot := _plot(profile)
		var map := TerrainGenerator.generate(plot)
		var battery := map.battery_position_m()
		assert_near(battery.y, -plot.height_advantage_m, 0.26, "profile %d battery ground" % profile)
		var zone := map.target_zone_center_m()
		assert_near(zone.x - battery.x, plot.target_distance_m, 0.01, "target distance")
		assert_near(zone.y, 0.0, 0.26, "profile %d target ground" % profile)
		# Pads are flat.
		for dx in [-6.0, -3.0, 3.0, 6.0]:
			assert_near(map.surface_height_at(battery.x + dx), battery.y, 0.01, "battery pad flat")
		for p in map.target_positions_m(3):
			assert_near(p.y, zone.y, 0.01, "target spot flat")
			assert_true(p.x >= map.target_zone_min_x_m and p.x <= map.target_zone_max_x_m, "target in zone")
		# Spots sit on the surface: solid just below, air just above.
		assert_true(map.is_solid(battery + Vector2(0, 0.2)), "solid under battery")
		assert_false(map.is_solid(battery - Vector2(0, 0.2)), "air over battery")


func test_profiles_shape_the_gap() -> void:
	var flat := TerrainGenerator.generate(_plot(GameConstants.TerrainProfile.FLAT))
	var ridge := TerrainGenerator.generate(_plot(GameConstants.TerrainProfile.RIDGE))
	var valley := TerrainGenerator.generate(_plot(GameConstants.TerrainProfile.VALLEY))
	var mid := (flat.battery_x_m + flat.target_zone_center_m().x) * 0.5
	# +y is down: the ridge is higher (smaller y) than flat ground mid-way, the valley lower.
	assert_true(_min_surface(ridge, mid - 40, mid + 40) < _min_surface(flat, mid - 40, mid + 40) - 5.0, "ridge rises")
	assert_true(valley.surface_height_at(mid) > flat.surface_height_at(mid) + 4.0, "valley dips")


func test_carve_removes_inside_keeps_outside() -> void:
	var map := TerrainGenerator.generate(_plot(GameConstants.TerrainProfile.FLAT))
	var center := map.target_zone_center_m() + Vector2(0, 1.0)
	const R := 2.5
	var before := map.solid_cell_count()
	var removed := map.carve(center, R)
	assert_true(removed > 0, "removed cells")
	assert_eq(map.solid_cell_count(), before - removed, "solid count drops by removed")
	for i in 16:
		var dir := Vector2.RIGHT.rotated(TAU * i / 16.0)
		assert_false(map.is_solid(center + dir * (R - 0.3)), "inside at angle %d" % i)
		var outside := center + dir * (R + 0.5)
		if outside.y > 0.3:  # below the original flat surface, so it was solid before
			assert_true(map.is_solid(outside), "outside at angle %d" % i)
	assert_false(map.is_solid(center), "centre")
	# Surface cache follows the crater: the crater floor is the new surface.
	assert_near(map.surface_height_at(center.x), center.y + R, 0.3, "surface drops into crater")


func test_carve_never_removes_bedrock() -> void:
	var map := TerrainGenerator.generate(_plot(GameConstants.TerrainProfile.FLAT))
	var bottom_y := map.origin_m.y + map.height * map.cell_size_m
	var p := Vector2(map.battery_x_m, bottom_y - 0.5)
	map.carve(p, 5.0)
	assert_true(map.is_solid(p), "bedrock stays")
	assert_true(map.is_solid(Vector2(map.battery_x_m, bottom_y + 10.0)), "below the grid is solid")


func test_carve_in_air_does_nothing() -> void:
	var map := TerrainGenerator.generate(_plot(GameConstants.TerrainProfile.FLAT))
	map.take_dirty_chunks()
	var hash_before := map.cells_hash()
	assert_eq(map.carve(map.battery_position_m() - Vector2(0, 8.0), 2.0), 0)
	assert_eq(map.cells_hash(), hash_before, "unchanged")
	assert_false(map.has_dirty_chunks(), "nothing dirty")


func test_raycast_hits_flat_surface_with_up_normal() -> void:
	var map := TerrainGenerator.generate(_plot(GameConstants.TerrainProfile.FLAT))
	var x := map.target_zone_center_m().x
	var surface := map.surface_height_at(x)
	var r := map.raycast(Vector2(x, surface - 30.0), Vector2(x, surface + 30.0))
	assert_true(r.hit, "hit")
	assert_near(r.position.y, surface, map.cell_size_m, "hit at surface")
	assert_near(r.position.x, x, 1e-4, "x unchanged on vertical ray")
	assert_true(r.normal.dot(Vector2.UP) > 0.98, "normal points up, got %s" % r.normal)
	# Diagonal ray onto the same flat pad.
	var d := map.raycast(Vector2(x - 10.0, surface - 10.0), Vector2(x + 10.0, surface + 10.0))
	assert_true(d.hit, "diagonal hit")
	assert_near(d.position.y, surface, map.cell_size_m, "diagonal hit at surface")
	assert_near(d.position.x, x, map.cell_size_m * 1.5, "diagonal hit near x")
	assert_true(d.normal.dot(Vector2.UP) > 0.95, "diagonal normal up, got %s" % d.normal)


func test_raycast_misses_and_edges() -> void:
	var map := TerrainGenerator.generate(_plot(GameConstants.TerrainProfile.HILLS))
	var top := map.origin_m.y
	var miss := map.raycast(Vector2(10, top - 50), Vector2(300, top - 40))
	assert_false(miss.hit, "ray through sky misses")
	# Starting inside the ground is an immediate hit at the start.
	var inside := map.battery_position_m() + Vector2(0, 2.0)
	var r := map.raycast(inside, inside + Vector2(5, -5))
	assert_true(r.hit, "inside hit")
	assert_eq(r.position, inside, "inside hit position")
	# Off the side of the map, a falling shell still lands on the bedrock plane.
	var bottom_y := map.origin_m.y + map.height * map.cell_size_m
	var off := map.raycast(Vector2(-50, 0), Vector2(-50, bottom_y + 20.0))
	assert_true(off.hit, "off-map hit")
	assert_near(off.position.y, bottom_y, 1e-3, "lands on bottom plane")
	assert_eq(off.normal, Vector2.UP, "bottom plane normal")


func test_raycast_normal_follows_crater_wall() -> void:
	var map := TerrainGenerator.generate(_plot(GameConstants.TerrainProfile.FLAT))
	var zone := map.target_zone_center_m()
	const R := 4.0
	var center := zone + Vector2(0, 1.0)
	map.carve(center, R)
	# Straight down the middle: hits the crater floor, normal up.
	var down := map.raycast(Vector2(center.x, zone.y - 20.0), Vector2(center.x, zone.y + 20.0))
	assert_true(down.hit, "floor hit")
	assert_near(down.position.y, center.y + R, 0.3, "floor depth")
	assert_true(down.normal.dot(Vector2.UP) > 0.9, "floor normal up, got %s" % down.normal)
	# Horizontally from inside the crater toward the right wall: normal points back left.
	var side := map.raycast(center, center + Vector2(10.0, 0))
	assert_true(side.hit, "wall hit")
	assert_near(side.position.x, center.x + R, 0.3, "wall distance")
	assert_true(side.normal.dot(Vector2.LEFT) > 0.85, "wall normal faces centre, got %s" % side.normal)


func test_terrain_node_carve_emits_and_rebuilds() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var terrain := Terrain.new()
	tree.root.add_child(terrain)
	terrain.build(_plot(GameConstants.TerrainProfile.FLAT))
	var grid := terrain.map.chunk_grid_size()
	assert_eq(terrain.chunk_count(), grid.x * grid.y, "all chunks built")

	var seen := []
	var cb := func(pos: Vector2, radius: float): seen.append([pos, radius])
	EventBus.terrain_carved.connect(cb)
	var center := terrain.map.target_zone_center_m()
	terrain.carve(center, 3.0)
	terrain.carve(center + Vector2(0, -50.0), 3.0)  # in the air: no signal
	EventBus.terrain_carved.disconnect(cb)
	assert_eq(seen.size(), 1, "one signal")
	if seen.size() == 1:
		assert_eq(seen[0], [center, 3.0], "signal args")

	# The surface chunk gets a collision outline that dips into the crater.
	assert_true(terrain.map.has_dirty_chunks(), "dirty after carve")
	terrain.rebuild_dirty()
	assert_false(terrain.map.has_dirty_chunks(), "clean after rebuild")
	var coord := terrain.map.world_to_cell(center) / TerrainMap.CHUNK_CELLS
	var chunk := terrain.get_chunk(coord)
	assert_not_null(chunk, "chunk at crater")
	if chunk:
		assert_true(chunk.segment_count() > 0, "collision segments")
	terrain.free()


func test_outline_is_closed_across_chunks() -> void:
	var map := TerrainGenerator.generate(_plot(GameConstants.TerrainProfile.HILLS))
	var zone := map.target_zone_center_m()
	map.carve(zone + Vector2(0, 10.0), 2.0)  # fully underground: a cave
	map.carve(zone + Vector2(-12.0, 0.5), 3.0)  # an open crater
	var segs := PackedVector2Array()
	var grid := map.chunk_grid_size()
	for cy in grid.y:
		for cx in grid.x:
			var c := Vector2i(cx, cy)
			segs.append_array(map.chunk_segments_m(c, map.chunk_bytes_with_border(c)))
	assert_true(segs.size() > 0, "outline exists")
	# Every endpoint is shared by exactly two segments, except where the surface meets the map sides.
	var counts := {}
	for p in segs:
		var key := Vector2i((p * 1000.0).round())
		counts[key] = counts.get(key, 0) + 1
	var side_margin := map.cell_size_m * 2.0
	for key: Vector2i in counts:
		var x := key.x / 1000.0
		if x < map.origin_m.x + side_margin or x > map.origin_m.x + map.size_m().x - side_margin:
			continue
		assert_eq(counts[key], 2, "endpoint %s degree" % key)
	# The cave is outlined: some segment endpoint sits on its rim.
	var rim := zone + Vector2(0, 10.0) + Vector2(2.0, 0)
	var near_rim := false
	for p in segs:
		near_rim = near_rim or p.distance_to(rim) < map.cell_size_m * 1.5
	assert_true(near_rim, "cave rim outlined")


func test_perf_many_carves() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var terrain := Terrain.new()
	tree.root.add_child(terrain)
	terrain.build(_plot(GameConstants.TerrainProfile.HILLS))
	var map := terrain.map
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var xs := []
	for i in PERF_CARVES:
		xs.append(rng.randf_range(map.battery_x_m, map.target_zone_max_x_m))
	var t0 := Time.get_ticks_usec()
	for i in PERF_CARVES:
		var x: float = xs[i]
		terrain.carve(Vector2(x, map.surface_height_at(x)), rng.randf_range(1.5, 4.0))
	var carve_ms := (Time.get_ticks_usec() - t0) / 1000.0
	var t1 := Time.get_ticks_usec()
	terrain.rebuild_dirty()
	var rebuild_ms := (Time.get_ticks_usec() - t1) / 1000.0
	# And a typical frame's worth of ballistics queries afterwards.
	var t2 := Time.get_ticks_usec()
	for i in 1000:
		var x := rng.randf_range(map.battery_x_m, map.target_zone_max_x_m)
		map.raycast(Vector2(x, map.origin_m.y), Vector2(x + 3.0, map.origin_m.y + map.size_m().y))
	var ray_ms := (Time.get_ticks_usec() - t2) / 1000.0
	# Worst realistic case: redraw and re-collide after each impact.
	var t3 := Time.get_ticks_usec()
	for i in PERF_CARVES:
		var x := rng.randf_range(map.battery_x_m, map.target_zone_max_x_m)
		terrain.carve(Vector2(x, map.surface_height_at(x)), rng.randf_range(1.5, 4.0))
		terrain.rebuild_dirty()
	var per_impact_ms := (Time.get_ticks_usec() - t3) / 1000.0
	print("     terrain perf: %d carves %.1f ms, rebuild %.1f ms, 1000 raycasts %.1f ms, %d carve+rebuilds %.1f ms" % [
			PERF_CARVES, carve_ms, rebuild_ms, ray_ms, PERF_CARVES, per_impact_ms])
	assert_true(per_impact_ms < PERF_PER_IMPACT_BUDGET_MS, "carve+rebuild after every impact took %.1f ms in total" % per_impact_ms)
	assert_true(carve_ms < PERF_CARVE_BUDGET_MS, "carves took %.1f ms" % carve_ms)
	assert_true(rebuild_ms < PERF_REBUILD_BUDGET_MS, "rebuild took %.1f ms" % rebuild_ms)
	assert_true(ray_ms < 1000.0, "raycasts took %.1f ms" % ray_ms)
	terrain.free()


func _min_surface(map: TerrainMap, x0: float, x1: float) -> float:
	var best := INF
	var x := x0
	while x <= x1:
		best = minf(best, map.surface_height_at(x))
		x += 1.0
	return best
