class_name WeaponIcon
extends Control
## A weapon's line-art silhouette fitted into a small box (shop and repair lists).

var weapon: WeaponData
var ink := Blueprint.INK


static func create(p_weapon: WeaponData, box := Vector2(64, 40)) -> WeaponIcon:
	var icon := WeaponIcon.new()
	icon.weapon = p_weapon
	icon.custom_minimum_size = box
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return icon


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(Blueprint.PAPER_DARK, 0.6))
	Blueprint.draw_corner_ticks(self, Rect2(Vector2.ZERO, size).grow(-2), Color(Blueprint.LINE, 0.4), 5.0, 0.0)
	if weapon == null:
		return
	# Silhouettes are about 6 m wide and 5 m tall around the ground point.
	var scale := minf(size.x / 7.0, size.y / 5.5)
	var ground := Vector2(size.x * 0.5, size.y - 5.0)
	LauncherArt.draw_data(self, weapon, ground, scale, 40.0, ink, Color(Blueprint.PAPER, 0.9), 1.2)
