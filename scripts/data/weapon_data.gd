class_name WeaponData
extends Resource
## Static definition of an artillery piece. Instances live in res://data/weapons/*.tres.

@export var id: StringName
@export var display_name: String
@export_multiline var description: String
@export var era: GameConstants.Era = GameConstants.Era.MEDIEVAL
@export var launcher_type: GameConstants.LauncherType = GameConstants.LauncherType.MECHANICAL

@export_group("Economy")
@export var purchase_cost: int = 0
## Repair cost per point of missing health.
@export var repair_cost_per_hp: int = 1
## Energy drawn per shot (Tier 4). Charged as money in the battle ledger.
@export var energy_cost_per_shot: int = 0

@export_group("Durability")
@export var max_health: float = 100.0

@export_group("Aiming")
@export_range(-10.0, 90.0) var elevation_min_deg: float = 15.0
@export_range(-10.0, 90.0) var elevation_max_deg: float = 75.0
## Muzzle velocity in m/s at minimum and maximum charge. The player dials a charge in [0, 1].
@export var muzzle_velocity_min: float = 20.0
@export var muzzle_velocity_max: float = 60.0
## Random spread added to elevation at launch, in degrees (crude weapons are imprecise).
@export var spread_deg: float = 0.0

@export_group("Rate of fire")
@export var reload_time: float = 5.0
## Shots per trigger pull (MLRS). Each shot still costs one shell.
@export var salvo_size: int = 1
@export var salvo_interval: float = 0.0
## Extra lockout after firing (Tier 4 cooldowns), on top of reload_time.
@export var cooldown: float = 0.0

@export_group("Ammo")
@export var allowed_ammo: Array[StringName] = []


## Maps a charge dial value in [0, 1] to muzzle velocity in m/s.
func velocity_for_charge(charge: float) -> float:
	return lerpf(muzzle_velocity_min, muzzle_velocity_max, clampf(charge, 0.0, 1.0))


func clamp_elevation(deg: float) -> float:
	return clampf(deg, elevation_min_deg, elevation_max_deg)
