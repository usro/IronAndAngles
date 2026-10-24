class_name PlotData
extends Resource
## A piece of land on the region map. Winning it at auction decides the battlefield terrain.

@export var id: StringName
@export var display_name: String
@export_multiline var description: String
@export var terrain_profile: GameConstants.TerrainProfile = GameConstants.TerrainProfile.FLAT
## Seed for procedural terrain, so the same plot always produces the same ground.
@export var terrain_seed: int = 0
## Height above sea level in meters. Affects air density in battle.
@export var altitude_m: float = 0.0
## Height of the player's battery above the targets, in meters. Higher ground = advantage.
@export var height_advantage_m: float = 0.0
## Horizontal distance from battery to the target zone, in meters.
@export var target_distance_m: float = 300.0
## Position on the region map UI, normalized 0..1.
@export var map_position: Vector2 = Vector2(0.5, 0.5)
