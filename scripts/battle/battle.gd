extends Node2D
## Battle scene: builds the field from GameState.current_plot, runs a BattleSim, forwards input
## and draws its state as blueprint line art (LauncherArt, BattleArt); the FX session adds effects.
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
## Split screen: each half shows this much field (meters) at the same zoom.
const SPLIT_VIEW_M := Vector2(90.0, 100.0)
## Top-centre profile strip between the mission and conditions plates.
const MINIMAP_SIZE := Vector2(420.0, 64.0)
const SPLIT_BATTERY_OFFSET_M := Vector2(20.0, -25.0)
## The observer looks a little past the zone's centre so a spotted enemy gun is in frame.
const SPLIT_OBSERVER_OFFSET_M := Vector2(8.0, -25.0)
const TRAIL_MAX_POINTS := 600
const BLAST_LIFETIME_S := 0.8
const WHEEL_STEP_DEG := 0.5
const WHEEL_STEP_CHARGE := 0.01
const MAX_FRAME_DELTA_S := 0.1

const SKY_SHADER := preload("res://scripts/ui/blueprint_sky.gdshader")
const MOUNT_COLOR := Blueprint.INK
const SELECTED_COLOR := Blueprint.AMBER
const DEAD_COLOR := Color(0.45, 0.55, 0.68, 0.6)
const PLAYER_SHELL_COLOR := Blueprint.INK
const ENEMY_SHELL_COLOR := Blueprint.RED
## Range marks along the ground, measured from the battery.
const RANGE_MARK_STEP_M := 50.0

var sim: BattleSim
var terrain: Terrain
var camera: Camera2D
var hud: BattleHud
var firing_table: FiringTablePanel
var minimap: BattleMinimap
## Split screen: our battery on the left, the forward observer's view of the targets on the right.
var split := false
var _observer: ObserverPane
var _split_layer: CanvasLayer
var _observer_label: Label
## Rangefinder: held right mouse button; the measured ground point (meters) or INF.
var _ranging := false
var _range_point := Vector2.INF
var _range_label: Label
## Forward-observer calls, newest first ("OVER 25 m").
var observer_calls: Array[String] = []
var _calls_label: Label
const OBSERVER_CALLS_SHOWN := 3
## A shell landing within this distance of the target's centre is called "on line".
const OBSERVER_CLOSE_M := 3.0

var _overlay: Node2D
var _sky: ColorRect
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
## Enemy ShellFlights, remembered at launch so their trails stay red after they settle.
var _enemy_flights: Dictionary = {}


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
	_sky = ColorRect.new()
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = SKY_SHADER
	_sky.material = sky_mat
	_sky.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sky_layer.add_child(_sky)

	terrain = Terrain.new()
	add_child(terrain)
	terrain.build(plot)

	_overlay = Node2D.new()
	add_child(_overlay)
	_overlay.draw.connect(_draw_overlay)

	camera = Camera2D.new()
	add_child(camera)
	camera.make_current()

	_build_split_screen()
	hud = BattleHud.new()
	add_child(hud)
	_range_label = Label.new()
	_range_label.theme_type_variation = &"StatusLabel"
	_range_label.visible = false
	hud.add_child(_range_label)

	sim = BattleSim.new(contract, plot, GameState.player, terrain, GameState.rng.randi())
	sim.shell_launched.connect(_on_shell_launched)
	sim.blast.connect(_on_blast)
	sim.ended.connect(_on_ended)
	sim.shell_observed.connect(_on_shell_observed)
	firing_table = FiringTablePanel.new()
	firing_table.sim = sim
	hud.add_child(firing_table)
	minimap = BattleMinimap.new()
	minimap.sim = sim
	minimap.trails = _trails
	minimap.anchor_left = 0.5
	minimap.anchor_right = 0.5
	minimap.offset_left = -MINIMAP_SIZE.x * 0.5
	minimap.offset_right = MINIMAP_SIZE.x * 0.5
	minimap.offset_top = 14.0
	minimap.offset_bottom = 14.0 + MINIMAP_SIZE.y
	hud.add_child(minimap)
	sim.start()
	# Split screen by default whenever the targets lie beyond the home view.
	set_split(sim.target_zone_center_m().x - sim.battery_position_m().x > HOME_OFFSET_M.x + HOME_VIEW_M.x * 0.5)
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
	firing_table.refresh()
	_update_rangefinder()
	_update_trails()
	_update_blasts(delta)
	_update_camera(delta)
	_update_sky()
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
	elif event.is_action_pressed("charge_up") or event.is_action_pressed("charge_down"):
		var m := sim.selected_mount()
		if m and not m.is_orbital():
			m.step_charge(1 if event.is_action_pressed("charge_up") else -1)
	elif event.is_action_pressed("toggle_firing_table"):
		firing_table.toggle()
	elif event.is_action_pressed("apply_solution"):
		if not firing_table.apply_nearest():
			hud.flash_note("Fire-control computer: research Fire Control Computers first")
	elif event.is_action_pressed("relocate"):
		if not sim.relocate():
			hud.flash_note("Can't relocate yet (%.0f s)" % maxf(sim.relocate_cooldown_left, sim.relocating_left)
				if sim.relocate_cooldown_left > 0.0 else "Can't relocate now")
		else:
			hud.flash_note("Relocating: guns silent for %.0f s" % BattleSim.RELOCATE_S)
	elif event.is_action_pressed("toggle_split"):
		set_split(not split)
	elif event.is_action_pressed("toggle_overview"):
		_overview = not _overview
	elif event.is_action_pressed("retreat"):
		sim.retreat()
	elif event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_RIGHT:
		_ranging = event.pressed
		if not _ranging and _range_point != Vector2.INF:
			var m := _measure(_range_point)
			firing_table.set_measurement(m.x, m.y)
			if not firing_table.visible:
				firing_table.toggle()
		_range_label.visible = _ranging
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
		m.adjust_elevation(elev * WeaponMount.ELEVATION_RATE_DEG * m.elevation_scale() * delta / fine)
	# Charge moves in fixed increments, one per key press (see _unhandled_input).


func _wheel(dir: int, shift: bool) -> void:
	var m := sim.selected_mount()
	if m == null:
		return
	if m.is_orbital():
		sim.adjust_designator(m, dir * (5.0 if shift else 1.0))
	elif shift:
		m.step_charge(dir)
	else:
		m.adjust_elevation(dir * WHEEL_STEP_DEG * m.elevation_scale())


# --- Events ---

func _on_shell_launched(flight: ShellFlight, enemy: bool) -> void:
	_trails[flight] = PackedVector2Array([flight.position_m])
	if enemy:
		_enemy_flights[flight] = true
	_hold_left = CAMERA_HOLD_S
	var m := sim.selected_mount()
	if not enemy and m and not m.is_orbital():
		_launch_labels[flight] = ("last: %.2f° / %.1f%%" if m.weapon.is_direct_fire() else "last: %.1f° / %.1f%%") \
			% [m.elevation_deg, m.charge * 100.0]
		hud.note_shot(sim.selected, m.elevation_deg, m.charge)


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
	_observer.visible = _split_active()
	_split_layer.visible = _split_active()
	if _split_active():
		_frame_split(1.0 - exp(-CAMERA_SMOOTHING * delta))
		return
	var rect := _camera_rect()
	if not sim.flights.is_empty():
		_hold_left = CAMERA_HOLD_S
	elif _hold_left > 0.0:
		_hold_left -= delta
	var k := 1.0 - exp(-CAMERA_SMOOTHING * delta)
	var target_zoom := _zoom_for(rect)
	camera.position = camera.position.lerp(GameConstants.meters_to_pixels(rect.get_center()), k)
	camera.zoom = camera.zoom.lerp(target_zoom, k)


func _update_sky() -> void:
	var mat := _sky.material as ShaderMaterial
	mat.set_shader_parameter("view_size_px", get_viewport_rect().size)
	mat.set_shader_parameter("camera_center_px", camera.get_screen_center_position())
	mat.set_shader_parameter("zoom", camera.zoom.x)
	mat.set_shader_parameter("bedrock_y_px", sim.bounds_m().end.y * GameConstants.PIXELS_PER_METER)


func _snap_camera() -> void:
	if _split_active():
		_frame_split(1.0)
		return
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
		if sim.enemy_origin_m != Vector2.INF and sim.enemy_spotted:
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


# --- Forward observer ---

## The observer calls where a shell came down relative to the nearest standing target (or the
## spotted enemy gun): "OVER 25 m", "SHORT 40 m", "ON LINE" or "TARGET HIT".
func _on_shell_observed(position_m: Vector2, hit: bool) -> void:
	var call := observer_call(sim, position_m, hit)
	observer_calls.push_front(call)
	observer_calls.resize(mini(observer_calls.size(), OBSERVER_CALLS_SHOWN))
	_calls_label.text = "\n".join(observer_calls.map(func(c: String) -> String: return "▸ " + c))
	if not _split_active():
		hud.flash_note("OBSERVER: " + call)


static func observer_call(s: BattleSim, position_m: Vector2, hit: bool) -> String:
	if hit:
		return "TARGET HIT"
	var nearest := Vector2.INF
	for t in s.targets:
		if not t.is_destroyed():
			var c := t.rect_m().get_center()
			if nearest == Vector2.INF or absf(c.x - position_m.x) < absf(nearest.x - position_m.x):
				nearest = c
	if s.enemy_spotted and s.enemy_gun_alive():
		var g := s.enemy_gun_rect().get_center()
		if nearest == Vector2.INF or absf(g.x - position_m.x) < absf(nearest.x - position_m.x):
			nearest = g
	if nearest == Vector2.INF:
		return "SPLASH"
	var dx := position_m.x - nearest.x
	if absf(dx) <= OBSERVER_CLOSE_M:
		return "ON LINE, CLOSE"
	return "%s %d m" % ["OVER" if dx > 0.0 else "SHORT", roundi(absf(dx) / 5.0) * 5]


# --- Rangefinder ---

## While the right mouse button is held: the ground point under the cursor, as range and height
## from the battery. Releasing it writes them into the firing table.
func _update_rangefinder() -> void:
	if not _ranging:
		_range_point = Vector2.INF
		return
	var screen := get_viewport().get_mouse_position()
	var world := _screen_to_world_m(screen)
	var x := clampf(world.x, sim.bounds_m().position.x, sim.bounds_m().end.x)
	_range_point = Vector2(x, sim.map.surface_height_at(x))
	var m := _measure(_range_point)
	_range_label.text = "RANGE %.0f m   HEIGHT %+.0f m" % [m.x, m.y]
	_range_label.position = screen + Vector2(16, -28)


## Range (x) and height (y, + = above the battery) of a ground point.
func _measure(point_m: Vector2) -> Vector2:
	var battery := sim.battery_position_m()
	return Vector2(point_m.x - battery.x, battery.y - point_m.y)


func _screen_to_world_m(screen: Vector2) -> Vector2:
	var vp := get_viewport_rect().size
	var px: Vector2
	if _split_active() and screen.x > vp.x * 0.5:
		px = _observer.camera.get_canvas_transform().affine_inverse() * (screen - Vector2(vp.x * 0.5, 0.0))
	else:
		px = get_viewport().get_canvas_transform().affine_inverse() * screen
	return px / GameConstants.PIXELS_PER_METER


# --- Split screen ---

func set_split(on: bool) -> void:
	split = on
	_observer.visible = _split_active()
	_split_layer.visible = _split_active()
	_snap_camera()


## The overview (V) always takes the whole screen.
func _split_active() -> bool:
	return split and not _overview


func _build_split_screen() -> void:
	_split_layer = CanvasLayer.new()
	add_child(_split_layer)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_split_layer.add_child(root)
	_observer = ObserverPane.new(get_world_2d())
	_observer.anchor_left = 0.5
	_observer.anchor_right = 1.0
	_observer.anchor_bottom = 1.0
	root.add_child(_observer)
	var divider := ColorRect.new()
	divider.color = Blueprint.LINE
	divider.anchor_left = 0.5
	divider.anchor_right = 0.5
	divider.anchor_bottom = 1.0
	divider.offset_left = -1.0
	divider.offset_right = 1.0
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(divider)
	for spec in [[0.25, "BATTERY"], [0.75, ""]]:
		var l := Label.new()
		l.theme_type_variation = &"SectionLabel"
		l.text = spec[1]
		l.anchor_left = spec[0]
		l.anchor_right = spec[0]
		l.offset_top = 92.0
		l.grow_horizontal = Control.GROW_DIRECTION_BOTH
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(l)
		if spec[1] == "":
			_calls_label = Label.new()
			_calls_label.theme_type_variation = &"MonoLabel"
			_calls_label.add_theme_color_override("font_color", Blueprint.AMBER)
			_calls_label.anchor_left = 0.5
			_calls_label.anchor_right = 0.5
			_calls_label.offset_left = 16.0
			_calls_label.offset_top = 114.0
			_calls_label.grow_horizontal = Control.GROW_DIRECTION_END
			_calls_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			root.add_child(_calls_label)
			# Right of the divider, clear of the conditions plate in the top-right corner.
			_observer_label = l
			l.anchor_left = 0.5
			l.anchor_right = 0.5
			l.offset_left = 16.0
			l.grow_horizontal = Control.GROW_DIRECTION_END
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT


## Left half: the battery's home view. Right half: the observer on the target zone. Same zoom,
## so the overlay's line widths (sized for the main camera) are right in both.
func _frame_split(k: float) -> void:
	var vp := get_viewport_rect().size
	var half := Vector2(vp.x * 0.5, vp.y)
	var size_px := GameConstants.meters_to_pixels(SPLIT_VIEW_M)
	var z := clampf(minf(half.x / size_px.x, half.y / size_px.y), 0.02, 2.0)
	var battery := GameConstants.meters_to_pixels(sim.battery_position_m() + SPLIT_BATTERY_OFFSET_M)
	# The main camera fills the screen; shift it so the battery sits in the left half's middle.
	var main_pos := battery + Vector2(half.x * 0.5 / z, 0.0)
	camera.position = camera.position.lerp(main_pos, k)
	camera.zoom = camera.zoom.lerp(Vector2(z, z), k)
	var zone := sim.target_zone_center_m()
	_observer.frame(GameConstants.meters_to_pixels(zone + SPLIT_OBSERVER_OFFSET_M), camera.zoom.x,
		sim.bounds_m().end.y * GameConstants.PIXELS_PER_METER)
	_observer_label.text = "OBSERVER  ·  TARGET ZONE %.0f m" % (zone.x - sim.battery_position_m().x)


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
				_enemy_flights.erase(f)
				_trails.erase(f)


func _update_blasts(delta: float) -> void:
	for b in _blasts:
		b["age"] += delta
	_blasts = _blasts.filter(func(b: Dictionary) -> bool: return b.age < BLAST_LIFETIME_S)


func _draw_overlay() -> void:
	var px := GameConstants.PIXELS_PER_METER
	var line_w := 1.5 / camera.zoom.x
	if _range_point != Vector2.INF:
		BattleArt.draw_crosshair(_overlay, _range_point * px, 10.0 / camera.zoom.x, Blueprint.AMBER, line_w)

	_range_marks(line_w)

	for t in sim.targets:
		var r := _px_rect(t.rect_m())
		BattleArt.draw_target(_overlay, r, line_w, t.is_destroyed())
		if not t.is_destroyed():
			BattleArt.draw_health(_overlay, r, t.health / t.max_health, 0.4 * px, Blueprint.RED)

	for i in sim.mounts.size():
		var m := sim.mounts[i]
		var r := _px_rect(m.rect_m())
		var col := DEAD_COLOR if not m.is_alive() else (SELECTED_COLOR if i == sim.selected else MOUNT_COLOR)
		LauncherArt.draw_data(_overlay, m.weapon, m.position_m * px, px, m.elevation_deg, col,
			Color(Blueprint.PAPER_DARK, 0.85), line_w)
		BattleArt.draw_health(_overlay, Rect2(r.position - Vector2(0, 2.0 * px), r.size), m.health / m.weapon.max_health,
			0.35 * px, Blueprint.LINE)
		if i == sim.selected and m.is_alive():
			var tip := Vector2(r.get_center().x, r.position.y - 3.6 * px)
			_overlay.draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(-0.6, -0.9) * px,
				tip + Vector2(0.6, -0.9) * px]), SELECTED_COLOR)

	# The enemy gun is only drawn once spotted (first muzzle flash, or a hit on it).
	if sim.enemy_origin_m != Vector2.INF and sim.enemy_weapon and sim.enemy_spotted:
		var ground := sim.enemy_origin_m + Vector2(0.0, 2.0)
		var alive := sim.enemy_gun_alive()
		LauncherArt.draw_data(_overlay, sim.enemy_weapon, ground * px, px, 50.0 if alive else 15.0,
			ENEMY_SHELL_COLOR if alive else DEAD_COLOR, BattleArt.ENEMY_FILL, line_w, -1)
		var r := _px_rect(sim.enemy_gun_rect())
		BattleArt.draw_health(_overlay, Rect2(r.position - Vector2(0, 2.0 * px), r.size),
			sim.enemy_health / maxf(sim.enemy_max_health, 1.0), 0.35 * px, ENEMY_SHELL_COLOR)
		if alive:
			# Constant on-screen size, so the spotted gun stays findable at any zoom.
			BattleArt.draw_crosshair(_overlay, r.get_center(), 12.0 / camera.zoom.x, ENEMY_SHELL_COLOR, line_w)

	var sel := sim.selected_mount()
	if sel and sel.is_orbital() and sel.is_alive():
		_strike_marker(sel.designated_x_m, SELECTED_COLOR, line_w)
	for s in sim.strikes:
		_strike_marker(s.x, ENEMY_SHELL_COLOR, line_w * 2.0)

	if _ghost_trail.size() >= 2:
		var ghost := PackedVector2Array()
		for p in _ghost_trail:
			ghost.append(p * px)
		BattleArt.draw_dashed_polyline(_overlay, ghost, Color(Blueprint.AMBER, 0.45), line_w, 1.2 * px, 0.8 * px)
		var end := ghost[ghost.size() - 1]
		BattleArt.draw_crosshair(_overlay, end, 1.5 * px, Color(Blueprint.AMBER, 0.75), line_w)
		var font_size := roundi(13.0 / camera.zoom.x)
		_overlay.draw_string(Blueprint.FONT_MONO_BOLD, end + Vector2(-3.0 * px, -3.0 * px), _ghost_label,
				HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(Blueprint.AMBER, 0.85))

	for f: ShellFlight in _trails:
		var trail: PackedVector2Array = _trails[f]
		var col := ENEMY_SHELL_COLOR if _enemy_flights.has(f) or sim.is_enemy_flight(f) else PLAYER_SHELL_COLOR
		if trail.size() >= 2:
			var pts := PackedVector2Array()
			for p in trail:
				pts.append(p * px)
			_overlay.draw_polyline(pts, Color(col, 0.55), line_w)
	for f in sim.flights:
		var col := ENEMY_SHELL_COLOR if sim.is_enemy_flight(f) else PLAYER_SHELL_COLOR
		if not f.is_finished:
			var trail: PackedVector2Array = _trails.get(f, PackedVector2Array())
			var vel := trail[trail.size() - 1] - trail[trail.size() - 2] if trail.size() >= 2 else Vector2.ZERO
			BattleArt.draw_shell(_overlay, f.get_render_position() * px, vel, maxf(0.4 * px, 3.0 / camera.zoom.x), col)
		for frag in f.fragments:
			if not frag.is_finished:
				_overlay.draw_circle(frag.get_render_position() * px, 1.5 / camera.zoom.x, col)

	for b in _blasts:
		var k: float = b.age / BLAST_LIFETIME_S
		BattleArt.draw_blast(_overlay, b.position * px, b.radius * px, k, b.kind, 2.0 / camera.zoom.x)


## Distance ticks along the ground every RANGE_MARK_STEP_M from the battery, like a survey line.
func _range_marks(line_w: float) -> void:
	var px := GameConstants.PIXELS_PER_METER
	var origin := sim.battery_position_m().x
	var far := sim.target_zone_center_m().x + 40.0
	var font_size := roundi(11.0 / camera.zoom.x)
	var x := origin + RANGE_MARK_STEP_M
	while x < far:
		var ground := Vector2(x, sim.map.surface_height_at(x)) * px
		var col := Color(Blueprint.LINE, 0.55)
		_overlay.draw_line(ground + Vector2(0, -0.5 * px), ground + Vector2(0, -2.5 * px), col, line_w)
		_overlay.draw_string(Blueprint.FONT_MONO, ground + Vector2(1.0 / camera.zoom.x, -2.8 * px),
			"%d m" % roundi(x - origin), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)
		x += RANGE_MARK_STEP_M


func _strike_marker(x_m: float, col: Color, width: float) -> void:
	var px := GameConstants.PIXELS_PER_METER
	var ground := sim.map.surface_height_at(x_m)
	_overlay.draw_dashed_line(Vector2(x_m, ground - 60.0) * px, Vector2(x_m, ground) * px, col, width, 2.0 * px)
	BattleArt.draw_crosshair(_overlay, Vector2(x_m, ground) * px, 2.0 * px, col, width)


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
