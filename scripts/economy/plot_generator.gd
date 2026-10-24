class_name PlotGenerator
extends RefCounted
## Makes fresh PlotData for the weekly auction. Pure: pass the content tables and a seeded RNG.
##
## Every number is drawn from the era's handcrafted plots and contracts (EraRanges), so generated
## plots stay inside the balance the content was tuned for (data/BALANCE.md). A plot is only
## accepted if the era's reference weapon (its cheapest non-orbital gun) can reach it with margin.

## A generated plot must lie within this share of the reference weapon's maximum range.
const REACH_MARGIN := 0.92
const MAX_ATTEMPTS := 12
## Coarse integration step for range checks; accurate to a few meters, fast enough for every offer.
const RANGE_DT := 1.0 / 30.0

const NAME_PREFIXES := {
	GameConstants.Era.MEDIEVAL: ["Ash", "Crow", "Raven", "Elder", "Thorn", "Wolf", "Briar", "Heron",
		"Stag", "Monk's", "Abbot's", "King's", "Fen", "Oak", "Black", "Grey", "Saint Ebb's", "Mill"],
	GameConstants.Era.INDUSTRIAL: ["Coalbrook", "Ironvale", "Sutter", "Brannock", "Kettering", "Halloway",
		"Pike", "Gantry", "Slagheap", "Furnace", "Lockwood", "Canal", "Wexford", "Marrow"],
}
const NAME_SUFFIXES := {
	GameConstants.TerrainProfile.FLAT: ["Flats", "Fields", "Plain", "Meadow", "Levels"],
	GameConstants.TerrainProfile.HILLS: ["Hills", "Downs", "Knolls", "Rise", "Barrows"],
	GameConstants.TerrainProfile.RIDGE: ["Ridge", "Crest", "Spine", "Edge", "Scarp"],
	GameConstants.TerrainProfile.VALLEY: ["Vale", "Hollow", "Dale", "Bottom", "Ford"],
	GameConstants.TerrainProfile.MOUNTAIN: ["Peak", "Pass", "Crag", "Heights", "Tor"],
}
const GRID_WORDS := ["Kilo", "Oscar", "Tango", "Sierra", "Delta", "Echo", "Victor", "Lima", "Zulu",
	"Hotel", "Juliet", "Romeo"]
const PROFILE_WORDS := {
	GameConstants.TerrainProfile.FLAT: "Flats",
	GameConstants.TerrainProfile.HILLS: "Hills",
	GameConstants.TerrainProfile.RIDGE: "Ridge",
	GameConstants.TerrainProfile.VALLEY: "Basin",
	GameConstants.TerrainProfile.MOUNTAIN: "Massif",
}


## The spread of an era's handcrafted content, used as bounds for generated plots and weather.
class EraRanges:
	var era: GameConstants.Era
	var distance_m := Vector2(INF, -INF)
	var height_m := Vector2(INF, -INF)
	var altitude_m := Vector2(INF, -INF)
	var profiles: Array[GameConstants.TerrainProfile] = []
	var wind_max := 0.0
	var gust_max := 0.0
	var rain_max := 0.0

	static func for_era(p_era: GameConstants.Era, contracts: Array) -> EraRanges:
		var r := EraRanges.new()
		r.era = p_era
		for c: ContractData in contracts:
			if c.era_required != p_era:
				continue
			if c.weather:
				r.wind_max = maxf(r.wind_max, absf(c.weather.wind_speed))
				r.gust_max = maxf(r.gust_max, c.weather.gust_strength)
				r.rain_max = maxf(r.rain_max, c.weather.rain_intensity)
			for p in c.plots:
				r.distance_m = Vector2(minf(r.distance_m.x, p.target_distance_m), maxf(r.distance_m.y, p.target_distance_m))
				r.height_m = Vector2(minf(r.height_m.x, p.height_advantage_m), maxf(r.height_m.y, p.height_advantage_m))
				r.altitude_m = Vector2(minf(r.altitude_m.x, p.altitude_m), maxf(r.altitude_m.y, p.altitude_m))
				if not r.profiles.has(p.terrain_profile):
					r.profiles.append(p.terrain_profile)
		# Gentle ground is always fair game; ridges and mountains only where the era already has them.
		for gentle in [GameConstants.TerrainProfile.FLAT, GameConstants.TerrainProfile.HILLS,
				GameConstants.TerrainProfile.VALLEY]:
			if not r.profiles.has(gentle):
				r.profiles.append(gentle)
		r.profiles.sort()
		return r

	func is_valid() -> bool:
		return distance_m.x <= distance_m.y


## The weapon and ammo a player entering `era` can count on: the cheapest non-orbital weapon of
## that era with its cheapest allowed ammo. Returns [] if the era has none.
static func reference_loadout(era: GameConstants.Era, weapons: Dictionary, ammo: Dictionary) -> Array:
	var best: WeaponData
	for w: WeaponData in weapons.values():
		if w.era != era or w.launcher_type == GameConstants.LauncherType.ORBITAL or w.allowed_ammo.is_empty():
			continue
		if best == null or w.purchase_cost < best.purchase_cost \
				or (w.purchase_cost == best.purchase_cost and w.id < best.id):
			best = w
	if best == null:
		return []
	var shell: AmmoData
	for id in best.allowed_ammo:
		var a: AmmoData = ammo.get(id)
		if a and (shell == null or a.cost_per_shell < shell.cost_per_shell):
			shell = a
	return [best, shell] if shell else []


## A new plot for `era`, drawn from `ranges`. `loadout` ([WeaponData, AmmoData]) guards reach;
## pass [] to skip the check. `serial` makes the id unique (e.g. week * 10 + index).
static func generate(ranges: EraRanges, loadout: Array, rng: RandomNumberGenerator, serial: int) -> PlotData:
	var plot := PlotData.new()
	plot.id = StringName("gen_plot_%d" % serial)
	plot.terrain_seed = rng.randi()
	plot.terrain_profile = ranges.profiles[rng.randi_range(0, ranges.profiles.size() - 1)]
	plot.altitude_m = snappedf(rng.randf_range(ranges.altitude_m.x, ranges.altitude_m.y), 5.0)
	plot.map_position = Vector2(rng.randf_range(0.08, 0.7), rng.randf_range(0.14, 0.86))
	var distance_hi := ranges.distance_m.y
	for attempt in MAX_ATTEMPTS:
		plot.target_distance_m = snappedf(rng.randf_range(ranges.distance_m.x, distance_hi), 5.0)
		plot.height_advantage_m = snappedf(rng.randf_range(ranges.height_m.x, ranges.height_m.y), 1.0)
		if loadout.is_empty() or plot.target_distance_m <= max_range_m(loadout[0], loadout[1], plot) * REACH_MARGIN:
			break
		# Out of reach: pull the far bound in toward the near one and try again.
		distance_hi = lerpf(ranges.distance_m.x, distance_hi, 0.8)
		if attempt == MAX_ATTEMPTS - 1:
			plot.target_distance_m = ranges.distance_m.x
			plot.height_advantage_m = maxf(plot.height_advantage_m, 0.0)
	plot.display_name = place_name(ranges.era, plot.terrain_profile, rng)
	plot.description = "%s, %.0f m to the target zone, %+.0f m above it." % [
		GameConstants.TerrainProfile.keys()[plot.terrain_profile].capitalize(), plot.target_distance_m,
		plot.height_advantage_m]
	return plot


## A WeatherState inside the era's bounds.
static func weather(ranges: EraRanges, rng: RandomNumberGenerator) -> WeatherState:
	var w := WeatherState.new()
	var wind_cap := maxf(ranges.wind_max, 2.0)
	w.wind_speed = snappedf(rng.randf_range(-wind_cap, wind_cap), 0.5)
	w.gust_strength = snappedf(rng.randf_range(0.5, maxf(ranges.gust_max, 1.0)), 0.5)
	# Rain on about a third of days, never wetter than the era's wettest handcrafted contract.
	w.rain_intensity = snappedf(rng.randf_range(0.1, maxf(ranges.rain_max, 0.3)), 0.05) if rng.randf() < 0.33 else 0.0
	return w


static func place_name(era: GameConstants.Era, profile: GameConstants.TerrainProfile, rng: RandomNumberGenerator) -> String:
	if NAME_PREFIXES.has(era):
		var prefixes: Array = NAME_PREFIXES[era]
		var suffixes: Array = NAME_SUFFIXES[profile]
		return "%s %s" % [prefixes[rng.randi_range(0, prefixes.size() - 1)], suffixes[rng.randi_range(0, suffixes.size() - 1)]]
	# Modern and experimental theatres are map grid references.
	return "Grid %s-%02d %s" % [GRID_WORDS[rng.randi_range(0, GRID_WORDS.size() - 1)], rng.randi_range(1, 99),
		PROFILE_WORDS[profile]]


## Farthest landing distance (meters) at full charge over the weapon's elevation range, landing
## `plot.height_advantage_m` below the muzzle. Point mass, quadratic drag, rocket thrust, no wind.
static func max_range_m(w: WeaponData, a: AmmoData, plot: PlotData) -> float:
	var rho := GameConstants.SEA_LEVEL_AIR_DENSITY * exp(-plot.altitude_m / 8500.0)
	var k := 0.5 * rho * a.drag_coefficient * a.cross_section_m2 / a.mass_kg
	var best := 0.0
	var elev := w.elevation_min_deg
	while elev <= w.elevation_max_deg + 0.001:
		var x := _land_x(w.muzzle_velocity_max, elev, k, a, plot.height_advantage_m)
		if not is_nan(x):
			best = maxf(best, x)
		elev += 2.0
	return best


## +y is down; NaN if the shell never comes back down to the target plane within 60 s.
static func _land_x(speed: float, elev_deg: float, k: float, a: AmmoData, drop_m: float) -> float:
	var pos := Vector2.ZERO
	var vel := Vector2(cos(deg_to_rad(elev_deg)), -sin(deg_to_rad(elev_deg))) * speed
	var t := 0.0
	# Uphill shots only count once the shell has climbed above the target plane.
	var above := drop_m >= 0.0
	while t < 60.0:
		var acc := Vector2(0.0, GameConstants.STANDARD_GRAVITY) - vel * vel.length() * k
		if t < a.burn_time and vel.length() > 0.0:
			acc += vel.normalized() * a.thrust_n / a.mass_kg
		var prev := pos
		vel += acc * RANGE_DT
		pos += vel * RANGE_DT
		t += RANGE_DT
		above = above or pos.y < drop_m
		if above and vel.y > 0.0 and pos.y >= drop_m:
			# Interpolate the crossing inside the coarse step.
			var f := (drop_m - prev.y) / maxf(pos.y - prev.y, 1e-6)
			return lerpf(prev.x, pos.x, clampf(f, 0.0, 1.0))
	return NAN
