class_name BattleRules
extends RefCounted
## Pure battle rules: blast damage, counter-battery reveal and battlefield weather.
## No nodes, no autoloads, so tests and the AI can use them directly.

## Targets are boxes standing on the ground: width x height in meters.
const TARGET_SIZE_M := Vector2(4.0, 3.0)
## Battery weapons are boxes too (enemy shells can strike them directly).
const MOUNT_SIZE_M := Vector2(3.0, 2.0)
## Within this distance of a box a blast does full damage. Shells with no blast radius
## (shrapnel fragments) only damage what they touch, up to this distance.
const CONTACT_RADIUS_M := 0.5
## Counter-battery: every shot raises reveal_level by this much...
const REVEAL_PER_SHOT := 0.05
## ...and a shell that damages nothing raises it by this much more when it settles.
const REVEAL_PER_MISS := 0.08
## A bounce strikes with this share of the shell's damage and digs this share of its crater.
const BOUNCE_DAMAGE_SCALE := 0.5
const BOUNCE_CRATER_SCALE := 0.4


## Damage a blast of `ammo` does to something `distance_m` away (measured to the edge of its box).
## Full damage within CONTACT_RADIUS_M, then linear falloff to 0 over explosion_radius_m.
## Incendiary damage is reduced by rain (rain_factor).
static func blast_damage(ammo: AmmoData, distance_m: float, rain_intensity: float = 0.0) -> float:
	var full := ammo.damage * rain_factor(ammo, rain_intensity)
	var d := maxf(distance_m, 0.0)
	if d <= CONTACT_RADIUS_M:
		return full
	var r := ammo.explosion_radius_m
	if r <= 0.0:
		return 0.0
	return full * maxf(0.0, 1.0 - (d - CONTACT_RADIUS_M) / r)


## Multiplier on an ammo's damage under rain: incendiary loses rain_penalty per unit of rain.
static func rain_factor(ammo: AmmoData, rain_intensity: float) -> float:
	if ammo.damage_type != GameConstants.DamageType.INCENDIARY:
		return 1.0
	return clampf(1.0 - ammo.rain_penalty * clampf(rain_intensity, 0.0, 1.0), 0.0, 1.0)


## Distance from a point to a rectangle (0 inside or on the edge).
static func distance_to_rect(point: Vector2, rect: Rect2) -> float:
	var dx := maxf(maxf(rect.position.x - point.x, 0.0), point.x - rect.end.x)
	var dy := maxf(maxf(rect.position.y - point.y, 0.0), point.y - rect.end.y)
	return sqrt(dx * dx + dy * dy)


## Box of something standing on the ground at ground_m (bottom centre), +y down.
static func standing_rect(ground_m: Vector2, size_m: Vector2) -> Rect2:
	return Rect2(ground_m - Vector2(size_m.x * 0.5, size_m.y), size_m)


## Reveal level after a shot, or after a missed shot settles.
static func reveal_after_shot(level: float) -> float:
	return minf(1.0, level + REVEAL_PER_SHOT)


static func reveal_after_miss(level: float) -> float:
	return minf(1.0, level + REVEAL_PER_MISS)


## Air density at the battlefield (y = 0) from a sea-level density and the plot's altitude.
static func air_density_at(sea_level_density: float, altitude_m: float) -> float:
	return sea_level_density * exp(-altitude_m / ShellFlight.AIR_SCALE_HEIGHT_M)


## The battle's weather: a copy of the contract's (treated as sea-level air) with the density
## lowered for the plot's altitude. Never modifies the contract's resource.
static func battle_weather(contract: ContractData, plot: PlotData) -> WeatherState:
	var w: WeatherState = contract.weather.duplicate() if contract != null and contract.weather != null \
			else WeatherState.new()
	w.air_density = air_density_at(w.air_density, plot.altitude_m if plot != null else 0.0)
	return w


## First point where segment from->to enters rect, as {"position", "normal"}, or {} if it doesn't.
## A segment starting inside the rect is ignored (so a burst on a box doesn't stick to it).
static func segment_enters_rect(from: Vector2, to: Vector2, rect: Rect2) -> Dictionary:
	if rect.has_point(from):
		return {}
	var d := to - from
	var t_enter := 0.0
	var t_exit := 1.0
	var normal := Vector2.UP
	for axis in 2:
		var p := from[axis]
		var v := d[axis]
		var lo := rect.position[axis]
		var hi := rect.end[axis]
		if absf(v) < 1e-9:
			if p < lo or p > hi:
				return {}
			continue
		var t0 := (lo - p) / v
		var t1 := (hi - p) / v
		var n := Vector2.ZERO
		n[axis] = -1.0
		if t0 > t1:
			var tmp := t0
			t0 = t1
			t1 = tmp
			n[axis] = 1.0
		if t0 > t_enter:
			t_enter = t0
			normal = n
		t_exit = minf(t_exit, t1)
		if t_enter > t_exit:
			return {}
	return {"position": from + d * t_enter, "normal": normal, "t": t_enter}
