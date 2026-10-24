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
static func solve(weapon: WeaponData, ammo: AmmoData, origin_m: Vector2, target_m: Vector2,
		weather: WeatherState, arc: Arc = Arc.LOW, elevation_step_deg: float = 2.0) -> Dictionary:
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
		var r := solve_charge(weapon, ammo, origin_m, target_m, weather, elev)
		if r.ok:
			return r
		if best.is_empty() or absf(r.miss_m) < absf(best.miss_m):
			best = r
	return best


## Best charge for a fixed elevation (bisection; range grows with charge).
static func solve_charge(weapon: WeaponData, ammo: AmmoData, origin_m: Vector2, target_m: Vector2,
		weather: WeatherState, elevation_deg: float) -> Dictionary:
	var facing := 1 if target_m.x >= origin_m.x else -1
	var lo := 0.0
	var hi := 1.0
	var miss_lo := _miss(weapon, ammo, origin_m, target_m, weather, elevation_deg, lo, facing)
	var miss_hi := _miss(weapon, ammo, origin_m, target_m, weather, elevation_deg, hi, facing)
	var result := {"ok": false, "elevation_deg": elevation_deg, "facing": facing}
	if miss_lo > 0.0:
		# Even the lowest charge overshoots.
		return _with(result, weapon, ammo, origin_m, target_m, weather, lo, miss_lo, false)
	if miss_hi < 0.0:
		return _with(result, weapon, ammo, origin_m, target_m, weather, hi, miss_hi, false)
	for i in CHARGE_ITERATIONS:
		var mid := (lo + hi) * 0.5
		if _miss(weapon, ammo, origin_m, target_m, weather, elevation_deg, mid, facing) < 0.0:
			lo = mid
		else:
			hi = mid
	var charge := (lo + hi) * 0.5
	var miss := _miss(weapon, ammo, origin_m, target_m, weather, elevation_deg, charge, facing)
	return _with(result, weapon, ammo, origin_m, target_m, weather, charge, miss, true)


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
