extends Node
## Autoload "AudioDirector": turns EventBus facts into sound. It never changes game state.
##
## World sounds (launches, impacts, debris, targets) are placed in the battle: each one reaches
## the listener (the player's battery) after distance / 343 m/s, is quieter and duller with
## distance (a per-voice low-pass) and is panned by where it is on screen. UI, music and the
## weather ambience bed play unplaced on their own buses (default_bus_layout.tres):
##   Master (compressor + limiter) <- SFX <- UI, Ambience, SFX Voice N;  Master <- Music
##
## On the dummy audio driver (headless tests) everything is still scheduled and logged in
## `played`, but nothing is sent to a player.

## Positional voices: each has its own bus with a low-pass and a panner, sending to SFX.
const VOICE_COUNT := 16
const UI_VOICE_COUNT := 6
const MAX_PENDING := 64
const PLAYED_LOG_SIZE := 32
const HOVER_COOLDOWN_S := 0.06
const FADE_DB_PER_S := 24.0
const SILENT_DB := -60.0
## Reveal level steps that sound the "you've been spotted" alert.
const REVEAL_ALERT_STEP := 0.25
## The incoming whistle is this long and crescendos to its end, which should meet the impact.
const WHISTLE_LENGTH_S := 2.2
## Only whistle for enemy shells coming down within this many meters of the battery.
const WHISTLE_RADIUS_M := 120.0
const ORBITAL_DESCENT_LENGTH_S := 3.0
## The listener's ears are this far above the battery ground.
const EAR_HEIGHT_M := 2.0
## Ambience levels: wind by speed (m/s), rain by intensity (0..1).
const WIND_DB_CALM := -34.0
const WIND_DB_GALE := -10.0
const WIND_GALE_M_S := 14.0
const RAIN_DB_LIGHT := -26.0
const RAIN_DB_DOWNPOUR := -8.0

var settings: AudioSettings
## False on the dummy driver: sounds are scheduled and logged but not played.
var audible := true
## Seconds since start, the clock that `pending` entries are due on.
var clock := 0.0
## Sounds still travelling to the listener: {"at", "id", "position", "gain_db", "pitch", "offset"}.
var pending: Array[Dictionary] = []
## The last sounds that started (newest last), as the {"id", "gain_db", "cutoff_hz", "pan", ...} used.
var played: Array[Dictionary] = []
## Tests (or a future camera listener) can pin the listener here; Vector2.INF = automatic.
var listener_override := Vector2.INF

var _battle: Node
var _rng := RandomNumberGenerator.new()
var _streams: Dictionary = {}
var _voices: Array[Dictionary] = []
var _ui_players: Array[AudioStreamPlayer] = []
var _music: AudioStreamPlayer
var _sting: AudioStreamPlayer
var _wind: AudioStreamPlayer
var _rain: AudioStreamPlayer
var _levels: Dictionary = {}  # looping player -> target dB
var _mount_ready: Dictionary = {}  # WeaponMount -> bool
var _enemy_flights: Array[ShellFlight] = []
var _last_selection := ""
var _reveal_step := 0
var _research_pending := false
var _hover_left := 0.0
var _last_usec := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	audible = AudioServer.get_driver_name() != "Dummy"
	_rng.randomize()
	settings = AudioSettings.load_from()
	settings.apply()
	_build_players()
	_connect_events()
	get_tree().node_added.connect(_on_node_added)
	SceneRouter.screen_changed.connect(_on_screen_changed)
	_on_screen_changed.call_deferred(SceneRouter.current)


## Quitting mid-sound would leave the server holding live playbacks (leaked at exit).
func _exit_tree() -> void:
	for p in find_children("", "AudioStreamPlayer", false, false):
		(p as AudioStreamPlayer).stop()
		(p as AudioStreamPlayer).stream = null
	_streams.clear()


func _process(_delta: float) -> void:
	# Sound travels in real time: frame deltas are smoothed and drift a few percent from it.
	var now := Time.get_ticks_usec()
	advance((now - _last_usec) / 1e6 if _last_usec > 0 else 0.0)
	_last_usec = now


## Moves the clock: starts sounds that have arrived, follows the battle, fades loops.
func advance(delta: float) -> void:
	clock += delta
	_hover_left -= delta
	var due: Array[Dictionary] = []
	for e in pending:
		if e.at <= clock:
			due.append(e)
	for e in due:
		pending.erase(e)
		_start(e)
	if _research_pending:
		_research_pending = false
		play_ui(&"research")
	if _battle_sim() != null:
		_follow_battle()
	_fade_loops(delta)


## Clears every pending sound and the battle state (tests call this).
func reset() -> void:
	pending.clear()
	played.clear()
	_enemy_flights.clear()
	_mount_ready.clear()
	_battle = null
	listener_override = Vector2.INF


func save_settings() -> void:
	settings.save()


# --- Playing ---

## A sound made at position_m (world meters). It arrives after the distance to the listener at
## the speed of sound, plus extra_delay. Vector2.INF = unplaced (plays now, centred).
func play_at(id: StringName, position_m: Vector2, gain_db: float = 0.0, pitch: float = 1.0,
		extra_delay: float = 0.0) -> void:
	var listener := listener_position_m()
	var delay := extra_delay
	if position_m != Vector2.INF and listener != Vector2.INF:
		delay += AudioMath.arrival_delay(position_m, listener)
	_schedule({"id": id, "position": position_m, "gain_db": gain_db, "pitch": pitch, "offset": 0.0}, delay)


func play_ui(id: StringName, gain_db: float = 0.0, pitch: float = 1.0) -> void:
	_start({"id": id, "position": Vector2.INF, "gain_db": gain_db, "pitch": pitch, "offset": 0.0})


## Where the player hears from: the battery in battle (Vector2.INF outside one).
func listener_position_m() -> Vector2:
	if listener_override != Vector2.INF:
		return listener_override
	var sim := _battle_sim()
	if sim == null:
		return Vector2.INF
	return sim.battery_position_m() + Vector2(0.0, -EAR_HEIGHT_M)


func _schedule(entry: Dictionary, delay: float) -> void:
	if delay <= 0.0:
		_start(entry)
		return
	if pending.size() >= MAX_PENDING:
		pending.pop_front()
	entry["at"] = clock + delay
	pending.append(entry)


func _start(e: Dictionary) -> void:
	var id: StringName = e.id
	var pos: Vector2 = e.position
	var listener := listener_position_m()
	var placed := pos != Vector2.INF and listener != Vector2.INF
	var dist := pos.distance_to(listener) if placed else 0.0
	var spread := SoundBank.pitch_spread(id)
	var info := {
		"id": id,
		"time": clock,
		"distance_m": dist,
		"gain_db": SoundBank.base_db(id) + e.gain_db + AudioMath.distance_gain_db(dist)
			+ (_rng.randf_range(-1.5, 1.5) if spread > 0.0 else 0.0),
		"cutoff_hz": AudioMath.distance_cutoff_hz(dist),
		"pan": _pan_for(pos, listener) if placed else 0.0,
		"pitch": e.pitch * AudioMath.vary(_rng, spread),
	}
	played.append(info)
	if played.size() > PLAYED_LOG_SIZE:
		played.pop_front()
	if not audible:
		return
	var stream := _stream(id)
	if stream == null:
		return
	var player: AudioStreamPlayer
	if SoundBank.bus(id) == SoundBank.SFX:
		var v := _free_voice()
		(v.lpf as AudioEffectLowPassFilter).cutoff_hz = info.cutoff_hz
		(v.panner as AudioEffectPanner).pan = info.pan
		v["started"] = clock
		player = v.player
	elif SoundBank.bus(id) == SoundBank.MUSIC:
		player = _sting
	else:
		player = _free_ui_player()
	player.stream = stream
	player.volume_db = info.gain_db
	player.pitch_scale = maxf(info.pitch, 0.05)
	player.play(e.offset)


func _pan_for(pos: Vector2, listener: Vector2) -> float:
	var cam: Camera2D = _battle.get("camera") if is_instance_valid(_battle) else null
	if cam != null and cam.is_inside_tree():
		var offset_px := (GameConstants.meters_to_pixels(pos).x - cam.get_screen_center_position().x) * cam.zoom.x
		return AudioMath.pan_from_screen(offset_px, cam.get_viewport_rect().size.x * 0.5)
	return AudioMath.pan_from_offset(pos.x - listener.x)


func _stream(id: StringName) -> AudioStream:
	if not _streams.has(id):
		var path := SoundBank.path(id)
		_streams[id] = load(path) if path != "" and ResourceLoader.exists(path) else null
	return _streams[id]


func _free_voice() -> Dictionary:
	var oldest: Dictionary = _voices[0]
	for v in _voices:
		if not (v.player as AudioStreamPlayer).playing:
			return v
		if v.started < oldest.started:
			oldest = v
	return oldest


func _free_ui_player() -> AudioStreamPlayer:
	for p in _ui_players:
		if not p.playing:
			return p
	return _ui_players[0]


func _build_players() -> void:
	var sfx_bus := SoundBank.SFX if AudioServer.get_bus_index(SoundBank.SFX) >= 0 else &"Master"
	for i in VOICE_COUNT:
		var bus_name := StringName("SFX Voice %d" % i)
		var idx := AudioServer.get_bus_index(bus_name)
		if idx < 0:
			idx = AudioServer.bus_count
			AudioServer.add_bus(idx)
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, sfx_bus)
			AudioServer.add_bus_effect(idx, AudioEffectLowPassFilter.new())
			AudioServer.add_bus_effect(idx, AudioEffectPanner.new())
		var p := _player(bus_name)
		_voices.append({"player": p, "lpf": AudioServer.get_bus_effect(idx, 0),
			"panner": AudioServer.get_bus_effect(idx, 1), "started": 0.0})
	for i in UI_VOICE_COUNT:
		_ui_players.append(_player(SoundBank.UI))
	_sting = _player(SoundBank.MUSIC)
	_music = _loop_player(&"menu_theme")
	_wind = _loop_player(&"wind")
	_rain = _loop_player(&"rain")


func _player(bus_name: StringName) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus_name
	add_child(p)
	return p


func _loop_player(id: StringName) -> AudioStreamPlayer:
	var p := _player(SoundBank.bus(id))
	p.volume_db = SILENT_DB
	_levels[p] = SILENT_DB
	p.set_meta(&"sound_id", id)
	return p


## Fades a looping player toward target_db (SILENT_DB stops it once it gets there).
func _set_loop_level(p: AudioStreamPlayer, target_db: float) -> void:
	_levels[p] = target_db
	if target_db > SILENT_DB and audible and not p.playing:
		var stream := _stream(p.get_meta(&"sound_id"))
		if stream != null:
			p.stream = stream
			p.volume_db = SILENT_DB
			# Ambience starts somewhere random in its loop; music from the top.
			p.play(0.0 if p == _music else _rng.randf() * stream.get_length())


func _fade_loops(delta: float) -> void:
	for p: AudioStreamPlayer in _levels:
		var target: float = _levels[p]
		p.volume_db = move_toward(p.volume_db, target, FADE_DB_PER_S * delta)
		if p.playing and target <= SILENT_DB and p.volume_db <= SILENT_DB:
			p.stop()


# --- EventBus ---

func _connect_events() -> void:
	EventBus.battle_started.connect(_on_battle_started)
	EventBus.weather_changed.connect(_on_weather_changed)
	EventBus.shot_fired.connect(_on_shot_fired)
	EventBus.projectile_impacted.connect(_on_projectile_impacted)
	EventBus.projectile_bounced.connect(_on_projectile_bounced)
	EventBus.terrain_carved.connect(_on_terrain_carved)
	EventBus.target_hit.connect(_on_target_hit)
	EventBus.target_destroyed.connect(_on_target_destroyed)
	EventBus.battery_damaged.connect(_on_battery_damaged)
	EventBus.battery_revealed.connect(_on_battery_revealed)
	EventBus.battle_ended.connect(_on_battle_ended)
	EventBus.money_changed.connect(_on_money_changed)
	EventBus.bid_placed.connect(_on_bid_placed)
	EventBus.auction_won.connect(_on_auction_won)
	EventBus.tech_unlocked.connect(_on_tech_unlocked)
	EventBus.era_changed.connect(_on_era_changed)
	EventBus.game_saved.connect(func(_slot: int) -> void: play_ui(&"stamp"))


func _on_battle_started(_contract: ContractData, _plot: PlotData) -> void:
	pending.clear()
	_enemy_flights.clear()
	_mount_ready.clear()
	_last_selection = ""
	_reveal_step = 0
	_set_loop_level(_music, SILENT_DB)
	play_ui(&"battle_start")
	# The battle scene sets `sim` before it starts the sim; find it once the frame settles.
	_attach_battle.call_deferred()


func _on_weather_changed(weather: WeatherState) -> void:
	var wind := clampf((absf(weather.wind_speed) + weather.gust_strength * 0.5) / WIND_GALE_M_S, 0.0, 1.0)
	_set_loop_level(_wind, lerpf(WIND_DB_CALM, WIND_DB_GALE, wind))
	var rain := weather.rain_intensity
	_set_loop_level(_rain, lerpf(RAIN_DB_LIGHT, RAIN_DB_DOWNPOUR, rain) if rain > 0.02 else SILENT_DB)


func _on_shot_fired(weapon_id: StringName, _ammo_id: StringName, _cost: int) -> void:
	var weapon := DataRegistry.get_weapon(weapon_id)
	if weapon == null:
		return
	var mount := _mount_for(weapon_id)
	var pos := mount.muzzle_m() if mount else listener_position_m()
	var pitch: float = SoundBank.WEAPON_PITCH.get(weapon_id, 1.0)
	play_at(SoundBank.launch_sound(weapon.launcher_type), pos, 0.0, pitch)
	if mount and mount.is_orbital():
		# The rod drops ORBITAL_DELAY_S later and falls 400 m: the roar rises to meet the impact,
		# and travels from the strike point like the impact itself.
		var strike := Vector2(mount.designated_x_m, _battle_sim().map.surface_height_at(mount.designated_x_m))
		var fall := BattleSim.ORBITAL_DROP_HEIGHT_M / maxf(mount.muzzle_velocity(), 1.0)
		var lead := BattleSim.ORBITAL_DELAY_S + fall - ORBITAL_DESCENT_LENGTH_S
		play_at(&"orbital_descent", strike, 0.0, 1.0, maxf(lead, 0.0))


func _on_projectile_impacted(position_m: Vector2, ammo_id: StringName) -> void:
	var ammo := DataRegistry.get_ammo(ammo_id)
	var size := SoundBank.blast_size(ammo)
	play_at(SoundBank.impact_sound(ammo), position_m, size.db, size.pitch)


func _on_projectile_bounced(position_m: Vector2, ammo_id: StringName) -> void:
	var size := SoundBank.blast_size(DataRegistry.get_ammo(ammo_id))
	play_at(&"bounce_thud", position_m, size.db, size.pitch)


func _on_terrain_carved(position_m: Vector2, radius_m: float) -> void:
	play_at(&"debris", position_m, clampf(-6.0 + radius_m * 1.5, -6.0, 4.0), clampf(1.25 - 0.05 * radius_m, 0.8, 1.25))


func _on_target_hit(target_id: StringName, damage: float) -> void:
	play_at(&"target_hit", _target_position(target_id), clampf(-6.0 + damage / 20.0, -6.0, 2.0))


func _on_target_destroyed(target_id: StringName) -> void:
	play_at(&"target_collapse", _target_position(target_id))


func _on_battery_damaged(weapon_id: StringName, damage: float) -> void:
	var mount := _mount_for(weapon_id)
	play_at(&"battery_hit", mount.position_m if mount else listener_position_m(), clampf(-4.0 + damage / 25.0, -4.0, 2.0))


func _on_battery_revealed(level: float) -> void:
	var step := floori(level / REVEAL_ALERT_STEP + 1e-6)
	if step > _reveal_step:
		play_ui(&"alert")
	_reveal_step = step


func _on_battle_ended(_result: BattleResult) -> void:
	# Results are committed after the banner; the sting already played on sim.ended.
	_enemy_flights.clear()


func _on_money_changed(_balance: int, delta: int, reason: String) -> void:
	if delta < 0 and (reason.begins_with("Bought") or reason.begins_with("Repaired")):
		play_ui(&"purchase")
	elif delta > 0 and reason == "Contract payout":
		play_ui(&"payout")


func _on_bid_placed(bidder_id: StringName, _contract_id: StringName, _plot_id: StringName, _amount: int) -> void:
	if bidder_id == Auction.PLAYER_ID:
		play_ui(&"stamp")


func _on_auction_won(winner_id: StringName, _contract: ContractData, _plot: PlotData, _price: int) -> void:
	play_ui(&"gavel", 0.0 if winner_id == Auction.PLAYER_ID else -6.0)


func _on_tech_unlocked(_tech_id: StringName) -> void:
	# Deferred to the next frame: an era gate also changes era, and then the fanfare plays instead.
	_research_pending = true


func _on_era_changed(_era: GameConstants.Era) -> void:
	_research_pending = false
	play_ui(&"era")


# --- Battle scene ---

func _attach_battle() -> void:
	var scene := get_tree().current_scene
	if not _has_sim(scene):
		scene = null
		for child in get_tree().root.get_children():
			if _has_sim(child):
				scene = child
	if scene == null or scene == _battle:
		return
	_battle = scene
	var sim: BattleSim = scene.get("sim")
	sim.shell_launched.connect(_on_shell_launched)
	sim.ended.connect(_on_sim_ended)
	scene.tree_exiting.connect(_on_battle_exiting.bind(scene), CONNECT_ONE_SHOT)


func _has_sim(node: Node) -> bool:
	return node != null and node.get("sim") is BattleSim


func _battle_sim() -> BattleSim:
	if not is_instance_valid(_battle):
		return null
	return _battle.get("sim") as BattleSim


func _on_battle_exiting(scene: Node) -> void:
	if scene != _battle:
		return
	_battle = null
	pending.clear()
	_enemy_flights.clear()
	_mount_ready.clear()
	_set_loop_level(_wind, SILENT_DB)
	_set_loop_level(_rain, SILENT_DB)


func _on_shell_launched(flight: ShellFlight, enemy: bool) -> void:
	if not enemy:
		return
	_enemy_flights.append(flight)
	# The defender's gun, far off: its boom arrives late and dull.
	var weapon := flight.params.weapon
	play_at(SoundBank.launch_sound(weapon.launcher_type), flight.position_m, -2.0,
		0.92 * SoundBank.WEAPON_PITCH.get(weapon.id, 1.0))


func _on_sim_ended(victory: bool, _reason: String) -> void:
	play_ui(&"sting_victory" if victory else &"sting_defeat")


## Per frame in battle: reload sounds, weapon/ammo selection clicks, incoming whistles.
func _follow_battle() -> void:
	var sim := _battle_sim()
	if sim.outcome != BattleSim.Outcome.NONE:
		return
	for m in sim.mounts:
		var ready := m.is_ready()
		if ready and not _mount_ready.get(m, true) and m.is_alive():
			play_at(SoundBank.reload_sound(m.weapon.launcher_type), m.muzzle_m(), 0.0,
				SoundBank.WEAPON_PITCH.get(m.weapon.id, 1.0))
		_mount_ready[m] = ready
	var sel := sim.selected_mount()
	var selection := "%d:%s" % [sim.selected, sel.ammo_id if sel else &""]
	if _last_selection != "" and selection != _last_selection:
		play_ui(&"weapon_select")
	_last_selection = selection
	_track_incoming(sim)


func _track_incoming(sim: BattleSim) -> void:
	var listener := listener_position_m()
	for f: ShellFlight in _enemy_flights.duplicate():
		if f.is_finished:
			_enemy_flights.erase(f)
			continue
		var pos := f.position_m
		var vel := f.velocity_m
		var t := time_to_fall(pos.y, vel.y, listener.y + EAR_HEIGHT_M, sim.weather.gravity)
		if t > WHISTLE_LENGTH_S or absf(pos.x + vel.x * t - listener.x) > WHISTLE_RADIUS_M:
			continue
		_enemy_flights.erase(f)
		_start({"id": &"incoming_whistle", "position": pos, "gain_db": 0.0, "pitch": 1.0,
			"offset": WHISTLE_LENGTH_S - t})


## Seconds until a shell at y (moving vy, +y down) falls to ground_y under gravity (drag ignored,
## so it is a slight overestimate). Already below the ground: 0.
static func time_to_fall(y: float, vy: float, ground_y: float, gravity: float) -> float:
	var dy := ground_y - y
	if dy <= 0.0:
		return 0.0
	if gravity <= 0.0:
		return dy / vy if vy > 0.0 else INF
	return (-vy + sqrt(vy * vy + 2.0 * gravity * dy)) / gravity


func _mount_for(weapon_id: StringName) -> WeaponMount:
	var sim := _battle_sim()
	if sim == null:
		return null
	var sel := sim.selected_mount()
	if sel and sel.weapon.id == weapon_id:
		return sel
	for m in sim.mounts:
		if m.weapon.id == weapon_id:
			return m
	return null


func _target_position(target_id: StringName) -> Vector2:
	var sim := _battle_sim()
	if sim:
		for t in sim.targets:
			if t.id == target_id:
				return t.position_m + Vector2(0.0, -BattleRules.TARGET_SIZE_M.y * 0.5)
	return Vector2.INF


# --- UI and screens ---

func _on_node_added(node: Node) -> void:
	if node is BaseButton and not node.pressed.is_connected(_on_button_pressed):
		node.pressed.connect(_on_button_pressed)
		node.mouse_entered.connect(_on_button_hovered.bind(node))
	elif node is TabBar and not node.tab_clicked.is_connected(_on_tab_clicked):
		node.tab_clicked.connect(_on_tab_clicked)


func _on_tab_clicked(_tab: int) -> void:
	play_ui(&"click")


func _on_button_pressed() -> void:
	play_ui(&"click")


func _on_button_hovered(button: BaseButton) -> void:
	if button.disabled or _hover_left > 0.0:
		return
	_hover_left = HOVER_COOLDOWN_S
	play_ui(&"hover")


## Menu music everywhere but the battle, which has its own weather bed.
func _on_screen_changed(screen: SceneRouter.Screen) -> void:
	var music_db := SoundBank.base_db(&"menu_theme")
	_set_loop_level(_music, SILENT_DB if screen == SceneRouter.Screen.BATTLE else music_db)
