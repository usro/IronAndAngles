class_name ContractOffers
extends RefCounted
## Picks which contracts the region offers this round. Pure: pass in the data and a seeded RNG.


## Returns up to `count` contracts the player's era allows, shuffled by `rng`.
## Contracts without plots can't be fought and are skipped. Contracts not yet completed come
## first; completed ones only fill the remaining slots, so a small content set never runs dry.
static func generate(contracts: Array, era: GameConstants.Era, completed: Array[StringName],
		rng: RandomNumberGenerator, count: int = 3) -> Array[ContractData]:
	var eligible: Array[ContractData] = []
	for c: ContractData in contracts:
		if c.era_required <= era and not c.plots.is_empty():
			eligible.append(c)
	# Registry order depends on the file system; sort first so the same seed gives the same offers.
	eligible.sort_custom(func(a: ContractData, b: ContractData) -> bool: return a.id < b.id)
	_shuffle(eligible, rng)

	var fresh: Array[ContractData] = []
	var repeats: Array[ContractData] = []
	for c in eligible:
		(repeats if completed.has(c.id) else fresh).append(c)
	fresh.append_array(repeats)
	return fresh.slice(0, count)


## Fisher-Yates with the given RNG (Array.shuffle() uses the global RNG, which breaks determinism).
static func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: Variant = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
