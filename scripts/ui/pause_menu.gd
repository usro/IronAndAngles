class_name PauseMenu
extends OverlaySheet
## Esc in battle: pauses the battle. Retreat (which forfeits the contract) asks to confirm first.

var _on_retreat: Callable


func _init(on_retreat: Callable) -> void:
	super("FIELD COMMAND", "PAUSED", 460.0)
	_on_retreat = on_retreat


func build() -> void:
	get_tree().paused = true
	add_button("Resume", close_sheet, &"PrimaryButton")
	add_button("How to Play", func() -> void: add_child(HowToPlayPanel.new()))
	add_button("Settings", func() -> void: add_child(SettingsPanel.new()))
	add_button("Audio", func() -> void: add_child(AudioSettingsPanel.new()))
	add_text("Retreating forfeits the contract: no payout, and the auction price and shells are lost.",
		&"CaptionLabel")
	add_button("Retreat from the contract…", _confirm_retreat)


func _confirm_retreat() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.process_mode = Node.PROCESS_MODE_ALWAYS
	dialog.title = "Retreat?"
	dialog.dialog_text = "Retreat and forfeit this contract?\nYou keep nothing for it, and the auction price is lost."
	dialog.ok_button_text = "Retreat"
	dialog.confirmed.connect(func() -> void:
		close_sheet()
		_on_retreat.call())
	add_child(dialog)
	dialog.popup_centered()


func close_sheet() -> void:
	get_tree().paused = false
	super()
