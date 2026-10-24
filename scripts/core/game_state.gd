extends Node
## Autoload "GameState": the live campaign. Holds the player model and the current contract,
## and relays model signals to EventBus so views can listen without holding references.

var player: PlayerState
var campaign_seed: int = 0
var rng := RandomNumberGenerator.new()

## Set by the auction when the player wins; read by the battle scene.
var current_contract: ContractData
var current_plot: PlotData
## Set by the battle scene when it ends; read by the results screen.
var last_battle_result: BattleResult
## Campaign data owned by the economy (rival funds, last contract price). JSON-safe values only;
## SaveSystem stores it as-is. Read and written through scripts/economy, not directly.
var economy_state: Dictionary = {}


func _ready() -> void:
	new_game()


func new_game(seed_value: int = -1) -> void:
	campaign_seed = seed_value if seed_value >= 0 else randi()
	rng.seed = campaign_seed
	_set_player(PlayerState.new())
	current_contract = null
	current_plot = null
	last_battle_result = null
	economy_state = {}
	_grant_starting_kit()


## Applies a finished battle to the campaign. Shell costs were already charged when fired.
func apply_battle_result(result: BattleResult) -> void:
	last_battle_result = result
	if result.victory:
		player.earn(result.payout_earned, "Contract payout")
		# Generated contracts count as their client (template), so offers rotate between clients.
		var contract := DataRegistry.get_contract(result.contract_id)
		var done_id := contract.template_id if contract and contract.template_id != &"" else result.contract_id
		if not player.completed_contracts.has(done_id):
			player.completed_contracts.append(done_id)
	for weapon_id in result.damage_taken:
		var hp: float = player.weapon_health.get(weapon_id, 0.0)
		player.weapon_health[weapon_id] = maxf(0.0, hp - result.damage_taken[weapon_id])
	current_contract = null
	current_plot = null


func load_player(state: PlayerState, seed_value: int) -> void:
	campaign_seed = seed_value
	rng.seed = seed_value
	_set_player(state)


func _set_player(state: PlayerState) -> void:
	if player:
		player.money_changed.disconnect(EventBus.money_changed.emit)
		player.inventory_changed.disconnect(EventBus.inventory_changed.emit)
	player = state
	player.money_changed.connect(EventBus.money_changed.emit)
	player.inventory_changed.connect(EventBus.inventory_changed.emit)
	EventBus.money_changed.emit(player.money, 0, "Loaded")


func _grant_starting_kit() -> void:
	# Placeholder kit; the tech-tree/content session decides the real one.
	var trebuchet := DataRegistry.get_weapon(&"trebuchet")
	if trebuchet:
		player.add_weapon(trebuchet)
	if DataRegistry.get_ammo(&"stone_ball"):
		player.add_ammo(&"stone_ball", 20)
