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
var _sight: SightData = null
var sprite_path: String = ""
var ammo_current: int = 0
var fire_mode_index: int = 0

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
	return w

func get_sight() -> SightData:
	return _sight if _sight != null else SightData.iron_sights()

func cycle_fire_mode() -> void:
	if fire_modes.size() <= 1:
		return
	fire_mode_index = (fire_mode_index + 1) % fire_modes.size()

func calc_damage(distance: float) -> int:
	if distance <= damage_falloff_start:
		return damage
	if distance >= damage_falloff_end:
		return int(damage * 0.2)
	var t := (distance - damage_falloff_start) / (damage_falloff_end - damage_falloff_start)
	return int(lerpf(float(damage), float(damage) * 0.2, t))
