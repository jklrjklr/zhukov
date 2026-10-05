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


## Real-time light / occluder shadows and drawn drop shadows. Off for performance; flip to bring back.
var shadows_enabled := false

## Visual settings (user://settings.cfg): screen shake / hit-stop on big explosions.
var shake_enabled := true
## FPS / frame-time overlay (pause menu toggle), off by default.
var perf_overlay := false
const SETTINGS_PATH := "user://settings.cfg"


func _ready() -> void:
	reset_stats()
	RigAtlas.ensure(get_tree())
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		shake_enabled = bool(cfg.get_value("video", "shake", true))
		perf_overlay = bool(cfg.get_value("video", "perf", false))


func set_shake(on: bool) -> void:
	shake_enabled = on
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("video", "shake", on)
	cfg.save(SETTINGS_PATH)


func set_perf_overlay(on: bool) -> void:
	perf_overlay = on
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("video", "perf", on)
	cfg.save(SETTINGS_PATH)


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
