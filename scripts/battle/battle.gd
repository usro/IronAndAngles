extends Node2D
## PLACEHOLDER battle scene. The battle session replaces this; it must still finish by
## emitting EventBus.battle_ended, calling GameState.apply_battle_result and going to RESULTS.

var _result := BattleResult.new()
var _status: Label


func _ready() -> void:
	var contract := GameState.current_contract
	var plot := GameState.current_plot
	if contract:
		_result.contract_id = contract.id
		EventBus.battle_started.emit(contract, plot)
	if plot:
		_result.plot_id = plot.id

	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(root)
	var box := PlaceholderUI.centered_box(root)
	PlaceholderUI.label(box, "BATTLE (placeholder): %s" % (contract.client_name if contract else "no contract"), 28)
	_status = PlaceholderUI.label(box, "")
	PlaceholderUI.button(box, "Fire stone ball (debug)", _fire_debug)
	PlaceholderUI.button(box, "Win (debug)", _end.bind(true))
	PlaceholderUI.button(box, "Retreat (debug)", _end.bind(false))
	_refresh()


func _fire_debug() -> void:
	var ammo := DataRegistry.get_ammo(&"stone_ball")
	if ammo == null or not GameState.player.consume_ammo(ammo.id):
		return
	GameState.player.charge(ammo.cost_per_shell, "Shell fired")
	_result.shells_fired += 1
	_result.ammo_spent += ammo.cost_per_shell
	_result.ammo_used[ammo.id] = _result.ammo_used.get(ammo.id, 0) + 1
	EventBus.shot_fired.emit(&"trebuchet", ammo.id, ammo.cost_per_shell)
	_refresh()


func _refresh() -> void:
	_status.text = "Shells fired: %d   Spent: %d   Funds: %d   Stones left: %d" % [
		_result.shells_fired, _result.ammo_spent, GameState.player.money,
		GameState.player.ammo_count(&"stone_ball")]


func _end(victory: bool) -> void:
	_result.victory = victory
	var contract := GameState.current_contract
	_result.payout_earned = contract.payout if victory and contract else 0
	EventBus.battle_ended.emit(_result)
	GameState.apply_battle_result(_result)
	SceneRouter.goto(SceneRouter.Screen.RESULTS)
