extends TestCase
## Content integrity and balance: references resolve, eras match the GDD, contracts are winnable and
## shells cost enough that misses hurt.

## Allowed band for the cheapest same-era par cost (perfect accuracy) as a share of payout. See data/BALANCE.md.
const PAR_SHARE_MIN := 0.08
const PAR_SHARE_MAX := 0.20


class FakeRegistry:
	var weapons := {}
	var ammo := {}
	var tech := {}
	var contracts := {}
	var plots := {}
	var rivals := {}


func test_content_validator_passes() -> void:
	var errors := ContentValidator.validate(DataRegistry)
	assert_true(errors.is_empty(), "content errors:\n  " + "\n  ".join(errors))


func test_content_validator_catches_broken_references() -> void:
	var reg := FakeRegistry.new()
	var w := WeaponData.new()
	w.id = &"gun"
	w.allowed_ammo = [&"ghost_shell"]
	reg.weapons[w.id] = w
	var t := TechNodeData.new()
	t.id = &"t"
	t.prerequisites = [&"nowhere"]
	t.unlocks_weapons = [&"ghost_gun"]
	reg.tech[t.id] = t
	var errors := " ".join(ContentValidator.validate(reg))
	assert_true(errors.contains("ghost_shell"), "unknown ammo reported")
	assert_true(errors.contains("nowhere"), "unknown prerequisite reported")
	assert_true(errors.contains("ghost_gun"), "unknown unlock reported")
	assert_true(errors.contains("no era_gate"), "missing era gates reported")


func test_sample_ids_still_exist() -> void:
	for id in [&"trebuchet"]:
		assert_not_null(DataRegistry.get_weapon(id), String(id))
	assert_not_null(DataRegistry.get_ammo(&"stone_ball"))
	assert_not_null(DataRegistry.get_tech(&"early_mortar"))
	assert_not_null(DataRegistry.get_plot(&"river_ridge"))
	assert_not_null(DataRegistry.get_contract(&"siege_of_aldmoor"))
	assert_not_null(DataRegistry.get_rival(&"marshal_voss"))


func test_every_era_has_content() -> void:
	for era in GameConstants.Era.values():
		var w := DataRegistry.weapons.values().filter(func(x): return x.era == era).size()
		var a := DataRegistry.ammo.values().filter(func(x): return x.era == era).size()
		var c := DataRegistry.contracts.values().filter(func(x): return x.era_required == era).size()
		assert_true(w >= 2, "era %d weapons: %d" % [era, w])
		assert_true(a >= 2, "era %d ammo: %d" % [era, a])
		assert_true(c >= 2, "era %d contracts: %d" % [era, c])
	assert_eq(DataRegistry.rivals.size(), 3, "rival count")


func test_every_item_is_base_or_unlocked_by_one_node() -> void:
	var tree := TechTree.new(PlayerState.new(), DataRegistry.tech)
	for id in DataRegistry.weapons:
		var n := tree.unlocked_by(id).size()
		assert_true(n <= 1, "weapon %s unlocked by %d nodes" % [id, n])
		if n == 0:
			assert_eq(DataRegistry.get_weapon(id).era, GameConstants.Era.MEDIEVAL, "base weapon %s must be medieval" % id)
	for id in DataRegistry.ammo:
		var n := tree.unlocked_by(id).size()
		assert_true(n <= 1, "ammo %s unlocked by %d nodes" % [id, n])
		if n == 0:
			assert_eq(DataRegistry.get_ammo(id).era, GameConstants.Era.MEDIEVAL, "base ammo %s must be medieval" % id)


## Unlocking a node that grants ammo must leave the player able to buy something that fires it.
func test_unlocked_ammo_has_a_launcher() -> void:
	for node: TechNodeData in DataRegistry.tech.values():
		var p := PlayerState.new()
		p.unlocked_tech.assign(_ancestors(node.id))
		var tree := TechTree.new(p, DataRegistry.tech)
		var guns := tree.purchasable_weapons(DataRegistry.weapons.keys())
		for ammo_id in node.unlocks_ammo:
			var fired := guns.any(func(w): return DataRegistry.get_weapon(w).allowed_ammo.has(ammo_id))
			assert_true(fired, "%s unlocks %s but no purchasable weapon fires it" % [node.id, ammo_id])
	for ammo_id in DataRegistry.ammo:
		var used := DataRegistry.weapons.values().any(func(w): return w.allowed_ammo.has(ammo_id))
		assert_true(used, "no weapon fires %s" % ammo_id)


func test_era_traits_match_design() -> void:
	for w: WeaponData in DataRegistry.weapons.values():
		match w.era:
			GameConstants.Era.MEDIEVAL:
				assert_true(w.elevation_min_deg >= 30.0, "%s: medieval arcs are high" % w.id)
				assert_true(w.spread_deg >= 1.0, "%s: medieval engines are imprecise" % w.id)
			GameConstants.Era.INDUSTRIAL:
				assert_true(w.muzzle_velocity_max >= 250.0, "%s: industrial guns are fast" % w.id)
			GameConstants.Era.EXPERIMENTAL:
				assert_true(w.energy_cost_per_shot > 0, "%s: experimental weapons cost energy" % w.id)
				assert_true(w.cooldown >= 15.0, "%s: experimental weapons have long cooldowns" % w.id)
		for ammo_id in w.allowed_ammo:
			if w.launcher_type in [GameConstants.LauncherType.RAILGUN, GameConstants.LauncherType.ORBITAL]:
				assert_eq(DataRegistry.get_ammo(ammo_id).wind_sensitivity, 0.0, "%s/%s: no wind drift" % [w.id, ammo_id])
	for a: AmmoData in DataRegistry.ammo.values():
		if a.era == GameConstants.Era.MEDIEVAL:
			assert_true(a.wind_sensitivity >= 1.0, "%s: medieval shot is wind-heavy" % a.id)
	assert_true(DataRegistry.get_weapon(&"mlrs_launcher").salvo_size > 1, "MLRS fires salvos")
	assert_true(DataRegistry.get_ammo(&"laser_guided_shell").guided, "laser-guided shell is guided")
	assert_true(DataRegistry.get_ammo(&"rocket_he").thrust_n > 0.0, "rockets have thrust")
	assert_true(DataRegistry.get_ammo(&"shrapnel_shell").fragment_count > 0, "shrapnel bursts")
	assert_eq(DataRegistry.get_ammo(&"ap_shell").damage_type, GameConstants.DamageType.ARMOR_PIERCING)
	assert_true(DataRegistry.get_ammo(&"stone_ball").max_bounces > 0, "stone balls bounce")


## Cheapest same-era par cost (every shot a hit) must sit in a band of the payout, so a typical
## one-in-three hit rate eats a third or more of it and a bad day loses money.
func test_shell_costs_make_misses_hurt() -> void:
	for c: ContractData in DataRegistry.contracts.values():
		var best := INF
		for w: WeaponData in DataRegistry.weapons.values():
			if w.era != c.era_required:
				continue
			for ammo_id in w.allowed_ammo:
				var a := DataRegistry.get_ammo(ammo_id)
				var hits := c.target_count * ceili(c.target_health / a.damage)
				best = minf(best, hits * (a.cost_per_shell + w.energy_cost_per_shot))
		var share := best / c.payout
		assert_true(share >= PAR_SHARE_MIN and share <= PAR_SHARE_MAX,
			"%s: par cost %d is %.1f%% of payout %d" % [c.id, best, share * 100.0, c.payout])


## Every plot of every contract can be reached by some same-era weapon (orbital excluded: its
## launch model belongs to ballistics). Point-mass check with quadratic drag and no wind, not
## the real ballistics model, so it only catches gross mistakes.
func test_contract_plots_are_in_range() -> void:
	for c: ContractData in DataRegistry.contracts.values():
		for plot in c.plots:
			var reachable := false
			for w: WeaponData in DataRegistry.weapons.values():
				if w.era != c.era_required or w.launcher_type == GameConstants.LauncherType.ORBITAL:
					continue
				for ammo_id in w.allowed_ammo:
					var span := _range_span(w, DataRegistry.get_ammo(ammo_id), plot)
					if span.x <= plot.target_distance_m and plot.target_distance_m <= span.y:
						reachable = true
			assert_true(reachable, "%s/%s at %.0f m: out of range" % [c.id, plot.id, plot.target_distance_m])


func _ancestors(id: StringName) -> Array[StringName]:
	var out: Array[StringName] = [id]
	var i := 0
	while i < out.size():
		for p in DataRegistry.get_tech(out[i]).prerequisites:
			if not out.has(p):
				out.append(p)
		i += 1
	return out


## Min and max landing distance over a grid of elevations and charges, landing height_advantage below the muzzle.
static func _range_span(w: WeaponData, a: AmmoData, plot: PlotData) -> Vector2:
	var rho := GameConstants.SEA_LEVEL_AIR_DENSITY * exp(-plot.altitude_m / 8500.0)
	var k := 0.5 * rho * a.drag_coefficient * a.cross_section_m2 / a.mass_kg
	var lo := INF
	var hi := -INF
	var elev := w.elevation_min_deg
	while elev <= w.elevation_max_deg + 0.001:
		for charge in [0.0, 0.25, 0.5, 0.75, 1.0]:
			var x := _land_x(w.velocity_for_charge(charge), elev, k, a, plot.height_advantage_m)
			if not is_nan(x):
				lo = minf(lo, x)
				hi = maxf(hi, x)
		elev += 1.0
	return Vector2(lo, hi)


## +y is down; returns NaN if the shell never comes back down to the target plane in 60 s.
static func _land_x(speed: float, elev_deg: float, k: float, a: AmmoData, drop_m: float) -> float:
	const DT := 1.0 / 120.0
	var pos := Vector2.ZERO
	var vel := Vector2(cos(deg_to_rad(elev_deg)), -sin(deg_to_rad(elev_deg))) * speed
	var t := 0.0
	# The target plane only counts once the shell has been above it (uphill shots start below it).
	var above := drop_m >= 0.0
	while t < 60.0:
		var acc := Vector2(0.0, GameConstants.STANDARD_GRAVITY) - vel * vel.length() * k
		if t < a.burn_time and vel.length() > 0.0:
			acc += vel.normalized() * a.thrust_n / a.mass_kg
		vel += acc * DT
		pos += vel * DT
		t += DT
		above = above or pos.y < drop_m
		if above and vel.y > 0.0 and pos.y >= drop_m:
			return pos.x
	return NAN


## Lobbing guns of the Modern era must use their whole charge dial on the era's plots: full charge
## reaches the farthest plot with headroom, but not absurdly far, and minimum charge lands short of
## the nearest one in thin air. (Was 150-420 m/s: 10 km at full charge, 90% of the dial useless.)
func test_modern_howitzer_charge_dial_fits_the_era() -> void:
	var r := PlotGenerator.EraRanges.for_era(GameConstants.Era.MODERN, DataRegistry.contracts.values())
	for w: WeaponData in DataRegistry.weapons.values():
		if w.era != GameConstants.Era.MODERN or w.launcher_type != GameConstants.LauncherType.GUNPOWDER:
			continue
		for ammo_id in w.allowed_ammo:
			var a := DataRegistry.get_ammo(ammo_id)
			var far := PlotData.new()
			far.altitude_m = r.altitude_m.x
			far.height_advantage_m = r.height_m.x
			var reach := PlotGenerator.max_range_m(w, a, far)
			assert_true(reach >= r.distance_m.y * 1.3 and reach <= r.distance_m.y * 3.0,
				"%s/%s full charge reaches %.0f m vs farthest plot %.0f m" % [w.id, ammo_id, reach, r.distance_m.y])
			var weak: WeaponData = w.duplicate()
			weak.muzzle_velocity_max = w.muzzle_velocity_min
			var near := PlotData.new()
			near.altitude_m = r.altitude_m.y
			near.height_advantage_m = r.height_m.y
			var short := PlotGenerator.max_range_m(weak, a, near)
			assert_true(short < r.distance_m.x,
				"%s/%s minimum charge already reaches %.0f m (nearest plot %.0f m)" % [w.id, ammo_id, short, r.distance_m.x])
