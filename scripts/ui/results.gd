extends Control
## PLACEHOLDER results screen (UI session replaces the visuals).


func _ready() -> void:
	var box := PlaceholderUI.centered_box(self)
	var r := GameState.last_battle_result
	if r == null:
		PlaceholderUI.label(box, "No battle result")
	else:
		PlaceholderUI.label(box, "VICTORY" if r.victory else "DEFEAT", 40)
		var report := StrategyController.new().last_settlement()
		if report:
			for line in report.summary_lines():
				PlaceholderUI.label(box, line)
		else:
			PlaceholderUI.label(box, "Payout: %d" % r.payout_earned)
			PlaceholderUI.label(box, "Net profit: %d" % r.net_profit(), 24)
		PlaceholderUI.label(box, "Shells: %d fired, %d hit (%d%% accuracy)" % [
				r.shells_fired, r.shells_hit, roundi(r.accuracy() * 100.0)])
		PlaceholderUI.label(box, "Targets destroyed: %d   Time: %ds" % [r.targets_destroyed, roundi(r.duration_s)])
		PlaceholderUI.label(box, "Funds now: %d" % GameState.player.money, 24)
	PlaceholderUI.button(box, "Continue", SceneRouter.goto.bind(SceneRouter.Screen.REGION_MAP))
