extends TestCase
## Checks that the wave 1 systems fit together: ballistics flying over generated terrain.


func _plot(profile: GameConstants.TerrainProfile) -> PlotData:
	var plot := PlotData.new()
	plot.id = &"integration_plot"
	plot.terrain_profile = profile
	plot.terrain_seed = 99
	plot.height_advantage_m = 10.0
	plot.target_distance_m = 150.0
	return plot


func test_aimed_shot_lands_near_target_on_real_terrain() -> void:
	var map := TerrainGenerator.generate(_plot(GameConstants.TerrainProfile.FLAT))
	var weapon := DataRegistry.get_weapon(&"trebuchet")
	var ammo := DataRegistry.get_ammo(&"stone_ball")
	var weather := WeatherState.new()
	var origin := map.battery_position_m() + Vector2(0, -1.0)
	var target := map.target_zone_center_m()

	var aim := AimSolver.solve(weapon, ammo, origin, target, weather)
	assert_true(aim.ok, "solver reaches a 150 m target")
	var params := ShotParams.create(weapon, ammo, aim.elevation_deg, aim.charge, origin, aim.facing,
			weather, RandomNumberGenerator.new())
	var traj := Ballistics.predict(params, map.raycast)

	assert_true(traj.has_impact(), "shell hits the ground")
	assert_true(traj.time_of_flight > 1.0, "shell actually flies (a miss result must not count as a hit)")
	# Bounces scatter a stone ball, so only check the first contact lands in the target area.
	var first: Vector2 = traj.bounces[0].position if not traj.bounces.is_empty() else traj.impact_point_m()
	assert_near(first.x, target.x, 10.0, "first contact x")


func test_impact_carves_terrain() -> void:
	var map := TerrainGenerator.generate(_plot(GameConstants.TerrainProfile.HILLS))
	var target := map.target_zone_center_m()
	var probe := target + Vector2(0, 0.5)
	assert_true(map.is_solid(probe), "ground under the target zone")
	map.carve(target, 2.0)
	assert_false(map.is_solid(probe), "crater removed the ground")
