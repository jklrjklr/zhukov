extends Node
## Autoload "Game": scene flow and per-mission stats.

const MENU := "res://scenes/main_menu.tscn"
const MISSION := "res://scenes/mission.tscn"
const RANGE := "res://scenes/main.tscn"

## Stats of the current run (reset when a mission or the range starts).
var stats := {}
## Chosen loadout (main menu): primary weapon resource and stratagem ids.
var loadout := {
	"primary": "res://weapons/liberator.tres",
	"stratagems": ["resupply", "eat17", "eagle_airstrike", "orbital_120", "sentry_mg"],
}

const PRIMARIES := ["res://weapons/liberator.tres", "res://weapons/smg5.tres"]


func primary_stats() -> FirearmStats:
	return load(loadout.primary) as FirearmStats


func _ready() -> void:
	reset_stats()


func reset_stats() -> void:
	stats = {"shots": 0, "hits": 0, "kills": 0, "deaths": 0, "grenades": 0, "stims": 0}


func add_stat(key: String, amount := 1) -> void:
	stats[key] = stats.get(key, 0) + amount


func accuracy() -> float:
	return 100.0 * stats.hits / maxf(stats.shots, 1)


func goto_menu() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(MENU)


func start_mission() -> void:
	reset_stats()
	get_tree().paused = false
	get_tree().change_scene_to_file(MISSION)


func start_range() -> void:
	reset_stats()
	get_tree().paused = false
	get_tree().change_scene_to_file(RANGE)
