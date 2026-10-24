class_name ContentValidator
extends RefCounted
## Cross-checks all content: ids match file names, every referenced id resolves, the tech tree
## is acyclic and era-consistent. Pass the DataRegistry (or anything with the same dictionaries).
## Returns human-readable problems; an empty array means the content is consistent.


static func validate(registry: Object) -> Array[String]:
	var errors: Array[String] = []
	var weapons: Dictionary = registry.weapons
	var ammo: Dictionary = registry.ammo
	var tech: Dictionary = registry.tech

	for weapon: WeaponData in weapons.values():
		_check_file_name(weapon, errors)
		if weapon.allowed_ammo.is_empty():
			errors.append("weapon %s allows no ammo" % weapon.id)
		for ammo_id in weapon.allowed_ammo:
			if not ammo.has(ammo_id):
				errors.append("weapon %s allows unknown ammo %s" % [weapon.id, ammo_id])
	for a: AmmoData in ammo.values():
		_check_file_name(a, errors)

	var gates := {}
	for node: TechNodeData in tech.values():
		_check_file_name(node, errors)
		for p in node.prerequisites:
			var pre: TechNodeData = tech.get(p)
			if pre == null:
				errors.append("tech %s requires unknown tech %s" % [node.id, p])
			elif pre.era > node.era:
				errors.append("tech %s (era %d) requires later-era tech %s" % [node.id, node.era, p])
		for w in node.unlocks_weapons:
			if not weapons.has(w):
				errors.append("tech %s unlocks unknown weapon %s" % [node.id, w])
			elif weapons[w].era != node.era:
				errors.append("tech %s unlocks weapon %s from another era" % [node.id, w])
		for a in node.unlocks_ammo:
			if not ammo.has(a):
				errors.append("tech %s unlocks unknown ammo %s" % [node.id, a])
		if node.era_gate:
			if gates.has(node.era):
				errors.append("era %d has two gates: %s and %s" % [node.era, gates[node.era], node.id])
			gates[node.era] = node.id
		elif node.era > GameConstants.Era.MEDIEVAL and _all_prereqs_earlier(node, tech):
			errors.append("tech %s enters era %d without being an era_gate" % [node.id, node.era])
	for era in range(GameConstants.Era.INDUSTRIAL, GameConstants.Era.EXPERIMENTAL + 1):
		if not gates.has(era):
			errors.append("era %d has no era_gate tech" % era)

	var cycle := TechTree.find_cycle(tech)
	if not cycle.is_empty():
		errors.append("tech cycle: %s" % " -> ".join(cycle.map(func(s): return String(s))))

	for contract: ContractData in registry.contracts.values():
		_check_file_name(contract, errors)
		if contract.plots.is_empty():
			errors.append("contract %s has no plots" % contract.id)
		for plot in contract.plots:
			if plot == null or not registry.plots.has(plot.id):
				errors.append("contract %s references an unregistered plot" % contract.id)
		if contract.weather == null:
			errors.append("contract %s has no weather" % contract.id)
		if contract.reserve_price >= contract.payout:
			errors.append("contract %s reserve %d >= payout %d" % [contract.id, contract.reserve_price, contract.payout])
	for plot: PlotData in registry.plots.values():
		_check_file_name(plot, errors)
	for rival: RivalData in registry.rivals.values():
		_check_file_name(rival, errors)
	return errors


static func _check_file_name(res: Resource, errors: Array[String]) -> void:
	if res.resource_path.is_empty():
		return
	var file := res.resource_path.get_file().get_basename()
	if StringName(file) != res.get("id"):
		errors.append("%s has id %s; ids must equal the file name" % [res.resource_path, res.get("id")])


## True if no prerequisite is in the node's own era, i.e. this node is an entry into its era.
static func _all_prereqs_earlier(node: TechNodeData, tech: Dictionary) -> bool:
	for p in node.prerequisites:
		var pre: TechNodeData = tech.get(p)
		if pre != null and pre.era == node.era:
			return false
	return true
