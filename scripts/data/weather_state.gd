class_name WeatherState
extends Resource
## Environmental conditions for one battle. Read by ballistics, battle and FX.

## Horizontal wind in m/s. Positive blows toward +x (right).
@export var wind_speed: float = 0.0
## Maximum random gust added to wind_speed, in m/s.
@export var gust_strength: float = 0.0
## 0 = dry, 1 = downpour. Reduces incendiary effectiveness.
@export_range(0.0, 1.0) var rain_intensity: float = 0.0
@export var gravity: float = GameConstants.STANDARD_GRAVITY
## Air density at ground level of the battlefield (kg/m^3). Lower at altitude.
@export var air_density: float = GameConstants.SEA_LEVEL_AIR_DENSITY


func to_dict() -> Dictionary:
	return {
		"wind_speed": wind_speed,
		"gust_strength": gust_strength,
		"rain_intensity": rain_intensity,
		"gravity": gravity,
		"air_density": air_density,
	}


static func from_dict(d: Dictionary) -> WeatherState:
	var w := WeatherState.new()
	w.wind_speed = d.get("wind_speed", 0.0)
	w.gust_strength = d.get("gust_strength", 0.0)
	w.rain_intensity = d.get("rain_intensity", 0.0)
	w.gravity = d.get("gravity", GameConstants.STANDARD_GRAVITY)
	w.air_density = d.get("air_density", GameConstants.SEA_LEVEL_AIR_DENSITY)
	return w
