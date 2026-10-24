class_name AmmoData
extends Resource
## Static definition of a projectile type. Instances live in res://data/ammo/*.tres.

@export var id: StringName
@export var display_name: String
@export_multiline var description: String
@export var era: GameConstants.Era = GameConstants.Era.MEDIEVAL
@export var damage_type: GameConstants.DamageType = GameConstants.DamageType.KINETIC

@export_group("Economy")
## Money deducted every time one shell is fired.
@export var cost_per_shell: int = 10

@export_group("Flight")
@export var mass_kg: float = 10.0
@export var drag_coefficient: float = 0.47
@export var cross_section_m2: float = 0.03
## Multiplier on wind force. 0 = immune (railgun).
@export var wind_sensitivity: float = 1.0
## Homes toward a designated point (laser-guided). Ballistics session defines the steering model.
@export var guided: bool = false
## Rockets: thrust (N) applied for burn_time seconds after launch.
@export var thrust_n: float = 0.0
@export var burn_time: float = 0.0

@export_group("Impact")
@export var damage: float = 50.0
@export var explosion_radius_m: float = 2.0
## How much terrain is removed, in meters. 0 = no crater.
@export var crater_radius_m: float = 1.5
## 0 = sticks on impact, 1 = perfectly elastic.
@export_range(0.0, 1.0) var bounce_restitution: float = 0.0
## Random deflection on bounce in degrees (seeded, so learnable but not fixed).
@export var bounce_randomness_deg: float = 0.0
@export var max_bounces: int = 0
## Shrapnel: fragments spawned when the shell bursts.
@export var fragment_count: int = 0
## Multiplier applied to incendiary damage per unit of rain intensity (0..1).
@export var rain_penalty: float = 0.0
