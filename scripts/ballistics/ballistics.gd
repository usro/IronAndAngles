class_name Ballistics
extends RefCounted
## Entry points for the ballistics simulation. Pure functions, no nodes, no terrain dependency:
## the ground is reached through `hit_test(from_m: Vector2, to_m: Vector2) -> Dictionary`, which
## returns {} for no hit or {"position": Vector2, "normal": Vector2} for the first solid point.


## Runs a whole shot to the end and returns its trajectory (fragments included).
static func simulate(weapon: WeaponData, ammo: AmmoData, elevation_deg: float, charge: float,
		origin_m: Vector2, facing: int, weather: WeatherState, rng: RandomNumberGenerator,
		hit_test: Callable) -> Trajectory:
	return simulate_shot(
		ShotParams.create(weapon, ammo, elevation_deg, charge, origin_m, facing, weather, rng),
		hit_test)


## Like simulate(), with the optional settings of ShotParams (guidance target, bounds...).
static func simulate_shot(params: ShotParams, hit_test: Callable) -> Trajectory:
	var flight := ShellFlight.new(params, hit_test)
	flight.run_to_end()
	return flight.trajectory


## Starts a live shot for the battle to advance frame by frame (ShellFlight.advance(delta)).
static func launch(params: ShotParams, hit_test: Callable) -> ShellFlight:
	return ShellFlight.new(params, hit_test)


## The shot without any randomness (no spread, gusts or bounce deflection). For aim previews;
## does not touch params.rng.
static func predict(params: ShotParams, hit_test: Callable) -> Trajectory:
	var p := params.copy()
	p.nominal = true
	return simulate_shot(p, hit_test)


## A hit_test for a flat, endless ground at height y_m (tests, previews, AI estimates).
static func flat_ground(y_m: float) -> Callable:
	return func(from_m: Vector2, to_m: Vector2) -> Dictionary:
		if to_m.y < y_m or from_m.y > y_m:
			return {}
		var dy := to_m.y - from_m.y
		var f := 0.0 if dy <= 0.0 else (y_m - from_m.y) / dy
		return {"position": Vector2(lerpf(from_m.x, to_m.x, f), y_m), "normal": Vector2.UP}


## A hit_test that never hits anything.
static func no_ground() -> Callable:
	return func(_from_m: Vector2, _to_m: Vector2) -> Dictionary:
		return {}


## The projectile a shrapnel fragment is simulated as: a small steel sphere that does not bounce.
static func make_fragment_ammo(ammo: AmmoData) -> AmmoData:
	var a := AmmoData.new()
	a.id = StringName(String(ammo.id) + "_fragment")
	a.display_name = ammo.display_name + " fragment"
	a.era = ammo.era
	a.damage_type = GameConstants.DamageType.SHRAPNEL
	a.cost_per_shell = 0
	a.mass_kg = maxf(ammo.fragment_mass_kg, 0.001)
	var radius := pow(3.0 * a.mass_kg / (4.0 * PI * ShellFlight.FRAGMENT_DENSITY_KG_M3), 1.0 / 3.0)
	a.cross_section_m2 = PI * radius * radius
	a.drag_coefficient = ShellFlight.FRAGMENT_DRAG_COEFFICIENT
	a.wind_sensitivity = ammo.wind_sensitivity
	a.damage = ammo.damage / maxi(ammo.fragment_count, 1)
	a.explosion_radius_m = 0.0
	a.crater_radius_m = 0.0
	return a


## Bounded random value in [-1, 1], peaked at 0 (sum of two uniforms). Used for spread and bounce
## deflection so outliers are rare but never unbounded.
static func triangular(rng: RandomNumberGenerator) -> float:
	return (rng.randf_range(-1.0, 1.0) + rng.randf_range(-1.0, 1.0)) * 0.5
