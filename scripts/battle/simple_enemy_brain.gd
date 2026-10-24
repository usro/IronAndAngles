class_name SimpleEnemyBrain
extends EnemyBrain
## Default counter-battery: holds fire until the battery is somewhat revealed, then aims at a
## random working battery weapon with AimSolver plus a seeded error that shrinks as reveal_level
## and contract difficulty rise.

## Below this reveal level the defender doesn't know where to shoot.
const HOLD_BELOW_REVEAL := 0.1
## Error radius (meters, along the ground) at reveal 0 and at reveal 1, before difficulty.
const MAX_ERROR_M := 60.0
const MIN_ERROR_M := 2.0
## Each difficulty step above 1 divides the error by (1 + this).
const DIFFICULTY_SHARPNESS := 0.35
const SOLVER_STEP_DEG := 4.0


## Maximum aiming error in meters for a reveal level (0..1) and difficulty (1..5).
static func error_radius_m(reveal_level: float, difficulty: int) -> float:
	var base := lerpf(MAX_ERROR_M, MIN_ERROR_M, clampf(reveal_level, 0.0, 1.0))
	return base / (1.0 + DIFFICULTY_SHARPNESS * maxi(difficulty - 1, 0))


func plan_shot(s: Situation, rng: RandomNumberGenerator) -> Dictionary:
	if s.reveal_level < HOLD_BELOW_REVEAL or s.battery_positions_m.is_empty():
		return {}
	var target: Vector2 = s.battery_positions_m[rng.randi_range(0, s.battery_positions_m.size() - 1)]
	var error := Ballistics.triangular(rng) * error_radius_m(s.reveal_level, s.difficulty)
	var aim := target + Vector2(error, 0.0)
	# High arc: the defender usually has to lob over whatever lies between.
	var sol := AimSolver.solve(s.weapon, s.ammo, s.origin_m, aim, s.weather, AimSolver.Arc.HIGH,
		SOLVER_STEP_DEG)
	if sol.is_empty():
		return {}
	return {"elevation_deg": sol.elevation_deg, "charge": sol.charge, "facing": sol.facing}
