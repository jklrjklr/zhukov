class_name WeaponSystem
extends Node

const MAX_SLOTS := 3

signal shot_fired(origin: Vector2, direction: Vector2, damage: int, data: WeaponData)
signal reloading(duration: float)
signal reload_complete
signal ammo_changed(current: int, mag_size: int)
signal weapon_switched(slot: int)
signal fire_mode_changed(mode: String)
signal attachments_changed(slot_idx: int)

@onready var slots: Array[WeaponSlot] = [$WeaponSlot0]
@onready var player: Player = get_parent()
@onready var body_sprite: Node2D = get_parent().get_node("Sprite2D")
@onready var camera: Camera2D = get_parent().get_node("Camera2D")

var _item_db: Node = null
var _active_slot: int = 0
var _fire_timer: float = 0.0
var _is_reloading: bool = false
var _reload_timer: float = 0.0
var _rise_current: float = 0.0
var _lateral_current: float = 0.0

var _burst_remaining: int = 0
@warning_ignore("unused_private_class_variable")
var _burst_timer: float = 0.0

var _state_machine: CharacterStateMachine = null

var fire_blocked: bool = false

func _ready() -> void:
	_item_db = get_node_or_null("/root/ItemDB")
	shot_fired.connect(_on_shot_fired)
	await get_tree().process_frame
	_state_machine = get_parent().get_node_or_null("CharacterStateMachine")

func _on_shot_fired(origin: Vector2, direction: Vector2, damage: int, data: WeaponData) -> void:
	BulletSpawner.spawn(origin, direction, damage, data.get_effective_muzzle_velocity(), data.headshot_multiplier)

func get_active_weapon() -> WeaponData:
	return slots[_active_slot].data

func get_active_slot() -> int:
	return _active_slot

func _physics_process(delta: float) -> void:
	_fire_timer = max(0.0, _fire_timer - delta)

	if _is_reloading:
		_reload_timer -= delta
		if _reload_timer <= 0.0:
			_finish_reload()

	if _burst_remaining > 0 and _fire_timer <= 0.0:
		if fire_blocked:
			_burst_remaining = 0
		else:
			_do_shoot()
			_burst_remaining -= 1

	_decay_recoil(delta)

# Load weapon by item ID with no attachments (starter loadout / testing).
func equip(slot: int, item_id: String) -> void:
	if slot < 0 or slot >= MAX_SLOTS:
		push_error("WeaponSystem: invalid slot %d" % slot)
		return

	var def: Dictionary = _item_db.get_item(item_id)
	var weapon: WeaponData = WeaponData.from_dict(item_id, def)
	if weapon == null:
		return

	slots[slot].load_weapon(weapon)

	if slot == _active_slot:
		_apply_ergonomics()
		ammo_changed.emit(weapon.ammo_current, weapon.get_effective_magazine_size())
		fire_mode_changed.emit(weapon.active_fire_mode)

# Load weapon from an inventory Item, applying any stored attachments.
func equip_item(slot: int, item: Item) -> void:
	if slot < 0 or slot >= MAX_SLOTS:
		push_error("WeaponSystem: invalid slot %d" % slot)
		return
	if item == null:
		return

	var def: Dictionary = _item_db.get_item(item.item_id)
	var weapon: WeaponData = WeaponData.from_dict(item.item_id, def)
	if weapon == null:
		return

	for att_slot: String in item.attachments:
		var att_id: String = item.attachments[att_slot]
		var att_def: Dictionary = _item_db.get_item(att_id)
		if att_def.is_empty():
			push_warning("WeaponSystem: attachment '%s' not found in ItemDB" % att_id)
			continue
		var att := AttachmentData.from_dict(att_id, att_def)
		if not weapon.attach(att_slot, att):
			push_warning("WeaponSystem: attachment '%s' rejected for slot '%s'" % [att_id, att_slot])

	weapon.ammo_current = mini(weapon.ammo_current, weapon.get_effective_magazine_size())

	slots[slot].load_weapon(weapon)

	if slot == _active_slot:
		_apply_ergonomics()
		ammo_changed.emit(weapon.ammo_current, weapon.get_effective_magazine_size())
		fire_mode_changed.emit(weapon.active_fire_mode)

func unequip(slot: int) -> void:
	slots[slot].clear()
	if slot == _active_slot:
		player.set_ergonomics(0.5)

func switch_slot(slot: int) -> void:
	if slot == _active_slot or slot < 0 or slot >= MAX_SLOTS:
		return

	if _is_reloading:
		cancel_reload()

	slots[_active_slot].visible = false
	_active_slot = slot
	slots[_active_slot].visible = slots[_active_slot].data != null
	_apply_ergonomics()

	var w: WeaponData = get_active_weapon()
	if w:
		ammo_changed.emit(w.ammo_current, w.get_effective_magazine_size())
		fire_mode_changed.emit(w.active_fire_mode)

	weapon_switched.emit(_active_slot)

func shoot() -> void:
	if fire_blocked:
		return
	if _state_machine != null and not _state_machine.can_shoot():
		return
	if _is_reloading or _fire_timer > 0.0:
		return

	var w: WeaponData = get_active_weapon()
	if w == null:
		return
	if w.ammo_current <= 0:
		reload()
		return

	_do_shoot()

func start_burst(count: int) -> void:
	if fire_blocked:
		return
	if _state_machine != null and not _state_machine.can_shoot():
		return
	if _is_reloading or _fire_timer > 0.0:
		return

	var w: WeaponData = get_active_weapon()
	if w == null or w.ammo_current <= 0:
		return

	_burst_remaining = count
	_do_shoot()
	_burst_remaining -= 1

func _do_shoot() -> void:
	var w: WeaponData = get_active_weapon()
	if w == null or w.ammo_current <= 0:
		_burst_remaining = 0
		return

	_fire_timer = w.fire_interval

	var dir: Vector2 = Vector2.UP.rotated(body_sprite.global_rotation)
	var origin: Vector2 = player.global_position + dir * 28.0
	var lateral_sign: float = _lateral_sign(w)

	var spread_rad: float = deg_to_rad(w.get_effective_spread())
	for i in range(w.pellet_count):
		var offset: float = randf_range(-spread_rad, spread_rad)
		shot_fired.emit(origin, dir.rotated(offset), int(w.get_effective_damage()), w)

	w.ammo_current -= 1
	ammo_changed.emit(w.ammo_current, w.get_effective_magazine_size())

	_rise_current += w.get_effective_muzzle_rise()
	camera.add_muzzle_rise_kick(w.get_effective_muzzle_rise())
	_lateral_current += w.get_effective_lateral_recoil() * lateral_sign
	_apply_recoil_to_camera(w, lateral_sign)

func reload() -> void:
	if _state_machine != null and not _state_machine.can_reload():
		return
	var w: WeaponData = get_active_weapon()
	if w == null or _is_reloading or w.ammo_current == w.get_effective_magazine_size():
		return

	_is_reloading = true
	_reload_timer = w.get_effective_reload_time()
	reloading.emit(w.get_effective_reload_time())

func _finish_reload() -> void:
	_is_reloading = false

	var w: WeaponData = get_active_weapon()
	if w:
		w.ammo_current = w.get_effective_magazine_size()
		ammo_changed.emit(w.ammo_current, w.get_effective_magazine_size())

	reload_complete.emit()

func cancel_reload() -> void:
	_is_reloading = false
	_reload_timer = 0.0

func cycle_fire_mode() -> void:
	var w: WeaponData = get_active_weapon()
	if w == null:
		return
	w.cycle_fire_mode()
	fire_mode_changed.emit(w.active_fire_mode)

func _decay_recoil(delta: float) -> void:
	var w: WeaponData = get_active_weapon()
	if w == null:
		_rise_current = 0.0
		_lateral_current = 0.0
		return

	var z := camera.zoom.x
	_rise_current = move_toward(_rise_current, 0.0, w.get_effective_muzzle_rise_recovery() * z * z * delta)
	_lateral_current = move_toward(_lateral_current, 0.0, w.get_effective_muzzle_rise_recovery() * z * z * delta)

func _apply_recoil_to_camera(w: WeaponData, lateral_sign: float) -> void:
	var lateral_rad: float = w.get_effective_lateral_recoil() * 0.001 * lateral_sign
	camera.add_lateral_recoil(lateral_rad)

func _lateral_sign(w: WeaponData) -> float:
	var left_chance: float = clampf(w.lateral_recoil_left_chance, 0.0, 1.0)
	return -1.0 if randf() < left_chance else 1.0

func _apply_ergonomics() -> void:
	var w: WeaponData = get_active_weapon()
	player.set_ergonomics(w.get_effective_ergonomics() if w != null else 0.5)
	camera.set_muzzle_rise_recovery(w.get_effective_muzzle_rise_recovery() if w != null else 0.1)

func get_is_reloading() -> bool:
	return _is_reloading

func get_reload_progress() -> float:
	var w: WeaponData = get_active_weapon()
	if not _is_reloading or w == null:
		return 1.0
	return 1.0 - _reload_timer / w.get_effective_reload_time()

# --- Attachment API ---
# These operate on the live WeaponData in a given slot.
# The caller must also update Item.attachments for the change to persist through save/load.

func attach_to_slot(weapon_slot_idx: int, att_slot_name: String, att: AttachmentData) -> bool:
	if weapon_slot_idx < 0 or weapon_slot_idx >= slots.size():
		return false
	var w: WeaponData = slots[weapon_slot_idx].data
	if w == null:
		return false
	var ok := w.attach(att_slot_name, att)
	if ok:
		if weapon_slot_idx == _active_slot:
			_apply_ergonomics()
			ammo_changed.emit(w.ammo_current, w.get_effective_magazine_size())
		attachments_changed.emit(weapon_slot_idx)
	return ok

func detach_from_slot(weapon_slot_idx: int, att_slot_name: String) -> AttachmentData:
	if weapon_slot_idx < 0 or weapon_slot_idx >= slots.size():
		return null
	var w: WeaponData = slots[weapon_slot_idx].data
	if w == null:
		return null
	var att: AttachmentData = w.detach(att_slot_name)
	if att != null:
		# Clamp ammo if magazine was removed
		w.ammo_current = mini(w.ammo_current, w.get_effective_magazine_size())
		if weapon_slot_idx == _active_slot:
			_apply_ergonomics()
			ammo_changed.emit(w.ammo_current, w.get_effective_magazine_size())
		attachments_changed.emit(weapon_slot_idx)
	return att
