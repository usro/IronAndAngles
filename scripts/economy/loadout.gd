class_name Loadout
extends RefCounted
## Which owned weapons go to battle. Pure rules over PlayerState.loadout and a weapon table.
##
## - The battery has a limited number of slots, growing with the era (BATTERY_SLOTS).
## - Only weapons with health left can deploy; a destroyed gun must be repaired first.
## - PlayerState.loadout empty means "automatic": the best serviceable weapons (newest era,
##   then most expensive) fill the slots. The first manual change turns that pick into an
##   explicit list, which is then kept as the player sets it.
## - If none of the chosen weapons can deploy, the automatic pick is used, so a battle always
##   has a gun when the player owns a working one.

enum Status { OK, NOT_OWNED, NO_FREE_SLOT, BROKEN }

## Battery slots per era: Medieval, Industrial, Modern, Experimental.
const BATTERY_SLOTS: Array[int] = [2, 3, 3, 4]


static func slots(era: GameConstants.Era) -> int:
	return BATTERY_SLOTS[clampi(era, 0, BATTERY_SLOTS.size() - 1)]


static func status_text(status: Status) -> String:
	match status:
		Status.OK: return "Done"
		Status.NOT_OWNED: return "You don't own that weapon"
		Status.NO_FREE_SLOT: return "Battery full: stand another gun down first"
		Status.BROKEN: return "Destroyed: repair it before deploying"
	return "Unknown status"


## The weapons that will deploy in the next battle, in pad order.
static func deployed(player: PlayerState, weapons: Dictionary) -> Array[WeaponData]:
	var out: Array[WeaponData] = []
	for id in player.loadout:
		var w: WeaponData = weapons.get(id)
		if w and player.owned_weapons.has(id) and _serviceable(player, id) and out.size() < slots(player.current_era):
			out.append(w)
	return out if not out.is_empty() else auto_pick(player, weapons)


static func is_deployed(player: PlayerState, weapons: Dictionary, weapon_id: StringName) -> bool:
	return deployed(player, weapons).any(func(w: WeaponData) -> bool: return w.id == weapon_id)


## Best serviceable weapons for the slots: newest era first, then the most expensive.
static func auto_pick(player: PlayerState, weapons: Dictionary) -> Array[WeaponData]:
	var pool: Array[WeaponData] = []
	for id in player.owned_weapons:
		var w: WeaponData = weapons.get(id)
		if w and _serviceable(player, id):
			pool.append(w)
	pool.sort_custom(func(a: WeaponData, b: WeaponData) -> bool:
		if a.era != b.era:
			return a.era > b.era
		if a.purchase_cost != b.purchase_cost:
			return a.purchase_cost > b.purchase_cost
		return a.id < b.id)
	return pool.slice(0, slots(player.current_era))


static func check_toggle(player: PlayerState, weapons: Dictionary, weapon_id: StringName) -> Status:
	if not player.owned_weapons.has(weapon_id) or not weapons.has(weapon_id):
		return Status.NOT_OWNED
	if is_deployed(player, weapons, weapon_id):
		return Status.OK
	if not _serviceable(player, weapon_id):
		return Status.BROKEN
	if deployed(player, weapons).size() >= slots(player.current_era):
		return Status.NO_FREE_SLOT
	return Status.OK


## Deploys a reserve gun or stands a deployed one down.
static func toggle(player: PlayerState, weapons: Dictionary, weapon_id: StringName) -> Status:
	var status := check_toggle(player, weapons, weapon_id)
	if status != Status.OK:
		return status
	_materialize(player, weapons)
	if player.loadout.has(weapon_id):
		player.loadout.erase(weapon_id)
	else:
		player.loadout.append(weapon_id)
	player.inventory_changed.emit()
	return Status.OK


## A newly bought gun joins the battery if there is a free slot.
static func on_bought(player: PlayerState, weapons: Dictionary, weapon_id: StringName) -> void:
	if is_deployed(player, weapons, weapon_id):
		return
	if deployed(player, weapons).size() < slots(player.current_era):
		_materialize(player, weapons)
		player.loadout.append(weapon_id)
		player.inventory_changed.emit()


## Turns the current deployment (automatic or not) into the explicit list.
static func _materialize(player: PlayerState, weapons: Dictionary) -> void:
	var ids: Array[StringName] = []
	for w in deployed(player, weapons):
		ids.append(w.id)
	player.loadout = ids


static func _serviceable(player: PlayerState, weapon_id: StringName) -> bool:
	return float(player.weapon_health.get(weapon_id, 0.0)) > 0.0
