class_name FireControl
extends RefCounted
## The fire-control computer, unlocked by researching Fire Control Computers. Given a target point
## it returns the nominal elevation and charge, correcting for the mean wind, air density and
## height difference (not for gusts or the weapon's spread). Pure; the battle panel shows it.

const TECH_ID := &"fire_control"


static func is_unlocked(player: PlayerState) -> bool:
	return player.unlocked_tech.has(TECH_ID)


## {"ok", "elevation_deg", "charge", "distance_m"} for the mount's loaded ammo; orbital weapons
## get {"ok": true, "designate_x_m"}. Empty if the mount can't fire.
static func solve(sim: BattleSim, m: WeaponMount, target_m: Vector2) -> Dictionary:
	var ammo: AmmoData = sim.ammo_table.get(m.ammo_id)
	if ammo == null or not m.is_alive():
		return {}
	var distance := absf(target_m.x - m.position_m.x)
	if m.is_orbital():
		return {"ok": true, "designate_x_m": target_m.x, "distance_m": distance}
	var aim := AimSolver.solve(m.weapon, ammo, m.muzzle_m(), target_m, sim.weather)
	if aim.is_empty():
		return {}
	return {"ok": aim.ok, "elevation_deg": aim.elevation_deg, "charge": aim.charge, "distance_m": distance}


## Dials the mount onto a solution from solve().
static func apply(m: WeaponMount, solution: Dictionary) -> void:
	if solution.is_empty():
		return
	if solution.has("designate_x_m"):
		m.designated_x_m = solution.designate_x_m
		return
	m.elevation_deg = m.weapon.clamp_elevation(solution.elevation_deg)
	m.charge = clampf(solution.charge, 0.0, 1.0)
