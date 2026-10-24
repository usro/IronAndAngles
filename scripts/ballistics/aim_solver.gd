class_name AimSolver
extends RefCounted
## Finds an elevation and charge that land a nominal shot (no spread, no gusts) on a target point.
## Used by the AI and the easy-difficulty aim assist. Terrain is ignored: the shot is "on target"
## when it comes down through the target's height at the target's x.

enum Arc {
	LOW,  ## Flattest shot that reaches (fast, but terrain may block it).
	HIGH,  ## Steepest shot that reaches (lobs over cover, longer flight).
}

const CHARGE_ITERATIONS := 18
## Returned miss for a shot that never comes down through the target height.
const NEVER_REACHES := -1.0e9


## Returns {"ok": bool, "elevation_deg": float, "charge": float, "facing": int,
## "predicted_m": Vector2, "miss_m": float}. ok is false if no elevation in the weapon's range
## reaches the target; the closest attempt is still returned.
## `precise` = false skips the exact refine (fast model only, within a few meters): for callers that
## add their own error anyway, like the enemy gun.
static func solve(weapon: WeaponData, ammo: AmmoData, origin_m: Vector2, target_m: Vector2,
		weather: WeatherState, arc: Arc = Arc.LOW, elevation_step_deg: float = 2.0, precise := true) -> Dictionary:
	var elevations: Array[float] = []
	var e := weapon.elevation_min_deg
	while e < weapon.elevation_max_deg:
		elevations.append(e)
		e += elevation_step_deg
	elevations.append(weapon.elevation_max_deg)
	if arc == Arc.HIGH:
		elevations.reverse()
	var best := {}
	for elev in elevations:
		var r := solve_charge(weapon, ammo, origin_m, target_m, weather, elev, precise)
		if r.ok:
			return r
		if best.is_empty() or absf(r.miss_m) < absf(best.miss_m):
			best = r
	# Hypervelocity weapons (railguns) span hundreds of meters per degree: no grid elevation lands,
	# but the miss changes sign between two of them. Bisect the elevation at a fixed charge.
	var refined := _bisect_elevation(weapon, ammo, origin_m, target_m, weather, elevations)
	if not refined.is_empty() and (refined.ok or absf(refined.miss_m) < absf(best.miss_m)):
		return refined
	return best


const ELEVATION_ITERATIONS := 32
## Elevation sampling step when solving at a fixed charge.
const FIXED_CHARGE_SCAN_DEG := 1.0


## Elevation that lands a nominal shot on target at a FIXED charge (propellant increments).
## LOW picks the flatter of the two solutions, HIGH the steeper one. Direct-fire weapons use the
## height-at-distance miss so uphill shots count while rising. Same result keys as solve().
static func solve_at_charge(weapon: WeaponData, ammo: AmmoData, origin_m: Vector2, target_m: Vector2,
		weather: WeatherState, charge: float, arc: Arc = Arc.LOW) -> Dictionary:
	var facing := 1 if target_m.x >= origin_m.x else -1
	var direct := weapon.is_direct_fire()
	var result := {"ok": false, "elevation_deg": weapon.elevation_min_deg, "facing": facing, "charge": charge,
		"miss_m": INF, "predicted_m": Vector2.INF}
	# 1. Search with the fast point-mass model (no bounces, no guidance): cheap enough to scan.
	var step := FAST_SCAN_DIRECT_DEG if direct else FIXED_CHARGE_SCAN_DEG
	var hi_elev := minf(weapon.elevation_max_deg, 15.0) if direct else weapon.elevation_max_deg
	var samples: Array[Vector2] = []  # (elevation, fast miss)
	var e := weapon.elevation_min_deg
	while e <= hi_elev + 1e-6:
		var m := _fast_miss(weapon, ammo, origin_m, target_m, weather, e, charge, facing, direct)
		if not is_nan(m):
			samples.append(Vector2(e, m))
		e += step
	var brackets: Array[Vector2] = []
	for i in range(1, samples.size()):
		if signf(samples[i].y) != signf(samples[i - 1].y):
			brackets.append(Vector2(samples[i - 1].x, samples[i].x))
	if brackets.is_empty():
		# Out of reach at this charge: report the closest sample.
		for smp in samples:
			if absf(smp.y) < absf(result.miss_m):
				result.elevation_deg = smp.x
				result.miss_m = smp.y
		return result
	var br: Vector2 = brackets[0] if arc == Arc.LOW else brackets[brackets.size() - 1]
	var a := br.x
	var b := br.y
	var miss_a := _fast_miss(weapon, ammo, origin_m, target_m, weather, a, charge, facing, direct)
	for i in FAST_ITERATIONS:
		var mid := (a + b) * 0.5
		var miss_mid := _fast_miss(weapon, ammo, origin_m, target_m, weather, mid, charge, facing, direct)
		if is_nan(miss_mid):
			break
		if signf(miss_mid) == signf(miss_a):
			a = mid
			miss_a = miss_mid
		else:
			b = mid
	# 2. Land it with a few exact simulations (secant on the real flight model).
	var elev := _refine(func(x: float) -> float:
		return _miss_any(direct, weapon, ammo, origin_m, target_m, weather, x, charge, facing),
		(a + b) * 0.5, REFINE_STEP_DIRECT_DEG if direct else REFINE_STEP_DEG,
		weapon.elevation_min_deg, weapon.elevation_max_deg)
	var miss := _miss_any(direct, weapon, ammo, origin_m, target_m, weather, elev, charge, facing)
	result.elevation_deg = elev
	result.miss_m = miss
	result.ok = not is_nan(miss) and miss != NEVER_REACHES and absf(miss) <= ON_TARGET_M * (1.0 if direct else 4.0)
	result.predicted_m = target_m + Vector2(miss * facing, 0.0) if not direct else target_m - Vector2(0.0, miss)
	return result


const FAST_SCAN_DIRECT_DEG := 0.25
const FAST_ITERATIONS := 24
const REFINE_STEP_DEG := 0.3
const REFINE_STEP_DIRECT_DEG := 0.01
const REFINE_ITERATIONS := 5
## Stop refining once the exact miss is this small (each extra exact flight costs milliseconds).
const REFINE_GOOD_ENOUGH_M := 0.3
## Fast model step for near-straight (direct-fire) shots, in meters flown.
const FAST_DIRECT_STEP_M := 5.0


## Miss from the fast point-mass model, with the mean wind; NAN if it never gets there.
## Arcing: meters long (+) or short (-) where it comes down through the target's height.
## Direct fire: meters above (+) or below (-) the target where it passes the target's distance,
## the same measure as _height_miss (a near-straight slug may cross the target's height early).
## Used to search; exact answers come from _miss / _height_miss.
static func _fast_miss(weapon: WeaponData, ammo: AmmoData, origin_m: Vector2, target_m: Vector2,
		weather: WeatherState, elevation_deg: float, charge: float, facing: int, direct: bool) -> float:
	var k := 0.5 * weather.air_density * ammo.drag_coefficient * ammo.cross_section_m2 / ammo.mass_kg
	var speed := weapon.velocity_for_charge(charge)
	if direct:
		return _fast_height_at(absf(target_m.x - origin_m.x), speed, elevation_deg, k, ammo, weather.gravity,
			weather.wind_speed * facing) - (origin_m.y - target_m.y)
	var r := FiringTable._fly(speed, elevation_deg, k, ammo, target_m.y - origin_m.y, weather.gravity,
		weather.wind_speed * facing)
	return r.x - absf(target_m.x - origin_m.x) if not is_nan(r.x) else NAN


## Height (m, up = +) of a fast, near-straight shot above the muzzle at horizontal distance x_m.
static func _fast_height_at(x_m: float, speed: float, elev_deg: float, k: float, a: AmmoData, gravity: float,
		wind: float) -> float:
	var pos := Vector2.ZERO
	var vel := Vector2(cos(deg_to_rad(elev_deg)), -sin(deg_to_rad(elev_deg))) * speed
	var air := Vector2(wind * a.wind_sensitivity, 0.0)
	var dt := FAST_DIRECT_STEP_M / maxf(speed, 1.0)
	var t := 0.0
	while t < 30.0:
		var rel := vel - air
		var prev := pos
		vel += (Vector2(0.0, gravity) - rel * rel.length() * k) * dt
		pos += vel * dt
		t += dt
		if pos.x >= x_m:
			var f := (x_m - prev.x) / maxf(pos.x - prev.x, 1e-6)
			return -lerpf(prev.y, pos.y, f)
	return NAN


## Secant iterations on f (exact miss, monotonic near the root) from x0; returns the best x seen.
static func _refine(f: Callable, x0: float, dx: float, lo: float, hi: float) -> float:
	var xa := x0
	var fa: float = f.call(xa)
	if _bad(fa):
		return x0
	var xb := clampf(x0 + (dx if fa < 0.0 else -dx), lo, hi)
	var fb: float = f.call(xb)
	var best := xa if _bad(fb) or absf(fa) <= absf(fb) else xb
	var best_f := fa if best == xa else fb
	for i in REFINE_ITERATIONS:
		if _bad(fb) or absf(best_f) < REFINE_GOOD_ENOUGH_M or fb == fa:
			break
		var xc := clampf(xb - fb * (xb - xa) / (fb - fa), lo, hi)
		xa = xb
		fa = fb
		xb = xc
		fb = f.call(xb)
		if not _bad(fb) and absf(fb) < absf(best_f):
			best = xb
			best_f = fb
	return best


static func _bad(v: float) -> bool:
	return is_nan(v) or v == NEVER_REACHES


static func _miss_any(direct: bool, weapon: WeaponData, ammo: AmmoData, origin_m: Vector2, target_m: Vector2,
		weather: WeatherState, elevation_deg: float, charge: float, facing: int) -> float:
	return _height_miss(weapon, ammo, origin_m, target_m, weather, elevation_deg, charge, facing) if direct \
		else _miss(weapon, ammo, origin_m, target_m, weather, elevation_deg, charge, facing)
## A bisected shot within this distance of the target counts as on target.
const ON_TARGET_M := 0.5


static func _bisect_elevation(weapon: WeaponData, ammo: AmmoData, origin_m: Vector2, target_m: Vector2,
		weather: WeatherState, elevations: Array[float]) -> Dictionary:
	const CHARGE := 0.5
	var facing := 1 if target_m.x >= origin_m.x else -1
	var sorted := elevations.duplicate()
	sorted.sort()
	var prev_e := NAN
	var prev_m := 0.0
	for e in sorted:
		var m := _height_miss(weapon, ammo, origin_m, target_m, weather, e, CHARGE, facing)
		if is_nan(m):
			prev_e = NAN
			continue
		if not is_nan(prev_e) and signf(m) != signf(prev_m):
			var a: float = prev_e
			var b: float = e
			var miss_a := prev_m
			for i in ELEVATION_ITERATIONS:
				var mid := (a + b) * 0.5
				var miss_mid := _height_miss(weapon, ammo, origin_m, target_m, weather, mid, CHARGE, facing)
				if is_nan(miss_mid):
					break
				if signf(miss_mid) == signf(miss_a):
					a = mid
					miss_a = miss_mid
				else:
					b = mid
			var elev := (a + b) * 0.5
			var vertical := _height_miss(weapon, ammo, origin_m, target_m, weather, elev, CHARGE, facing)
			var result := {"ok": false, "elevation_deg": elev, "facing": facing, "charge": CHARGE,
				"miss_m": vertical, "predicted_m": target_m - Vector2(0.0, vertical)}
			result.ok = not is_nan(vertical) and absf(vertical) <= ON_TARGET_M
			return result
		prev_e = e
		prev_m = m
	return {}


## Direct-fire miss: how far above (+) or below (-) the target point the shell passes at the
## target's distance, whether rising or falling. NaN if it never gets that far.
static func _height_miss(weapon: WeaponData, ammo: AmmoData, origin_m: Vector2, target_m: Vector2,
		weather: WeatherState, elevation_deg: float, charge: float, facing: int) -> float:
	var p := ShotParams.create(weapon, ammo, elevation_deg, charge, origin_m, facing, weather, null)
	p.nominal = true
	p.record_points = false
	p.stop_at_first_contact = true
	var t := Ballistics.simulate_shot(p, _vertical_plane(target_m.x, facing))
	if not t.has_impact():
		return NAN
	return target_m.y - t.end_point_m.y


static func _vertical_plane(x_m: float, facing: int) -> Callable:
	return func(from_m: Vector2, to_m: Vector2) -> Dictionary:
		if (from_m.x - x_m) * facing > 0.0 or (to_m.x - x_m) * facing < 0.0:
			return {}
		var f := (x_m - from_m.x) / (to_m.x - from_m.x) if to_m.x != from_m.x else 0.0
		return {"position": Vector2(x_m, lerpf(from_m.y, to_m.y, f)), "normal": Vector2.LEFT * facing}


## Best charge for a fixed elevation: fast-model bisection (range grows with charge), then an
## exact secant refine.
static func solve_charge(weapon: WeaponData, ammo: AmmoData, origin_m: Vector2, target_m: Vector2,
		weather: WeatherState, elevation_deg: float, precise := true) -> Dictionary:
	var facing := 1 if target_m.x >= origin_m.x else -1
	var direct := weapon.is_direct_fire()
	var result := {"ok": false, "elevation_deg": elevation_deg, "facing": facing}
	var fast := func(c: float) -> float:
		var m := _fast_miss(weapon, ammo, origin_m, target_m, weather, elevation_deg, c, facing, direct)
		return -1.0e6 if is_nan(m) else m
	var lo := 0.0
	var hi := 1.0
	var miss_lo: float = fast.call(lo)
	var miss_hi: float = fast.call(hi)
	if miss_lo > 0.0:
		# Even the lowest charge overshoots.
		return _with(result, weapon, ammo, origin_m, target_m, weather, lo, miss_lo, false)
	if miss_hi < 0.0:
		return _with(result, weapon, ammo, origin_m, target_m, weather, hi, miss_hi, false)
	for i in CHARGE_ITERATIONS:
		var mid := (lo + hi) * 0.5
		if fast.call(mid) < 0.0:
			lo = mid
		else:
			hi = mid
	if not precise:
		var c_fast := (lo + hi) * 0.5
		return _with(result, weapon, ammo, origin_m, target_m, weather, c_fast, fast.call(c_fast), true)
	var charge := _refine(func(c: float) -> float:
		return _miss(weapon, ammo, origin_m, target_m, weather, elevation_deg, c, facing),
		(lo + hi) * 0.5, 0.01, 0.0, 1.0)
	var miss := _miss(weapon, ammo, origin_m, target_m, weather, elevation_deg, charge, facing)
	return _with(result, weapon, ammo, origin_m, target_m, weather, charge, miss,
		miss != NEVER_REACHES and absf(miss) <= ON_TARGET_M * 4.0)


static func _with(result: Dictionary, weapon: WeaponData, ammo: AmmoData, origin_m: Vector2,
		target_m: Vector2, weather: WeatherState, charge: float, miss: float, ok: bool) -> Dictionary:
	result["ok"] = ok
	result["charge"] = charge
	result["miss_m"] = miss
	var facing: int = result.facing
	result["predicted_m"] = Vector2(target_m.x + miss * facing, target_m.y) \
			if miss != NEVER_REACHES else Vector2.INF
	return result


## Signed miss along the firing direction where the shell descends through target_m.y:
## negative = short, positive = long.
static func _miss(weapon: WeaponData, ammo: AmmoData, origin_m: Vector2, target_m: Vector2,
		weather: WeatherState, elevation_deg: float, charge: float, facing: int) -> float:
	var p := ShotParams.create(weapon, ammo, elevation_deg, charge, origin_m, facing, weather, null)
	p.nominal = true
	p.record_points = false
	p.stop_at_first_contact = true
	var floor_y := maxf(origin_m.y, target_m.y) + 1.0
	p.world_bounds_m = Rect2(-1.0e7, -1.0e7, 2.0e7, 1.0e7 + floor_y)
	var t := Ballistics.simulate_shot(p, _descending_plane(target_m.y))
	if not t.has_impact():
		return NEVER_REACHES
	return (t.end_point_m.x - target_m.x) * facing


## Hits only when the shell crosses y_m going down (so an uphill shot is not caught on the way up).
static func _descending_plane(y_m: float) -> Callable:
	return func(from_m: Vector2, to_m: Vector2) -> Dictionary:
		if not (to_m.y > from_m.y and from_m.y <= y_m and to_m.y >= y_m):
			return {}
		var f := (y_m - from_m.y) / (to_m.y - from_m.y)
		return {"position": Vector2(lerpf(from_m.x, to_m.x, f), y_m), "normal": Vector2.UP}
