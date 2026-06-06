extends Object

# Minimal stand-in for a character node used in bullet resolution tests.
class MockCharacter:
	extends Node
	var last_damage: int = 0
	var last_is_headshot: bool = false
	var call_count: int = 0

	func take_damage(amount: int, is_headshot: bool = false) -> void:
		last_damage = amount
		last_is_headshot = is_headshot
		call_count += 1


func test_hurtbox_default_type_is_body() -> void:
	var hb := HurtBox.new()
	assert(hb.hit_type == HurtBox.HitType.BODY, "default type is BODY")
	hb.free()


func test_hurtbox_head_type() -> void:
	var hb := HurtBox.new()
	hb.hit_type = HurtBox.HitType.HEAD
	assert(hb.hit_type == HurtBox.HitType.HEAD)
	hb.free()


func test_bullet_default_headshot_multiplier() -> void:
	var b := Bullet.new()
	assert(b.headshot_multiplier == 3.0, "default multiplier is 3.0")
	b.free()


func test_resolve_body_hit_applies_normal_damage() -> void:
	var b := Bullet.new()
	b.damage = 30
	var char := MockCharacter.new()
	b._body_target = char
	b._resolve_hit()
	assert(char.last_damage == 30, "body hit deals base damage")
	assert(char.last_is_headshot == false, "body hit is not flagged as headshot")
	assert(char.call_count == 1, "take_damage called exactly once")
	b.free()
	char.free()


func test_resolve_head_hit_applies_multiplied_damage() -> void:
	var b := Bullet.new()
	b.damage = 30
	b.headshot_multiplier = 3.0
	var char := MockCharacter.new()
	b._head_target = char
	b._resolve_hit()
	assert(char.last_damage == 90, "headshot: 30 × 3 = 90")
	assert(char.last_is_headshot == true, "headshot flag is true")
	b.free()
	char.free()


func test_head_takes_priority_over_body() -> void:
	var b := Bullet.new()
	b.damage = 20
	b.headshot_multiplier = 3.0
	var head_char := MockCharacter.new()
	var body_char := MockCharacter.new()
	b._head_target = head_char
	b._body_target = body_char
	b._resolve_hit()
	assert(head_char.last_damage == 60, "head char takes headshot damage")
	assert(body_char.call_count == 0, "body char takes no damage when head wins")
	b.free()
	head_char.free()
	body_char.free()


func test_resolve_clears_targets() -> void:
	var b := Bullet.new()
	b.damage = 10
	var char := MockCharacter.new()
	b._body_target = char
	b._resolve_hit()
	assert(b._head_target == null, "head target cleared after resolve")
	assert(b._body_target == null, "body target cleared after resolve")
	b.free()
	char.free()


func test_headshot_multiplier_custom_value() -> void:
	var b := Bullet.new()
	b.damage = 25
	b.headshot_multiplier = 4.0
	var char := MockCharacter.new()
	b._head_target = char
	b._resolve_hit()
	assert(char.last_damage == 100, "25 × 4 = 100")
	b.free()
	char.free()


func test_player_headshot_received_signal() -> void:
	var p := Player.new()
	p.max_health = 200
	p.health = 200
	var signal_fired := false
	p.headshot_received.connect(func(): signal_fired = true)
	p.take_damage(10, true)
	assert(signal_fired, "headshot_received emitted on headshot")
	assert(p.health == 190, "health reduced correctly")
	p.free()


func test_player_normal_damage_no_headshot_signal() -> void:
	var p := Player.new()
	p.max_health = 100
	p.health = 100
	var signal_fired := false
	p.headshot_received.connect(func(): signal_fired = true)
	p.take_damage(20, false)
	assert(not signal_fired, "headshot_received NOT emitted for body shot")
	p.free()


func test_weapon_data_headshot_multiplier_default() -> void:
	var w := WeaponData.new()
	assert(w.headshot_multiplier == 3.0, "WeaponData default multiplier is 3.0")


func test_weapon_data_from_dict_loads_multiplier() -> void:
	var def := {"damage": 30, "rpm": 600, "headshot_multiplier": 4.5}
	var w := WeaponData.from_dict("test_gun", def)
	assert(w.headshot_multiplier == 4.5, "from_dict reads headshot_multiplier")
