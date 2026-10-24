class_name Trajectory
extends RefCounted
## The recorded flight of one shell (or fragment). Filled step by step by ShellFlight.

enum EndReason { IN_FLIGHT, IMPACT, AIRBURST, OUT_OF_BOUNDS, TIMEOUT }

## One sample per fixed step, plus the exact contact points of bounces and the impact.
var points := PackedVector2Array()
## Simulation time of each point (same index as points).
var times := PackedFloat64Array()

## Elevation actually fired, after spread, in degrees.
var launch_elevation_deg: float = 0.0
var launch_velocity_m: Vector2 = Vector2.ZERO
var start_time: float = 0.0

var end_reason: EndReason = EndReason.IN_FLIGHT
## Where the flight ended (impact, airburst, edge of the world or timeout).
var end_point_m: Vector2 = Vector2.ZERO
var end_velocity_m: Vector2 = Vector2.ZERO
## Surface normal at the impact point. Zero unless end_reason is IMPACT.
var impact_normal: Vector2 = Vector2.ZERO
## Seconds from launch to the end of the flight.
var time_of_flight: float = 0.0

## One entry per bounce: {"position": Vector2, "normal": Vector2, "time": float,
## "velocity_in": Vector2, "velocity_out": Vector2}.
var bounces: Array[Dictionary] = []
## Shrapnel fragments spawned by a burst. Empty for other ammo.
var fragments: Array[Trajectory] = []


func is_finished() -> bool:
	return end_reason != EndReason.IN_FLIGHT


func has_impact() -> bool:
	return end_reason == EndReason.IMPACT


## Impact point, or Vector2.INF if the shell did not hit the ground.
func impact_point_m() -> Vector2:
	return end_point_m if has_impact() else Vector2.INF


## Highest recorded point (smallest y).
func apex_m() -> Vector2:
	var best := Vector2.INF
	for p in points:
		if p.y < best.y:
			best = p
	return best


## Position at simulation time t, interpolated between recorded points.
func position_at(t: float) -> Vector2:
	if points.is_empty():
		return Vector2.INF
	if t <= times[0]:
		return points[0]
	for i in range(1, times.size()):
		if t <= times[i]:
			var span := times[i] - times[i - 1]
			var f := 0.0 if span <= 0.0 else (t - times[i - 1]) / span
			return points[i - 1].lerp(points[i], f)
	return points[points.size() - 1]


func add_point(p: Vector2, t: float) -> void:
	points.append(p)
	times.append(t)
