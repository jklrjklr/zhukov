class_name WeaponData
extends Resource

var item_id: String = ""
var display_name: String = ""
var type: String = ""
var damage: int = 0
var armor_penetration: int = 0
var stagger_power: float = 0.0
var damage_falloff_start: float = 0.0
var damage_falloff_end: float = 0.0
var rpm: int = 0
var muzzle_velocity: float = 0.0
var fire_modes: Array = ["semi"]
var pellet_count: int = 1
var spread: float = 0.0
var muzzle_rise: float = 0.0
var muzzle_rise_recovery: float = 0.0
var lateral_recoil: float = 0.0
var lateral_recoil_left_chance: float = 0.5
var ergonomics: float = 0.5
var ads_speed: float = 0.2
var reload_time: float = 2.0
var reload_type: String = "magazine"
var magazine_size: int = 0
var weight: float = 1.0
var sound_level: float = 0.5
var muzzle_flash_scale: float = 1.0
var headshot_multiplier: float = 3.0
var slot_size: Array = [1, 2]
var sprite_path: String = ""
var ammo_current: int = 0
var fire_mode_index: int = 0

# Attachment slot registry: slot_name → { "accepts_tags": [], "accepts_ids": [] }
var _attachment_slots: Dictionary = {}
# Currently fitted attachments: slot_name → AttachmentData
var _attachments: Dictionary = {}

var _sight: SightData = null

var fire_interval: float:
	get: return 60.0 / float(rpm) if rpm > 0 else 999.0

var active_fire_mode: String:
	get: return fire_modes[fire_mode_index] if fire_modes.size() > 0 else "semi"

static func from_dict(id: String, def: Dictionary) -> WeaponData:
	if def.is_empty():
		return null

	var w := WeaponData.new()
	w.item_id = id
	w.display_name = def.get("display_name", id)
	w.type = def.get("type", "")
	w.damage = def.get("damage", 30)
	w.armor_penetration = def.get("armor_penetration", 20)
	w.stagger_power = def.get("stagger_power", 0.0)
	w.damage_falloff_start = def.get("damage_falloff_start", 300.0)
	w.damage_falloff_end = def.get("damage_falloff_end", 800.0)
	w.rpm = def.get("rpm", 300)
	w.muzzle_velocity = def.get("muzzle_velocity", 1800.0)
	w.fire_modes = def.get("fire_modes", ["semi"])
	w.pellet_count = def.get("pellet_count", 1)
	w.spread = def.get("spread", 2.0)
	w.muzzle_rise = def.get("muzzle_rise", 8.0)
	w.muzzle_rise_recovery = def.get("muzzle_rise_recovery", 6.0)
	w.lateral_recoil = def.get("lateral_recoil", 3.0)
	w.lateral_recoil_left_chance = def.get("lateral_recoil_left_chance", 0.5)
	w.ergonomics = def.get("ergonomics", 0.5)
	w.ads_speed = def.get("ads_speed", 0.2)
	w.reload_time = def.get("reload_time", 2.0)
	w.reload_type = def.get("reload_type", "magazine")
	w.magazine_size = def.get("magazine_size", 0)
	w.weight = def.get("weight", 1.0)
	w.sound_level = def.get("sound_level", 0.5)
	w.muzzle_flash_scale = def.get("muzzle_flash_scale", 1.0)
	w.headshot_multiplier = def.get("headshot_multiplier", 3.0)
	w.slot_size = def.get("slot_size", [1, 2])
	w.sprite_path = def.get("sprite", "")
	w.ammo_current = w.magazine_size
	if def.has("sight"):
		w._sight = SightData.from_dict(def["sight"])
	if def.has("attachment_slots"):
		w._load_attachment_slots(def["attachment_slots"])
	return w

func _load_attachment_slots(slots_def: Dictionary) -> void:
	for slot_name: String in slots_def:
		var entry: Dictionary = slots_def[slot_name]
		_attachment_slots[slot_name] = {
			"accepts_tags": entry.get("accepts_tags", []),
			"accepts_ids": entry.get("accepts_ids", []),
		}

# --- Slot queries ---

func has_slot(slot_name: String) -> bool:
	return _attachment_slots.has(slot_name)

func get_slot_names() -> Array:
	return _attachment_slots.keys()

func can_attach(slot_name: String, att: AttachmentData) -> bool:
	if not _attachment_slots.has(slot_name):
		return false
	var slot: Dictionary = _attachment_slots[slot_name]
	var tag_ok := false
	for t: String in att.tags:
		if (slot["accepts_tags"] as Array).has(t):
			tag_ok = true
			break
	var id_ok: bool = (slot["accepts_ids"] as Array).has(att.item_id)
	if not (tag_ok or id_ok):
		return false
	if att.compatible_types.size() > 0 and not (att.compatible_types as Array).has(type):
		return false
	if att.compatible_ids.size() > 0 and not (att.compatible_ids as Array).has(item_id):
		return false
	return true

func attach(slot_name: String, att: AttachmentData) -> bool:
	if not can_attach(slot_name, att):
		return false
	_attachments[slot_name] = att
	return true

func detach(slot_name: String) -> AttachmentData:
	if not _attachments.has(slot_name):
		return null
	var att: AttachmentData = _attachments[slot_name]
	_attachments.erase(slot_name)
	return att

func get_attachment(slot_name: String) -> AttachmentData:
	return _attachments.get(slot_name, null)

func get_all_attachments() -> Dictionary:
	return _attachments.duplicate()

# --- Effective stat computation ---

func _sum_mod(stat: String) -> float:
	var total := 0.0
	for att: AttachmentData in _attachments.values():
		total += float(att.stat_mods.get(stat, 0))
	return total

func get_effective_damage() -> float:
	return float(damage) + _sum_mod("damage")

func get_effective_armor_penetration() -> float:
	return float(armor_penetration) + _sum_mod("armor_penetration")

func get_effective_spread() -> float:
	return maxf(0.0, spread + _sum_mod("spread"))

func get_effective_muzzle_rise() -> float:
	return maxf(0.0, muzzle_rise + _sum_mod("muzzle_rise"))

func get_effective_muzzle_rise_recovery() -> float:
	return maxf(0.1, muzzle_rise_recovery + _sum_mod("muzzle_rise_recovery"))

func get_effective_lateral_recoil() -> float:
	return maxf(0.0, lateral_recoil + _sum_mod("lateral_recoil"))

func get_effective_ergonomics() -> float:
	return clampf(ergonomics + _sum_mod("ergonomics"), 0.0, 1.0)

func get_effective_ads_speed() -> float:
	return maxf(0.05, ads_speed + _sum_mod("ads_speed"))

func get_effective_reload_time() -> float:
	return maxf(0.3, reload_time + _sum_mod("reload_time"))

func get_effective_magazine_size() -> int:
	return max(1, magazine_size + int(_sum_mod("magazine_size")))

func get_effective_sound_level() -> float:
	return clampf(sound_level + _sum_mod("sound_level"), 0.0, 1.0)

func get_effective_muzzle_velocity() -> float:
	return maxf(100.0, muzzle_velocity + _sum_mod("muzzle_velocity"))

func get_effective_weight() -> float:
	return maxf(0.1, weight + _sum_mod("weight"))

func get_effective_sight() -> SightData:
	var optic: AttachmentData = _attachments.get("optic", null)
	if optic != null and optic.sight_override != null:
		return optic.sight_override
	return _sight if _sight != null else SightData.iron_sights()

# --- Legacy alias (used by Player ADS) ---
func get_sight() -> SightData:
	return get_effective_sight()

func cycle_fire_mode() -> void:
	if fire_modes.size() <= 1:
		return
	fire_mode_index = (fire_mode_index + 1) % fire_modes.size()

func calc_damage(distance: float) -> int:
	var eff := get_effective_damage()
	if distance <= damage_falloff_start:
		return int(eff)
	if distance >= damage_falloff_end:
		return int(eff * 0.2)
	var t := (distance - damage_falloff_start) / (damage_falloff_end - damage_falloff_start)
	return int(lerpf(eff, eff * 0.2, t))
