extends Node

var save_slot:        int        = -1
var playtime:         float      = 0.0
var save_data:        Dictionary = {}
var ads_toggle_mode:  bool       = false

func load_slot(slot: int) -> void:
	save_slot = slot
	save_data = {}
	var path := "user://save_slot_%d.json" % slot
	if not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		save_data = parsed as Dictionary
	playtime = float(save_data.get("playtime", 0.0))
