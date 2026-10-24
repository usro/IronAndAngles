# Balance sheet

Units: meters, m/s, kg, seconds. Money is an int. `data/**/*.tres` is the source of truth; this sheet explains the intent and is checked by `tests/progression/test_content.gd`.

## Rules of thumb

1. **Par cost** of a contract = `target_count × ceil(target_health / damage) × (cost_per_shell + energy_cost_per_shot)`: what it costs with every shot a hit.
2. The cheapest same-era par cost sits at **8–20 % of the payout** (test-enforced). At a typical 1-in-3 hit rate that's 30–45 %, and with the auction price on top, a sloppy battle loses money. Misses also raise `reveal_level`, so they cost twice.
3. **Each era multiplies money by about ×3–5**: payouts 1.5k–3k → 6k–10k → 36k–40k → 160k–220k. Shells scale with them (25 → 90 → 450 → 1.9k per railgun shot), so a miss always costs about 1–2 % of the payout.
4. **Research**: a normal node costs about 0.5–1.5 contract payouts of its era; an **era gate** costs about 2–3 payouts of the previous era (rifling 6k, fire control 20k, capacitor banks 60k). Entering a new era takes about 4–6 good contracts.
5. **Weapon prices** are 1–2 contract payouts of their era. The trebuchet and stone ball are the free base kit (no tech unlocks them, so they can always be bought). The starting kit (`GameState._grant_starting_kit`: trebuchet + 20 stone balls, 5,000 money) is unchanged.
6. **Target health** rises per era (120–150 → 300–350 → 400–700 → 1,500–4,000), so older-era shells need more hits, and older launchers mostly can't reach later plots. One exception is deliberate: the SP howitzer still fires old `howitzer_shell` stock, which is the budget option (3 hits on a 700 HP bunker at 220 each, vs 2 `he_155` hits at 450).

## Physics choices

- **Drag:** `F = ½ ρ v² Cd A`. Masses and cross-sections match real objects of the class (a 40 kg granite ball ≈ 0.3 m across; a 155 mm shell is 43 kg and 0.0189 m²).
- **Game-scale distances:** plots are 220–300 m (medieval), 520–780 m (industrial), 950–1,400 m (modern), 2,000–2,400 m (experimental). Real guns outrange these by a lot, so later-era muzzle velocities sit at the low, reduced-charge end of real values (rifled cannon 150–320 m/s). The rifled cannon is a flat-fire gun: it's aimed by elevation, at low angles. The **howitzers lob**, so their charge dial is fitted to the era's distances instead: full charge reaches about 1.5–1.8× the farthest plot in the densest air, and minimum charge lands short of the nearest plot (modern 155 mm: 70–170 m/s; it used to be 150–420 m/s, which reached about 10 km and left 90% of the dial useless). `tests/progression/test_content.gd` enforces this for Modern-era tube artillery.
- **Wind:** medieval shot is light for its size and gets `wind_sensitivity ≥ 1` (fire pots 1.4). Shells drop to 0.3–0.6, rockets weathercock (0.8), and railgun and orbital rounds are 0.
- **Bounce:** only medieval round shot bounces, with seeded random deflection (`bounce_randomness_deg` 12–20°).
- **Rockets:** 45 kg, 3.5 kN for 0.8 s (≈ +62 m/s on top of a 30–110 m/s rail exit).
- **Railguns:** 1,400–3,200 m/s, so drop over 2 km is ≈ 2–10 m: nearly direct fire. Their cost is energy (1,500–2,500 per shot) plus 20–30 s cooldowns.
- **Orbital uplink:** `launcher_type = ORBITAL`, elevation 85–90°, "muzzle" velocity 900–1,300 m/s is the descent speed. The launch model belongs to the ballistics session. 12,000 energy + 6,000 per rod, 90 s cooldown.
- **Reach check:** a point-mass sim with drag and no wind confirms every contract plot is in range of a same-era weapon (orbital excluded). The base trebuchet reaches every medieval plot, but only just at Kessel/River Ridge (max ≈ 310–320 m), so the Great Trebuchet (≈ 420 m) is the comfortable upgrade.

## Design levers per era

- **Medieval:** cheap shells and unreliable flight. Fire pots do area damage but lose 80 % in rain (Greywater has rain 0.3).
- **Industrial:** choose the round. AP (260 dmg, 160) cracks Fort Marrow's 350 HP casemates in 2 hits; common shell (150 dmg, 90) needs 3 but is cheaper per target.
- **Modern:** reload management. The MLRS dumps 6 rockets (1,800) per pull, then reloads for 40 s. That's ideal for Mountain Pass (10 soft targets, 240 s limit), wasteful against hard bunkers. The autoloader fires 3-round bursts. A laser-guided shell (2,400) costs 5× an HE round but rarely misses.
- **Experimental:** time vs money. On Skyhook, railguns are cheapest (15 hits ≈ 28.5k), and with 19 s cycles (4 s reload + 15 s cooldown) the 480 s limit leaves room for only a few misses. Orbital rods one-shot each silo for 18k apiece (54k total).

### Weapons

| id | era | price | v (m/s) | elev (°) | spread (°) | reload / salvo / cooldown (s) | energy/shot | HP |
|---|---|---:|---|---|---:|---|---:|---:|
| `trebuchet` | Med | 0 | 25–58 | 30–70 | 1.5 | 12 | 0 | 120 |
| `great_trebuchet` | Med | 2500 | 30–68 | 30–70 | 1.2 | 18 | 0 | 180 |
| `bronze_mortar` | Med | 1800 | 40–85 | 45–80 | 2.5 | 9 | 0 | 90 |
| `rifled_cannon` | Ind | 7000 | 150–320 | -5–35 | 0.4 | 6 | 0 | 220 |
| `heavy_howitzer` | Ind | 12000 | 70–300 | 20–70 | 0.6 | 10 | 0 | 300 |
| `sp_howitzer` | Mod | 30000 | 70–170 | 0–70 | 0.25 | 5 | 0 | 450 |
| `mlrs_launcher` | Mod | 45000 | 30–110 | 10–60 | 1.2 | 40 / 6×0.5s | 0 | 300 |
| `autoloaded_howitzer` | Mod | 60000 | 70–170 | 0–70 | 0.2 | 14 / 3×2s | 0 | 480 |
| `railgun` | Exp | 120000 | 1400–2400 | -5–25 | 0.05 | 4 / +15 | 1500 | 400 |
| `heavy_railgun` | Exp | 200000 | 2000–3200 | -5–25 | 0.03 | 5 / +18 | 2500 | 500 |
| `orbital_platform` | Exp | 300000 | 900–1300 | 85–90 | 0.1 | 10 / +90 | 12000 | 1000 |

### Ammo

| id | era | cost | mass (kg) | Cd × A (m²) | wind | damage | blast / crater (m) | special |
|---|---|---:|---:|---|---:|---:|---|---|
| `stone_ball` | Med | 25 | 40 | 0.5 × 0.07 | 1 | 60 | 1 / 1.2 | bounce 0.35 ±12°×2 |
| `fire_pot` | Med | 45 | 12 | 0.6 × 0.05 | 1.4 | 80 | 3 / 0.5 | rain −80% |
| `iron_ball` | Med | 30 | 18 | 0.47 × 0.0216 | 1 | 70 | 1 / 1.4 | bounce 0.40 ±15°×2 |
| `powder_bomb` | Med | 60 | 20 | 0.47 × 0.03 | 1 | 100 | 3.5 / 2.5 | bounce 0.20 ±20°×1 |
| `common_shell` | Ind | 90 | 10 | 0.3 × 0.0082 | 0.6 | 150 | 4 / 2.5 |  |
| `ap_shell` | Ind | 160 | 12 | 0.28 × 0.0082 | 0.5 | 260 | 1.2 / 1.5 |  |
| `shrapnel_shell` | Ind | 130 | 10 | 0.3 × 0.0082 | 0.6 | 110 | 6 / 0.8 | 24 fragments |
| `howitzer_shell` | Ind | 220 | 43 | 0.3 × 0.0189 | 0.4 | 320 | 7 / 4 |  |
| `he_155` | Mod | 450 | 43.5 | 0.25 × 0.0189 | 0.35 | 400 | 9 / 4 |  |
| `laser_guided_shell` | Mod | 2400 | 62 | 0.25 × 0.0189 | 0.3 | 650 | 6 / 3.5 | guided |
| `rocket_he` | Mod | 300 | 45 | 0.35 × 0.0117 | 0.8 | 260 | 8 / 3 | 3500 N × 0.8s |
| `rocket_cluster` | Mod | 520 | 48 | 0.35 × 0.0117 | 0.8 | 180 | 14 / 1 | 40 fragments, 3500 N × 0.8s |
| `tungsten_slug` | Exp | 400 | 3.2 | 0.15 × 0.0008 | 0 | 900 | 1.5 / 3 |  |
| `flechette_canister` | Exp | 700 | 3 | 0.18 × 0.0008 | 0 | 500 | 8 / 1 | 60 fragments |
| `kinetic_rod` | Exp | 6000 | 100 | 0.1 × 0.008 | 0 | 5000 | 12 / 9 |  |

### Tech

| id | era | cost | gate | prerequisites | unlocks |
|---|---|---:|:-:|---|---|
| `greek_fire` | Med | 600 |  | — | fire_pot |
| `early_mortar` | Med | 800 |  | — | bronze_mortar, iron_ball |
| `great_trebuchet` | Med | 1200 |  | — | great_trebuchet |
| `corned_powder` | Med | 1500 |  | early_mortar | powder_bomb |
| `rifling` | Ind | 6000 | ✔ | corned_powder, great_trebuchet | rifled_cannon, common_shell |
| `armor_piercing` | Ind | 4000 |  | rifling | ap_shell |
| `heavy_howitzer` | Ind | 6000 |  | rifling | heavy_howitzer, howitzer_shell |
| `shrapnel_fuzes` | Ind | 3500 |  | rifling | shrapnel_shell |
| `fire_control` | Mod | 20000 | ✔ | heavy_howitzer, armor_piercing | sp_howitzer, he_155 |
| `mlrs` | Mod | 15000 |  | fire_control | mlrs_launcher, rocket_he |
| `autoloader` | Mod | 22000 |  | fire_control | autoloaded_howitzer |
| `laser_designation` | Mod | 18000 |  | fire_control, shrapnel_fuzes | laser_guided_shell |
| `cluster_munitions` | Mod | 12000 |  | mlrs | rocket_cluster |
| `capacitor_banks` | Exp | 60000 | ✔ | laser_designation, autoloader | railgun, tungsten_slug |
| `flechette_rounds` | Exp | 25000 |  | capacitor_banks | flechette_canister |
| `superconducting_rails` | Exp | 90000 |  | capacitor_banks | heavy_railgun |
| `orbital_uplink` | Exp | 150000 |  | superconducting_rails | orbital_platform, kinetic_rod |

### Contracts

| id | era | payout | reserve | targets × HP | plots (distance m) | weather (wind ± gust, rain) | par hits / cost (cheapest) | share of payout at 100% / 33% hits |
|---|---|---:|---:|---|---|---|---|---|
| `siege_of_aldmoor` | Med | 1500 | 200 | 3 × 120 | river_ridge (280) | -3 ± 1.5, 0 | 6 / 150 (`stone_ball`) | 10% / 30% |
| `burning_of_greywater` | Med | 2200 | 350 | 4 × 150 | greywater_marsh (260), millers_hill (220) | 5 ± 3, 0.3 | 12 / 300 (`stone_ball`) | 14% / 41% |
| `relief_of_kessel` | Med | 3200 | 500 | 5 × 150 | kessel_heights (300), river_ridge (280) | -6 ± 4, 0 | 15 / 375 (`stone_ball`) | 12% / 35% |
| `breach_at_hollow_creek` | Ind | 6000 | 900 | 4 × 300 | hollow_creek (520), signal_hill (650) | 2 ± 2, 0 | 8 / 720 (`common_shell`) | 12% / 36% |
| `fort_marrow_bombardment` | Ind | 10500 | 1500 | 6 × 350 | fort_marrow_flats (780), signal_hill (650) | -4 ± 3, 0.2 | 18 / 1620 (`common_shell`) | 15% / 46% |
| `operation_glass_valley` | Mod | 36000 | 5000 | 6 × 700 | glass_valley_rim (1100), saddle_gap (950) | 3 ± 2, 0 | 18 / 3960 (`howitzer_shell`) | 11% / 33% |
| `mountain_pass_interdiction` | Mod | 40000 | 6000 | 10 × 400 | pass_overlook (1400), saddle_gap (950) | -7 ± 5, 0, 240s limit | 20 / 4400 (`howitzer_shell`) | 11% / 33% |
| `citadel_zero` | Exp | 160000 | 20000 | 5 × 1500 | citadel_approach (2000) | 6 ± 6, 0.4 | 10 / 19000 (`tungsten_slug`) | 12% / 36% |
| `skyhook_defense` | Exp | 220000 | 30000 | 3 × 4000 | silo_plateau (2400), citadel_approach (2000) | -9 ± 8, 0, 480s limit | 15 / 28500 (`tungsten_slug`) | 13% / 39% |

### Clients added for procedural offers

`watchtowers_of_wyckham`, `saltmere_barges` (Medieval), `pithead_towers`, `coastal_batteries` (Industrial), `radar_picket`, `emplacement_sweep` (Modern), `fabricator_domes`, `mass_driver_capacitors` (Experimental). They follow the same par-cost band (test-enforced). Their listed plot only exists for validation, because every offer is put on generated land.

## Procedural offers

Each week, `ContractOffers` picks up to 3 clients (current era first, uncompleted first), and `ProceduralContracts` puts each one on 1–2 freshly generated plots (`PlotGenerator`):

- **Bounds come from the content.** Distance, height advantage and altitude are drawn inside the min–max of that era's handcrafted plots. Wind, gusts and rain stay inside that era's handcrafted contracts. FLAT, HILLS and VALLEY are always allowed; RIDGE and MOUNTAIN only in eras that already have them. Editing a handcrafted plot or contract therefore retunes generation too.
- **Reach guard.** A plot is accepted only if its distance is at most 92% of the max range (full charge, point mass with drag) of the era's reference weapon: the cheapest non-orbital weapon of the era (trebuchet, rifled cannon, SP howitzer, railgun). Otherwise the far bound shrinks and the draw is retried.
- **Line of sight for direct fire.** When the reference weapon is a railgun (`WeaponData.is_direct_fire()`), the plot must also pass `TerrainGenerator.has_line_of_sight()`. The generator's smooth slope always rounds off just below a higher battery pad, so a flat shot downhill hits the hillside about 100 m out. Railgun plots therefore put the battery **level with or up to 30 m below** the targets; ridges and mountains are retried, and the last resort is flat, level ground.
- **Money.** Payout and reserve are the client's × 0.9–1.15, rounded (50 below 10k, 500 below 100k, then 5k).
- Ids are `<client>_w<week>` and `gen_plot_<n>`. Winning one marks the **client** completed, so offers rotate between clients.

## Experimental era (railgun) fixes

The probe found every Experimental battle lost with a railgun, for three reasons, all fixed:

1. **AimSolver couldn't aim a railgun.** It scanned elevation in 2° steps, which is hundreds of meters at 2,000+ m/s. It now bisects elevation on the direct-fire "height at the target's distance" miss when no grid angle lands.
2. **No line of sight downhill** (see *Line of sight for direct fire* above).
3. **Cycle time vs time limits.** Railgun cooldown 20 → 15 s, heavy railgun 30 → 18 s. Skyhook limit 360 → 480 s, Mass Driver 420 → 480 s.

**Defenders lob.** The enemy gun is the cheapest non-orbital, non-railgun weapon of the contract's era (or the latest earlier era with one) that reaches the battery. In the Experimental era that's the Modern SP howitzer. A defender railgun would face the same blocked line of sight the other way, which would make the duel a stalemate. Your railgun can't see the defender behind the targets either, so in the Experimental era the duel is fought by the howitzers in your battery.

**Aiming:** railgun elevation dials move 10× finer (`WeaponMount.elevation_scale()`), and the dial and last-shot label show hundredths of a degree. At 2 km, 0.05° is about 2 m.
