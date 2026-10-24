class_name WeaponMount
extends RefCounted
## One battery weapon in battle: its dials, health and fire-control timers. Pure model.
##
## Fire control: pull_trigger() starts a salvo of weapon.salvo_size shells, tick(delta) returns
## how many are due (the first at once, then one per salvo_interval). After the last shell the
## weapon is locked for reload_time + cooldown.

const ELEVATION_RATE_DEG := 12.0
const CHARGE_RATE := 0.3
const DESIGNATOR_RATE_M := 60.0
## Holding the fine-adjust key divides dial rates by this.
const FINE_FACTOR := 10.0

var weapon: WeaponData
## Ground point under the weapon (bottom centre of its box), meters.
var position_m: Vector2
var health: float
var ammo_id: StringName = &""
var elevation_deg: float
var charge: float = 0.5
## ORBITAL only: the x the strike is aimed at.
var designated_x_m: float = 0.0
## Seconds until the trigger can be pulled again.
var reload_left: float = 0.0
## Shells still to fire in the current salvo.
var salvo_left: int = 0

var _salvo_timer: float = 0.0
var _lockout_total: float = 0.0


func _init(p_weapon: WeaponData, p_position_m: Vector2, p_health: float) -> void:
	weapon = p_weapon
	position_m = p_position_m
	health = p_health
	elevation_deg = (weapon.elevation_min_deg + weapon.elevation_max_deg) * 0.5
	_lockout_total = lockout_time()


func is_alive() -> bool:
	return health > 0.0


func is_orbital() -> bool:
	return weapon.launcher_type == GameConstants.LauncherType.ORBITAL


## Can a new salvo start now? (Ammo is checked by the battle.)
func is_ready() -> bool:
	return is_alive() and salvo_left == 0 and reload_left <= 0.0


func is_firing() -> bool:
	return salvo_left > 0


## Time the weapon is locked after its last shell.
func lockout_time() -> float:
	return weapon.reload_time + weapon.cooldown


## 0 right after firing, 1 when ready.
func ready_fraction() -> float:
	if salvo_left > 0 or _lockout_total <= 0.0:
		return 0.0 if salvo_left > 0 else 1.0
	return clampf(1.0 - reload_left / _lockout_total, 0.0, 1.0)


## Starts a salvo. False while reloading, firing or destroyed.
func pull_trigger() -> bool:
	if not is_ready():
		return false
	salvo_left = maxi(weapon.salvo_size, 1)
	_salvo_timer = 0.0
	return true


## Advances the timers by delta seconds and returns the number of shells due now.
func tick(delta: float) -> int:
	if not is_alive():
		salvo_left = 0
		return 0
	if salvo_left == 0:
		reload_left = maxf(0.0, reload_left - delta)
		return 0
	var shots := 0
	_salvo_timer -= delta
	while salvo_left > 0 and _salvo_timer <= 0.0:
		shots += 1
		salvo_left -= 1
		_salvo_timer += weapon.salvo_interval
	if salvo_left == 0:
		_start_lockout()
	return shots


## Ends the current salvo early (e.g. out of ammo); the lockout starts now.
func abort_salvo() -> void:
	if salvo_left > 0:
		salvo_left = 0
		_start_lockout()


## Dial speed multiplier: direct-fire weapons need hundredths of a degree at 2 km.
func elevation_scale() -> float:
	return 0.1 if weapon.is_direct_fire() else 1.0


func adjust_elevation(delta_deg: float) -> void:
	elevation_deg = weapon.clamp_elevation(elevation_deg + delta_deg)


func adjust_charge(delta: float) -> void:
	charge = clampf(charge + delta, 0.0, 1.0)


## Propellant: the player picks one of the weapon's fixed increments (Charge 1..N, like charge
## zones or mortar rings; see ChargeIncrements); elevation is the fine control.
func increments() -> PackedFloat32Array:
	return ChargeIncrements.for_weapon(weapon)


## Nearest increment (0-based) to the current charge.
func charge_increment() -> int:
	return ChargeIncrements.nearest(weapon, charge)


## Steps to the next (+1) or previous (-1) increment.
func step_charge(dir: int) -> void:
	var inc := increments()
	charge = inc[clampi(charge_increment() + dir, 0, inc.size() - 1)]


func muzzle_velocity() -> float:
	return weapon.velocity_for_charge(charge)


## Where shells leave the barrel: the top of the weapon's box.
func muzzle_m() -> Vector2:
	return position_m + Vector2(0.0, -BattleRules.MOUNT_SIZE_M.y)


func rect_m() -> Rect2:
	return BattleRules.standing_rect(position_m, BattleRules.MOUNT_SIZE_M)


func _start_lockout() -> void:
	_lockout_total = lockout_time()
	reload_left = _lockout_total
