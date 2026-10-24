extends Control
## PLACEHOLDER region map. The economy session replaces this with the real auction;
## it must still set GameState.current_contract / current_plot before going to battle.

var _money_label: Label


func _ready() -> void:
	var box := PlaceholderUI.centered_box(self)
	PlaceholderUI.label(box, "REGION MAP (placeholder)", 32)
	_money_label = PlaceholderUI.label(box, "")
	EventBus.money_changed.connect(_on_money_changed)
	_on_money_changed(GameState.player.money, 0, "")

	for contract: ContractData in DataRegistry.contracts.values():
		var text := "%s - payout %d" % [contract.client_name, contract.payout]
		PlaceholderUI.button(box, text, _take_contract.bind(contract))
	if DataRegistry.contracts.is_empty():
		PlaceholderUI.label(box, "No contracts in res://data/contracts")

	PlaceholderUI.button(box, "Save", SaveSystem.save_game)
	PlaceholderUI.button(box, "Main Menu", SceneRouter.goto.bind(SceneRouter.Screen.MAIN_MENU))


func _on_money_changed(balance: int, _delta: int, _reason: String) -> void:
	_money_label.text = "Funds: %d" % balance


func _take_contract(contract: ContractData) -> void:
	GameState.current_contract = contract
	GameState.current_plot = contract.plots[0] if not contract.plots.is_empty() else null
	SceneRouter.goto(SceneRouter.Screen.BATTLE)
