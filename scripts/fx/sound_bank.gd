class_name SoundBank
extends RefCounted
## Which file plays for which moment, on which bus and how loud. The files are synthesized by
## audio/tools/generate_sounds.py; levels here are relative to their -1 dBFS peak.

const SFX := &"SFX"
const UI := &"UI"
const MUSIC := &"Music"
const AMBIENCE := &"Ambience"

## id -> [path, bus, base dB, pitch spread (± fraction)].
const SOUNDS := {
	&"launch_trebuchet": ["res://audio/sfx/launch_trebuchet.wav", SFX, -2.0, 0.06],
	&"launch_gunpowder": ["res://audio/sfx/launch_gunpowder.wav", SFX, 0.0, 0.05],
	&"launch_rocket": ["res://audio/sfx/launch_rocket.wav", SFX, -2.0, 0.06],
	&"launch_railgun": ["res://audio/sfx/launch_railgun.wav", SFX, -1.0, 0.03],
	&"railgun_charge": ["res://audio/sfx/railgun_charge.wav", SFX, -9.0, 0.02],
	&"orbital_uplink": ["res://audio/sfx/orbital_uplink.wav", SFX, -12.0, 0.02],
	&"orbital_descent": ["res://audio/sfx/orbital_descent.wav", SFX, -3.0, 0.03],
	&"reload_clank": ["res://audio/sfx/reload_clank.wav", SFX, -6.0, 0.06],
	&"reload_trebuchet": ["res://audio/sfx/reload_trebuchet.wav", SFX, -8.0, 0.06],
	&"bounce_thud": ["res://audio/sfx/bounce_thud.wav", SFX, -3.0, 0.1],
	&"impact_explosive": ["res://audio/sfx/impact_explosive.wav", SFX, 0.0, 0.07],
	&"impact_kinetic": ["res://audio/sfx/impact_kinetic.wav", SFX, -1.0, 0.08],
	&"impact_incendiary": ["res://audio/sfx/impact_incendiary.wav", SFX, -1.0, 0.07],
	&"impact_shrapnel": ["res://audio/sfx/impact_shrapnel.wav", SFX, -1.0, 0.07],
	&"impact_ap": ["res://audio/sfx/impact_ap.wav", SFX, -1.0, 0.07],
	&"impact_massive": ["res://audio/sfx/impact_massive.wav", SFX, 1.0, 0.05],
	&"debris": ["res://audio/sfx/debris.wav", SFX, -8.0, 0.12],
	&"target_hit": ["res://audio/sfx/target_hit.wav", SFX, -5.0, 0.1],
	&"target_collapse": ["res://audio/sfx/target_collapse.wav", SFX, 0.0, 0.06],
	&"battery_hit": ["res://audio/sfx/battery_hit.wav", SFX, -1.0, 0.06],
	&"incoming_whistle": ["res://audio/sfx/incoming_whistle.wav", SFX, -4.0, 0.06],
	&"weapon_select": ["res://audio/sfx/weapon_select.wav", UI, -10.0, 0.05],
	&"click": ["res://audio/ui/click.wav", UI, -8.0, 0.05],
	&"hover": ["res://audio/ui/hover.wav", UI, -20.0, 0.08],
	&"purchase": ["res://audio/ui/purchase.wav", UI, -6.0, 0.02],
	&"research": ["res://audio/ui/research.wav", UI, -6.0, 0.0],
	&"era": ["res://audio/ui/era.wav", UI, -4.0, 0.0],
	&"gavel": ["res://audio/ui/gavel.wav", UI, -2.0, 0.04],
	&"stamp": ["res://audio/ui/stamp.wav", UI, -6.0, 0.06],
	&"payout": ["res://audio/ui/payout.wav", UI, -6.0, 0.02],
	&"alert": ["res://audio/ui/alert.wav", UI, -14.0, 0.0],
	&"battle_start": ["res://audio/music/battle_start.wav", MUSIC, -6.0, 0.0],
	&"sting_victory": ["res://audio/music/sting_victory.wav", MUSIC, -3.0, 0.0],
	&"sting_defeat": ["res://audio/music/sting_defeat.wav", MUSIC, -3.0, 0.0],
	&"menu_theme": ["res://audio/music/menu_theme.wav", MUSIC, -10.0, 0.0],
	&"wind": ["res://audio/ambience/wind.wav", AMBIENCE, 0.0, 0.0],
	&"rain": ["res://audio/ambience/rain.wav", AMBIENCE, 0.0, 0.0],
}

## Pitch per weapon id: bigger guns sound lower.
const WEAPON_PITCH := {
	&"great_trebuchet": 0.85,
	&"bronze_mortar": 1.12,
	&"rifled_cannon": 1.0,
	&"heavy_howitzer": 0.8,
	&"sp_howitzer": 0.9,
	&"autoloaded_howitzer": 0.95,
	&"heavy_railgun": 0.85,
}


static func path(id: StringName) -> String:
	return SOUNDS[id][0] if SOUNDS.has(id) else ""


static func bus(id: StringName) -> StringName:
	return SOUNDS[id][1] if SOUNDS.has(id) else SFX


static func base_db(id: StringName) -> float:
	return SOUNDS[id][2] if SOUNDS.has(id) else 0.0


static func pitch_spread(id: StringName) -> float:
	return SOUNDS[id][3] if SOUNDS.has(id) else 0.0


static func launch_sound(launcher: GameConstants.LauncherType) -> StringName:
	match launcher:
		GameConstants.LauncherType.MECHANICAL: return &"launch_trebuchet"
		GameConstants.LauncherType.ROCKET: return &"launch_rocket"
		GameConstants.LauncherType.RAILGUN: return &"launch_railgun"
		GameConstants.LauncherType.ORBITAL: return &"orbital_uplink"
	return &"launch_gunpowder"


## Played when a weapon finishes reloading: winch, breech clank, capacitor whine.
static func reload_sound(launcher: GameConstants.LauncherType) -> StringName:
	match launcher:
		GameConstants.LauncherType.MECHANICAL: return &"reload_trebuchet"
		GameConstants.LauncherType.RAILGUN: return &"railgun_charge"
		GameConstants.LauncherType.ORBITAL: return &"orbital_uplink"
	return &"reload_clank"


static func impact_sound(ammo: AmmoData) -> StringName:
	if ammo == null:
		return &"impact_explosive"
	if ammo.crater_radius_m >= 8.0:
		return &"impact_massive"
	match ammo.damage_type:
		GameConstants.DamageType.KINETIC: return &"impact_kinetic"
		GameConstants.DamageType.INCENDIARY: return &"impact_incendiary"
		GameConstants.DamageType.SHRAPNEL: return &"impact_shrapnel"
		GameConstants.DamageType.ARMOR_PIERCING: return &"impact_ap"
	return &"impact_explosive"


## Bigger blasts are louder and lower: {"db", "pitch"} from the ammo's explosion radius.
static func blast_size(ammo: AmmoData) -> Dictionary:
	var r := ammo.explosion_radius_m if ammo else 4.0
	return {"db": clampf(-5.0 + 0.7 * r, -5.0, 2.0), "pitch": clampf(1.2 - 0.035 * r, 0.8, 1.2)}
