extends Node
## Autoload "SaveSystem": JSON saves in user://saves/. JSON (not .tres) so a save file
## can never carry executable script content.

const SAVE_DIR := "user://saves"
const SAVE_VERSION := 1


func save_game(slot: int = 0) -> Error:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var data := {
		"version": SAVE_VERSION,
		"saved_at": Time.get_datetime_string_from_system(),
		"campaign_seed": GameState.campaign_seed,
		"player": GameState.player.to_dict(),
	}
	var f := FileAccess.open(_path(slot), FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(data, "\t"))
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
	EventBus.game_loaded.emit(slot)
	return OK


func has_save(slot: int = 0) -> bool:
	return FileAccess.file_exists(_path(slot))


func delete_save(slot: int = 0) -> void:
	if has_save(slot):
		DirAccess.remove_absolute(_path(slot))


func _path(slot: int) -> String:
	return SAVE_DIR.path_join("slot_%d.json" % slot)
