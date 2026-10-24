class_name Shop
extends RefCounted
## Buying weapons and ammo, and repairing weapons, through PlayerState.spend.
## Pure: built from the registry dictionaries, so tests can pass their own data.
##
## Availability: an item is for sale when its era is at most the player's era and either no
## tech node unlocks it (base kit) or a tech node the player has unlocked lists it in
## unlocks_weapons / unlocks_ammo. Only the TechNodeData fields are read, not TechTree.
##
## Ammo pricing: firing a shell charges its full cost_per_shell in battle (the GDD's
## "every shell fired costs money"). Stocking shells here only costs a requisition fee of
## AMMO_STOCK_FEE_RATE x cost_per_shell, so the per-shot cost stays the main expense.

enum Status { OK, UNKNOWN_ITEM, LOCKED, UNAFFORDABLE, ALREADY_OWNED, NOT_OWNED, NOTHING_TO_REPAIR, INVALID_AMOUNT,
	LAST_WEAPON }

const AMMO_STOCK_FEE_RATE := 0.25
## A weapon sells for this share of its purchase price, minus what its damage would cost to repair.
const RESALE_RATE := 0.5

var _weapons: Dictionary  # StringName -> WeaponData
var _ammo: Dictionary     # StringName -> AmmoData
var _tech: Dictionary     # StringName -> TechNodeData


func _init(weapons: Dictionary, ammo: Dictionary, tech: Dictionary) -> void:
	_weapons = weapons
	_ammo = ammo
	_tech = tech


static func status_text(status: Status) -> String:
	match status:
		Status.OK: return "Done"
		Status.UNKNOWN_ITEM: return "Unknown item"
		Status.LOCKED: return "Not unlocked yet"
		Status.UNAFFORDABLE: return "Not enough funds"
		Status.ALREADY_OWNED: return "Already owned"
		Status.NOT_OWNED: return "You don't own that weapon"
		Status.NOTHING_TO_REPAIR: return "Already at full health"
		Status.INVALID_AMOUNT: return "Invalid amount"
		Status.LAST_WEAPON: return "Can't sell your only weapon"
	return "Unknown status"


# --- Availability ---

func is_weapon_unlocked(player: PlayerState, weapon_id: StringName) -> bool:
	var weapon: WeaponData = _weapons.get(weapon_id)
	return weapon != null and _is_unlocked(player, weapon_id, weapon.era, true)


func is_ammo_unlocked(player: PlayerState, ammo_id: StringName) -> bool:
	var ammo: AmmoData = _ammo.get(ammo_id)
	return ammo != null and _is_unlocked(player, ammo_id, ammo.era, false)


## All weapons in id order, locked ones included so the view can show what's coming.
func weapon_catalog() -> Array[WeaponData]:
	var out: Array[WeaponData] = []
	out.assign(_weapons.values())
	out.sort_custom(func(a: WeaponData, b: WeaponData) -> bool: return a.id < b.id)
	return out


func ammo_catalog() -> Array[AmmoData]:
	var out: Array[AmmoData] = []
	out.assign(_ammo.values())
	out.sort_custom(func(a: AmmoData, b: AmmoData) -> bool: return a.id < b.id)
	return out


func _is_unlocked(player: PlayerState, item_id: StringName, era: GameConstants.Era, is_weapon: bool) -> bool:
	if era > player.current_era:
		return false
	var gated := false
	for node: TechNodeData in _tech.values():
		var unlocks: Array[StringName] = node.unlocks_weapons if is_weapon else node.unlocks_ammo
		if unlocks.has(item_id):
			if player.unlocked_tech.has(node.id):
				return true
			gated = true
	return not gated


# --- Buying ---

func weapon_price(weapon_id: StringName) -> int:
	var weapon: WeaponData = _weapons.get(weapon_id)
	return weapon.purchase_cost if weapon else 0


func check_weapon(player: PlayerState, weapon_id: StringName) -> Status:
	if not _weapons.has(weapon_id):
		return Status.UNKNOWN_ITEM
	if player.owned_weapons.has(weapon_id):
		return Status.ALREADY_OWNED
	if not is_weapon_unlocked(player, weapon_id):
		return Status.LOCKED
	if not player.can_afford(weapon_price(weapon_id)):
		return Status.UNAFFORDABLE
	return Status.OK


func buy_weapon(player: PlayerState, weapon_id: StringName) -> Status:
	var status := check_weapon(player, weapon_id)
	if status != Status.OK:
		return status
	var weapon: WeaponData = _weapons[weapon_id]
	player.spend(weapon.purchase_cost, "Bought %s" % weapon.display_name)
	player.add_weapon(weapon)
	Loadout.on_bought(player, _weapons, weapon_id)
	return Status.OK


# --- Selling ---

## What the shop pays for an owned weapon: RESALE_RATE of its price minus its full repair cost.
func sell_value(player: PlayerState, weapon_id: StringName) -> int:
	var weapon: WeaponData = _weapons.get(weapon_id)
	if weapon == null or not player.owned_weapons.has(weapon_id):
		return 0
	return maxi(0, floori(weapon.purchase_cost * RESALE_RATE) - repair_cost(player, weapon_id))


func check_sell(player: PlayerState, weapon_id: StringName) -> Status:
	if not _weapons.has(weapon_id):
		return Status.UNKNOWN_ITEM
	if not player.owned_weapons.has(weapon_id):
		return Status.NOT_OWNED
	if player.owned_weapons.size() <= 1:
		return Status.LAST_WEAPON
	return Status.OK


## Sells the weapon (it leaves the battery too). Ammo stays in stock.
func sell_weapon(player: PlayerState, weapon_id: StringName) -> Status:
	var status := check_sell(player, weapon_id)
	if status != Status.OK:
		return status
	var value := sell_value(player, weapon_id)
	player.remove_weapon(weapon_id)
	player.earn(value, "Sold %s" % (_weapons[weapon_id] as WeaponData).display_name)
	return Status.OK


func ammo_price(ammo_id: StringName, count: int) -> int:
	var ammo: AmmoData = _ammo.get(ammo_id)
	return ceili(ammo.cost_per_shell * AMMO_STOCK_FEE_RATE * count) if ammo else 0


func check_ammo(player: PlayerState, ammo_id: StringName, count: int) -> Status:
	if not _ammo.has(ammo_id):
		return Status.UNKNOWN_ITEM
	if count <= 0:
		return Status.INVALID_AMOUNT
	if not is_ammo_unlocked(player, ammo_id):
		return Status.LOCKED
	if not player.can_afford(ammo_price(ammo_id, count)):
		return Status.UNAFFORDABLE
	return Status.OK


func buy_ammo(player: PlayerState, ammo_id: StringName, count: int) -> Status:
	var status := check_ammo(player, ammo_id, count)
	if status != Status.OK:
		return status
	var ammo: AmmoData = _ammo[ammo_id]
	player.spend(ammo_price(ammo_id, count), "Bought %d x %s" % [count, ammo.display_name])
	player.add_ammo(ammo_id, count)
	return Status.OK


# --- Repairs ---

func missing_health(player: PlayerState, weapon_id: StringName) -> float:
	var weapon: WeaponData = _weapons.get(weapon_id)
	if weapon == null or not player.owned_weapons.has(weapon_id):
		return 0.0
	return maxf(0.0, weapon.max_health - float(player.weapon_health.get(weapon_id, 0.0)))


## Cost of restoring `hp` health (partial points round up). Defaults to a full repair.
func repair_cost(player: PlayerState, weapon_id: StringName, hp: float = INF) -> int:
	var weapon: WeaponData = _weapons.get(weapon_id)
	if weapon == null:
		return 0
	return ceili(minf(hp, missing_health(player, weapon_id))) * weapon.repair_cost_per_hp


## Most health the player can restore right now with their funds.
func affordable_repair_hp(player: PlayerState, weapon_id: StringName) -> float:
	var weapon: WeaponData = _weapons.get(weapon_id)
	var missing := missing_health(player, weapon_id)
	if weapon == null or weapon.repair_cost_per_hp <= 0:
		return missing
	return minf(missing, floorf(maxf(0, player.money) / float(weapon.repair_cost_per_hp)))


func check_repair(player: PlayerState, weapon_id: StringName, hp: float = INF) -> Status:
	if not _weapons.has(weapon_id):
		return Status.UNKNOWN_ITEM
	if not player.owned_weapons.has(weapon_id):
		return Status.NOT_OWNED
	if hp <= 0.0:
		return Status.INVALID_AMOUNT
	if missing_health(player, weapon_id) <= 0.0:
		return Status.NOTHING_TO_REPAIR
	if not player.can_afford(repair_cost(player, weapon_id, hp)):
		return Status.UNAFFORDABLE
	return Status.OK


## Restores up to `hp` health (default: all of it). Refuses if the whole repair is unaffordable.
func repair(player: PlayerState, weapon_id: StringName, hp: float = INF) -> Status:
	var status := check_repair(player, weapon_id, hp)
	if status != Status.OK:
		return status
	var weapon: WeaponData = _weapons[weapon_id]
	var restored := minf(hp, missing_health(player, weapon_id))
	player.spend(repair_cost(player, weapon_id, hp), "Repaired %s" % weapon.display_name)
	player.weapon_health[weapon_id] = minf(weapon.max_health, float(player.weapon_health[weapon_id]) + restored)
	player.inventory_changed.emit()
	return Status.OK
