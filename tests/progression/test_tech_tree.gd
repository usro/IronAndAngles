extends TestCase
## TechTree rules: unlocking, prerequisites, funds, era gates, purchasable items, cycle detection.

var player: PlayerState
var tree: TechTree


func before_each() -> void:
	player = PlayerState.new()
	player.money = 1_000_000
	tree = TechTree.new(player, DataRegistry.tech)


static func _node(id: StringName, era: int, cost: int, prereqs: Array = [], gate := false) -> TechNodeData:
	var n := TechNodeData.new()
	n.id = id
	n.display_name = String(id)
	n.era = era as GameConstants.Era
	n.research_cost = cost
	n.era_gate = gate
	n.prerequisites.assign(prereqs)
	return n


static func _nodes(list: Array) -> Dictionary:
	var out := {}
	for n: TechNodeData in list:
		out[n.id] = n
	return out


func test_root_node_unlocks_and_spends() -> void:
	var cost := DataRegistry.get_tech(&"early_mortar").research_cost
	var seen: Array = []
	tree.tech_unlocked.connect(func(id): seen.append(id))
	assert_true(tree.can_unlock(&"early_mortar"), "root node unlockable")
	assert_true(tree.unlock(&"early_mortar"), "unlock succeeds")
	assert_eq(player.money, 1_000_000 - cost, "research cost spent")
	assert_true(player.unlocked_tech.has(&"early_mortar"), "recorded in player state")
	assert_eq(seen, [&"early_mortar"], "tech_unlocked emitted")


func test_cannot_unlock_twice() -> void:
	tree.unlock(&"early_mortar")
	var money := player.money
	assert_eq(tree.status(&"early_mortar"), TechTree.Status.ALREADY_UNLOCKED)
	assert_false(tree.unlock(&"early_mortar"), "second unlock refused")
	assert_eq(player.money, money, "no double charge")
	assert_eq(player.unlocked_tech.count(&"early_mortar"), 1)


func test_unknown_id_is_refused() -> void:
	assert_eq(tree.status(&"no_such_tech"), TechTree.Status.UNKNOWN)
	assert_false(tree.unlock(&"no_such_tech"))


func test_prerequisites_are_enforced() -> void:
	assert_eq(tree.status(&"corned_powder"), TechTree.Status.MISSING_PREREQUISITES)
	assert_false(tree.unlock(&"corned_powder"), "locked behind early_mortar")
	assert_true(tree.unlock(&"early_mortar"))
	assert_true(tree.unlock(&"corned_powder"), "unlocks once prerequisite is met")
	# rifling needs both corned_powder and great_trebuchet.
	assert_eq(tree.status(&"rifling"), TechTree.Status.MISSING_PREREQUISITES)
	assert_true(tree.unlock(&"great_trebuchet"))
	assert_true(tree.can_unlock(&"rifling"))


func test_insufficient_funds_changes_nothing() -> void:
	var cost := DataRegistry.get_tech(&"early_mortar").research_cost
	player.money = cost - 1
	var seen: Array = []
	tree.tech_unlocked.connect(func(id): seen.append(id))
	assert_eq(tree.status(&"early_mortar"), TechTree.Status.INSUFFICIENT_FUNDS)
	assert_false(tree.unlock(&"early_mortar"))
	assert_eq(player.money, cost - 1, "money untouched")
	assert_true(player.unlocked_tech.is_empty(), "nothing unlocked")
	assert_true(seen.is_empty(), "no signal")
	player.money = cost
	assert_true(tree.unlock(&"early_mortar"), "exact amount is enough")
	assert_eq(player.money, 0)


func test_era_gate_advances_era_once() -> void:
	var eras: Array = []
	tree.era_changed.connect(func(e): eras.append(e))
	for id in [&"early_mortar", &"corned_powder", &"great_trebuchet"]:
		assert_true(tree.unlock(id), "unlock %s" % id)
	assert_eq(player.current_era, GameConstants.Era.MEDIEVAL, "non-gate nodes keep the era")
	assert_true(eras.is_empty(), "no era change yet")
	assert_true(tree.unlock(&"rifling"))
	assert_eq(player.current_era, GameConstants.Era.INDUSTRIAL)
	assert_eq(eras, [GameConstants.Era.INDUSTRIAL], "era_changed emitted once")
	assert_true(tree.unlock(&"armor_piercing"))
	assert_eq(eras.size(), 1, "later nodes in the era don't re-emit")


func test_later_era_nodes_need_their_gate() -> void:
	var nodes := _nodes([
		_node(&"root", 0, 10),
		_node(&"gate", 1, 10, [&"root"], true),
		_node(&"sneaky", 1, 10, [&"root"]),
		_node(&"jump", 2, 10, [&"root"], true),
	])
	var t := TechTree.new(player, nodes)
	t.unlock(&"root")
	assert_eq(t.status(&"sneaky"), TechTree.Status.ERA_LOCKED, "non-gate node of next era")
	assert_eq(t.status(&"jump"), TechTree.Status.ERA_LOCKED, "a gate cannot skip an era")
	assert_true(t.unlock(&"gate"))
	assert_true(t.can_unlock(&"sneaky"), "unlocked after the gate")
	assert_true(t.can_unlock(&"jump"), "next gate reachable from the new era")


func test_whole_tree_is_reachable_and_ends_in_last_era() -> void:
	var progress := true
	while progress:
		progress = false
		for id in tree.unlockable_ids():
			progress = tree.unlock(id) or progress
	assert_eq(player.unlocked_tech.size(), DataRegistry.tech.size(), "every node reachable")
	assert_eq(player.current_era, GameConstants.Era.EXPERIMENTAL)


func test_visible_ids_include_unaffordable() -> void:
	player.money = 0
	var visible := tree.visible_ids()
	assert_true(visible.has(&"early_mortar"), "root visible when broke")
	assert_false(visible.has(&"corned_powder"), "missing prerequisite hidden")
	assert_true(tree.unlockable_ids().is_empty(), "nothing affordable")


func test_purchasable_items_follow_unlocks() -> void:
	var weapons := DataRegistry.weapons.keys()
	var ammo := DataRegistry.ammo.keys()
	assert_eq(tree.purchasable_weapons(weapons), [&"trebuchet"] as Array[StringName], "base weapon only")
	assert_eq(tree.purchasable_ammo(ammo), [&"stone_ball"] as Array[StringName], "base ammo only")
	tree.unlock(&"early_mortar")
	assert_true(tree.purchasable_weapons(weapons).has(&"bronze_mortar"))
	assert_true(tree.purchasable_ammo(ammo).has(&"iron_ball"))
	assert_false(tree.is_ammo_unlocked(&"powder_bomb"), "still behind corned_powder")
	assert_eq(tree.unlocked_by(&"powder_bomb"), [&"corned_powder"] as Array[StringName])


func test_starting_kit_is_base_kit() -> void:
	GameState.new_game(5)
	var t := TechTree.new(GameState.player, DataRegistry.tech)
	assert_true(GameState.player.owned_weapons.has(&"trebuchet"))
	assert_true(GameState.player.ammo_count(&"stone_ball") > 0)
	for w in GameState.player.owned_weapons:
		assert_true(t.is_weapon_unlocked(w), "starting weapon %s is base kit" % w)
	for a in GameState.player.ammo:
		assert_true(t.is_ammo_unlocked(a), "starting ammo %s is base kit" % a)
	var cheapest := INF
	for id in t.unlockable_ids():
		cheapest = minf(cheapest, DataRegistry.get_tech(id).research_cost)
	assert_true(cheapest <= GameConstants.STARTING_MONEY, "something is researchable at start")


func test_for_game_relays_to_event_bus() -> void:
	GameState.new_game(6)
	GameState.player.money = 100_000
	var t := TechTree.for_game()
	var techs: Array = []
	var eras: Array = []
	var on_tech := func(id): techs.append(id)
	var on_era := func(e): eras.append(e)
	EventBus.tech_unlocked.connect(on_tech)
	EventBus.era_changed.connect(on_era)
	for id in [&"early_mortar", &"corned_powder", &"great_trebuchet", &"rifling"]:
		t.unlock(id)
	EventBus.tech_unlocked.disconnect(on_tech)
	EventBus.era_changed.disconnect(on_era)
	assert_eq(techs.size(), 4, "tech_unlocked relayed")
	assert_eq(eras, [GameConstants.Era.INDUSTRIAL], "era_changed relayed")
	assert_eq(GameState.player.current_era, GameConstants.Era.INDUSTRIAL)


func test_unlocks_survive_save_round_trip() -> void:
	tree.unlock(&"early_mortar")
	tree.unlock(&"corned_powder")
	tree.unlock(&"great_trebuchet")
	tree.unlock(&"rifling")
	var q := PlayerState.from_dict(JSON.parse_string(JSON.stringify(player.to_dict())))
	var t := TechTree.new(q, DataRegistry.tech)
	assert_eq(t.status(&"rifling"), TechTree.Status.ALREADY_UNLOCKED)
	assert_true(t.can_unlock(&"armor_piercing"), "era and prerequisites restored")


func test_find_cycle_detects_loops() -> void:
	var cyclic := _nodes([
		_node(&"a", 0, 1, [&"c"]),
		_node(&"b", 0, 1, [&"a"]),
		_node(&"c", 0, 1, [&"b"]),
		_node(&"d", 0, 1, []),
	])
	var cycle := TechTree.find_cycle(cyclic)
	assert_eq(cycle.size(), 4, "three nodes plus the repeated start: %s" % [cycle])
	if cycle.size() == 4:
		assert_eq(cycle[0], cycle[3], "cycle is closed")
	assert_eq(TechTree.find_cycle(_nodes([_node(&"self", 0, 1, [&"self"])])), [&"self", &"self"] as Array[StringName])
	var diamond := _nodes([
		_node(&"top", 0, 1),
		_node(&"l", 0, 1, [&"top"]),
		_node(&"r", 0, 1, [&"top"]),
		_node(&"bottom", 0, 1, [&"l", &"r", &"missing"]),
	])
	assert_true(TechTree.find_cycle(diamond).is_empty(), "diamond is not a cycle")


func test_shipped_tree_has_no_cycle() -> void:
	assert_true(TechTree.find_cycle(DataRegistry.tech).is_empty())
