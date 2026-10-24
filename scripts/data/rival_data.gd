class_name RivalData
extends Resource
## An AI commander who bids against the player at auction.

@export var id: StringName
@export var display_name: String
@export var starting_money: int = GameConstants.STARTING_MONEY
## 0 = cautious bidder, 1 = overbids freely.
@export_range(0.0, 1.0) var aggression: float = 0.5
## Preferred terrain profiles; bids higher on these.
@export var preferred_terrain: Array[GameConstants.TerrainProfile] = []
