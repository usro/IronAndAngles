class_name PlayerState
extends RefCounted
## The player's persistent campaign data. Pure model: no node or autoload dependencies.
## GameState relays its signals to EventBus.

signal money_changed(balance: int, delta: int, reason: String)
signal inventory_changed

var money: int = GameConstants.STARTING_MONEY
var owned_weapons: Array[StringName] = []
## ammo id -> shell count
var ammo: Dictionary = {}
var unlocked_tech: Array[StringName] = []
## weapon id -> current health
var weapon_health: Dictionary = {}
var current_era: GameConstants.Era = GameConstants.Era.MEDIEVAL
var completed_contracts: Array[StringName] = []
## Weapons the player chose to deploy (see Loadout for the slot rules). Empty = automatic.
var loadout: Array[StringName] = []
var reputation: int = 0


func can_afford(amount: int) -> bool:
	return amount <= money


## Returns false (and changes nothing) if the player cannot afford it.
func spend(amount: int, reason: String) -> bool:
	assert(amount >= 0, "spend() takes a positive amount")
	if not can_afford(amount):
		return false
	money -= amount
	money_changed.emit(money, -amount, reason)
	return true


func earn(amount: int, reason: String) -> void:
	assert(amount >= 0, "earn() takes a positive amount")
	money += amount
	money_changed.emit(money, amount, reason)


## Battle costs are charged even if they push money negative (debt is allowed mid-contract).
func charge(amount: int, reason: String) -> void:
	money -= amount
	money_changed.emit(money, -amount, reason)


func ammo_count(ammo_id: StringName) -> int:
	return ammo.get(ammo_id, 0)


func add_ammo(ammo_id: StringName, count: int) -> void:
	ammo[ammo_id] = ammo_count(ammo_id) + count
	inventory_changed.emit()


## Returns false if there is not enough ammo.
func consume_ammo(ammo_id: StringName, count: int = 1) -> bool:
	if ammo_count(ammo_id) < count:
		return false
	ammo[ammo_id] = ammo_count(ammo_id) - count
	inventory_changed.emit()
	return true


func add_weapon(weapon: WeaponData) -> void:
	if not owned_weapons.has(weapon.id):
		owned_weapons.append(weapon.id)
		weapon_health[weapon.id] = weapon.max_health
		inventory_changed.emit()


func remove_weapon(weapon_id: StringName) -> void:
	owned_weapons.erase(weapon_id)
	weapon_health.erase(weapon_id)
	loadout.erase(weapon_id)
	inventory_changed.emit()


func to_dict() -> Dictionary:
	return {
		"money": money,
		"owned_weapons": owned_weapons.map(func(s): return String(s)),
		"ammo": _keys_to_string(ammo),
		"unlocked_tech": unlocked_tech.map(func(s): return String(s)),
		"weapon_health": _keys_to_string(weapon_health),
		"current_era": current_era,
		"completed_contracts": completed_contracts.map(func(s): return String(s)),
		"loadout": loadout.map(func(s): return String(s)),
		"reputation": reputation,
	}


static func from_dict(d: Dictionary) -> PlayerState:
	var p := PlayerState.new()
	p.money = int(d.get("money", GameConstants.STARTING_MONEY))
	p.owned_weapons = _to_names(d.get("owned_weapons", []))
	p.unlocked_tech = _to_names(d.get("unlocked_tech", []))
	p.completed_contracts = _to_names(d.get("completed_contracts", []))
	p.loadout = _to_names(d.get("loadout", []))
	for k in d.get("ammo", {}):
		p.ammo[StringName(k)] = int(d["ammo"][k])
	for k in d.get("weapon_health", {}):
		p.weapon_health[StringName(k)] = float(d["weapon_health"][k])
	p.current_era = int(d.get("current_era", 0)) as GameConstants.Era
	p.reputation = int(d.get("reputation", 0))
	return p


static func _keys_to_string(src: Dictionary) -> Dictionary:
	var out := {}
	for k in src:
		out[String(k)] = src[k]
	return out


static func _to_names(arr: Array) -> Array[StringName]:
	var out: Array[StringName] = []
	for s in arr:
		out.append(StringName(s))
	return out
