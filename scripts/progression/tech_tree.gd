class_name TechTree
extends RefCounted
## Tech tree rules over a set of TechNodeData and one PlayerState. Pure logic: no nodes.
## Use TechTree.for_game() in scenes; it reads DataRegistry/GameState and relays signals to EventBus.
##
## Rules:
## - A node is unlockable when it is known, not yet unlocked, every prerequisite is unlocked,
##   the player can afford research_cost, and its era is reached (an era_gate node may be one era ahead).
## - Unlocking an era_gate node advances PlayerState.current_era to the node's era.
## - Weapons/ammo that no node unlocks are base kit and always purchasable.

signal tech_unlocked(tech_id: StringName)
signal era_changed(era: GameConstants.Era)

enum Status { UNLOCKABLE, UNKNOWN, ALREADY_UNLOCKED, MISSING_PREREQUISITES, ERA_LOCKED, INSUFFICIENT_FUNDS }

var player: PlayerState
## StringName -> TechNodeData
var nodes: Dictionary


func _init(p_player: PlayerState, p_nodes: Dictionary) -> void:
	player = p_player
	nodes = p_nodes


## A tree over the live campaign, relaying its signals to EventBus.
static func for_game() -> TechTree:
	var tree := TechTree.new(GameState.player, DataRegistry.tech)
	tree.tech_unlocked.connect(EventBus.tech_unlocked.emit)
	tree.era_changed.connect(EventBus.era_changed.emit)
	return tree


func status(id: StringName) -> Status:
	var node: TechNodeData = nodes.get(id)
	if node == null:
		return Status.UNKNOWN
	if player.unlocked_tech.has(id):
		return Status.ALREADY_UNLOCKED
	if not node.is_available(player.unlocked_tech):
		return Status.MISSING_PREREQUISITES
	var reachable_era := player.current_era + (1 if node.era_gate else 0)
	if node.era > reachable_era:
		return Status.ERA_LOCKED
	if not player.can_afford(node.research_cost):
		return Status.INSUFFICIENT_FUNDS
	return Status.UNLOCKABLE


func can_unlock(id: StringName) -> bool:
	return status(id) == Status.UNLOCKABLE


## Spends the research cost and unlocks the node. Returns false (and changes nothing) if not unlockable.
func unlock(id: StringName) -> bool:
	if not can_unlock(id):
		return false
	var node: TechNodeData = nodes[id]
	if not player.spend(node.research_cost, "Research: %s" % node.display_name):
		return false
	player.unlocked_tech.append(id)
	tech_unlocked.emit(id)
	if node.era_gate and node.era > player.current_era:
		player.current_era = node.era
		era_changed.emit(node.era)
	return true


func is_unlocked(id: StringName) -> bool:
	return player.unlocked_tech.has(id)


## Ids of nodes the player could unlock right now, sorted by tree position.
func unlockable_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for id in sorted_ids():
		if can_unlock(id):
			out.append(id)
	return out


## Ids of nodes whose prerequisites are met and era is reachable, affordable or not.
func visible_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for id in sorted_ids():
		var s := status(id)
		if s == Status.UNLOCKABLE or s == Status.INSUFFICIENT_FUNDS:
			out.append(id)
	return out


## Every node id, ordered by era, then tree_position (x, then y), then id.
func sorted_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	out.assign(nodes.keys())
	out.sort_custom(func(a: StringName, b: StringName) -> bool:
		var na: TechNodeData = nodes[a]
		var nb: TechNodeData = nodes[b]
		if na.era != nb.era:
			return na.era < nb.era
		if na.tree_position.x != nb.tree_position.x:
			return na.tree_position.x < nb.tree_position.x
		if na.tree_position.y != nb.tree_position.y:
			return na.tree_position.y < nb.tree_position.y
		return String(a) < String(b))
	return out


func is_weapon_unlocked(weapon_id: StringName) -> bool:
	return _is_item_unlocked(weapon_id, "unlocks_weapons")


func is_ammo_unlocked(ammo_id: StringName) -> bool:
	return _is_item_unlocked(ammo_id, "unlocks_ammo")


## Weapon ids the shop may sell: base kit plus everything unlocked. Includes weapons already owned.
func purchasable_weapons(all_weapon_ids: Array) -> Array[StringName]:
	return _filter_sorted(all_weapon_ids, is_weapon_unlocked)


## Ammo ids the shop may sell: base kit plus everything unlocked.
func purchasable_ammo(all_ammo_ids: Array) -> Array[StringName]:
	return _filter_sorted(all_ammo_ids, is_ammo_unlocked)


## The tech node ids that unlock an item, for "requires X" tooltips.
func unlocked_by(item_id: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	for id in sorted_ids():
		var node: TechNodeData = nodes[id]
		if node.unlocks_weapons.has(item_id) or node.unlocks_ammo.has(item_id):
			out.append(id)
	return out


## Returns the ids forming one prerequisite cycle (first id repeated at the end), or [] if acyclic.
## Unknown prerequisites are ignored here; ContentValidator reports them.
static func find_cycle(p_nodes: Dictionary) -> Array[StringName]:
	const WHITE := 0
	const GREY := 1
	const BLACK := 2
	var color := {}
	var keys: Array = p_nodes.keys()
	keys.sort_custom(func(a, b): return String(a) < String(b))
	for start in keys:
		if color.get(start, WHITE) != WHITE:
			continue
		# Iterative DFS: stack of [id, next prerequisite index]; path mirrors the grey chain.
		var stack: Array = [[start, 0]]
		var path: Array[StringName] = [start]
		color[start] = GREY
		while not stack.is_empty():
			var frame: Array = stack.back()
			var prereqs: Array[StringName] = p_nodes[frame[0]].prerequisites
			if frame[1] >= prereqs.size():
				color[frame[0]] = BLACK
				stack.pop_back()
				path.pop_back()
				continue
			var next: StringName = prereqs[frame[1]]
			frame[1] += 1
			if not p_nodes.has(next):
				continue
			match color.get(next, WHITE):
				GREY:
					var cycle: Array[StringName] = path.slice(path.find(next))
					cycle.append(next)
					return cycle
				WHITE:
					color[next] = GREY
					stack.append([next, 0])
					path.append(next)
	return []


func _is_item_unlocked(item_id: StringName, field: String) -> bool:
	var referenced := false
	for node: TechNodeData in nodes.values():
		var items: Array[StringName] = node.get(field)
		if items.has(item_id):
			if player.unlocked_tech.has(node.id):
				return true
			referenced = true
	return not referenced


static func _filter_sorted(ids: Array, pred: Callable) -> Array[StringName]:
	var out: Array[StringName] = []
	for id in ids:
		if pred.call(StringName(id)):
			out.append(StringName(id))
	out.sort_custom(func(a, b): return String(a) < String(b))
	return out
