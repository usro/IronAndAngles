extends Node
## Autoload "DataRegistry": loads every content .tres at startup and looks them up by id.
## Content folders are owned by the tech-tree/content session; adding a file is enough to register it.

const WEAPON_DIR := "res://data/weapons"
const AMMO_DIR := "res://data/ammo"
const TECH_DIR := "res://data/tech"
const CONTRACT_DIR := "res://data/contracts"
const PLOT_DIR := "res://data/plots"
const RIVAL_DIR := "res://data/rivals"

var weapons: Dictionary = {}    # StringName -> WeaponData
var ammo: Dictionary = {}       # StringName -> AmmoData
var tech: Dictionary = {}       # StringName -> TechNodeData
var contracts: Dictionary = {}  # StringName -> ContractData
var plots: Dictionary = {}      # StringName -> PlotData
var rivals: Dictionary = {}     # StringName -> RivalData


func _ready() -> void:
	reload()


func reload() -> void:
	weapons = _load_dir(WEAPON_DIR, WeaponData)
	ammo = _load_dir(AMMO_DIR, AmmoData)
	tech = _load_dir(TECH_DIR, TechNodeData)
	contracts = _load_dir(CONTRACT_DIR, ContractData)
	plots = _load_dir(PLOT_DIR, PlotData)
	rivals = _load_dir(RIVAL_DIR, RivalData)


func get_weapon(id: StringName) -> WeaponData:
	return weapons.get(id)


func get_ammo(id: StringName) -> AmmoData:
	return ammo.get(id)


func get_tech(id: StringName) -> TechNodeData:
	return tech.get(id)


func get_contract(id: StringName) -> ContractData:
	return contracts.get(id)


func get_plot(id: StringName) -> PlotData:
	return plots.get(id)


func get_rival(id: StringName) -> RivalData:
	return rivals.get(id)


static func _load_dir(path: String, type: Script) -> Dictionary:
	var out := {}
	var dir := DirAccess.open(path)
	if dir == null:
		return out
	for file in dir.get_files():
		# Exported builds list "x.tres.remap"; load() resolves the original path.
		file = file.trim_suffix(".remap")
		if not (file.ends_with(".tres") or file.ends_with(".res")):
			continue
		var res := load(path.path_join(file))
		if res == null or res.get_script() != type:
			push_warning("DataRegistry: skipping %s (not a %s)" % [file, type.get_global_name()])
			continue
		if res.id == &"":
			push_warning("DataRegistry: %s has no id" % file)
			continue
		if out.has(res.id):
			push_error("DataRegistry: duplicate id '%s' in %s" % [res.id, path])
		out[res.id] = res
	return out
