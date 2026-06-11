extends Object

# All fixtures are built inline — no autoload dependency.

func _make_m1911() -> WeaponData:
	var def := {
		"type": "pistol", "display_name": "M1911", "damage": 38,
		"armor_penetration": 12, "rpm": 180, "muzzle_velocity": 1500.0,
		"fire_modes": ["semi"], "spread": 1.5, "muzzle_rise": 9.0,
		"muzzle_rise_recovery": 6.0, "lateral_recoil": 3.5,
		"ergonomics": 0.65, "ads_speed": 0.2, "reload_time": 1.6,
		"magazine_size": 8, "weight": 1.1, "sound_level": 0.75,
		"attachment_slots": {
			"muzzle":      { "accepts_tags": ["pistol_muzzle"],      "accepts_ids": [] },
			"optic":       { "accepts_tags": ["universal_optic"],    "accepts_ids": [] },
			"underbarrel": { "accepts_tags": ["pistol_underbarrel"], "accepts_ids": [] },
			"magazine":    { "accepts_tags": ["m1911_magazine"],     "accepts_ids": [] },
		},
	}
	return WeaponData.from_dict("m1911", def)

func _make_suppressor() -> AttachmentData:
	return AttachmentData.from_dict("suppressor_45acp", {
		"attachment_slot": "muzzle",
		"display_name": ".45 ACP Suppressor",
		"tags": ["pistol_muzzle"],
		"compatible_types": ["pistol"],
		"compatible_ids": [],
		"grid_size": [1, 3],
		"weight": 0.35,
		"stat_mods": { "sound_level": -0.55, "spread": 0.3, "weight": 0.35 },
	})

func _make_smg_compensator() -> AttachmentData:
	return AttachmentData.from_dict("compensator_9mm", {
		"attachment_slot": "muzzle",
		"display_name": "9mm Compensator",
		"tags": ["smg_muzzle"],
		"compatible_types": ["smg"],
		"compatible_ids": [],
		"grid_size": [1, 1],
		"weight": 0.07,
		"stat_mods": { "muzzle_rise": -2.5, "lateral_recoil": -0.5, "spread": -0.3 },
	})

func _make_red_dot() -> AttachmentData:
	return AttachmentData.from_dict("micro_red_dot", {
		"attachment_slot": "optic",
		"display_name": "Micro Red Dot",
		"tags": ["universal_optic"],
		"compatible_types": [],
		"compatible_ids": [],
		"grid_size": [1, 1],
		"weight": 0.08,
		"stat_mods": { "ergonomics": 0.05, "weight": 0.08 },
		"sight_override": {
			"display_name": "Micro Red Dot",
			"reticle_type": "dot",
			"ergo_mult": 0.92,
			"scope_mult": 1.0,
			"fov_radius": 0.28,
		},
	})

func _make_extended_mag() -> AttachmentData:
	return AttachmentData.from_dict("extended_mag_45acp_13rd", {
		"attachment_slot": "magazine",
		"display_name": ".45 ACP Extended Mag (13rd)",
		"tags": ["m1911_magazine"],
		"compatible_types": [],
		"compatible_ids": ["m1911"],
		"grid_size": [1, 2],
		"weight": 0.22,
		"stat_mods": { "magazine_size": 5, "reload_time": 0.15, "weight": 0.22 },
	})

func _make_pistol_laser() -> AttachmentData:
	return AttachmentData.from_dict("pistol_laser", {
		"attachment_slot": "underbarrel",
		"display_name": "Pistol Laser",
		"tags": ["pistol_underbarrel"],
		"compatible_types": ["pistol"],
		"compatible_ids": [],
		"grid_size": [1, 1],
		"weight": 0.04,
		"stat_mods": { "spread": -0.4, "ergonomics": 0.04, "weight": 0.04 },
	})

# ---- Tests ----

func test_attachment_from_dict_loads_fields() -> void:
	var att := _make_suppressor()
	assert(att != null, "AttachmentData.from_dict returned null")
	assert(att.item_id == "suppressor_45acp", "item_id mismatch")
	assert(att.attachment_slot == "muzzle", "attachment_slot mismatch")
	assert(att.tags.has("pistol_muzzle"), "tag not loaded")
	assert(att.compatible_types.has("pistol"), "compatible_types not loaded")
	assert(att.stat_mods["sound_level"] == -0.55, "sound_level mod mismatch")
	assert(att.grid_size == Vector2i(1, 3), "grid_size mismatch")

func test_weapon_has_declared_slots() -> void:
	var w := _make_m1911()
	assert(w.has_slot("muzzle"), "should have muzzle slot")
	assert(w.has_slot("optic"), "should have optic slot")
	assert(w.has_slot("underbarrel"), "should have underbarrel slot")
	assert(w.has_slot("magazine"), "should have magazine slot")
	assert(not w.has_slot("stock"), "should not have stock slot")

func test_can_attach_matching_tag() -> void:
	var w := _make_m1911()
	var att := _make_suppressor()
	assert(w.can_attach("muzzle", att), "pistol muzzle attachment should be accepted")

func test_cannot_attach_wrong_weapon_type() -> void:
	var w := _make_m1911()
	var att := _make_smg_compensator()
	assert(not w.can_attach("muzzle", att), "smg muzzle should be rejected on pistol")

func test_cannot_attach_to_wrong_slot() -> void:
	var w := _make_m1911()
	var att := _make_suppressor()
	assert(not w.can_attach("optic", att), "muzzle attachment should not fit optic slot")
	assert(not w.can_attach("underbarrel", att), "muzzle attachment should not fit underbarrel slot")

func test_attach_returns_true_on_success() -> void:
	var w := _make_m1911()
	assert(w.attach("muzzle", _make_suppressor()), "attach should return true")

func test_attach_returns_false_on_incompatible() -> void:
	var w := _make_m1911()
	assert(not w.attach("muzzle", _make_smg_compensator()), "incompatible attach should return false")

func test_get_attachment_returns_fitted() -> void:
	var w := _make_m1911()
	var att := _make_suppressor()
	w.attach("muzzle", att)
	assert(w.get_attachment("muzzle") == att, "get_attachment should return fitted attachment")

func test_get_attachment_returns_null_when_empty() -> void:
	var w := _make_m1911()
	assert(w.get_attachment("muzzle") == null, "empty slot should return null")

func test_detach_returns_attachment() -> void:
	var w := _make_m1911()
	var att := _make_suppressor()
	w.attach("muzzle", att)
	var removed := w.detach("muzzle")
	assert(removed == att, "detach should return the attachment")

func test_detach_empties_slot() -> void:
	var w := _make_m1911()
	w.attach("muzzle", _make_suppressor())
	w.detach("muzzle")
	assert(w.get_attachment("muzzle") == null, "slot should be empty after detach")

func test_detach_from_empty_slot_returns_null() -> void:
	var w := _make_m1911()
	assert(w.detach("muzzle") == null, "detach from empty slot should return null")

func test_suppressor_reduces_sound_level() -> void:
	var w := _make_m1911()
	var base_sound := w.get_effective_sound_level()
	w.attach("muzzle", _make_suppressor())
	assert(w.get_effective_sound_level() < base_sound, "suppressor should reduce sound_level")

func test_suppressor_increases_spread() -> void:
	var w := _make_m1911()
	var base_spread := w.get_effective_spread()
	w.attach("muzzle", _make_suppressor())
	assert(w.get_effective_spread() > base_spread, "suppressor should increase spread")

func test_suppressor_increases_weight() -> void:
	var w := _make_m1911()
	var base_weight := w.get_effective_weight()
	w.attach("muzzle", _make_suppressor())
	assert(w.get_effective_weight() > base_weight, "suppressor should increase weight")

func test_laser_reduces_spread() -> void:
	var w := _make_m1911()
	var base_spread := w.get_effective_spread()
	w.attach("underbarrel", _make_pistol_laser())
	assert(w.get_effective_spread() < base_spread, "laser should reduce spread")

func test_extended_mag_increases_magazine_size() -> void:
	var w := _make_m1911()
	assert(w.get_effective_magazine_size() == 8, "base mag should be 8")
	w.attach("magazine", _make_extended_mag())
	assert(w.get_effective_magazine_size() == 13, "extended mag should give 13 rounds")

func test_extended_mag_increases_reload_time() -> void:
	var w := _make_m1911()
	var base_reload := w.get_effective_reload_time()
	w.attach("magazine", _make_extended_mag())
	assert(w.get_effective_reload_time() > base_reload, "extended mag should increase reload time")

func test_multiple_attachments_stack() -> void:
	var w := _make_m1911()
	w.attach("muzzle", _make_suppressor())
	w.attach("underbarrel", _make_pistol_laser())
	# Suppressor adds +0.3 spread, laser adds -0.4; net -0.1 vs base 1.5 → 1.4
	var expected := 1.5 + 0.3 + (-0.4)
	assert(absf(w.get_effective_spread() - expected) < 0.001, "stacked mods should sum")

func test_detach_restores_base_stat() -> void:
	var w := _make_m1911()
	var base_sound := w.sound_level
	w.attach("muzzle", _make_suppressor())
	w.detach("muzzle")
	assert(absf(w.get_effective_sound_level() - base_sound) < 0.001, "detach should restore base stat")

func test_optic_overrides_sight() -> void:
	var w := _make_m1911()
	assert(w.get_effective_sight().display_name == "Iron Sights", "default should be iron sights")
	w.attach("optic", _make_red_dot())
	assert(w.get_effective_sight().display_name == "Micro Red Dot", "optic should override sight")

func test_optic_detach_restores_iron_sights() -> void:
	var w := _make_m1911()
	w.attach("optic", _make_red_dot())
	w.detach("optic")
	assert(w.get_effective_sight().display_name == "Iron Sights", "detach optic should restore iron sights")

func test_optic_fov_radius_change() -> void:
	var w := _make_m1911()
	var base_fov := w.get_effective_sight().fov_radius
	w.attach("optic", _make_red_dot())
	assert(w.get_effective_sight().fov_radius < base_fov, "red dot should tighten ADS cone")

func test_id_based_compatibility() -> void:
	# extended_mag is compatible_ids: ["m1911"], should be rejected on a non-m1911
	var def := {
		"type": "pistol", "display_name": "Other Gun", "damage": 30,
		"rpm": 200, "magazine_size": 10, "weight": 1.0,
		"attachment_slots": {
			"magazine": { "accepts_tags": ["m1911_magazine"], "accepts_ids": [] },
		},
	}
	var other := WeaponData.from_dict("other_pistol", def)
	var ext_mag := _make_extended_mag()
	assert(not other.can_attach("magazine", ext_mag), "id-locked mag should not fit other weapon")

func test_item_attachments_persist_to_dict() -> void:
	var item := Item.new()
	item.item_id = "m1911"
	item.type = "pistol"
	item.attachments["muzzle"] = "suppressor_45acp"
	item.attachments["optic"] = "micro_red_dot"
	var d := item.to_dict()
	assert(d.has("attachments"), "to_dict should include attachments")
	assert((d["attachments"] as Dictionary)["muzzle"] == "suppressor_45acp", "muzzle attachment should round-trip")

func test_item_attachments_restore_from_save() -> void:
	var d := {
		"id": "m1911", "display_name": "M1911", "type": "pistol",
		"grid_size": [1, 2], "weight": 1.1, "max_stack": 1, "quantity": 1,
		"attachments": { "muzzle": "suppressor_45acp", "optic": "micro_red_dot" },
	}
	var item := Item.from_save(d)
	assert(item.attachments["muzzle"] == "suppressor_45acp", "muzzle should restore from save")
	assert(item.attachments["optic"] == "micro_red_dot", "optic should restore from save")

func test_item_no_attachments_omitted_from_dict() -> void:
	var item := Item.new()
	item.item_id = "ammo_45acp_fmj"
	item.type = "ammo"
	var d := item.to_dict()
	assert(not d.has("attachments"), "non-weapon items should not have attachments key")

func test_get_all_attachments_returns_copy() -> void:
	var w := _make_m1911()
	var att := _make_suppressor()
	w.attach("muzzle", att)
	var all := w.get_all_attachments()
	assert(all.size() == 1, "should have 1 attachment")
	assert(all["muzzle"] == att, "should contain the suppressor")
	# Mutating the copy should not affect internal state
	all.erase("muzzle")
	assert(w.get_attachment("muzzle") != null, "internal state should not be mutated")

func test_effective_damage_with_mod() -> void:
	var att := AttachmentData.from_dict("barrel_ext", {
		"attachment_slot": "barrel",
		"tags": [],
		"compatible_types": [],
		"compatible_ids": [],
		"grid_size": [1, 1],
		"weight": 0.1,
		"stat_mods": { "damage": 3.0 },
	})
	# Manually force it into a slot that accepts it by accepting_ids
	var def := {
		"type": "pistol", "display_name": "M1911", "damage": 38,
		"rpm": 180, "magazine_size": 8, "weight": 1.1,
		"attachment_slots": {
			"barrel": { "accepts_tags": [], "accepts_ids": ["barrel_ext"] },
		},
	}
	var w := WeaponData.from_dict("m1911", def)
	w.attach("barrel", att)
	assert(w.get_effective_damage() == 41.0, "damage mod should add to base")
