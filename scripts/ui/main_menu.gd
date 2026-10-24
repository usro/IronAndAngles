extends Control
## PLACEHOLDER main menu (UI session replaces the visuals; keep the flow calls).


func _ready() -> void:
	var box := PlaceholderUI.centered_box(self)
	PlaceholderUI.label(box, "IRON & ANGLES", 48)
	PlaceholderUI.button(box, "New Campaign", _on_new)
	var cont := PlaceholderUI.button(box, "Continue", _on_continue)
	cont.disabled = not SaveSystem.has_save()
	PlaceholderUI.button(box, "How to Play", func() -> void: add_child(HowToPlayPanel.new()))
	PlaceholderUI.button(box, "Quit", get_tree().quit)


func _on_new() -> void:
	GameState.new_game()
	SceneRouter.goto(SceneRouter.Screen.REGION_MAP)


func _on_continue() -> void:
	if SaveSystem.load_game() == OK:
		SceneRouter.goto(SceneRouter.Screen.REGION_MAP)
