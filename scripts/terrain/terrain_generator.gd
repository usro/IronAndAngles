class_name TerrainGenerator
extends RefCounted
## Builds a TerrainMap from a PlotData. Deterministic: the same plot fields give the same cells.
##
## Layout (meters, +y down): the battery pad is centred at x = SIDE_MARGIN_M with its ground at
## y = -height_advantage_m; the target zone is centred target_distance_m further right with its
## ground at y = 0. Both are flat. Between them, terrain_profile shapes the ground.

const DEFAULT_CELL_SIZE_M := 0.25
const SIDE_MARGIN_M := 80.0
const BATTERY_PAD_HALF_M := 8.0
const TARGET_ZONE_HALF_M := 20.0
## Distance over which noise and features fade in next to a pad.
const PAD_BLEND_M := 15.0
## Air kept above the highest ground and solid ground kept below the lowest point.
const HEADROOM_M := 12.0
const DEPTH_M := 30.0
## Bottom rows that craters never remove.
const BEDROCK_M := 2.0


static func generate(plot: PlotData, cell_size_m: float = DEFAULT_CELL_SIZE_M) -> TerrainMap:
	var battery_x := SIDE_MARGIN_M
	var target_x := battery_x + maxf(plot.target_distance_m, BATTERY_PAD_HALF_M + TARGET_ZONE_HALF_M)
	var world_w := target_x + TARGET_ZONE_HALF_M + SIDE_MARGIN_M
	var chunk_m := TerrainMap.CHUNK_CELLS * cell_size_m
	var width := ceili(world_w / chunk_m) * TerrainMap.CHUNK_CELLS

	var shape := _ProfileShape.new(plot, battery_x, target_x)
	var elevations := PackedFloat32Array()
	elevations.resize(width)
	var max_elev := -INF
	var min_elev := INF
	for x in width:
		var e := shape.elevation((x + 0.5) * cell_size_m)
		elevations[x] = e
		max_elev = maxf(max_elev, e)
		min_elev = minf(min_elev, e)

	# Elevation is up; world y is down. Align the grid top to whole cells.
	var top_y := floorf((-max_elev - HEADROOM_M) / cell_size_m) * cell_size_m
	var depth := (-min_elev + DEPTH_M) - top_y
	var height := ceili(depth / chunk_m) * TerrainMap.CHUNK_CELLS

	var map := TerrainMap.new(Vector2(0.0, top_y), width, height, cell_size_m)
	map.bedrock_row = height - ceili(BEDROCK_M / cell_size_m)
	map.battery_x_m = battery_x
	map.target_zone_min_x_m = target_x - TARGET_ZONE_HALF_M
	map.target_zone_max_x_m = target_x + TARGET_ZONE_HALF_M

	var rows := PackedInt32Array()
	rows.resize(width)
	for x in width:
		# A cell is solid when its centre is below the surface.
		rows[x] = roundi((-elevations[x] - top_y) / cell_size_m)
	map.fill_from_surface_rows(rows)
	return map


## Elevation function for one plot. Pads are exactly flat; everything else is base slope
## + profile feature + noise, faded in near the pads.
class _ProfileShape:
	var _battery_x: float
	var _target_x: float
	var _battery_elev: float
	var _profile: GameConstants.TerrainProfile
	var _gap_start: float
	var _gap_end: float
	var _noise := FastNoiseLite.new()
	var _noise_amp: float
	var _feature_h: float
	var _feature_center: float

	func _init(plot: PlotData, battery_x: float, target_x: float) -> void:
		_battery_x = battery_x
		_target_x = target_x
		_battery_elev = plot.height_advantage_m
		_profile = plot.terrain_profile
		_gap_start = battery_x + TerrainGenerator.BATTERY_PAD_HALF_M
		_gap_end = target_x - TerrainGenerator.TARGET_ZONE_HALF_M
		var gap := maxf(_gap_end - _gap_start, 1.0)
		var rng := RandomNumberGenerator.new()
		rng.seed = plot.terrain_seed
		_noise.seed = plot.terrain_seed
		_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
		_noise.fractal_octaves = 4
		_noise.frequency = 0.012
		_feature_center = 0.5
		match _profile:
			GameConstants.TerrainProfile.FLAT:
				_noise_amp = 0.8
				_feature_h = 0.0
			GameConstants.TerrainProfile.HILLS:
				_noise_amp = 6.0
				_noise.frequency = 0.018
				_feature_h = 0.0
			GameConstants.TerrainProfile.RIDGE:
				_noise_amp = 3.0
				_feature_h = clampf(gap * 0.15, 12.0, 50.0)
				_feature_center = rng.randf_range(0.4, 0.6)
			GameConstants.TerrainProfile.VALLEY:
				_noise_amp = 2.5
				_feature_h = -clampf(gap * 0.1, 8.0, 30.0)
			GameConstants.TerrainProfile.MOUNTAIN:
				_noise_amp = 8.0
				_noise.frequency = 0.02
				_feature_h = clampf(gap * 0.22, 20.0, 70.0)
				_feature_center = rng.randf_range(0.35, 0.65)

	func elevation(x: float) -> float:
		var base: float
		var feature := 0.0
		if x <= _gap_start:
			base = _battery_elev
		elif x >= _gap_end:
			base = 0.0
		else:
			var t := (x - _gap_start) / (_gap_end - _gap_start)
			base = lerpf(_battery_elev, 0.0, smoothstep(0.0, 1.0, t))
			feature = _feature(t)
		return base + feature + _noise.get_noise_1d(x) * _noise_amp * _pad_fade(x)

	func _feature(t: float) -> float:
		match _profile:
			GameConstants.TerrainProfile.RIDGE:
				return _feature_h * exp(-pow((t - _feature_center) / 0.12, 2.0)) * sin(PI * t)
			GameConstants.TerrainProfile.VALLEY:
				return _feature_h * pow(sin(PI * t), 2.0)
			GameConstants.TerrainProfile.MOUNTAIN:
				return _feature_h * exp(-pow((t - _feature_center) / 0.18, 2.0)) * sin(PI * t)
		return 0.0

	## 0 on a pad, rising smoothly to 1 within PAD_BLEND_M of its edge.
	func _pad_fade(x: float) -> float:
		var d_battery := absf(x - _battery_x) - TerrainGenerator.BATTERY_PAD_HALF_M
		var d_target := absf(x - _target_x) - TerrainGenerator.TARGET_ZONE_HALF_M
		var d := minf(d_battery, d_target)
		return smoothstep(0.0, TerrainGenerator.PAD_BLEND_M, d)
