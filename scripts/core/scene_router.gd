extends Node
## Autoload "SceneRouter": the only place that changes the top-level scene.
## Flow: MAIN_MENU -> REGION_MAP (auction, shop, tech) -> BATTLE -> RESULTS -> REGION_MAP

enum Screen { MAIN_MENU, REGION_MAP, BATTLE, RESULTS }

const SCENES := {
	Screen.MAIN_MENU: "res://scenes/menu/main_menu.tscn",
	Screen.REGION_MAP: "res://scenes/strategy/region_map.tscn",
	Screen.BATTLE: "res://scenes/battle/battle.tscn",
	Screen.RESULTS: "res://scenes/results/results.tscn",
}

signal screen_changed(screen: Screen)

var current: Screen = Screen.MAIN_MENU


func goto(screen: Screen) -> void:
	current = screen
	# Deferred so callers can finish their frame (e.g. a button handler) before the swap.
	get_tree().change_scene_to_file.call_deferred(SCENES[screen])
	screen_changed.emit(screen)
