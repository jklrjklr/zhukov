extends Node2D

var _playtime:    float = 0.0
var _game_active: bool  = false
var _pause_menu:  PauseMenu = null
var _player:      Player = null

func _ready() -> void:
	var slot      := GameState.save_slot
	var save_data := GameState.save_data

	# Fallback for running main.tscn directly during dev
	if slot < 0:
		slot = 0

	_playtime = GameState.playtime

	_player = $Player
	var inventory_sys: InventorySystem = $Player/InventorySystem
	var inventory_ui:  CanvasLayer     = $InventoryUI

	if save_data.has("inventory"):
		inventory_sys.load_from_dict(save_data["inventory"])
	else:
		_apply_starter_loadout()

	inventory_ui.setup(inventory_sys)
	inventory_ui.visibility_changed.connect(func():
		TouchInputHandler.joystick_disabled = inventory_ui.visible)
	$HUD.inventory_requested.connect(inventory_ui.toggle)

	if save_data.has("health"):
		_player.health     = int(save_data["health"])
		_player.max_health = int(save_data.get("max_health", 100))
	if save_data.has("position"):
		var pos: Array = save_data["position"]
		_player.global_position = Vector2(float(pos[0]), float(pos[1]))
	if save_data.has("survival"):
		var sv: Dictionary = save_data["survival"]
		_player.survival.stamina = float(sv.get("stamina", 100.0))
		_player.survival.hunger  = float(sv.get("hunger",  100.0))
		_player.survival.thirst  = float(sv.get("thirst",  100.0))

	var ads_overlay: CanvasLayer = $AdsOverlay
	ads_overlay.setup(_player)
	_player.entered_ads.connect(ads_overlay.show_ads)
	_player.exited_ads.connect(ads_overlay.hide_ads)
	_player.player_died.connect(_on_player_died)
	$HUD.ads_pressed.connect(_on_ads_pressed)
	$HUD.ads_released.connect(_player.on_ads_released)

	var screen_fx := ScreenEffects.new()
	add_child(screen_fx)

	_pause_menu = PauseMenu.new()
	_pause_menu.setup(_player, inventory_sys, screen_fx)
	_pause_menu.save_slot = slot
	_pause_menu.playtime  = _playtime
	add_child(_pause_menu)
	$HUD.pause_requested.connect(_pause_menu.open)
	_pause_menu.edit_layout_requested.connect($HUD.begin_layout_edit)

	_game_active = true


func _process(delta: float) -> void:
	if _game_active and not get_tree().paused:
		_playtime += delta
		if _pause_menu != null:
			_pause_menu.playtime = _playtime
		GameState.playtime = _playtime


func _on_ads_pressed() -> void:
	var weapon_sys: WeaponSystem = _player.get_node("WeaponSystem")
	var sight: SightData = weapon_sys.get_active_weapon().get_sight() \
		if weapon_sys.get_active_weapon() != null else SightData.iron_sights()
	_player.on_ads_pressed(sight)

func _on_player_died() -> void:
	_player.health = _player.max_health
	_player.health_changed.emit(_player.health)
	_apply_starter_loadout()
	_player.get_node("WeaponSystem").equip(0, "m1911")

func _apply_starter_loadout() -> void:
	var inv := _player.inventory
	inv.reset_to_empty()
	inv.set_backpack_layout("{(2,3)}")
	var db: Node = get_node_or_null("/root/ItemDB")
	if db == null:
		return
	var hs_def: Dictionary = db.get_item("hipsack")
	if not hs_def.is_empty():
		inv.equip("chest_rig", Item.from_dict("hipsack", hs_def))
	var ammo_def: Dictionary = db.get_item("ammo_45acp_fmj")
	if not ammo_def.is_empty():
		var ammo := Item.from_dict("ammo_45acp_fmj", ammo_def)
		ammo.quantity = 60
		inv.auto_add_to_backpack(ammo)
