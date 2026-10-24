extends Node
## Autoload "SaveSystem": JSON saves in user://saves/. JSON (not .tres) so a save file
## can never carry executable script content.
##
## Autosave: once a campaign is started (start_new_campaign) or loaded (load_game), every
## campaign-changing event on EventBus schedules one save at the end of the frame, written to
## the active slot. Nothing is saved before that, so booting the game never overwrites a save.

const SAVE_DIR := "user://saves"
const SAVE_VERSION := 1

## Slot that autosave writes to, or -1 while no campaign is active (main menu at boot, tests).
var active_slot: int = -1
var _pending := false


func _ready() -> void:
	# Every event that changes what a save would contain.
	EventBus.money_changed.connect(func(_b: int, _d: int, _r: String) -> void: request_autosave())
	EventBus.inventory_changed.connect(request_autosave)
	EventBus.tech_unlocked.connect(func(_id: StringName) -> void: request_autosave())
	EventBus.era_changed.connect(func(_era: int) -> void: request_autosave())
	EventBus.auction_won.connect(func(_w: StringName, _c: ContractData, _p: PlotData, _price: int) -> void:
		request_autosave())
	EventBus.battle_started.connect(func(_c: ContractData, _p: PlotData) -> void: request_autosave())
	EventBus.battle_ended.connect(func(_r: BattleResult) -> void: request_autosave())
	# Results and the region map also change state through GameState directly; save on arrival.
	# Deferred: SceneRouter is a later autoload.
	(func() -> void: SceneRouter.screen_changed.connect(func(_s: int) -> void: request_autosave())).call_deferred()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		flush()


## Fresh campaign in `slot`, saved immediately; autosave follows it from now on.
func start_new_campaign(slot: int = 0) -> void:
	GameState.new_game()
	active_slot = slot
	save_game(slot)


## Stops autosave (e.g. tests, or before deleting the active slot).
func stop_autosave() -> void:
	active_slot = -1
	_pending = false


func request_autosave() -> void:
	if active_slot < 0 or _pending:
		return
	_pending = true
	flush.call_deferred()


## Writes a pending autosave now.
func flush() -> void:
	if not _pending or active_slot < 0:
		_pending = false
		return
	_pending = false
	save_game(active_slot)


func save_game(slot: int = 0) -> Error:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var data := {
		"version": SAVE_VERSION,
		"saved_at": Time.get_datetime_string_from_system(),
		"campaign_seed": GameState.campaign_seed,
		"player": GameState.player.to_dict(),
		"economy": GameState.economy_state,
	}
	# Write a temp file and swap it in, so a crash mid-write never corrupts the save.
	var tmp := _path(slot) + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	var err := DirAccess.rename_absolute(tmp, _path(slot))
	if err != OK:
		return err
	EventBus.game_saved.emit(slot)
	return OK


func load_game(slot: int = 0) -> Error:
	if not has_save(slot):
		return ERR_FILE_NOT_FOUND
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(_path(slot)))
	if typeof(parsed) != TYPE_DICTIONARY:
		return ERR_PARSE_ERROR
	# Future: migrate older versions here based on parsed["version"].
	GameState.load_player(PlayerState.from_dict(parsed.get("player", {})), int(parsed.get("campaign_seed", 0)))
	var economy: Variant = parsed.get("economy", {})
	GameState.economy_state = economy if typeof(economy) == TYPE_DICTIONARY else {}
	active_slot = slot
	_pending = false
	EventBus.game_loaded.emit(slot)
	return OK


func has_save(slot: int = 0) -> bool:
	return FileAccess.file_exists(_path(slot))


func delete_save(slot: int = 0) -> void:
	if slot == active_slot:
		stop_autosave()
	if has_save(slot):
		DirAccess.remove_absolute(_path(slot))


func _path(slot: int) -> String:
	return SAVE_DIR.path_join("slot_%d.json" % slot)
