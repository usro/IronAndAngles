class_name ShotParams
extends RefCounted
## Everything needed to fire one shell. Build with ShotParams.create(), then set the optional
## fields (guidance target, world bounds...) before handing it to Ballistics or ShellFlight.

var weapon: WeaponData
var ammo: AmmoData
## Dialed elevation in degrees above the horizontal, toward `facing`. Clamped to the weapon's range.
var elevation_deg: float = 45.0
## Charge dial in [0, 1], mapped to muzzle velocity by WeaponData.velocity_for_charge().
var charge: float = 1.0
var origin_m: Vector2 = Vector2.ZERO
## +1 fires toward +x (right), -1 toward -x (left).
var facing: int = 1
var weather: WeatherState
## Source of spread, gusts, bounce deflection and fragment directions. Null = no randomness.
var rng: RandomNumberGenerator

## Laser designation for guided ammo. Vector2.INF = nothing designated (the shell flies ballistic).
var guidance_target_m: Vector2 = Vector2.INF
## y at which weather.air_density applies; density falls off with height above it. create() sets
## it to origin_m.y.
var reference_y_m: float = 0.0
## The flight ends (OUT_OF_BOUNDS) when the shell passes the left, right or bottom edge.
## The top edge is ignored, shells may leave the screen upward. Zero size = unbounded.
var world_bounds_m: Rect2 = Rect2()
## Safety cap on flight time, in seconds since launch.
var max_time: float = 60.0
var step: float = GameConstants.PHYSICS_STEP
## Nominal shot: no spread, no gusts, no bounce deflection, no rng draws. Used for previews and
## the aim solver.
var nominal: bool = false
## Record every step into Trajectory.points. Off for the solver, which only needs the end point.
var record_points: bool = true
## End at the first ground contact: no bounces, no fuse, no fragments (aim solver).
var stop_at_first_contact: bool = false
## Overrides elevation/charge/spread with a launch velocity (fragments). Vector2.INF = unused.
var initial_velocity_m: Vector2 = Vector2.INF
## Simulation clock at launch. Fragments start at their parent's burst time.
var start_time: float = 0.0


static func create(p_weapon: WeaponData, p_ammo: AmmoData, p_elevation_deg: float, p_charge: float,
		p_origin_m: Vector2, p_facing: int, p_weather: WeatherState,
		p_rng: RandomNumberGenerator) -> ShotParams:
	var p := ShotParams.new()
	p.weapon = p_weapon
	p.ammo = p_ammo
	p.elevation_deg = p_elevation_deg
	p.charge = p_charge
	p.origin_m = p_origin_m
	p.facing = 1 if p_facing >= 0 else -1
	p.weather = p_weather
	p.rng = p_rng
	p.reference_y_m = p_origin_m.y
	return p


func copy() -> ShotParams:
	var p := ShotParams.new()
	for prop in ["weapon", "ammo", "elevation_deg", "charge", "origin_m", "facing", "weather", "rng",
			"guidance_target_m", "reference_y_m", "world_bounds_m", "max_time", "step", "nominal",
			"record_points", "stop_at_first_contact", "initial_velocity_m", "start_time"]:
		p.set(prop, get(prop))
	return p
