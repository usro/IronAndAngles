class_name TutorialTips
extends PanelContainer
## First-battle coaching: a tip card above the key strip that appears when its moment comes, once
## per player (Settings.tips_seen), and only while tips are enabled. Key names follow the player's
## bindings. Each tip leaves when its follow-up happens or after SHOW_S seconds.

const SHOW_S := 14.0

var battle: Node
var _current := ""
var _left := 0.0
var _label: Label
var _observed := false
var _damaged := false


func _ready() -> void:
	theme_type_variation = &"HudPanel"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Bottom right, over the observer pane's ground: clear of every HUD plate.
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_right = -14.0
	offset_bottom = -40.0
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	var box := VBoxContainer.new()
	add_child(box)
	var kicker := Label.new()
	kicker.theme_type_variation = &"SectionLabel"
	kicker.text = "FIELD TIP"
	kicker.add_theme_color_override("font_color", Blueprint.AMBER)
	box.add_child(kicker)
	_label = Label.new()
	_label.theme_type_variation = &"BodyLabel"
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.custom_minimum_size = Vector2(520, 0)
	box.add_child(_label)
	visible = false
	battle.sim.shell_observed.connect(func(_p: Vector2, _h: bool) -> void: _observed = true)
	EventBus.battery_damaged.connect(_on_damaged)


func _on_damaged(_id: StringName, _dmg: float) -> void:
	_damaged = true


## The tips in order: id, when it may show, when it's done (then the next may come).
func _tips() -> Array:
	var sim: BattleSim = battle.sim
	var table: FiringTablePanel = battle.firing_table
	return [
		["welcome", func() -> bool: return true, func() -> bool: return table.visible,
			"Your battery is on the left; the forward observer watches the targets on the right. Press %s to open the firing table." % _k(&"toggle_firing_table")],
		["rangefinder", func() -> bool: return table.visible, func() -> bool: return table.input_range_m > 0.0 and not battle._ranging and _was_measured(),
			"Hold the RIGHT MOUSE BUTTON on a target to measure its range and height, then let go: the numbers go into the table."],
		["read_table", func() -> bool: return table.input_range_m > 0.0, func() -> bool: return sim.result.shells_fired > 0,
			"The amber line is your solution: dial that ELEVATION with %s / %s (hold %s for fine steps). If it says out of reach, change CHARGE with %s / %s. Then fire with %s." % [
				_k(&"aim_up"), _k(&"aim_down"), _k(&"fine_adjust"), _k(&"charge_up"), _k(&"charge_down"), _k(&"fire")]],
		["observer", func() -> bool: return _observed, func() -> bool: return sim.result.shells_fired >= 3,
			"The observer calls each shot (SHORT / OVER). At a low angle, short means raise the barrel; at a high angle it's the reverse. Bracket: one short, one over, then split the difference."],
		["return_fire", func() -> bool: return sim.reveal_level >= SimpleEnemyBrain.HOLD_BELOW_REVEAL, func() -> bool: return sim.enemy_spotted,
			"Every shot reveals you. The enemy gun will fire back soon: its red muzzle flash gives away its position. Destroy it to silence it for good, and earn a bonus."],
		["relocate", func() -> bool: return _damaged, func() -> bool: return sim.relocating_left > 0.0,
			"You're taking hits. Press %s to relocate: your guns go quiet for 15 s, and the enemy loses most of its fix on you." % _k(&"relocate")],
		["computer", func() -> bool: return FireControl.is_unlocked(sim.player) and table.visible, func() -> bool: return false,
			"Your fire-control computer is online: press %s to dial in the nearest target, wind included." % _k(&"apply_solution")],
	]


var _measured_seen := false


func _was_measured() -> bool:
	# Done once the player has measured something themselves (or typed a range).
	_measured_seen = _measured_seen or battle._range_point != Vector2.INF
	return _measured_seen or GameState.player.current_era > GameConstants.Era.MEDIEVAL


func _process(delta: float) -> void:
	if battle == null or not Settings.tips_enabled:
		visible = false
		return
	var tips := _tips()
	if _current != "":
		_left -= delta
		for t in tips:
			if t[0] == _current and (t[2].call() or _left <= 0.0):
				_current = ""
				visible = false
		return
	for t in tips:
		if Settings.tips_seen.has(t[0]):
			continue
		if t[1].call():
			_current = t[0]
			_left = SHOW_S
			_label.text = t[3]
			visible = true
			Settings.mark_tip(t[0])
		return


static func _k(action: StringName) -> String:
	return "[%s]" % Settings.key_name(action)
