class_name FiringTable
extends RefCounted
## A gunner's firing table for one weapon, ammo and propellant charge, laid out like the real
## thing: RANGE rows -> the ELEVATION that lands there (low and high angle), TIME OF FLIGHT, and
## the WIND correction (meters of drift per 1 m/s of wind). Still air, no spread: the crew applies
## wind and corrections themselves. Pure; computed once per weapon/ammo/charge/height.
##
## Direct-fire weapons (railguns) barely arc, so they only have the low-angle column.

const ROWS := 12
## Elevation sweep step (deg) used to build the table; rows are interpolated from it.
const SWEEP_DEG := 0.5
## Direct-fire rows: spacing, default centre, bisection steps, and fast-model step (meters).
const DIRECT_ROW_M := 50.0
const DIRECT_DEFAULT_CENTRE_M := 2000.0
const DIRECT_ITERATIONS := 16
const DIRECT_STEP_M := 10.0
## Integration step: coarse but fine for a card read to the nearest few meters.
const DT := 1.0 / 60.0
const MAX_FLIGHT_S := 90.0
## Wind used to measure drift; the table shows drift per 1 m/s.
const PROBE_WIND := 5.0

var weapon: WeaponData
var ammo: AmmoData
var charge: float
var direct_fire: bool
## Height of the target ground above the battery's (m) the table was built for.
var height_m: float
var ranges: Array[float] = []
## Per row: elevation (deg) or NAN when that angle can't reach the range.
var low_elevations: Array[float] = []
var high_elevations: Array[float] = []
var low_tof: Array[float] = []
var high_tof: Array[float] = []
## Meters the impact moves per 1 m/s of tailwind, at each angle.
var low_wind_drift: Array[float] = []
var high_wind_drift: Array[float] = []
var min_range: float = INF
var max_range: float = 0.0

## Sweep samples: elevation, range, time of flight, drift. Ascending elevation.
var _sweep: Array[Vector4] = []
var _peak := 0


## `around_m`: direct-fire rows are centred on this range (0 = a default span).
static func build(p_weapon: WeaponData, p_ammo: AmmoData, weather: WeatherState, p_charge: float,
		p_height_m: float, around_m := 0.0) -> FiringTable:
	var t := FiringTable.new()
	t.weapon = p_weapon
	t.ammo = p_ammo
	t.charge = p_charge
	t.height_m = p_height_m
	t.direct_fire = p_weapon.is_direct_fire()
	var k := 0.5 * weather.air_density * p_ammo.drag_coefficient * p_ammo.cross_section_m2 / p_ammo.mass_kg
	var speed := p_weapon.velocity_for_charge(p_charge)
	var drop := -p_height_m
	if t.direct_fire:
		t._build_direct(speed, k, drop, weather.gravity, around_m)
		return t
	var step := SWEEP_DEG
	var hi := minf(p_weapon.elevation_max_deg, 10.0) if t.direct_fire else p_weapon.elevation_max_deg
	var e := p_weapon.elevation_min_deg
	while e <= hi + 1e-6:
		var calm := _fly(speed, e, k, p_ammo, drop, weather.gravity, 0.0, t.direct_fire)
		if not is_nan(calm.x):
			# Wind drift is filled in per displayed row below (one extra flight per row, not per sample).
			t._sweep.append(Vector4(e, calm.x, calm.y, 0.0))
		e += step
	if t._sweep.is_empty():
		return t
	for i in t._sweep.size():
		if t._sweep[i].y > t._sweep[t._peak].y:
			t._peak = i
		t.min_range = minf(t.min_range, t._sweep[i].y)
	t.max_range = t._sweep[t._peak].y
	var lo := maxf(t.min_range, 1.0)
	var row_step := _nice_step((t.max_range - lo) / (ROWS - 1))
	var r := ceilf(lo / row_step) * row_step
	while r <= t.max_range + 1e-6 and t.ranges.size() < ROWS + 2:
		t.ranges.append(r)
		var low := t.solve(r, false)
		var high := t.solve(r, true)
		t.low_elevations.append(low.x)
		t.high_elevations.append(high.x)
		t.low_tof.append(low.y)
		t.low_wind_drift.append(t._drift(low.x, r, speed, k, drop, weather.gravity))
		t.high_tof.append(high.y)
		t.high_wind_drift.append(t._drift(high.x, r, speed, k, drop, weather.gravity))
		r += row_step
	return t


## Meters a 1 m/s tailwind moves a shot fired at `elev` that lands at `range_m` in still air.
func _drift(elev: float, range_m: float, speed: float, k: float, drop: float, gravity: float) -> float:
	if is_nan(elev):
		return NAN
	var windy := _fly(speed, elev, k, ammo, drop, gravity, PROBE_WIND, direct_fire)
	return (windy.x - range_m) / PROBE_WIND if not is_nan(windy.x) else NAN


## Direct fire: each row solved on its own (the path is nearly straight, so a sweep would need
## hundredths of a degree). Fast model with a coarse step; rows every DIRECT_ROW_M around `around_m`.
func _build_direct(speed: float, k: float, drop: float, gravity: float, around_m: float) -> void:
	var centre := around_m if around_m > 0.0 else DIRECT_DEFAULT_CENTRE_M
	var first := maxf(DIRECT_ROW_M, snappedf(centre, DIRECT_ROW_M) - DIRECT_ROW_M * (ROWS / 2))
	for i in ROWS:
		var r := first + i * DIRECT_ROW_M
		var lo := weapon.elevation_min_deg
		var hi := minf(weapon.elevation_max_deg, 15.0)
		var ok := false
		for it in DIRECT_ITERATIONS:
			var mid := (lo + hi) * 0.5
			var x := _fly(speed, mid, k, ammo, drop, gravity, 0.0, true, DIRECT_STEP_M).x
			if is_nan(x) or x > r:
				hi = mid
			else:
				lo = mid
				ok = true
		var e := (lo + hi) * 0.5
		var calm := _fly(speed, e, k, ammo, drop, gravity, 0.0, true, DIRECT_STEP_M)
		ranges.append(r)
		low_elevations.append(e if ok and not is_nan(calm.x) else NAN)
		low_tof.append(calm.y)
		var windy := _fly(speed, e, k, ammo, drop, gravity, PROBE_WIND, true, DIRECT_STEP_M)
		low_wind_drift.append((windy.x - calm.x) / PROBE_WIND if not is_nan(windy.x) else 0.0)
		high_elevations.append(NAN)
		high_tof.append(NAN)
		high_wind_drift.append(NAN)
	min_range = ranges[0]
	max_range = ranges[ranges.size() - 1]


## (elevation, time of flight, wind drift per m/s) that lands at `range_m`, low or high angle.
## Components are NAN when that branch can't reach.
func solve(range_m: float, high: bool) -> Vector3:
	var nan3 := Vector3(NAN, NAN, NAN)
	if direct_fire:
		if high:
			return nan3
		for i in range(ranges.size() - 1):
			if range_m >= ranges[i] and range_m <= ranges[i + 1] and not is_nan(low_elevations[i]) \
					and not is_nan(low_elevations[i + 1]):
				var f := (range_m - ranges[i]) / (ranges[i + 1] - ranges[i])
				return Vector3(lerpf(low_elevations[i], low_elevations[i + 1], f), lerpf(low_tof[i], low_tof[i + 1], f),
					lerpf(low_wind_drift[i], low_wind_drift[i + 1], f))
		return nan3
	if _sweep.is_empty():
		return nan3
	var from := _peak if high else 0
	var to := _sweep.size() - 1 if high else _peak
	for i in range(from, to):
		var a := _sweep[i]
		var b := _sweep[i + 1]
		if (range_m - a.y) * (range_m - b.y) <= 0.0 and a.y != b.y:
			var f := (range_m - a.y) / (b.y - a.y)
			return Vector3(lerpf(a.x, b.x, f), lerpf(a.z, b.z, f), lerpf(a.w, b.w, f))
	return nan3


## First ground contact for one shot: (x, time of flight), NAN x if it never comes down.
## `step_m`: for fast, near-straight shots, the distance flown per step (0 = the default DT).
static func _fly(speed: float, elev_deg: float, k: float, a: AmmoData, drop_m: float, gravity: float,
		wind: float, direct := false, step_m := 0.0) -> Vector2:
	var pos := Vector2.ZERO
	var vel := Vector2(cos(deg_to_rad(elev_deg)), -sin(deg_to_rad(elev_deg))) * speed
	var t := 0.0
	var dt := minf(DT, step_m / maxf(speed, 1.0)) if step_m > 0.0 else DT
	var above := drop_m >= 0.0
	var air := Vector2(wind * a.wind_sensitivity, 0.0)
	while t < MAX_FLIGHT_S:
		var rel := vel - air
		var acc := Vector2(0.0, gravity) - rel * rel.length() * k
		if t < a.burn_time and vel.length() > 0.0:
			acc += vel.normalized() * a.thrust_n / a.mass_kg
		var prev := pos
		vel += acc * dt
		pos += vel * dt
		t += dt
		above = above or pos.y < drop_m
		if above and vel.y > 0.0 and pos.y >= drop_m:
			var f := clampf((drop_m - prev.y) / maxf(pos.y - prev.y, 1e-6), 0.0, 1.0)
			return Vector2(lerpf(prev.x, pos.x, f), t - dt * (1.0 - f))
		# Direct fire: count passing the target height while still rising, too.
		if direct and not above and pos.y <= drop_m and vel.y < 0.0:
			var f2 := clampf((drop_m - prev.y) / minf(pos.y - prev.y, -1e-6), 0.0, 1.0)
			return Vector2(lerpf(prev.x, pos.x, f2), t - dt * (1.0 - f2))
	return Vector2(NAN, NAN)


## 1, 2, 5 x 10^n at or above `raw`.
static func _nice_step(raw: float) -> float:
	var p := pow(10.0, floorf(log(maxf(raw, 1.0)) / log(10.0)))
	for m in [1.0, 2.0, 2.5, 5.0, 10.0]:
		if raw <= m * p:
			return m * p
	return 10.0 * p
