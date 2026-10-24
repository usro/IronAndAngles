extends Control
## PLACEHOLDER results screen (UI session replaces the visuals).


func _ready() -> void:
	var box := PlaceholderUI.centered_box(self)
	var r := GameState.last_battle_result
	if r == null:
		PlaceholderUI.label(box, "No battle result")
	else:
		PlaceholderUI.label(box, "VICTORY" if r.victory else "DEFEAT", 40)
		PlaceholderUI.label(box, "Payout: %d" % r.payout_earned)
		PlaceholderUI.label(box, "Shells fired: %d  (cost %d)" % [r.shells_fired, r.ammo_spent])
		PlaceholderUI.label(box, "Net profit: %d" % r.net_profit(), 24)
	PlaceholderUI.button(box, "Continue", SceneRouter.goto.bind(SceneRouter.Screen.REGION_MAP))
