extends Node2D
## Battle scene: builds the field from GameState.current_plot, runs a BattleSim, forwards input
## and draws its state. Plain shapes for now; the UI and FX sessions dress it up.
##
## Ends with the Battle -> Results contract: BattleSim.commit() (EventBus.battle_ended +
## GameState.apply_battle_result), then SceneRouter.goto(RESULTS).

## Seconds the end banner shows before the results screen.
const END_DELAY_S := 2.5
## Seconds the camera lingers on the last impact before going home.
const CAMERA_HOLD_S := 1.0
const CAMERA_SMOOTHING := 4.0
const CAMERA_MARGIN_M := 25.0
## The home view: this much field (meters) around the battery, looking toward the targets.
const HOME_VIEW_M := Vector2(170.0, 96.0)
const HOME_OFFSET_M := Vector2(55.0, -20.0)
const TRAIL_MAX_POINTS := 600
const BLAST_LIFETIME_S := 0.8
const WHEEL_STEP_DEG := 0.5
const WHEEL_STEP_CHARGE := 0.01
const MAX_FRAME_DELTA_S := 0.1

const SKY_COLOR := Color(0.04, 0.09, 0.18)
const TARGET_COLOR := Color(0.85, 0.55, 0.25)
const MOUNT_COLOR := Color(0.75, 0.9, 1.0)
const SELECTED_COLOR := Color(1.0, 0.95, 0.4)
const DEAD_COLOR := Color(0.3, 0.3, 0.35)
const PLAYER_SHELL_COLOR := Color(1.0, 0.95, 0.5)
const ENEMY_SHELL_COLOR := Color(1.0, 0.35, 0.3)

var sim: BattleSim
var terrain: Terrain
var camera: Camera2D
var hud: BattleHud

var _overlay: Node2D
var _overview := false
var _hold_left := 0.0
var _end_left := -1.0
var _committed := false
## ShellFlight -> PackedVector2Array of drawn positions (meters).
var _trails: Dictionary = {}
## {"position": Vector2, "radius": float, "age": float, "kind": StringName}
var _blasts: Array[Dictionary] = []
## The player's previous shell stays on screen as a faint reference for correcting the next shot.
var _ghost_trail := PackedVector2Array()
var _ghost_label := ""
## ShellFlight -> "elev / charge" text captured at launch (player shells only).
var _launch_labels: Dictionary = {}


func _ready() -> void:
	var contract := GameState.current_contract
	var plot := GameState.current_plot
	if contract == null:
		# Started directly from the editor: fight the first contract so the scene is testable.
		contract = _debug_contract()
		plot = contract.plots[0] if contract and not contract.plots.is_empty() else null
		GameState.current_contract = contract
		GameState.current_plot = plot
	if plot == null and contract and not contract.plots.is_empty():
		plot = contract.plots[0]

	var sky_layer := CanvasLayer.new()
	sky_layer.layer = -1
	add_child(sky_layer)
	var sky := ColorRect.new()
	sky.color = SKY_COLOR
	sky.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sky_layer.add_child(sky)

	terrain = Terrain.new()
	add_child(terrain)
	terrain.build(plot)

	_overlay = Node2D.new()
	add_child(_overlay)
	_overlay.draw.connect(_draw_overlay)

	camera = Camera2D.new()
	add_child(camera)
	camera.make_current()

	hud = BattleHud.new()
	add_child(hud)

	sim = BattleSim.new(contract, plot, GameState.player, terrain, GameState.rng.randi())
	sim.shell_launched.connect(_on_shell_launched)
	sim.blast.connect(_on_blast)
	sim.ended.connect(_on_ended)
	sim.start()
	_snap_camera()


func _process(delta: float) -> void:
	# A loading hitch must not teleport shells (or the clock) forward.
	delta = minf(delta, MAX_FRAME_DELTA_S)
	if _end_left < 0.0:
		_read_held_input(delta)
		sim.tick(delta)
	else:
		_end_left -= delta
		if _end_left <= 0.0 and not _committed:
			_finish()
	_update_trails()
	_update_blasts(delta)
	_update_camera(delta)
	hud.refresh(sim)
	_overlay.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if _end_left >= 0.0:
		return
	if event.is_action_pressed("fire"):
		sim.pull_trigger()
	elif event.is_action_pressed("next_weapon"):
		sim.select_next_weapon()
	elif event.is_action_pressed("next_ammo"):
		sim.cycle_ammo()
	elif event.is_action_pressed("toggle_overview"):
		_overview = not _overview
	elif event.is_action_pressed("retreat"):
		sim.retreat()
	elif event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		var dir := 0
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			dir = 1
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			dir = -1
		if dir != 0:
			_wheel(dir, mb.shift_pressed)


func _read_held_input(delta: float) -> void:
	var m := sim.selected_mount()
	if m == null:
		return
	var fine := WeaponMount.FINE_FACTOR if Input.is_action_pressed("fine_adjust") else 1.0
	var elev := Input.get_axis("aim_down", "aim_up")
	var chg := Input.get_axis("charge_down", "charge_up")
	if m.is_orbital():
		sim.adjust_designator(m, (chg + elev) * WeaponMount.DESIGNATOR_RATE_M * delta / fine)
		return
	if elev != 0.0:
		m.adjust_elevation(elev * WeaponMount.ELEVATION_RATE_DEG * delta / fine)
	if chg != 0.0:
		m.adjust_charge(chg * WeaponMount.CHARGE_RATE * delta / fine)


func _wheel(dir: int, shift: bool) -> void:
	var m := sim.selected_mount()
	if m == null:
		return
	if m.is_orbital():
		sim.adjust_designator(m, dir * (5.0 if shift else 1.0))
	elif shift:
		m.adjust_charge(dir * WHEEL_STEP_CHARGE)
	else:
		m.adjust_elevation(dir * WHEEL_STEP_DEG)


# --- Events ---

func _on_shell_launched(flight: ShellFlight, enemy: bool) -> void:
	_trails[flight] = PackedVector2Array([flight.position_m])
	_hold_left = CAMERA_HOLD_S
	var m := sim.selected_mount()
	if not enemy and m and not m.is_orbital():
		_launch_labels[flight] = "last: %.1f° / %.1f%%" % [m.elevation_deg, m.charge * 100.0]


func _on_blast(position_m: Vector2, radius_m: float, kind: StringName) -> void:
	_blasts.append({"position": position_m, "radius": maxf(radius_m, 0.5), "age": 0.0, "kind": kind})


func _on_ended(victory: bool, reason: String) -> void:
	hud.show_banner(("VICTORY" if victory else "DEFEAT") + "\n" + reason)
	_end_left = END_DELAY_S


func _finish() -> void:
	_committed = true
	sim.commit()
	SceneRouter.goto(SceneRouter.Screen.RESULTS)


# --- Camera ---

func _update_camera(delta: float) -> void:
	var rect := _camera_rect()
	if not sim.flights.is_empty():
		_hold_left = CAMERA_HOLD_S
	elif _hold_left > 0.0:
		_hold_left -= delta
	var k := 1.0 - exp(-CAMERA_SMOOTHING * delta)
	var target_zoom := _zoom_for(rect)
	camera.position = camera.position.lerp(GameConstants.meters_to_pixels(rect.get_center()), k)
	camera.zoom = camera.zoom.lerp(target_zoom, k)


func _snap_camera() -> void:
	var rect := _camera_rect()
	camera.position = GameConstants.meters_to_pixels(rect.get_center())
	camera.zoom = _zoom_for(rect)


## Following: frame the battery and every live shell's arc so far. Otherwise the home view
## (or the overview of the whole engagement).
func _camera_rect() -> Rect2:
	var battery := sim.battery_position_m()
	var rect: Rect2
	if _overview:
		rect = Rect2(battery, Vector2.ZERO).expand(sim.target_zone_center_m())
		if sim.enemy_origin_m != Vector2.INF:
			rect = rect.expand(sim.enemy_origin_m)
		rect = rect.grow(CAMERA_MARGIN_M)
	elif not sim.flights.is_empty() or _hold_left > 0.0 and not _trails.is_empty():
		rect = Rect2(battery, Vector2.ZERO)
		for trail: PackedVector2Array in _trails.values():
			for p in trail:
				rect = rect.expand(p)
		for s in sim.strikes:
			rect = rect.expand(Vector2(s.x, sim.map.surface_height_at(s.x)))
		rect = rect.grow(CAMERA_MARGIN_M)
	else:
		rect = Rect2(battery + HOME_OFFSET_M - HOME_VIEW_M * 0.5, HOME_VIEW_M)
		for s in sim.strikes:
			rect = rect.expand(Vector2(s.x, sim.map.surface_height_at(s.x))).grow(5.0)
	# Keep the aspect of the screen and at least the home view's size.
	var size := Vector2(maxf(rect.size.x, HOME_VIEW_M.x), maxf(rect.size.y, HOME_VIEW_M.y))
	return Rect2(rect.get_center() - size * 0.5, size)


func _zoom_for(rect_m: Rect2) -> Vector2:
	var vp := get_viewport_rect().size
	var size_px := GameConstants.meters_to_pixels(rect_m.size)
	var z := clampf(minf(vp.x / size_px.x, vp.y / size_px.y), 0.02, 2.0)
	return Vector2(z, z)


# --- Drawing ---

func _update_trails() -> void:
	var live := {}
	for f in sim.flights:
		live[f] = true
		if not _trails.has(f):
			_trails[f] = PackedVector2Array()
		var trail: PackedVector2Array = _trails[f]
		if not f.is_finished:
			trail.append(f.get_render_position())
			if trail.size() > TRAIL_MAX_POINTS:
				trail.remove_at(0)
			_trails[f] = trail
	# Finished shells keep their trail while the camera holds on the impact.
	if _hold_left <= 0.0:
		for f in _trails.keys():
			if not live.has(f):
				if _launch_labels.has(f) and _trails[f].size() >= 2:
					_ghost_trail = _trails[f]
					_ghost_label = _launch_labels[f]
				_launch_labels.erase(f)
				_trails.erase(f)


func _update_blasts(delta: float) -> void:
	for b in _blasts:
		b["age"] += delta
	_blasts = _blasts.filter(func(b: Dictionary) -> bool: return b.age < BLAST_LIFETIME_S)


func _draw_overlay() -> void:
	var px := GameConstants.PIXELS_PER_METER
	var line_w := 1.5 / camera.zoom.x

	for t in sim.targets:
		var r := _px_rect(t.rect_m())
		if t.is_destroyed():
			_overlay.draw_rect(r, DEAD_COLOR)
			_overlay.draw_line(r.position, r.end, TARGET_COLOR, line_w)
			_overlay.draw_line(Vector2(r.position.x, r.end.y), Vector2(r.end.x, r.position.y), TARGET_COLOR, line_w)
		else:
			_overlay.draw_rect(r, TARGET_COLOR)
			_health_bar(r, t.health / t.max_health)

	for i in sim.mounts.size():
		var m := sim.mounts[i]
		var r := _px_rect(m.rect_m())
		var col := DEAD_COLOR if not m.is_alive() else (SELECTED_COLOR if i == sim.selected else MOUNT_COLOR)
		_overlay.draw_rect(r, col)
		_health_bar(r, m.health / m.weapon.max_health)
		if m.is_alive() and not m.is_orbital():
			var dir := Vector2(cos(deg_to_rad(m.elevation_deg)), -sin(deg_to_rad(m.elevation_deg)))
			var muzzle := m.muzzle_m() * px
			_overlay.draw_line(muzzle, muzzle + dir * 4.0 * px, col, 3.0 / camera.zoom.x)

	if sim.enemy_origin_m != Vector2.INF:
		var e := sim.enemy_origin_m * px
		_overlay.draw_rect(Rect2(e - Vector2(1.5, -0.5) * px, Vector2(3.0, 2.0) * px), ENEMY_SHELL_COLOR)

	var sel := sim.selected_mount()
	if sel and sel.is_orbital() and sel.is_alive():
		_strike_marker(sel.designated_x_m, SELECTED_COLOR, line_w)
	for s in sim.strikes:
		_strike_marker(s.x, ENEMY_SHELL_COLOR, line_w * 2.0)

	if _ghost_trail.size() >= 2:
		var ghost := PackedVector2Array()
		for p in _ghost_trail:
			ghost.append(p * px)
		_overlay.draw_polyline(ghost, Color(PLAYER_SHELL_COLOR, 0.2), line_w)
		var end := ghost[ghost.size() - 1]
		_overlay.draw_arc(end, 1.5 * px, 0.0, TAU, 20, Color(PLAYER_SHELL_COLOR, 0.5), line_w)
		var font_size := roundi(14.0 / camera.zoom.x)
		_overlay.draw_string(ThemeDB.fallback_font, end + Vector2(-3.0 * px, -2.5 * px), _ghost_label,
				HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(PLAYER_SHELL_COLOR, 0.7))

	for f: ShellFlight in _trails:
		var trail: PackedVector2Array = _trails[f]
		var col := ENEMY_SHELL_COLOR if sim.is_enemy_flight(f) else PLAYER_SHELL_COLOR
		if trail.size() >= 2:
			var pts := PackedVector2Array()
			for p in trail:
				pts.append(p * px)
			_overlay.draw_polyline(pts, Color(col, 0.5), line_w)
	for f in sim.flights:
		var col := ENEMY_SHELL_COLOR if sim.is_enemy_flight(f) else PLAYER_SHELL_COLOR
		if not f.is_finished:
			_overlay.draw_circle(f.get_render_position() * px, maxf(0.4 * px, 3.0 / camera.zoom.x), col)
		for frag in f.fragments:
			if not frag.is_finished:
				_overlay.draw_circle(frag.get_render_position() * px, 1.5 / camera.zoom.x, col)

	for b in _blasts:
		var k: float = b.age / BLAST_LIFETIME_S
		var col := Color(1.0, 0.7, 0.3, 1.0 - k) if b.kind != &"bounce" else Color(0.8, 0.8, 0.8, 1.0 - k)
		_overlay.draw_arc(b.position * px, b.radius * px * (0.4 + 0.6 * k), 0.0, TAU, 32, col, 2.0 / camera.zoom.x)


func _health_bar(r: Rect2, fraction: float) -> void:
	var h := 0.4 * GameConstants.PIXELS_PER_METER
	var bar := Rect2(r.position - Vector2(0, h * 2.0), Vector2(r.size.x, h))
	_overlay.draw_rect(bar, Color(0.1, 0.1, 0.1))
	_overlay.draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(fraction, 0.0, 1.0), h)),
		Color(0.4, 0.95, 0.4))


func _strike_marker(x_m: float, col: Color, width: float) -> void:
	var px := GameConstants.PIXELS_PER_METER
	var ground := sim.map.surface_height_at(x_m)
	_overlay.draw_dashed_line(Vector2(x_m, ground - 60.0) * px, Vector2(x_m, ground) * px, col, width, 2.0 * px)
	_overlay.draw_arc(Vector2(x_m, ground) * px, 2.0 * px, 0.0, TAU, 24, col, width)


static func _px_rect(r: Rect2) -> Rect2:
	return Rect2(GameConstants.meters_to_pixels(r.position), GameConstants.meters_to_pixels(r.size))


static func _debug_contract() -> ContractData:
	var ids := DataRegistry.contracts.keys()
	ids.sort()
	for id in ids:
		var c: ContractData = DataRegistry.contracts[id]
		if c.era_required == GameState.player.current_era and not c.plots.is_empty():
			return c
	return null
