extends SceneTree
## Manual end-to-end check (not part of the test suite): plays menu -> auction -> battle ->
## results in a real window by pressing the screens' own buttons and the battle's input actions.
## Aims with AimSolver, so it plays like a decent player, not a perfect one.
##   godot --path . -s res://tests/battle/play_through.gd -- <screenshot dir>

const MAX_SECONDS := 600.0

var _shots_dir := ""
var _shot_index := 0
var _gs: Node  # GameState; autoload names are not visible to a -s script at compile time


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_shots_dir = args[0] if not args.is_empty() else ""
	await process_frame
	_gs = get_root().get_node("GameState")
	change_scene_to_file("res://scenes/menu/main_menu.tscn")
	await _frames(10)
	await _snap("menu")
	_press("New Campaign")
	await _frames(10)

	# Auction: bid on the first plot until a contract is won.
	var won := false
	for round_i in 6:
		var map := current_scene
		var plot_buttons: Dictionary = map.get("_plot_buttons")
		plot_buttons.values()[0].pressed.emit()
		await _frames(2)
		var spin: SpinBox = map.get("_bid_spin")
		spin.value = minf(spin.max_value, maxf(spin.min_value, _gs.player.money * 0.4))
		_press("Place sealed bid")
		await _frames(2)
		await _snap("auction_%d" % round_i)
		_press("Close bidding")
		await _frames(5)
		var deploy: Button = map.get("_deploy_button")
		if not deploy.disabled and deploy.visible:
			won = true
			break
		_press("Next week")
		await _frames(5)
	if not won:
		print("PLAY: never won an auction")
		quit(1)
		return
	print("PLAY: won %s" % _gs.economy_state.get("last_contract"))
	_press("Deploy to battle")
	await _frames(10)

	var battle := current_scene
	# Untyped: naming BattleSim here would compile it before the autoloads it uses exist.
	var sim = battle.get("sim")
	print("PLAY: battle %s on %s, %d targets, enemy gun %s" % [sim.contract.id, sim.plot.id,
		sim.targets.size(), sim.enemy_weapon.id if sim.enemy_weapon else &"none"])
	var t := 0.0
	var snapped_flight := false
	while current_scene == battle and t < MAX_SECONDS:
		if sim.outcome == 0:
			var m: WeaponMount = sim.selected_mount()
			if m and m.is_ready() and not sim.player_shots_pending():
				_aim(sim, m)
				_tap("fire")
				snapped_flight = false
			elif not snapped_flight and not sim.flights.is_empty() and t > 1.0:
				await _frames(40)
				await _snap("battle_flight")
				snapped_flight = true
		await process_frame
		t += get_root().get_process_delta_time()
	await _frames(20)
	var r: BattleResult = _gs.last_battle_result
	await _snap("results")
	if r == null:
		print("PLAY: no result after %.0f s" % t)
		quit(1)
		return
	print("PLAY: %s  shells %d hit %d  spent %d  payout %d  damage %s  %.1f s  ammo %s  funds %d" % [
		"VICTORY" if r.victory else "DEFEAT", r.shells_fired, r.shells_hit, r.ammo_spent,
		r.payout_earned, r.damage_taken, r.duration_s, r.ammo_used, _gs.player.money])
	quit(0)


## Dials the weapon onto the nearest live target the way a player would, then fires.
func _aim(sim, m: WeaponMount) -> void:
	for target in sim.targets:
		if target.is_destroyed():
			continue
		var sol := AimSolver.solve(m.weapon, sim.ammo_table[m.ammo_id], m.muzzle_m(), target.position_m,
			sim.weather, AimSolver.Arc.HIGH)
		m.elevation_deg = sol.elevation_deg
		m.charge = sol.charge
		return


func _tap(action: StringName) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event(up)


func _press(text: String) -> void:
	var b := _find_button(current_scene, text)
	if b == null:
		print("PLAY: no button '%s'" % text)
		return
	b.pressed.emit()


func _find_button(node: Node, text: String) -> Button:
	if node is Button and (node as Button).text.begins_with(text):
		return node
	for c in node.get_children():
		var found := _find_button(c, text)
		if found:
			return found
	return null


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _snap(name: String) -> void:
	if _shots_dir == "":
		return
	await process_frame
	var img := get_root().get_texture().get_image()
	_shot_index += 1
	img.save_png(_shots_dir.path_join("%02d_%s.png" % [_shot_index, name]))
