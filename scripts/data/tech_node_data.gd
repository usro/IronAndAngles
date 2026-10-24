class_name TechNodeData
extends Resource
## One node in the tech tree. Instances live in res://data/tech/*.tres.

@export var id: StringName
@export var display_name: String
@export_multiline var description: String
@export var era: GameConstants.Era = GameConstants.Era.MEDIEVAL
@export var research_cost: int = 0
## Unlocking this node moves the player into `era`. Other nodes of a later era stay locked until then.
@export var era_gate: bool = false
## Tech ids that must be unlocked first.
@export var prerequisites: Array[StringName] = []
## Weapon/ammo ids that become purchasable when unlocked.
@export var unlocks_weapons: Array[StringName] = []
@export var unlocks_ammo: Array[StringName] = []
## Position in the tech tree UI, in grid cells.
@export var tree_position: Vector2i = Vector2i.ZERO


func is_available(unlocked: Array[StringName]) -> bool:
	for p in prerequisites:
		if not unlocked.has(p):
			return false
	return true
