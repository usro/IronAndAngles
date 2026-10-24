class_name ShellFlight
extends RefCounted
## Step-wise flight of one shell or fragment. The battle calls advance(delta) every frame and
## reads position/events; Ballistics.simulate() runs the same steps to the end, so a live shot and
## a simulated one with the same seed are identical.
##
## Model: RK4 at a fixed step over gravity, quadratic drag against the air (wind and seeded gusts,
## scaled by AmmoData.wind_sensitivity), air density falling off with height, rocket thrust along
## the heading for burn_time, and guided steering that turns the velocity toward a designated point.
## State is kept in 64-bit floats; Vector2 (32-bit) is only used at the API boundary.
##
## Events returned by step()/advance() are dictionaries with "type" (&"bounce", &"impact",
## &"airburst", &"burst", &"out_of_bounds", &"timeout"), "flight" (the ShellFlight), "position",
## "velocity", "time", and depending on type "normal" (bounce, impact) or "fragments" (burst).

## Height over which air density falls by a factor of e (Earth's lower atmosphere).
const AIR_SCALE_HEIGHT_M := 8500.0
## A bounce slower than this ends the flight as an impact (the shell comes to rest).
const MIN_BOUNCE_SPEED := 1.0
## Tangential speed kept on a bounce goes from this (restitution 0) to 1 (restitution 1).
const BOUNCE_TANGENT_KEEP_MIN := 0.7
## Distance a bounced shell is lifted off the surface so the next step does not re-hit it.
const SURFACE_OFFSET_M := 0.01
const FRAGMENT_DRAG_COEFFICIENT := 0.8
const FRAGMENT_DENSITY_KG_M3 := 7850.0
## Safety cap on a fragment's flight time.
const FRAGMENT_MAX_TIME := 30.0

var params: ShotParams
var trajectory := Trajectory.new()
## Fragments spawned by this flight's burst. advance() also advances them.
var fragments: Array[ShellFlight] = []
## Simulation clock in seconds (starts at params.start_time).
var time: float = 0.0
var is_finished: bool = false

var _hit_test: Callable
var _ammo: AmmoData
var _px := 0.0
var _py := 0.0
var _vx := 0.0
var _vy := 0.0
var _prev_px := 0.0
var _prev_py := 0.0
var _accumulator := 0.0
var _bounce_count := 0

# Per-shot constants.
var _gravity := 0.0
var _drag_k := 0.0  # 0.5 * Cd * A / m, multiplied by density and airspeed
var _rho0 := 0.0
var _wind := 0.0
var _gust_amp := 0.0
var _gust_w1 := 0.0
var _gust_p1 := 0.0
var _gust_w2 := 0.0
var _gust_p2 := 0.0
var _thrust_acc := 0.0
var _burn_end := 0.0
var _launch_dx := 1.0
var _launch_dy := 0.0
var _guided := false
var _turn_rate := 0.0
var _arm_time := 0.0
var _fuse_end := INF
var _ax := 0.0
var _ay := 0.0


func _init(p_params: ShotParams, hit_test: Callable) -> void:
	params = p_params
	_hit_test = hit_test
	_ammo = params.ammo
	var weather: WeatherState = params.weather if params.weather != null else WeatherState.new()
	var rng := params.rng if not params.nominal else null
	time = params.start_time

	_gravity = weather.gravity
	_rho0 = maxf(weather.air_density, 0.0)
	if _ammo.mass_kg > 0.0:
		_drag_k = 0.5 * _ammo.drag_coefficient * _ammo.cross_section_m2 / _ammo.mass_kg
		_thrust_acc = _ammo.thrust_n / _ammo.mass_kg
	_burn_end = time + _ammo.burn_time
	_wind = weather.wind_speed * _ammo.wind_sensitivity

	# Launch. RNG draw order is fixed (spread, then gusts) so the same seed gives the same shot.
	var v0: Vector2
	if params.initial_velocity_m != Vector2.INF:
		v0 = params.initial_velocity_m
		trajectory.launch_elevation_deg = rad_to_deg(atan2(-v0.y, absf(v0.x)))
	else:
		var elev := params.elevation_deg
		if params.weapon != null:
			elev = params.weapon.clamp_elevation(elev)
		if rng != null and params.weapon != null:
			elev += Ballistics.triangular(rng) * params.weapon.spread_deg
		trajectory.launch_elevation_deg = elev
		var speed := params.weapon.velocity_for_charge(params.charge) if params.weapon != null else 0.0
		var rad := deg_to_rad(elev)
		v0 = Vector2(cos(rad) * speed * params.facing, -sin(rad) * speed)
	_vx = v0.x
	_vy = v0.y
	if rng != null:
		_gust_amp = weather.gust_strength * _ammo.wind_sensitivity
		_gust_w1 = TAU / rng.randf_range(2.0, 8.0)
		_gust_p1 = rng.randf_range(0.0, TAU)
		_gust_w2 = TAU / rng.randf_range(0.7, 2.5)
		_gust_p2 = rng.randf_range(0.0, TAU)

	var launch_dir := Vector2(_vx, _vy).normalized()
	if launch_dir == Vector2.ZERO:
		launch_dir = Vector2(params.facing, 0.0)
	_launch_dx = launch_dir.x
	_launch_dy = launch_dir.y
	_guided = _ammo.guided and params.guidance_target_m != Vector2.INF
	_turn_rate = deg_to_rad(_ammo.guidance_turn_rate_deg)
	_arm_time = time + _ammo.guidance_arm_time
	if _ammo.fragment_count > 0 and _ammo.fuse_time > 0.0 and not params.stop_at_first_contact:
		_fuse_end = time + _ammo.fuse_time

	_px = params.origin_m.x
	_py = params.origin_m.y
	_prev_px = _px
	_prev_py = _py
	trajectory.start_time = time
	trajectory.launch_velocity_m = v0
	trajectory.end_point_m = params.origin_m
	trajectory.add_point(params.origin_m, time)


var position_m: Vector2:
	get:
		return Vector2(_px, _py)

var velocity_m: Vector2:
	get:
		return Vector2(_vx, _vy)


## Position for drawing: interpolated between the last two fixed steps by the leftover frame time.
func get_render_position() -> Vector2:
	if is_finished:
		return position_m
	var f := clampf(_accumulator / params.step, 0.0, 1.0)
	return Vector2(lerpf(_prev_px, _px, f), lerpf(_prev_py, _py, f))


## True once this flight and every fragment it spawned have ended.
func is_settled() -> bool:
	if not is_finished:
		return false
	for f in fragments:
		if not f.is_settled():
			return false
	return true


## Advances by frame time. Runs as many fixed steps as fit and returns their events, including
## those of fragments spawned earlier.
func advance(delta: float) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for f in fragments:
		events.append_array(f.advance(delta))
	if is_finished:
		return events
	_accumulator += delta
	while _accumulator >= params.step and not is_finished:
		_accumulator -= params.step
		events.append_array(step())
	return events


## Runs this flight and all its fragments to the end.
func run_to_end() -> void:
	while not is_finished:
		step()
	for f in fragments:
		f.run_to_end()


## One fixed step. Returns the events it produced.
func step() -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if is_finished:
		return events
	var dt := params.step
	var ox := _px
	var oy := _py
	var ovx := _vx
	var ovy := _vy
	_prev_px = _px
	_prev_py = _py
	_integrate(dt)
	_steer(dt)

	var from := Vector2(ox, oy)
	var to := Vector2(_px, _py)
	var hit: Dictionary = _hit_test.call(from, to) if _hit_test.is_valid() else {}
	if not hit.is_empty():
		var hit_pos: Vector2 = hit["position"]
		var seg := from.distance_to(to)
		var f := 1.0 if seg <= 0.0 else clampf(from.distance_to(hit_pos) / seg, 0.0, 1.0)
		time += dt * f
		_px = hit_pos.x
		_py = hit_pos.y
		_vx = lerpf(ovx, _vx, f)
		_vy = lerpf(ovy, _vy, f)
		var normal: Vector2 = hit.get("normal", Vector2.UP)
		_contact(normal.normalized() if normal != Vector2.ZERO else Vector2.UP, events)
		return events

	time += dt
	if params.record_points:
		trajectory.add_point(to, time)
	if time >= _fuse_end:
		_finish(Trajectory.EndReason.AIRBURST, Vector2.ZERO)
		events.append(_event(&"airburst"))
		_burst(Vector2(_vx, _vy).normalized(), events)
	elif _out_of_bounds():
		_finish(Trajectory.EndReason.OUT_OF_BOUNDS, Vector2.ZERO)
		events.append(_event(&"out_of_bounds"))
	elif time - trajectory.start_time >= params.max_time:
		_finish(Trajectory.EndReason.TIMEOUT, Vector2.ZERO)
		events.append(_event(&"timeout"))
	return events


func _integrate(dt: float) -> void:
	var t := time
	var h := dt * 0.5
	_accel(_py, _vx, _vy, t)
	var k1x := _vx
	var k1y := _vy
	var k1vx := _ax
	var k1vy := _ay
	var v2x := _vx + k1vx * h
	var v2y := _vy + k1vy * h
	_accel(_py + k1y * h, v2x, v2y, t + h)
	var k2vx := _ax
	var k2vy := _ay
	var v3x := _vx + k2vx * h
	var v3y := _vy + k2vy * h
	_accel(_py + v2y * h, v3x, v3y, t + h)
	var k3vx := _ax
	var k3vy := _ay
	var v4x := _vx + k3vx * dt
	var v4y := _vy + k3vy * dt
	_accel(_py + v3y * dt, v4x, v4y, t + dt)
	_px += dt / 6.0 * (k1x + 2.0 * v2x + 2.0 * v3x + v4x)
	_py += dt / 6.0 * (k1y + 2.0 * v2y + 2.0 * v3y + v4y)
	_vx += dt / 6.0 * (k1vx + 2.0 * k2vx + 2.0 * k3vx + _ax)
	_vy += dt / 6.0 * (k1vy + 2.0 * k2vy + 2.0 * k3vy + _ay)


## Acceleration at (y, velocity, time) into _ax/_ay. x does not matter: the air is uniform sideways.
func _accel(y: float, vx: float, vy: float, t: float) -> void:
	var ax := 0.0
	var ay := _gravity
	if _drag_k > 0.0 and _rho0 > 0.0:
		var rho := _rho0 * exp((y - params.reference_y_m) / AIR_SCALE_HEIGHT_M)
		var rvx := vx - _wind_at(t)
		var f := rho * _drag_k * sqrt(rvx * rvx + vy * vy)
		ax -= f * rvx
		ay -= f * vy
	if t < _burn_end and _thrust_acc != 0.0:
		var s := sqrt(vx * vx + vy * vy)
		if s > 1e-6:
			ax += _thrust_acc * vx / s
			ay += _thrust_acc * vy / s
		else:
			ax += _thrust_acc * _launch_dx
			ay += _thrust_acc * _launch_dy
	_ax = ax
	_ay = ay


## Horizontal wind felt by this shell at time t: base wind plus two seeded sine gusts.
func _wind_at(t: float) -> float:
	if _gust_amp == 0.0:
		return _wind
	return _wind + _gust_amp * (0.6 * sin(_gust_w1 * t + _gust_p1) + 0.4 * sin(_gust_w2 * t + _gust_p2))


## Guided ammo: turn the velocity toward the designated point, at most turn_rate per second.
func _steer(dt: float) -> void:
	if not _guided or time < _arm_time:
		return
	var dx := params.guidance_target_m.x - _px
	var dy := params.guidance_target_m.y - _py
	if dx * dx + dy * dy < 1e-6:
		return
	var diff := wrapf(atan2(dy, dx) - atan2(_vy, _vx), -PI, PI)
	var turn := clampf(diff, -_turn_rate * dt, _turn_rate * dt)
	var c := cos(turn)
	var s := sin(turn)
	var nvx := _vx * c - _vy * s
	_vy = _vx * s + _vy * c
	_vx = nvx


## The shell touched the ground at the current position: bounce or impact.
func _contact(normal: Vector2, events: Array[Dictionary]) -> void:
	var v_in := Vector2(_vx, _vy)
	if v_in.dot(normal) > 0.0:
		normal = -normal
	if params.record_points:
		trajectory.add_point(position_m, time)
	var can_bounce := _ammo.bounce_restitution > 0.0 and _bounce_count < _ammo.max_bounces
	if can_bounce and not params.stop_at_first_contact:
		var vn := normal * v_in.dot(normal)
		var vt := v_in - vn
		var keep := lerpf(BOUNCE_TANGENT_KEEP_MIN, 1.0, _ammo.bounce_restitution)
		var v_out := vt * keep - vn * _ammo.bounce_restitution
		var rng := params.rng if not params.nominal else null
		if rng != null:
			var deflect := deg_to_rad(Ballistics.triangular(rng) * _ammo.bounce_randomness_deg)
			var turned := v_out.rotated(deflect)
			if turned.dot(normal) <= 0.0:
				turned = v_out.rotated(-deflect)
			v_out = turned
		if v_out.dot(normal) <= 0.0:
			v_out = (v_out - normal * v_out.dot(normal)) + normal * 0.1
		if v_out.length() >= MIN_BOUNCE_SPEED:
			_bounce_count += 1
			var bounce := {
				"position": position_m, "normal": normal, "time": time,
				"velocity_in": v_in, "velocity_out": v_out,
			}
			trajectory.bounces.append(bounce)
			_vx = v_out.x
			_vy = v_out.y
			_px += normal.x * SURFACE_OFFSET_M
			_py += normal.y * SURFACE_OFFSET_M
			var ev := _event(&"bounce")
			ev["normal"] = normal
			ev["bounce_index"] = _bounce_count
			events.append(ev)
			return
	_finish(Trajectory.EndReason.IMPACT, normal)
	var impact := _event(&"impact")
	impact["normal"] = normal
	events.append(impact)
	if _ammo.fragment_count > 0 and _fuse_end == INF and not params.stop_at_first_contact:
		_burst(normal, events)


func _finish(reason: Trajectory.EndReason, normal: Vector2) -> void:
	is_finished = true
	trajectory.end_reason = reason
	trajectory.end_point_m = position_m
	trajectory.end_velocity_m = velocity_m
	trajectory.impact_normal = normal
	trajectory.time_of_flight = time - trajectory.start_time


## Spawns fragment_count fragments in a cone around `axis`. Each gets its own seeded RNG.
func _burst(axis: Vector2, events: Array[Dictionary]) -> void:
	if axis == Vector2.ZERO:
		axis = Vector2(params.facing, 0.0)
	var frag_ammo := Ballistics.make_fragment_ammo(_ammo)
	var rng := params.rng if not params.nominal else null
	var half_cone := deg_to_rad(_ammo.fragment_cone_deg) * 0.5
	var count := _ammo.fragment_count
	# An airburst carries the shell's momentum; an impact burst sprays off the ground from rest.
	var on_ground := trajectory.end_reason == Trajectory.EndReason.IMPACT
	var base_v := Vector2.ZERO if on_ground else velocity_m
	var burst_origin := position_m + axis * SURFACE_OFFSET_M if on_ground else position_m
	var spawned: Array[ShellFlight] = []
	for i in count:
		var angle: float
		var speed := _ammo.fragment_speed_mps
		var child_rng: RandomNumberGenerator = null
		if rng != null:
			angle = rng.randf_range(-half_cone, half_cone)
			speed *= rng.randf_range(0.8, 1.2)
			child_rng = RandomNumberGenerator.new()
			child_rng.seed = rng.randi()
		else:
			# Nominal: spread evenly across the cone.
			angle = 0.0 if count == 1 else lerpf(-half_cone, half_cone, float(i) / (count - 1))
		var p := params.copy()
		p.ammo = frag_ammo
		p.rng = child_rng
		p.origin_m = burst_origin
		p.initial_velocity_m = base_v + axis.rotated(angle) * speed
		p.start_time = time
		p.max_time = minf(FRAGMENT_MAX_TIME, params.max_time)
		p.guidance_target_m = Vector2.INF
		var child := ShellFlight.new(p, _hit_test)
		spawned.append(child)
		trajectory.fragments.append(child.trajectory)
	fragments.append_array(spawned)
	var ev := _event(&"burst")
	ev["fragments"] = spawned
	events.append(ev)


func _out_of_bounds() -> bool:
	var b := params.world_bounds_m
	if not b.has_area():
		return false
	return _px < b.position.x or _px > b.end.x or _py > b.end.y


func _event(type: StringName) -> Dictionary:
	return {"type": type, "flight": self, "position": position_m, "velocity": velocity_m, "time": time}
