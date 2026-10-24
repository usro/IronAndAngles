class_name ChargeIncrements
extends RefCounted
## Propellant increments per weapon, like a howitzer's charge zones. Spaced geometrically in muzzle
## velocity (range grows with v^2), and as many as needed so the range bands of neighbouring
## charges overlap: with the weapon's elevation limits there's no distance it can't reach between
## its shortest and longest shot. Computed once per weapon (still air, sea level, level ground).

const MIN_COUNT := 5
const MAX_COUNT := 14
## Neighbouring bands must overlap by at least this share of the shorter band's reach.
const OVERLAP := 0.03

static var _cache: Dictionary = {}


## Charge values (0..1) of the weapon's increments, weakest first.
static func for_weapon(w: WeaponData) -> PackedFloat32Array:
	# Keyed on the stats that matter, not just the id (tests build guns that share ids).
	var key := "%s/%s/%s/%s/%s/%s" % [w.id, w.muzzle_velocity_min, w.muzzle_velocity_max, w.elevation_min_deg,
		w.elevation_max_deg, w.allowed_ammo]
	if _cache.has(key):
		return _cache[key]
	var result := _spaced(MIN_COUNT, w, true)
	if not w.is_direct_fire() and w.launcher_type != GameConstants.LauncherType.ORBITAL and not w.allowed_ammo.is_empty():
		var ammo := DataRegistry.get_ammo(w.allowed_ammo[0])
		if ammo:
			for n in range(MIN_COUNT, MAX_COUNT + 1):
				result = _spaced(n, w, false)
				if _covers(w, ammo, result):
					break
	_cache[key] = result
	return result


static func count(w: WeaponData) -> int:
	return for_weapon(w).size()


## Index of the increment nearest to `charge`.
static func nearest(w: WeaponData, charge: float) -> int:
	var inc := for_weapon(w)
	var best := 0
	for i in inc.size():
		if absf(inc[i] - charge) < absf(inc[best] - charge):
			best = i
	return best


static func _spaced(n: int, w: WeaponData, linear: bool) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if w.muzzle_velocity_max - w.muzzle_velocity_min <= 1e-6:
		# One fixed velocity: the increments are nominal.
		for i in n:
			out.append(i / float(n - 1))
		return out
	var lo := maxf(w.muzzle_velocity_min, 1.0)
	var hi := maxf(w.muzzle_velocity_max, lo + 1.0)
	for i in n:
		var f := i / float(n - 1)
		var v := lerpf(lo, hi, f) if linear else lo * pow(hi / lo, f)
		out.append(clampf((v - w.muzzle_velocity_min) / (w.muzzle_velocity_max - w.muzzle_velocity_min), 0.0, 1.0))
	return out


## True when the range bands of consecutive increments overlap (no gaps).
static func _covers(w: WeaponData, a: AmmoData, increments: PackedFloat32Array) -> bool:
	var k := 0.5 * GameConstants.SEA_LEVEL_AIR_DENSITY * a.drag_coefficient * a.cross_section_m2 / a.mass_kg
	var prev_max := -1.0
	for c in increments:
		var speed := w.velocity_for_charge(c)
		var lo := INF
		var hi := 0.0
		var e := w.elevation_min_deg
		while e <= w.elevation_max_deg + 1e-6:
			var x := FiringTable._fly(speed, e, k, a, 0.0, GameConstants.STANDARD_GRAVITY, 0.0).x
			if not is_nan(x):
				lo = minf(lo, x)
				hi = maxf(hi, x)
			e += 2.0
		if prev_max >= 0.0 and lo > prev_max * (1.0 - OVERLAP):
			return false
		prev_max = maxf(prev_max, hi)
	return true
