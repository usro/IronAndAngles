class_name GameConstants
extends RefCounted
## Shared enums and global constants. Not an autoload: reference as GameConstants.X.

enum Era { MEDIEVAL, INDUSTRIAL, MODERN, EXPERIMENTAL }

## How a weapon throws its projectile. Ballistics uses this to choose a launch model.
enum LauncherType { MECHANICAL, GUNPOWDER, ROCKET, RAILGUN, ORBITAL }

enum DamageType { KINETIC, EXPLOSIVE, INCENDIARY, SHRAPNEL, ARMOR_PIERCING }

enum TerrainProfile { FLAT, HILLS, RIDGE, VALLEY, MOUNTAIN }

## World units: simulation runs in meters and seconds. Rendering converts with these.
## Axis convention matches Godot: +x right, +y DOWN. Gravity is a positive y value.
const PIXELS_PER_METER := 8.0

## Fixed simulation step for ballistics, independent of render frame rate (determinism).
const PHYSICS_STEP := 1.0 / 120.0

const STANDARD_GRAVITY := 9.81
const SEA_LEVEL_AIR_DENSITY := 1.225  # kg/m^3

const STARTING_MONEY := 5000


static func meters_to_pixels(v: Vector2) -> Vector2:
	return v * PIXELS_PER_METER


static func pixels_to_meters(v: Vector2) -> Vector2:
	return v / PIXELS_PER_METER


static func era_name(era: Era) -> String:
	return ["Medieval", "Industrial", "Modern", "Experimental"][era]
