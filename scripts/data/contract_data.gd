class_name ContractData
extends Resource
## A siege/defense job offered at auction. Payout is fixed; shells fired come out of it.

@export var id: StringName
## For a contract generated for one week's auction: the handcrafted contract it was made from.
## Empty for handcrafted contracts.
@export var template_id: StringName
@export var client_name: String
@export_multiline var briefing: String
@export var era_required: GameConstants.Era = GameConstants.Era.MEDIEVAL
## Fixed payment on success.
@export var payout: int = 1000
## Minimum bid accepted at auction.
@export var reserve_price: int = 100
## Plots that can be bid on for this contract. The winner fights from that plot.
@export var plots: Array[PlotData] = []
@export var target_count: int = 3
@export var target_health: float = 100.0
@export var weather: WeatherState
## 1 = easy. Scales enemy counter-battery accuracy and target hardness.
@export_range(1, 5) var difficulty: int = 1
## Seconds before the contract is forfeit. 0 = no limit.
@export var time_limit: float = 0.0
