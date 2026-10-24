class_name BattleSim
extends RefCounted
## The battle model: battery weapons, targets, live shells, orbital strikes, counter-battery fire
## and the end conditions. No nodes of its own; the battle scene feeds it input and frame time
## (tick) and draws its state. Tests drive it headless with a TerrainMap.
##
## The field is a Terrain node (in the scene: carve() emits EventBus.terrain_carved and the view
## redraws) or a bare TerrainMap (tests). Queries always go to the TerrainMap.

enum Outcome { NONE, VICTORY, DEFEAT }

## Orbital strikes land this long after the trigger, dropped from this height above the ground.
const ORBITAL_DELAY_S := 3.0
const ORBITAL_DROP_HEIGHT_M := 400.0
## The enemy gun stands this far right of the target zone, its muzzle this high above ground.
const ENEMY_STANDOFF_M := 12.0
const ENEMY_MUZZLE_HEIGHT_M := 2.0
## Enemy shells do this share of their ammo's damage (the defender is not a full battery).
const ENEMY_DAMAGE_SCALE := 0.5
## Seconds before the enemy brain is asked again after it held fire.
const ENEMY_RETRY_S := 1.0
## Battery weapons stand this far apart (closer if many share the pad).
const MOUNT_SPACING_M := 5.0
const MAX_FLIGHT_TIME_S := 60.0

## Set by the AI session to replace the default counter-battery brain (see EnemyBrain).
static var brain_factory: Callable

## A live shell started (player or enemy). Fragments come later through `flight.fragments`.
signal shell_launched(flight: ShellFlight, enemy: bool)
## Something went off at position_m (impact, bounce, airburst). For the view.
signal blast(position_m: Vector2, radius_m: float, kind: StringName)
signal ended(victory: bool, reason: String)

var contract: ContractData
var plot: PlotData
var player: PlayerState
var weather: WeatherState
var map: TerrainMap
var mounts: Array[WeaponMount] = []
var targets: Array[BattleTarget] = []
var selected: int = 0
## 0..1: how precisely the defender knows the battery's position.
var reveal_level: float = 0.0
var elapsed: float = 0.0
var outcome: Outcome = Outcome.NONE
var end_reason: String = ""
var result := BattleResult.new()
## Live top-level flights, player and enemy (fragments are advanced by their parent).
var flights: Array[ShellFlight] = []
## Pending orbital strikes: {"x": float, "time_left": float, "mount": WeaponMount, "ammo": AmmoData}.
var strikes: Array[Dictionary] = []
var ammo_table: Dictionary

var enemy_brain: EnemyBrain
var enemy_weapon: WeaponData
var enemy_ammo: AmmoData
var enemy_origin_m: Vector2 = Vector2.INF
var enemy_reload_left: float = 0.0
var enemy_last_impact_m: Vector2 = Vector2.INF

var _field: Object
var _rng := RandomNumberGenerator.new()
var _enemy_rng := RandomNumberGenerator.new()
## ShellFlight (shell or fragment) -> shot record {"root", "enemy", "orbital", "hit", "ammo"}.
var _shots: Dictionary = {}


## field: a Terrain (already built) or a TerrainMap. seed_value seeds every random draw in the
## battle; derive it from GameState.rng. weapons/ammo default to DataRegistry's tables.
func _init(p_contract: ContractData, p_plot: PlotData, p_player: PlayerState, field: Object,
		seed_value: int, weapons: Dictionary = {}, ammo: Dictionary = {}) -> void:
	contract = p_contract
	plot = p_plot
	player = p_player
	_field = field
	map = field.map if field is Terrain else field
	ammo_table = ammo if not ammo.is_empty() else DataRegistry.ammo
	var weapon_table: Dictionary = weapons if not weapons.is_empty() else DataRegistry.weapons
	_rng.seed = seed_value
	_enemy_rng.seed = _rng.randi()
	weather = BattleRules.battle_weather(contract, plot)
	result.contract_id = contract.id
	result.plot_id = plot.id if plot else &""
	_place_mounts(weapon_table)
	_place_targets()
	_setup_enemy(weapon_table)


## Emits the battle's opening facts. Call once after construction.
func start() -> void:
	EventBus.battle_started.emit(contract, plot)
	EventBus.weather_changed.emit(weather)
	EventBus.battery_revealed.emit(reveal_level)


# --- Player controls ---

func selected_mount() -> WeaponMount:
	return mounts[selected] if selected < mounts.size() else null


func select_next_weapon(step: int = 1) -> void:
	if not mounts.is_empty():
		selected = posmod(selected + step, mounts.size())


## Allowed ammo of a weapon that exists in the content, in the weapon's order.
func ammo_choices(mount: WeaponMount) -> Array[StringName]:
	var out: Array[StringName] = []
	for id in mount.weapon.allowed_ammo:
		if ammo_table.has(id):
			out.append(id)
	return out


func cycle_ammo(step: int = 1) -> void:
	var m := selected_mount()
	if m == null:
		return
	var choices := ammo_choices(m)
	if choices.is_empty():
		return
	var i := choices.find(m.ammo_id)
	m.ammo_id = choices[posmod(i + step, choices.size())]


## ORBITAL: moves the designated x, kept inside the field.
func adjust_designator(m: WeaponMount, dx_m: float) -> void:
	var b := bounds_m()
	m.designated_x_m = clampf(m.designated_x_m + dx_m, b.position.x, b.end.x)


## Pulls the selected weapon's trigger. The first shell (or the orbital designation) goes at once.
func pull_trigger() -> bool:
	if outcome != Outcome.NONE:
		return false
	var m := selected_mount()
	if m == null or not m.is_ready() or m.ammo_id == &"" or player.ammo_count(m.ammo_id) <= 0:
		return false
	if not m.pull_trigger():
		return false
	_fire_due(m, m.tick(0.0))
	return true


## Gives up the contract (counts as a defeat).
func retreat() -> void:
	_end(false, "Retreated")


# --- Simulation ---

func tick(delta: float) -> void:
	if outcome != Outcome.NONE:
		return
	elapsed += delta
	for m in mounts:
		var due := m.tick(delta)
		if due > 0:
			_fire_due(m, due)
	_tick_strikes(delta)
	_tick_enemy(delta)
	_advance_flights(delta)
	_check_outcome()


## Damages targets (player blast) or battery weapons (enemy blast) around position_m.
## Returns total damage dealt. Public for tests.
func apply_blast(ammo: AmmoData, position_m: Vector2, scale: float = 1.0, enemy: bool = false) -> float:
	var total := 0.0
	if enemy:
		for m in mounts:
			if not m.is_alive():
				continue
			var dmg := BattleRules.blast_damage(ammo, BattleRules.distance_to_rect(position_m, m.rect_m()),
				weather.rain_intensity) * scale * ENEMY_DAMAGE_SCALE
			var lost := minf(dmg, m.health)
			if lost <= 0.0:
				continue
			m.health -= lost
			total += lost
			result.damage_taken[m.weapon.id] = result.damage_taken.get(m.weapon.id, 0.0) + lost
			EventBus.battery_damaged.emit(m.weapon.id, lost)
		return total
	for t in targets:
		if t.is_destroyed():
			continue
		var dmg := BattleRules.blast_damage(ammo, BattleRules.distance_to_rect(position_m, t.rect_m()),
			weather.rain_intensity) * scale
		var lost := t.apply_damage(dmg)
		if lost <= 0.0:
			continue
		total += lost
		EventBus.target_hit.emit(t.id, lost)
		if t.is_destroyed():
			result.targets_destroyed += 1
			EventBus.target_destroyed.emit(t.id)
	return total


func targets_left() -> int:
	return targets.filter(func(t: BattleTarget) -> bool: return not t.is_destroyed()).size()


func bounds_m() -> Rect2:
	return Rect2(map.origin_m, map.size_m())


func target_zone_center_m() -> Vector2:
	return map.target_zone_center_m()


func battery_position_m() -> Vector2:
	return map.battery_position_m()


## True while a player shell or strike is still out there.
func player_shots_pending() -> bool:
	if not strikes.is_empty():
		return true
	for f in flights:
		var rec: Dictionary = _shots.get(f, {})
		if not rec.get("enemy", false):
			return true
	return false


func is_enemy_flight(flight: ShellFlight) -> bool:
	return _shots.get(flight, {}).get("enemy", false)


## Emits battle_ended and applies the result to the campaign (the Battle -> Results contract,
## minus the scene change, which the scene does).
func commit() -> BattleResult:
	EventBus.battle_ended.emit(result)
	GameState.apply_battle_result(result)
	return result


# --- Setup ---

func _place_mounts(weapon_table: Dictionary) -> void:
	var owned: Array[WeaponData] = []
	for id in player.owned_weapons:
		var w: WeaponData = weapon_table.get(id)
		if w != null:
			owned.append(w)
	var n := owned.size()
	var spacing := MOUNT_SPACING_M if n <= 1 else minf(MOUNT_SPACING_M,
		(TerrainGenerator.BATTERY_PAD_HALF_M * 2.0 - BattleRules.MOUNT_SIZE_M.x) / (n - 1))
	var base := map.battery_position_m()
	for i in n:
		var w := owned[i]
		var x := base.x + (i - (n - 1) * 0.5) * spacing
		var m := WeaponMount.new(w, Vector2(x, map.surface_height_at(x)),
			float(player.weapon_health.get(w.id, w.max_health)))
		m.designated_x_m = map.target_zone_center_m().x
		for id in ammo_choices(m):
			if player.ammo_count(id) > 0:
				m.ammo_id = id
				break
		if m.ammo_id == &"" and not ammo_choices(m).is_empty():
			m.ammo_id = ammo_choices(m)[0]
		mounts.append(m)
	# Start on the first weapon that can fire.
	for i in n:
		if mounts[i].is_alive() and player.ammo_count(mounts[i].ammo_id) > 0:
			selected = i
			break


func _place_targets() -> void:
	var count := maxi(contract.target_count, 1)
	var spots := map.target_positions_m(count)
	for i in spots.size():
		targets.append(BattleTarget.new(StringName("target_%d" % (i + 1)), spots[i], contract.target_health))


## The defender fields the cheapest non-orbital gun of the contract's era (deterministic, from
## content), firing its first allowed ammo.
func _setup_enemy(weapon_table: Dictionary) -> void:
	var candidates: Array[WeaponData] = []
	for w: WeaponData in weapon_table.values():
		if w.era == contract.era_required and w.launcher_type != GameConstants.LauncherType.ORBITAL:
			candidates.append(w)
	candidates.sort_custom(func(a: WeaponData, b: WeaponData) -> bool:
		return a.purchase_cost < b.purchase_cost or (a.purchase_cost == b.purchase_cost and a.id < b.id))
	for w in candidates:
		for id in w.allowed_ammo:
			if ammo_table.has(id):
				enemy_weapon = w
				enemy_ammo = ammo_table[id]
				break
		if enemy_weapon:
			break
	if enemy_weapon == null:
		return
	var x := minf(map.target_zone_max_x_m + ENEMY_STANDOFF_M, bounds_m().end.x - 1.0)
	enemy_origin_m = Vector2(x, map.surface_height_at(x) - ENEMY_MUZZLE_HEIGHT_M)
	enemy_reload_left = enemy_weapon.reload_time + enemy_weapon.cooldown
	if brain_factory.is_valid():
		enemy_brain = brain_factory.call()
	else:
		enemy_brain = SimpleEnemyBrain.new()


# --- Firing ---

func _fire_due(m: WeaponMount, count: int) -> void:
	for i in count:
		if not _fire_one(m):
			m.abort_salvo()
			return


## Fires one shell from m: consumes ammo, charges shell + energy cost, launches it.
func _fire_one(m: WeaponMount) -> bool:
	var ammo: AmmoData = ammo_table.get(m.ammo_id)
	if ammo == null or not player.consume_ammo(ammo.id):
		return false
	var cost := ammo.cost_per_shell + m.weapon.energy_cost_per_shot
	player.charge(cost, "Shell fired: %s" % ammo.display_name)
	result.shells_fired += 1
	result.ammo_spent += cost
	result.ammo_used[ammo.id] = result.ammo_used.get(ammo.id, 0) + 1
	EventBus.shot_fired.emit(m.weapon.id, ammo.id, cost)
	if m.is_orbital():
		# The platform is in orbit, not on the pad: designating a strike doesn't reveal the battery.
		strikes.append({"x": m.designated_x_m, "time_left": ORBITAL_DELAY_S, "mount": m, "ammo": ammo})
		return true
	var p := ShotParams.create(m.weapon, ammo, m.elevation_deg, m.charge, m.muzzle_m(), 1, weather,
		_child_rng(_rng))
	_configure(p)
	if ammo.guided:
		p.guidance_target_m = _designate_for(p)
	_launch(p, _player_hit_test, false, false)
	_raise_reveal(BattleRules.reveal_after_shot(reveal_level))
	return true


func _tick_strikes(delta: float) -> void:
	for s in strikes.duplicate():
		s["time_left"] -= delta
		if s.time_left > 0.0:
			continue
		strikes.erase(s)
		var m: WeaponMount = s.mount
		var ammo: AmmoData = s.ammo
		var rng := _child_rng(_rng)
		var scatter := Ballistics.triangular(rng) * tan(deg_to_rad(m.weapon.spread_deg)) * ORBITAL_DROP_HEIGHT_M
		var x: float = s.x + scatter
		var origin := Vector2(x, map.surface_height_at(x) - ORBITAL_DROP_HEIGHT_M)
		var p := ShotParams.create(m.weapon, ammo, 90.0, m.charge, origin, 1, weather, rng)
		p.initial_velocity_m = Vector2(0.0, m.muzzle_velocity())
		_configure(p)
		_launch(p, _player_hit_test, false, true)


func _tick_enemy(delta: float) -> void:
	if enemy_weapon == null or enemy_brain == null or targets_left() == 0:
		return
	enemy_reload_left -= delta
	if enemy_reload_left > 0.0:
		return
	var plan := enemy_brain.plan_shot(_situation(), _enemy_rng)
	if plan.is_empty():
		enemy_reload_left = ENEMY_RETRY_S
		return
	enemy_reload_left = enemy_weapon.reload_time + enemy_weapon.cooldown
	var p := ShotParams.create(enemy_weapon, enemy_ammo, plan.elevation_deg, plan.charge,
		enemy_origin_m, int(plan.get("facing", -1)), weather, _child_rng(_enemy_rng))
	_configure(p)
	_launch(p, _enemy_hit_test, true, false)


func _situation() -> EnemyBrain.Situation:
	var s := EnemyBrain.Situation.new()
	s.weapon = enemy_weapon
	s.ammo = enemy_ammo
	s.origin_m = enemy_origin_m
	for m in mounts:
		if m.is_alive():
			s.battery_positions_m.append(m.position_m)
	s.reveal_level = reveal_level
	s.difficulty = contract.difficulty
	s.weather = weather
	s.time_s = elapsed
	s.last_impact_m = enemy_last_impact_m
	return s


func _configure(p: ShotParams) -> void:
	p.world_bounds_m = bounds_m()
	# Weather density applies at the target ground (y = 0), whoever fires.
	p.reference_y_m = 0.0
	p.max_time = MAX_FLIGHT_TIME_S


## Laser designation: the live target nearest to where the shot would land unguided.
func _designate_for(p: ShotParams) -> Vector2:
	var landing := Ballistics.predict(p, map.raycast).end_point_m
	var best := Vector2.INF
	for t in targets:
		if not t.is_destroyed() and (best == Vector2.INF or t.position_m.distance_to(landing) < best.distance_to(landing)):
			best = t.position_m
	return best + Vector2(0.0, -BattleRules.TARGET_SIZE_M.y * 0.5) if best != Vector2.INF else Vector2.INF


func _launch(p: ShotParams, hit_test: Callable, enemy: bool, orbital: bool) -> void:
	var flight := Ballistics.launch(p, hit_test)
	_shots[flight] = {"root": flight, "enemy": enemy, "orbital": orbital, "hit": false, "ammo": p.ammo}
	flights.append(flight)
	shell_launched.emit(flight, enemy)


# --- Flight events ---

func _advance_flights(delta: float) -> void:
	for f in flights.duplicate():
		for ev in f.advance(delta):
			_on_event(ev)
			if outcome != Outcome.NONE:
				return
		if f.is_settled():
			flights.erase(f)
			_on_settled(f)


func _on_event(ev: Dictionary) -> void:
	var flight: ShellFlight = ev.flight
	var rec: Dictionary = _shots.get(flight, {})
	if rec.is_empty():
		return
	var ammo: AmmoData = flight.params.ammo
	var is_root: bool = rec.root == flight
	var pos: Vector2 = ev.position
	match ev.type:
		&"impact":
			_detonate(rec, ammo, pos, 1.0, 1.0, &"impact")
			if is_root:
				EventBus.projectile_impacted.emit(pos, ammo.id)
				if rec.enemy:
					enemy_last_impact_m = pos
		&"bounce":
			_detonate(rec, ammo, pos, BattleRules.BOUNCE_DAMAGE_SCALE, BattleRules.BOUNCE_CRATER_SCALE, &"bounce")
			if is_root:
				EventBus.projectile_bounced.emit(pos, ammo.id)
		&"airburst":
			_detonate(rec, ammo, pos, 1.0, 0.0, &"airburst")
			if is_root:
				EventBus.projectile_impacted.emit(pos, ammo.id)
		&"burst":
			for frag: ShellFlight in ev.fragments:
				_shots[frag] = rec


func _detonate(rec: Dictionary, ammo: AmmoData, pos: Vector2, damage_scale: float,
		crater_scale: float, kind: StringName) -> void:
	var crater := ammo.crater_radius_m * crater_scale
	if crater > 0.0:
		_field.carve(pos, crater)
		_settle_on_ground()
	blast.emit(pos, maxf(ammo.explosion_radius_m * damage_scale, crater), kind)
	var dealt := apply_blast(ammo, pos, damage_scale, rec.enemy)
	if dealt > 0.0 and not rec.enemy and not rec.hit:
		rec["hit"] = true
		result.shells_hit += 1


func _on_settled(f: ShellFlight) -> void:
	var rec: Dictionary = _shots.get(f, {})
	_shots.erase(f)
	for frag in f.fragments:
		_shots.erase(frag)
	if rec.is_empty() or rec.enemy or rec.orbital or rec.hit:
		return
	_raise_reveal(BattleRules.reveal_after_miss(reveal_level))


## Targets and weapons drop into craters dug under them.
func _settle_on_ground() -> void:
	for t in targets:
		t.position_m.y = maxf(t.position_m.y, map.surface_height_at(t.position_m.x))
	for m in mounts:
		m.position_m.y = maxf(m.position_m.y, map.surface_height_at(m.position_m.x))


func _raise_reveal(level: float) -> void:
	if level != reveal_level:
		reveal_level = level
		EventBus.battery_revealed.emit(reveal_level)


# --- Hit tests ---

func _player_hit_test(from_m: Vector2, to_m: Vector2) -> Dictionary:
	var rects: Array[Rect2] = []
	for t in targets:
		if not t.is_destroyed():
			rects.append(t.rect_m())
	return _hit_with_boxes(from_m, to_m, rects)


func _enemy_hit_test(from_m: Vector2, to_m: Vector2) -> Dictionary:
	var rects: Array[Rect2] = []
	for m in mounts:
		if m.is_alive():
			rects.append(m.rect_m())
	return _hit_with_boxes(from_m, to_m, rects)


## Terrain raycast plus boxes standing on it; the nearest contact wins.
func _hit_with_boxes(from_m: Vector2, to_m: Vector2, rects: Array[Rect2]) -> Dictionary:
	var hit := map.raycast(from_m, to_m)
	var seg_len := from_m.distance_to(to_m)
	var best_t := 2.0
	if hit.get("hit", false) and seg_len > 0.0:
		best_t = from_m.distance_to(hit.position) / seg_len
	elif hit.get("hit", false):
		return hit
	for r in rects:
		var box := BattleRules.segment_enters_rect(from_m, to_m, r)
		if not box.is_empty() and box.t < best_t:
			best_t = box.t
			hit = {"hit": true, "position": box.position, "normal": box.normal}
	return hit


# --- End ---

func _check_outcome() -> void:
	if outcome != Outcome.NONE:
		return
	if targets_left() == 0:
		_end(true, "All targets destroyed")
	elif not mounts.any(func(m: WeaponMount) -> bool: return m.is_alive()):
		_end(false, "Battery destroyed")
	elif contract.time_limit > 0.0 and elapsed >= contract.time_limit:
		_end(false, "Time limit expired")
	elif _out_of_ammo():
		_end(false, "Out of ammunition")


## No working weapon has a shell left to fire and nothing of ours is still in the air.
func _out_of_ammo() -> bool:
	if player_shots_pending():
		return false
	for m in mounts:
		if not m.is_alive():
			continue
		if m.is_firing():
			return false
		for id in ammo_choices(m):
			if player.ammo_count(id) > 0:
				return false
	return true


func _end(victory: bool, reason: String) -> void:
	if outcome != Outcome.NONE:
		return
	outcome = Outcome.VICTORY if victory else Outcome.DEFEAT
	end_reason = reason
	result.victory = victory
	result.payout_earned = contract.payout if victory else 0
	result.duration_s = elapsed
	ended.emit(victory, reason)


static func _child_rng(parent: RandomNumberGenerator) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = parent.randi()
	return r
