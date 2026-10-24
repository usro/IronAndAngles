class_name FiringTable
extends RefCounted
## A gunner's range card for one weapon and ammo in one battle: where a shot lands in still air.
## Pure and approximate (point mass, quadratic drag, rocket thrust, no wind, no spread), so the
## player still corrects for wind, gusts and craters.
##
## Arcing weapons get a grid: elevation rows x charge columns -> landing distance.
## Direct-fire weapons (railguns) get a list: distance rows -> the elevation that hits at it.

const CHARGES: Array[float] = [0.0, 0.25, 0.5, 0.75, 1.0]
const TARGET_ROWS := 8
## Integration step: coarse but fine for a card read to the nearest few meters.
const DT := 1.0 / 60.0
const MAX_FLIGHT_S := 90.0
## Direct-fire card: distances every DIRECT_STEP_M around the target zone, at this charge.
const DIRECT_STEP_M := 25.0
const DIRECT_ROWS := 13
const DIRECT_CHARGE := 0.5

var weapon: WeaponData
var ammo: AmmoData
var direct_fire: bool
## Arcing: elevations (deg) for rows; distances[row][col] in meters (NAN = never comes down).
var elevations: Array[float] = []
var distances: Array[PackedFloat32Array] = []
## Direct fire: distances (m) for rows and the elevation (deg) that hits at each.
var direct_distances: Array[float] = []
var direct_elevations: Array[float] = []


## `drop_m`: how far the target ground lies below the muzzle (negative = above).
## `around_m`: the distance the direct-fire card is centred on (the target zone).
static func build(p_weapon: WeaponData, p_ammo: AmmoData, weather: WeatherState, drop_m: float,
		around_m: float) -> FiringTable:
	var t := FiringTable.new()
	t.weapon = p_weapon
	t.ammo = p_ammo
	t.direct_fire = p_weapon.is_direct_fire()
	var k := 0.5 * weather.air_density * p_ammo.drag_coefficient * p_ammo.cross_section_m2 / p_ammo.mass_kg
	if t.direct_fire:
		var speed := p_weapon.velocity_for_charge(DIRECT_CHARGE)
		for i in DIRECT_ROWS:
			var d := snappedf(around_m, DIRECT_STEP_M) + (i - DIRECT_ROWS / 2) * DIRECT_STEP_M
			t.direct_distances.append(d)
			t.direct_elevations.append(_elevation_for(d, speed, k, p_ammo, drop_m, weather.gravity, p_weapon))
		return t
	var span := p_weapon.elevation_max_deg - p_weapon.elevation_min_deg
	var step := maxf(1.0, snappedf(span / (TARGET_ROWS - 1), 1.0))
	var e := p_weapon.elevation_min_deg
	while e <= p_weapon.elevation_max_deg + 0.01:
		t.elevations.append(e)
		var row := PackedFloat32Array()
		for c in CHARGES:
			row.append(land_x(p_weapon.velocity_for_charge(c), e, k, p_ammo, drop_m, weather.gravity))
		t.distances.append(row)
		e += step
	return t


## Landing distance (m) for one shot, NAN if it never comes down to the target ground.
static func land_x(speed: float, elev_deg: float, k: float, a: AmmoData, drop_m: float, gravity: float) -> float:
	var pos := Vector2.ZERO
	var vel := Vector2(cos(deg_to_rad(elev_deg)), -sin(deg_to_rad(elev_deg))) * speed
	var t := 0.0
	var above := drop_m >= 0.0
	while t < MAX_FLIGHT_S:
		var acc := Vector2(0.0, gravity) - vel * vel.length() * k
		if t < a.burn_time and vel.length() > 0.0:
			acc += vel.normalized() * a.thrust_n / a.mass_kg
		var prev := pos
		vel += acc * DT
		pos += vel * DT
		t += DT
		above = above or pos.y < drop_m
		if above and vel.y > 0.0 and pos.y >= drop_m:
			var f := (drop_m - prev.y) / maxf(pos.y - prev.y, 1e-6)
			return lerpf(prev.x, pos.x, clampf(f, 0.0, 1.0))
	return NAN


## Direct fire: the elevation whose (nearly straight) path is at the target's height at `distance_m`.
static func _elevation_for(distance_m: float, speed: float, k: float, a: AmmoData, drop_m: float,
		gravity: float, w: WeaponData) -> float:
	var lo := w.elevation_min_deg
	var hi := minf(w.elevation_max_deg, 10.0)
	for i in 30:
		var mid := (lo + hi) * 0.5
		if _height_at(distance_m, speed, mid, k, a, gravity) > -drop_m:
			hi = mid
		else:
			lo = mid
	return (lo + hi) * 0.5


## Height (m, up positive) of the path above the muzzle at horizontal distance x.
static func _height_at(x: float, speed: float, elev_deg: float, k: float, a: AmmoData, gravity: float) -> float:
	var pos := Vector2.ZERO
	var vel := Vector2(cos(deg_to_rad(elev_deg)), -sin(deg_to_rad(elev_deg))) * speed
	var t := 0.0
	var dt := minf(DT, 2.0 / maxf(speed, 1.0))
	while pos.x < x and t < MAX_FLIGHT_S:
		var acc := Vector2(0.0, gravity) - vel * vel.length() * k
		var prev := pos
		vel += acc * dt
		pos += vel * dt
		t += dt
		if pos.x >= x:
			var f := (x - prev.x) / maxf(pos.x - prev.x, 1e-6)
			return -lerpf(prev.y, pos.y, f)
	return -INF
