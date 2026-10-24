extends TestCase
## Ballistics: physics against closed forms, per-era behaviour, determinism and the stepper.

const DT := GameConstants.PHYSICS_STEP
var ground := Ballistics.flat_ground(0.0)


func _weapon(v_min: float = 20.0, v_max: float = 60.0, spread: float = 0.0) -> WeaponData:
	var w := WeaponData.new()
	w.elevation_min_deg = -10.0
	w.elevation_max_deg = 90.0
	w.muzzle_velocity_min = v_min
	w.muzzle_velocity_max = v_max
	w.spread_deg = spread
	return w


func _ammo(drag: float = 0.0) -> AmmoData:
	var a := AmmoData.new()
	a.mass_kg = 10.0
	a.drag_coefficient = drag
	a.cross_section_m2 = 0.03
	return a


func _weather(wind: float = 0.0, gust: float = 0.0) -> WeatherState:
	var w := WeatherState.new()
	w.wind_speed = wind
	w.gust_strength = gust
	return w


func _rng(seed_value: int = 1234) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	return r


func _shoot(weapon: WeaponData, ammo: AmmoData, elev: float, charge: float, weather: WeatherState,
		facing: int = 1, seed_value: int = 1234) -> Trajectory:
	return Ballistics.simulate(weapon, ammo, elev, charge, Vector2.ZERO, facing, weather,
		_rng(seed_value), ground)


func test_no_drag_matches_closed_form_parabola() -> void:
	var v := 50.0
	var theta := deg_to_rad(40.0)
	var g := GameConstants.STANDARD_GRAVITY
	var t := _shoot(_weapon(v, v), _ammo(0.0), 40.0, 1.0, _weather())
	assert_true(t.has_impact(), "lands")
	assert_near(t.end_point_m.x, v * v * sin(2.0 * theta) / g, 0.01, "range R = v²·sin2θ/g")
	assert_near(t.time_of_flight, 2.0 * v * sin(theta) / g, 0.001, "time of flight 2v·sinθ/g")
	var worst := 0.0
	for i in t.points.size() - 1:
		var s := t.times[i]
		var expected := Vector2(v * cos(theta) * s, -v * sin(theta) * s + 0.5 * g * s * s)
		worst = maxf(worst, t.points[i].distance_to(expected))
	assert_true(worst < 1e-3, "every sample on the parabola (worst %f m)" % worst)
	assert_near(t.apex_m().y, -pow(v * sin(theta), 2) / (2.0 * g), 0.01, "apex height")


func test_drag_shortens_range() -> void:
	var vacuum := _shoot(_weapon(), _ammo(0.0), 45.0, 1.0, _weather())
	var air := _shoot(_weapon(), _ammo(0.47), 45.0, 1.0, _weather())
	assert_true(air.end_point_m.x < vacuum.end_point_m.x - 1.0,
		"drag %f < vacuum %f" % [air.end_point_m.x, vacuum.end_point_m.x])


func test_thin_air_at_altitude_flies_further() -> void:
	var low := _shoot(_weapon(), _ammo(0.47), 45.0, 1.0, _weather())
	# weather.air_density applies at reference_y_m (y = 0); this battery sits 4 km higher.
	var high_origin := Vector2(0.0, -4000.0)
	var params := ShotParams.create(_weapon(), _ammo(0.47), 45.0, 1.0, high_origin, 1, _weather(), _rng())
	params.reference_y_m = 0.0
	var high := Ballistics.simulate_shot(params, Ballistics.flat_ground(high_origin.y))
	assert_true(high.end_point_m.x > low.end_point_m.x + 0.5,
		"altitude %f > sea level %f" % [high.end_point_m.x, low.end_point_m.x])


func test_wind_drifts_downwind_for_both_facings() -> void:
	for facing in [1, -1]:
		var calm := _shoot(_weapon(), _ammo(0.47), 50.0, 1.0, _weather(0.0), facing)
		var east := _shoot(_weapon(), _ammo(0.47), 50.0, 1.0, _weather(10.0), facing)
		var west := _shoot(_weapon(), _ammo(0.47), 50.0, 1.0, _weather(-10.0), facing)
		assert_true(east.end_point_m.x > calm.end_point_m.x + 0.5, "+x wind pushes +x (facing %d)" % facing)
		assert_true(west.end_point_m.x < calm.end_point_m.x - 0.5, "-x wind pushes -x (facing %d)" % facing)


func test_wind_sensitivity_scales_drift() -> void:
	var calm := _shoot(_weapon(), _ammo(0.47), 50.0, 1.0, _weather(0.0))
	var normal := _shoot(_weapon(), _ammo(0.47), 50.0, 1.0, _weather(8.0))
	var light := _ammo(0.47)
	light.wind_sensitivity = 3.0
	var sensitive := _shoot(_weapon(), light, 50.0, 1.0, _weather(8.0))
	assert_true(sensitive.end_point_m.x - calm.end_point_m.x > normal.end_point_m.x - calm.end_point_m.x,
		"higher sensitivity drifts more")


func test_same_seed_gives_identical_trajectory() -> void:
	var ammo := _ammo(0.47)
	ammo.bounce_restitution = 0.5
	ammo.bounce_randomness_deg = 15.0
	ammo.max_bounces = 3
	var weapon := _weapon(20.0, 60.0, 2.0)
	var a := _shoot(weapon, ammo, 45.0, 0.8, _weather(4.0, 3.0), 1, 99)
	var b := _shoot(weapon, ammo, 45.0, 0.8, _weather(4.0, 3.0), 1, 99)
	var c := _shoot(weapon, ammo, 45.0, 0.8, _weather(4.0, 3.0), 1, 100)
	assert_eq(a.points, b.points, "points")
	assert_eq(a.times, b.times, "times")
	assert_eq(a.bounces, b.bounces, "bounces")
	assert_eq(a.end_point_m, b.end_point_m, "end point")
	assert_true(a.end_point_m != c.end_point_m, "a different seed gives a different shot")


func test_spread_stays_within_weapon_spread() -> void:
	var weapon := _weapon(20.0, 60.0, 3.0)
	for s in 50:
		var t := _shoot(weapon, _ammo(), 45.0, 1.0, _weather(), 1, s)
		assert_true(absf(t.launch_elevation_deg - 45.0) <= 3.0 + 1e-9, "spread bounded")


func test_stepper_matches_simulate_with_uneven_frames() -> void:
	var ammo := _ammo(0.47)
	ammo.bounce_restitution = 0.4
	ammo.bounce_randomness_deg = 10.0
	ammo.max_bounces = 2
	var weapon := _weapon(20.0, 60.0, 1.5)
	var full := _shoot(weapon, ammo, 55.0, 0.7, _weather(5.0, 2.0), 1, 7)
	var params := ShotParams.create(weapon, ammo, 55.0, 0.7, Vector2.ZERO, 1, _weather(5.0, 2.0), _rng(7))
	var flight := Ballistics.launch(params, ground)
	var frames := [0.016, 0.033, 0.007, 0.05, 0.016]
	var types: Array[StringName] = []
	var i := 0
	while not flight.is_settled() and i < 100000:
		for ev in flight.advance(frames[i % frames.size()]):
			types.append(ev.type)
		i += 1
	assert_eq(flight.trajectory.points, full.points, "same points")
	assert_eq(flight.trajectory.end_point_m, full.end_point_m, "same end")
	assert_eq(types, [&"bounce", &"bounce", &"impact"] as Array[StringName], "event order")


func test_bounce_count_respects_max_bounces() -> void:
	for max_b in [0, 1, 3]:
		var ammo := _ammo(0.0)
		ammo.bounce_restitution = 0.6
		ammo.max_bounces = max_b
		var t := _shoot(_weapon(), ammo, 45.0, 1.0, _weather())
		assert_eq(t.bounces.size(), max_b, "bounces with max_bounces=%d" % max_b)
		assert_true(t.has_impact(), "ends in an impact")


func test_no_restitution_means_no_bounce() -> void:
	var ammo := _ammo(0.0)
	ammo.max_bounces = 3
	var t := _shoot(_weapon(), ammo, 45.0, 1.0, _weather())
	assert_eq(t.bounces.size(), 0, "sticks")


func test_bounce_loses_speed_and_leaves_the_ground() -> void:
	var ammo := _ammo(0.0)
	ammo.bounce_restitution = 0.5
	ammo.bounce_randomness_deg = 20.0
	ammo.max_bounces = 1
	for s in 20:
		var t := _shoot(_weapon(), ammo, 45.0, 1.0, _weather(), 1, s)
		var b: Dictionary = t.bounces[0]
		var v_in: Vector2 = b.velocity_in
		var v_out: Vector2 = b.velocity_out
		assert_true(v_out.length() < v_in.length(), "slower after bounce")
		assert_true(v_out.y < 0.0, "goes back up")
		assert_true(t.end_point_m.x > b.position.x, "keeps travelling forward")


func test_bounce_deflection_is_seeded() -> void:
	var ammo := _ammo(0.0)
	ammo.bounce_restitution = 0.5
	ammo.bounce_randomness_deg = 20.0
	ammo.max_bounces = 1
	var ends := {}
	for s in 5:
		ends[_shoot(_weapon(), ammo, 45.0, 1.0, _weather(), 1, s).end_point_m] = true
	assert_true(ends.size() > 1, "different seeds bounce differently")


func test_rocket_thrust_extends_range_and_accelerates() -> void:
	var shell := _ammo(0.3)
	var rocket := _ammo(0.3)
	rocket.thrust_n = 2000.0
	rocket.burn_time = 1.5
	var plain := _shoot(_weapon(), shell, 45.0, 0.2, _weather())
	var boosted := _shoot(_weapon(), rocket, 45.0, 0.2, _weather())
	assert_true(boosted.end_point_m.x > plain.end_point_m.x * 1.5, "thrust extends range")
	var launch_speed := boosted.launch_velocity_m.length()
	var at_burnout := boosted.times.bsearch(1.5)
	var v_burnout := (boosted.points[at_burnout] - boosted.points[at_burnout - 1]).length() / DT
	assert_true(v_burnout > launch_speed + 100.0, "faster at burnout (%f vs %f)" % [v_burnout, launch_speed])


func test_rocket_thrust_stops_after_burn_time() -> void:
	# After burnout a drag-free rocket is a plain projectile: vertical acceleration is g.
	var rocket := _ammo(0.0)
	rocket.thrust_n = 500.0
	rocket.burn_time = 0.5
	var t := _shoot(_weapon(), rocket, 60.0, 0.5, _weather())
	# Second difference over k steps (points are 32-bit, so a single step is too noisy).
	var k := 24
	var i := t.times.bsearch(1.0)
	var ay := (t.points[i + 2 * k].y - 2.0 * t.points[i + k].y + t.points[i].y) / pow(k * DT, 2)
	var ax := (t.points[i + 2 * k].x - 2.0 * t.points[i + k].x + t.points[i].x) / pow(k * DT, 2)
	assert_near(ay, GameConstants.STANDARD_GRAVITY, 0.01, "only gravity after burnout")
	assert_near(ax, 0.0, 0.01, "no horizontal thrust after burnout")


func test_railgun_ammo_ignores_wind_and_gusts() -> void:
	var slug := _ammo(0.2)
	slug.wind_sensitivity = 0.0
	var weapon := _weapon(800.0, 1200.0)
	var calm := _shoot(weapon, slug, 5.0, 1.0, _weather(0.0, 0.0))
	var storm := _shoot(weapon, slug, 5.0, 1.0, _weather(25.0, 15.0))
	assert_eq(storm.end_point_m, calm.end_point_m, "zero wind drift")
	assert_near(calm.launch_velocity_m.length(), 1200.0, 0.01, "railgun muzzle velocity")


func test_guided_shell_homes_on_designated_point() -> void:
	var ammo := _ammo(0.3)
	ammo.guided = true
	ammo.guidance_turn_rate_deg = 25.0
	ammo.guidance_arm_time = 1.0
	var target := Vector2(180.0, 0.0)
	var params := ShotParams.create(_weapon(), ammo, 45.0, 1.0, Vector2.ZERO, 1, _weather(6.0), _rng())
	var unguided := Ballistics.simulate_shot(params, ground)
	params = params.copy()
	params.rng = _rng()
	params.guidance_target_m = target
	var guided := Ballistics.simulate_shot(params, ground)
	var miss_unguided := absf(unguided.end_point_m.x - target.x)
	var miss_guided := absf(guided.end_point_m.x - target.x)
	assert_true(miss_unguided > 20.0, "ballistic shot misses (%f)" % miss_unguided)
	assert_true(miss_guided < 2.0, "guided shot hits (%f)" % miss_guided)


func test_guided_without_designation_flies_ballistic() -> void:
	var plain := _ammo(0.3)
	var guided := _ammo(0.3)
	guided.guided = true
	var a := _shoot(_weapon(), plain, 45.0, 1.0, _weather())
	var b := _shoot(_weapon(), guided, 45.0, 1.0, _weather())
	assert_eq(b.end_point_m, a.end_point_m, "same as unguided")


func test_shrapnel_airburst_spawns_fragments() -> void:
	var ammo := _ammo(0.3)
	ammo.fragment_count = 12
	ammo.fuse_time = 2.0
	var t := _shoot(_weapon(), ammo, 45.0, 1.0, _weather())
	assert_eq(t.end_reason, Trajectory.EndReason.AIRBURST, "bursts in the air")
	assert_near(t.time_of_flight, 2.0, DT, "on the fuse")
	assert_true(t.end_point_m.y < -5.0, "above the ground")
	assert_eq(t.fragments.size(), 12, "fragment count")
	for f in t.fragments:
		assert_true(f.has_impact(), "fragment lands")
		assert_true(f.points[0] == t.end_point_m, "fragment starts at the burst")
		assert_true(f.times[0] == t.times[t.times.size() - 1], "fragment clock continues")


func test_shrapnel_without_fuse_bursts_on_impact() -> void:
	var ammo := _ammo(0.3)
	ammo.fragment_count = 6
	var params := ShotParams.create(_weapon(), ammo, 45.0, 1.0, Vector2.ZERO, 1, _weather(), _rng())
	var flight := Ballistics.launch(params, ground)
	var types: Array[StringName] = []
	while not flight.is_settled():
		for ev in flight.advance(0.02):
			if ev.flight == flight:
				types.append(ev.type)
	assert_eq(types, [&"impact", &"burst"] as Array[StringName], "impact then burst")
	assert_eq(flight.fragments.size(), 6, "fragments")
	for f in flight.trajectory.fragments:
		assert_true(f.is_finished(), "fragment finished")
		assert_true(f.apex_m().y < 0.0, "fragment flies up off the ground")


func test_out_of_bounds_and_timeout() -> void:
	var params := ShotParams.create(_weapon(), _ammo(), 45.0, 1.0, Vector2.ZERO, 1, _weather(), _rng())
	params.world_bounds_m = Rect2(-50.0, -1000.0, 100.0, 1100.0)
	var t := Ballistics.simulate_shot(params, Ballistics.no_ground())
	assert_eq(t.end_reason, Trajectory.EndReason.OUT_OF_BOUNDS, "left the map")
	params = ShotParams.create(_weapon(), _ammo(), 45.0, 1.0, Vector2.ZERO, 1, _weather(), _rng())
	params.max_time = 1.0
	t = Ballistics.simulate_shot(params, Ballistics.no_ground())
	assert_eq(t.end_reason, Trajectory.EndReason.TIMEOUT, "timed out")


func test_predict_does_not_consume_rng() -> void:
	var rng := _rng(5)
	var params := ShotParams.create(_weapon(20.0, 60.0, 3.0), _ammo(0.4), 45.0, 1.0, Vector2.ZERO, 1,
		_weather(3.0, 4.0), rng)
	var before := rng.state
	var t := Ballistics.predict(params, ground)
	assert_eq(rng.state, before, "rng untouched")
	assert_eq(t.launch_elevation_deg, 45.0, "no spread in a prediction")


func test_elevation_clamped_to_weapon_limits() -> void:
	var w := _weapon()
	w.elevation_min_deg = 30.0
	w.elevation_max_deg = 60.0
	var t := _shoot(w, _ammo(), 80.0, 1.0, _weather())
	assert_eq(t.launch_elevation_deg, 60.0, "clamped")


func test_aim_solver_hits_target() -> void:
	var weapon := _weapon(25.0, 55.0)
	weapon.elevation_min_deg = 30.0
	weapon.elevation_max_deg = 70.0
	var ammo := _ammo(0.5)
	var weather := _weather(-4.0)
	for arc in [AimSolver.Arc.LOW, AimSolver.Arc.HIGH]:
		for target in [Vector2(150.0, 0.0), Vector2(-120.0, -20.0)]:
			var s := AimSolver.solve(weapon, ammo, Vector2.ZERO, target, weather, arc)
			assert_true(s.ok, "solution for %s" % target)
			var t := Ballistics.simulate(weapon, ammo, s.elevation_deg, s.charge, Vector2.ZERO, s.facing,
				weather, null, Ballistics.flat_ground(target.y))
			assert_true(t.end_point_m.distance_to(target) < 0.5,
				"lands on %s (got %s)" % [target, t.end_point_m])
	var low := AimSolver.solve(weapon, ammo, Vector2.ZERO, Vector2(150.0, 0.0), weather, AimSolver.Arc.LOW)
	var high := AimSolver.solve(weapon, ammo, Vector2.ZERO, Vector2(150.0, 0.0), weather, AimSolver.Arc.HIGH)
	assert_true(high.elevation_deg > low.elevation_deg, "high arc is steeper")


func test_aim_solver_reports_out_of_range() -> void:
	var s := AimSolver.solve(_weapon(10.0, 20.0), _ammo(), Vector2.ZERO, Vector2(5000.0, 0.0), _weather())
	assert_false(s.ok, "too far")
	assert_true(s.miss_m < 0.0, "short")


## Railguns cover hundreds of meters per degree; the solver must bisect elevation to land them.
func test_solver_lands_a_railgun_slug() -> void:
	var w := DataRegistry.get_weapon(&"railgun")
	var a := DataRegistry.get_ammo(&"tungsten_slug")
	for case in [[2200.0, -50.0], [2400.0, -100.0], [2000.0, 0.0], [2100.0, 20.0]]:
		var origin := Vector2(0.0, case[1])
		var target := Vector2(case[0], 0.0)
		var r := AimSolver.solve(w, a, origin, target, WeatherState.new())
		assert_true(r.ok, "railgun at %.0f m, height %+.0f m: miss %.1f m" % [case[0], -case[1], r.miss_m])
