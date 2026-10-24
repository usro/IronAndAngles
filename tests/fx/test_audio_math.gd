extends TestCase
## Sound propagation math: delay at 343 m/s, distance loudness and air absorption, pan.


func test_delay_is_distance_over_speed_of_sound() -> void:
	assert_near(AudioMath.arrival_delay(Vector2(343, 0), Vector2.ZERO), 1.0, 1e-6, "343 m")
	assert_near(AudioMath.arrival_delay(Vector2(80, -20), Vector2(80 + 1029, -20)), 3.0, 1e-6, "1029 m")
	assert_near(AudioMath.arrival_delay(Vector2(0, 0), Vector2(300, 400)), 500.0 / 343.0, 1e-6, "diagonal")
	assert_near(AudioMath.arrival_delay(Vector2(5, 5), Vector2(5, 5)), 0.0, 1e-9, "at the listener")


func test_gain_falls_with_distance() -> void:
	assert_near(AudioMath.distance_gain_db(0.0), 0.0, 1e-6, "no loss at the listener")
	assert_near(AudioMath.distance_gain_db(60.0), -3.0103, 1e-3, "reference distance is -3 dB")
	assert_near(AudioMath.distance_gain_db(1000.0), -10.0 * log(1.0 + 1000.0 / 60.0) / log(10.0), 1e-6, "1 km")
	var last := 1.0
	for d in [0.0, 50.0, 200.0, 500.0, 1000.0, 2400.0]:
		var g := AudioMath.distance_gain_db(d)
		assert_true(g < last, "quieter at %d m" % d)
		last = g
	assert_eq(AudioMath.distance_gain_db(1e12), AudioMath.MIN_GAIN_DB, "floor")
	assert_near(AudioMath.distance_gain_db(-5.0), 0.0, 1e-6, "negative distance clamps")


func test_cutoff_closes_with_distance() -> void:
	assert_near(AudioMath.distance_cutoff_hz(0.0), AudioMath.CUTOFF_MAX_HZ, 1e-3, "open at the listener")
	assert_near(AudioMath.distance_cutoff_hz(900.0), AudioMath.CUTOFF_MAX_HZ / exp(1.0), 1e-2, "1/e at falloff")
	assert_eq(AudioMath.distance_cutoff_hz(50000.0), AudioMath.CUTOFF_MIN_HZ, "floor")
	assert_true(AudioMath.distance_cutoff_hz(2400.0) < AudioMath.distance_cutoff_hz(220.0), "far is duller")


func test_pan_by_screen_position() -> void:
	assert_near(AudioMath.pan_from_screen(0.0, 640.0), 0.0, 1e-9, "centre")
	assert_near(AudioMath.pan_from_screen(640.0, 640.0), AudioMath.PAN_WIDTH, 1e-9, "right edge")
	assert_near(AudioMath.pan_from_screen(-320.0, 640.0), -AudioMath.PAN_WIDTH * 0.5, 1e-9, "left half")
	assert_near(AudioMath.pan_from_screen(5000.0, 640.0), AudioMath.PAN_WIDTH, 1e-9, "off screen clamps")
	assert_near(AudioMath.pan_from_screen(10.0, 0.0), 0.0, 1e-9, "no viewport")
	assert_near(AudioMath.pan_from_offset(-AudioMath.PAN_FALLBACK_SPAN_M), -AudioMath.PAN_WIDTH, 1e-9, "fallback")


func test_slider_to_db() -> void:
	assert_near(AudioMath.slider_to_db(1.0), 0.0, 1e-6, "full")
	assert_near(AudioMath.slider_to_db(0.5), -6.0206, 1e-3, "half")
	assert_eq(AudioMath.slider_to_db(0.0), -80.0, "silent")


func test_variation_stays_in_range_and_varies() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var seen := {}
	for i in 50:
		var v := AudioMath.vary(rng, 0.05)
		assert_true(v >= 0.95 and v <= 1.05, "within spread")
		seen[snappedf(v, 0.001)] = true
	assert_true(seen.size() > 10, "not identical")
