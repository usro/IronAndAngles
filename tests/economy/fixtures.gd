extends RefCounted
## Builders for economy tests, so they don't depend on the content in data/.


static func plot(id: StringName, profile := GameConstants.TerrainProfile.FLAT) -> PlotData:
	var p := PlotData.new()
	p.id = id
	p.terrain_profile = profile
	return p


static func contract(id: StringName, payout := 1000, reserve := 100, plots: Array[PlotData] = [],
		era := GameConstants.Era.MEDIEVAL) -> ContractData:
	var c := ContractData.new()
	c.id = id
	c.payout = payout
	c.reserve_price = reserve
	c.era_required = era
	if plots.is_empty():
		plots = [plot(StringName("%s_plot" % id))]
	c.plots = plots
	return c


static func rival(id: StringName, money := 5000, aggression := 0.5,
		preferred: Array[GameConstants.TerrainProfile] = []) -> RivalData:
	var r := RivalData.new()
	r.id = id
	r.starting_money = money
	r.aggression = aggression
	r.preferred_terrain = preferred
	return r


static func weapon(id: StringName, cost := 500, max_hp := 100.0, repair_per_hp := 2,
		era := GameConstants.Era.MEDIEVAL) -> WeaponData:
	var w := WeaponData.new()
	w.id = id
	w.purchase_cost = cost
	w.max_health = max_hp
	w.repair_cost_per_hp = repair_per_hp
	w.era = era
	return w


static func ammo(id: StringName, cost_per_shell := 20, era := GameConstants.Era.MEDIEVAL) -> AmmoData:
	var a := AmmoData.new()
	a.id = id
	a.cost_per_shell = cost_per_shell
	a.era = era
	return a


static func tech(id: StringName, weapons: Array[StringName] = [], ammo_ids: Array[StringName] = []) -> TechNodeData:
	var t := TechNodeData.new()
	t.id = id
	t.unlocks_weapons = weapons
	t.unlocks_ammo = ammo_ids
	return t


static func rng(seed_value := 42) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	return r


static func player(money: int) -> PlayerState:
	var p := PlayerState.new()
	p.money = money
	return p
