class_name AttachmentData
extends RefCounted

var item_id: String = ""
var display_name: String = ""
var attachment_slot: String = ""
var tags: Array = []
var compatible_ids: Array = []
var compatible_types: Array = []
var grid_size: Vector2i = Vector2i(1, 1)
var weight: float = 0.0
var stat_mods: Dictionary = {}
var sight_override: SightData = null

static func from_dict(id: String, def: Dictionary) -> AttachmentData:
	var a := AttachmentData.new()
	a.item_id = id
	a.display_name = def.get("display_name", id)
	a.attachment_slot = def.get("attachment_slot", "")
	a.tags = def.get("tags", [])
	a.compatible_ids = def.get("compatible_ids", [])
	a.compatible_types = def.get("compatible_types", [])
	var sz: Array = def.get("grid_size", [1, 1])
	a.grid_size = Vector2i(sz[0], sz[1])
	a.weight = def.get("weight", 0.0)
	a.stat_mods = def.get("stat_mods", {})
	if def.has("sight_override"):
		a.sight_override = SightData.from_dict(def["sight_override"])
	return a

func to_dict() -> Dictionary:
	var d: Dictionary = {
		"id": item_id,
		"display_name": display_name,
		"attachment_slot": attachment_slot,
		"tags": tags,
		"compatible_ids": compatible_ids,
		"compatible_types": compatible_types,
		"grid_size": [grid_size.x, grid_size.y],
		"weight": weight,
		"stat_mods": stat_mods,
	}
	if sight_override != null:
		d["sight_override"] = {
			"display_name": sight_override.display_name,
			"reticle_type": sight_override.reticle_type,
			"ergo_mult": sight_override.ergo_mult,
			"scope_mult": sight_override.scope_mult,
			"fov_radius": sight_override.fov_radius,
		}
	return d
