class_name ProceduralContracts
extends RefCounted
## Turns handcrafted contracts (the clients: briefing, targets, payout, difficulty) into this
## week's offers on freshly generated plots and weather. Pure: pass the tables and a seeded RNG.

## Payout and reserve are scaled by a random factor in this band (rounded to tidy numbers).
const PAYOUT_JITTER := Vector2(0.9, 1.15)
## Chance that a contract offers two plots to bid on instead of one.
const TWO_PLOT_CHANCE := 0.6


## One offer per template. Ids are unique per week: "<template>_w<week>".
static func for_week(templates: Array[ContractData], week: int, rng: RandomNumberGenerator,
		all_contracts: Array, weapons: Dictionary, ammo: Dictionary) -> Array[ContractData]:
	var out: Array[ContractData] = []
	var ranges := {}
	var loadouts := {}
	for i in templates.size():
		var t := templates[i]
		if not ranges.has(t.era_required):
			ranges[t.era_required] = PlotGenerator.EraRanges.for_era(t.era_required, all_contracts)
			loadouts[t.era_required] = PlotGenerator.reference_loadout(t.era_required, weapons, ammo)
		var r: PlotGenerator.EraRanges = ranges[t.era_required]
		out.append(instantiate(t, week, i, rng, r, loadouts[t.era_required]) if r.is_valid() else t)
	_spread_on_map(out, rng)
	return out


## Map labels are wide and short (normalized map units); keep generated plots from overlapping.
const LABEL_CLEARANCE := Vector2(0.3, 0.13)


static func _spread_on_map(contracts: Array[ContractData], rng: RandomNumberGenerator) -> void:
	var placed: Array[Vector2] = []
	for c in contracts:
		if c.template_id == &"":
			continue
		for p in c.plots:
			for attempt in 40:
				var clear := placed.all(func(q: Vector2) -> bool:
					return absf(q.x - p.map_position.x) >= LABEL_CLEARANCE.x or absf(q.y - p.map_position.y) >= LABEL_CLEARANCE.y)
				if clear:
					break
				p.map_position = Vector2(rng.randf_range(0.08, 0.7), rng.randf_range(0.14, 0.86))
			placed.append(p.map_position)


static func instantiate(template: ContractData, week: int, index: int, rng: RandomNumberGenerator,
		ranges: PlotGenerator.EraRanges, loadout: Array) -> ContractData:
	var c: ContractData = template.duplicate()
	c.id = StringName("%s_w%d" % [template.id, week])
	c.template_id = template.id
	var scale := rng.randf_range(PAYOUT_JITTER.x, PAYOUT_JITTER.y)
	c.payout = _tidy(template.payout * scale)
	c.reserve_price = _tidy(template.reserve_price * scale)
	c.weather = PlotGenerator.weather(ranges, rng)
	var plots: Array[PlotData] = []
	var count := 2 if rng.randf() < TWO_PLOT_CHANCE else 1
	for p in count:
		plots.append(PlotGenerator.generate(ranges, loadout, rng, (week * 10 + index) * 10 + p))
	c.plots = plots
	return c


## Rounds money to 2 significant-ish figures: 50s under 10k, 500s under 100k, then 5k.
static func _tidy(amount: float) -> int:
	var step := 50 if amount < 10000.0 else (500 if amount < 100000.0 else 5000)
	return maxi(step, roundi(amount / step) * step)
