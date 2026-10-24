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
	# Like a fire-direction centre: the lowest propellant increment that reaches, low angle.
	var best := {}
	for c in m.increments():
		var aim := AimSolver.solve_at_charge(m.weapon, ammo, m.muzzle_m(), target_m, sim.weather, c)
		if aim.ok:
			best = aim
			break
		if best.is_empty() or absf(aim.miss_m) < absf(best.miss_m):
			best = aim
	if best.is_empty():
		return {}
	return {"ok": best.ok, "elevation_deg": best.elevation_deg, "charge": best.charge, "distance_m": distance}


## Dials the mount onto a solution from solve().
static func apply(m: WeaponMount, solution: Dictionary) -> void:
	if solution.is_empty():
		return
	if solution.has("designate_x_m"):
		m.designated_x_m = solution.designate_x_m
		return
	m.elevation_deg = m.weapon.clamp_elevation(solution.elevation_deg)
	m.charge = clampf(solution.charge, 0.0, 1.0)
