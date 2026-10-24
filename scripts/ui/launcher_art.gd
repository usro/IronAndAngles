class_name LauncherArt
extends RefCounted
## Line-art silhouettes of the battery's weapons, drawn procedurally so the battlefield, the shop
## and the menu share one look. Shapes are in meters around the weapon's ground point (+y down),
## facing +x; the barrel (or arm, or rails) pivots at the muzzle point, 2 m above the ground,
## matching WeaponMount.muzzle_m().

const PIVOT := Vector2(0.0, -2.0)


## Draws a weapon. `ground` is in the canvas item's pixels, `scale` is pixels per meter,
## `facing` is 1 (right) or -1 (left), `width` is the line width in pixels.
static func draw_weapon(ci: CanvasItem, weapon_id: StringName, launcher_type: int, ground: Vector2,
		scale: float, elevation_deg: float, ink: Color, fill: Color, width := 1.5, facing := 1) -> void:
	ci.draw_set_transform(ground, 0.0, Vector2(scale * facing, scale))
	var w := width / scale
	var e := deg_to_rad(elevation_deg)
	var id := String(weapon_id)
	match launcher_type:
		GameConstants.LauncherType.MECHANICAL:
			_trebuchet(ci, e, ink, fill, w, 1.25 if id.begins_with("great") else 1.0)
		GameConstants.LauncherType.ROCKET:
			_rocket_truck(ci, e, ink, fill, w)
		GameConstants.LauncherType.RAILGUN:
			_railgun(ci, e, ink, fill, w, id.begins_with("heavy"))
		GameConstants.LauncherType.ORBITAL:
			_uplink(ci, ink, fill, w)
		_:
			if id.contains("mortar"):
				_mortar(ci, e, ink, fill, w)
			elif id.begins_with("sp_"):
				_sp_gun(ci, e, ink, fill, w)
			elif id.contains("howitzer"):
				_howitzer(ci, e, ink, fill, w, id.begins_with("autoloaded"))
			else:
				_cannon(ci, e, ink, fill, w)
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)


## Same, looked up from a WeaponData.
static func draw_data(ci: CanvasItem, weapon: WeaponData, ground: Vector2, scale: float, elevation_deg: float,
		ink: Color, fill: Color, width := 1.5, facing := 1) -> void:
	draw_weapon(ci, weapon.id, weapon.launcher_type, ground, scale, elevation_deg, ink, fill, width, facing)


# --- Parts ---

static func _shape(ci: CanvasItem, pts: PackedVector2Array, ink: Color, fill: Color, w: float) -> void:
	if fill.a > 0.0:
		ci.draw_colored_polygon(pts, fill)
	var closed := pts.duplicate()
	closed.append(pts[0])
	ci.draw_polyline(closed, ink, w)


## A rectangle along `angle` starting `back` behind `pivot`, `length` long, `thick` across.
static func _bar(pivot: Vector2, angle: float, back: float, length: float, thick: float) -> PackedVector2Array:
	var d := Vector2(cos(angle), -sin(angle))
	var n := Vector2(-d.y, d.x) * thick * 0.5
	var a := pivot - d * back
	var b := pivot + d * (length - back)
	return PackedVector2Array([a - n, b - n, b + n, a + n])


static func _wheel(ci: CanvasItem, c: Vector2, r: float, ink: Color, fill: Color, w: float, spokes := 6) -> void:
	ci.draw_circle(c, r, fill)
	ci.draw_arc(c, r, 0.0, TAU, 20, ink, w)
	for i in spokes:
		var a := TAU * i / spokes
		ci.draw_line(c, c + Vector2(cos(a), sin(a)) * r, Color(ink, ink.a * 0.6), w * 0.6)
	ci.draw_circle(c, r * 0.18, ink)


# --- Launchers ---

static func _trebuchet(ci: CanvasItem, e: float, ink: Color, fill: Color, w: float, k: float) -> void:
	var top := Vector2(0, -2.6 * k)
	_shape(ci, PackedVector2Array([Vector2(-1.9 * k, -0.25), Vector2(1.9 * k, -0.25), Vector2(1.9 * k, -0.55),
		Vector2(-1.9 * k, -0.55)]), ink, fill, w)
	for x in [-1.3 * k, 1.3 * k]:
		_wheel(ci, Vector2(x, -0.3), 0.3, ink, fill, w, 4)
	ci.draw_line(Vector2(-1.3 * k, -0.55), top, ink, w)
	ci.draw_line(Vector2(1.3 * k, -0.55), top, ink, w)
	ci.draw_line(Vector2(-0.65 * k, -1.55 * k), Vector2(0.65 * k, -1.55 * k), ink, w * 0.7)
	# Arm: long end up along the throw, counterweight hanging off the short end.
	var d := Vector2(cos(e), -sin(e))
	var long_end := top + d * 2.9 * k
	var short_end := top - d * 1.0 * k
	ci.draw_line(short_end, long_end, ink, w * 1.6)
	ci.draw_line(long_end, long_end + Vector2(0.35, 0.9) * k, Color(ink, ink.a * 0.7), w * 0.6)
	_shape(ci, PackedVector2Array([short_end + Vector2(-0.45, 0.15) * k, short_end + Vector2(0.45, 0.15) * k,
		short_end + Vector2(0.35, 0.95) * k, short_end + Vector2(-0.35, 0.95) * k]), ink, fill, w)
	ci.draw_circle(top, 0.12 * k, ink)


static func _mortar(ci: CanvasItem, e: float, ink: Color, fill: Color, w: float) -> void:
	_shape(ci, PackedVector2Array([Vector2(-1.3, 0), Vector2(1.3, 0), Vector2(1.0, -0.8), Vector2(-1.0, -0.8)]),
		ink, fill, w)
	Blueprint.draw_hatch(ci, Rect2(-0.8, -0.65, 1.6, 0.5), Color(ink, ink.a * 0.35), 0.3, w * 0.5)
	var pivot := Vector2(0, -1.2)
	_shape(ci, _bar(pivot, e, 0.5, 1.6, 0.95), ink, fill, w)
	_shape(ci, _bar(pivot, e, -0.95, 0.15, 1.15), ink, fill, w)
	ci.draw_circle(pivot, 0.18, ink)


static func _cannon(ci: CanvasItem, e: float, ink: Color, fill: Color, w: float) -> void:
	ci.draw_line(Vector2(0, -0.9), Vector2(-2.2, -0.05), ink, w * 1.4)
	ci.draw_line(Vector2(-2.2, -0.05), Vector2(-2.5, -0.05), ink, w)
	_shape(ci, _bar(PIVOT + Vector2(0, 0.5), e, 1.0, 3.6, 0.38), ink, fill, w)
	_shape(ci, _bar(PIVOT + Vector2(0, 0.5), e, 1.0, 0.9, 0.55), ink, fill, w)
	_wheel(ci, Vector2(0, -0.9), 0.9, ink, fill, w, 8)


static func _howitzer(ci: CanvasItem, e: float, ink: Color, fill: Color, w: float, autoloaded: bool) -> void:
	ci.draw_line(Vector2(-0.3, -0.8), Vector2(-2.6, 0), ink, w * 1.5)
	ci.draw_line(Vector2(-0.3, -0.7), Vector2(-2.0, 0), Color(ink, ink.a * 0.6), w)
	_shape(ci, PackedVector2Array([Vector2(-0.7, -1.5), Vector2(0.8, -1.5), Vector2(0.6, -0.9), Vector2(-0.6, -0.9)]),
		ink, fill, w)
	var pivot := PIVOT + Vector2(0, 0.35)
	_shape(ci, _bar(pivot, e, 1.2, 3.8, 0.5), ink, fill, w)
	_shape(ci, _bar(pivot, e, 1.0, 1.6, 0.8), ink, fill, w)
	# Muzzle brake.
	_shape(ci, _bar(pivot, e, -2.15, 2.6, 0.7), ink, fill, w)
	if autoloaded:
		var d := Vector2(cos(e), -sin(e))
		var back := pivot - d * 1.4
		_shape(ci, PackedVector2Array([back + Vector2(-0.9, -0.3), back + Vector2(0.1, -0.3),
			back + Vector2(0.1, 0.5), back + Vector2(-0.9, 0.5)]), ink, fill, w)
		Blueprint.draw_hatch(ci, Rect2(back + Vector2(-0.8, -0.2), Vector2(0.8, 0.6)), Color(ink, ink.a * 0.4), 0.25,
			w * 0.5)
	_wheel(ci, Vector2(0.1, -0.7), 0.7, ink, fill, w, 6)


static func _sp_gun(ci: CanvasItem, e: float, ink: Color, fill: Color, w: float) -> void:
	_shape(ci, PackedVector2Array([Vector2(-2.3, -0.35), Vector2(-2.0, -1.1), Vector2(2.1, -1.1), Vector2(2.4, -0.35),
		Vector2(1.9, 0), Vector2(-1.8, 0)]), ink, fill, w)
	for i in 5:
		ci.draw_arc(Vector2(-1.6 + i * 0.8, -0.3), 0.28, 0.0, TAU, 12, ink, w * 0.8)
	var pivot := PIVOT + Vector2(0.3, 0.1)
	_shape(ci, _bar(pivot, e, 0.6, 4.6, 0.42), ink, fill, w)
	_shape(ci, PackedVector2Array([Vector2(-1.5, -1.1), Vector2(-1.3, -2.3), Vector2(0.8, -2.3), Vector2(1.2, -1.1)]),
		ink, fill, w)
	ci.draw_circle(pivot, 0.15, ink)


static func _rocket_truck(ci: CanvasItem, e: float, ink: Color, fill: Color, w: float) -> void:
	_shape(ci, PackedVector2Array([Vector2(-2.4, -0.6), Vector2(2.4, -0.6), Vector2(2.4, -0.95), Vector2(-2.4, -0.95)]),
		ink, fill, w)
	_shape(ci, PackedVector2Array([Vector2(1.2, -0.95), Vector2(2.4, -0.95), Vector2(2.4, -1.9), Vector2(1.6, -1.9),
		Vector2(1.2, -1.5)]), ink, fill, w)
	ci.draw_line(Vector2(1.75, -1.2), Vector2(2.3, -1.2), Color(ink, ink.a * 0.6), w * 0.6)
	for x in [-1.7, -0.8, 1.8]:
		_wheel(ci, Vector2(x, -0.4), 0.4, ink, fill, w, 4)
	var pivot := PIVOT + Vector2(-0.9, 0.6)
	var pod := _bar(pivot, minf(e, deg_to_rad(70.0)), 1.2, 3.0, 1.1)
	_shape(ci, pod, ink, fill, w)
	# Tube mouths across the pod's front face.
	var front_a := pod[1]
	var front_b := pod[2]
	for i in 3:
		ci.draw_circle(front_a.lerp(front_b, (i + 0.5) / 3.0), 0.15, ink)
	ci.draw_line(pod[0].lerp(pod[3], 0.5), pod[1].lerp(pod[2], 0.5), Color(ink, ink.a * 0.5), w * 0.6)
	ci.draw_line(pivot, Vector2(-0.9, -0.95), ink, w)


static func _railgun(ci: CanvasItem, e: float, ink: Color, fill: Color, w: float, heavy: bool) -> void:
	var len := 5.4 if heavy else 4.4
	_shape(ci, PackedVector2Array([Vector2(-1.8, 0), Vector2(1.8, 0), Vector2(1.2, -1.0), Vector2(-1.2, -1.0)]),
		ink, fill, w)
	ci.draw_line(Vector2(-1.2, -1.0), PIVOT, ink, w)
	ci.draw_line(Vector2(1.2, -1.0), PIVOT, ink, w)
	var d := Vector2(cos(e), -sin(e))
	var n := Vector2(-d.y, d.x)
	for side in [-1.0, 1.0]:
		var off: Vector2 = n * 0.28 * side
		_shape(ci, _bar(PIVOT + off, e, 1.2, len, 0.16), ink, fill, w * 0.8)
	var coils := 5 if heavy else 4
	for i in coils:
		var c := PIVOT + d * (-0.6 + (len - 1.6) * float(i) / (coils - 1))
		ci.draw_line(c - n * 0.55, c + n * 0.55, Color(Blueprint.LINE, ink.a), w * 1.6)
	ci.draw_circle(PIVOT, 0.2, ink)


static func _uplink(ci: CanvasItem, ink: Color, fill: Color, w: float) -> void:
	_shape(ci, PackedVector2Array([Vector2(-1.5, 0), Vector2(1.5, 0), Vector2(1.1, -0.6), Vector2(-1.1, -0.6)]),
		ink, fill, w)
	ci.draw_line(Vector2(-0.8, -0.6), Vector2(0, -1.7), ink, w)
	ci.draw_line(Vector2(0.8, -0.6), Vector2(0, -1.7), ink, w)
	# Dish tilted up-right, feed horn on a strut.
	var c := Vector2(0, -2.1)
	var tilt := deg_to_rad(-60.0)
	var pts := PackedVector2Array()
	for i in 13:
		var a := lerpf(-PI * 0.42, PI * 0.42, i / 12.0) + tilt + PI * 0.5
		pts.append(c + Vector2(cos(a), sin(a)) * 1.6 - Vector2(cos(tilt + PI * 0.5), sin(tilt + PI * 0.5)) * 1.3)
	ci.draw_polyline(pts, ink, w * 1.3)
	ci.draw_line(pts[0], pts[pts.size() - 1], Color(ink, ink.a * 0.5), w * 0.6)
	var axis := Vector2(cos(tilt), sin(tilt))
	ci.draw_line(c, c + axis * 1.4, ink, w * 0.8)
	ci.draw_circle(c + axis * 1.4, 0.15, ink)
	for r in [0.4, 0.7]:
		ci.draw_arc(c + axis * 1.4, r, tilt - 0.6, tilt + 0.6, 8, Color(Blueprint.LINE, ink.a * 0.6), w * 0.6)
