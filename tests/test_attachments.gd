extends Object

# All fixtures built inline — no autoload dependency.

func _make_m1911() -> WeaponData:
	return WeaponData.from_dict("m1911", {
		"type": "pistol", "display_name": "M1911", "damage": 38,
		"armor_penetration": 12, "rpm": 180, "muzzle_velocity": 1500.0,
		"fire_modes": ["semi"], "spread": 1.5, "muzzle_rise": 9.0,
		"muzzle_rise_recovery": 6.0, "lateral_recoil": 3.5,
		"ergonomics": 0.65, "ads_speed": 0.2, "reload_time": 1.6,
		"magazine_size": 8, "weight": 1.1, "sound_level": 0.75,
		"slots": {
			"barrel":       { "display_name": "Barrel",        "accepts_tag": "m1911_barrel",   "vital": true,  "default_part": "m1911_barrel_standard", "ui_pos": [0.5, 0.18] },
			"slide":        { "display_name": "Slide",         "accepts_tag": "m1911_slide",    "vital": true,  "default_part": "m1911_slide_standard",  "ui_pos": [0.5, 0.32] },
			"trigger_group":{ "display_name": "Trigger Group", "accepts_tag": "m1911_trigger",  "vital": true,  "default_part": "m1911_trigger_standard","ui_pos": [0.7, 0.58] },
			"hammer":       { "display_name": "Hammer",        "accepts_tag": "m1911_hammer",   "vital": false, "default_part": "m1911_hammer_standard", "ui_pos": [0.5, 0.48] },
			"grip":         { "display_name": "Grip Panels",   "accepts_tag": "m1911_grip",     "vital": false, "default_part": "m1911_grip_standard",  "ui_pos": [0.5, 0.82] },
			"muzzle":       { "display_name": "Muzzle Device", "accepts_tag": "45acp_muzzle",   "vital": false, "default_part": "",                      "ui_pos": [0.5, 0.04] },
			"magazine":     { "display_name": "Magazine",      "accepts_tag": "m1911_magazine", "vital": false, "default_part": "m1911_mag_standard",   "ui_pos": [0.38, 0.72] },
			"optic":        { "display_name": "Optic",         "accepts_tag": "universal_optic","vital": false, "default_part": "",                      "ui_pos": [0.5, 0.22] },
			"underbarrel":  { "display_name": "Underbarrel",   "accepts_tag": "pistol_underbarrel","vital": false,"default_part": "",                   "ui_pos": [0.65, 0.38] },
		},
	})

func _make_suppressor() -> AttachmentData:
	return AttachmentData.from_dict("suppressor_45acp", {
		"display_name": ".45 ACP Suppressor",
		"tags": ["45acp_muzzle"],
		"grid_size": [1, 3],
		"weight": 0.35,
		"stat_mods": { "sound_level": -0.55, "spread": 0.3, "weight": 0.35 },
	})

func _make_9mm_compensator() -> AttachmentData:
	return AttachmentData.from_dict("compensator_9mm", {
		"display_name": "9mm Compensator",
		"tags": ["9mm_muzzle"],
		"grid_size": [1, 1],
		"weight": 0.07,
		"stat_mods": { "muzzle_rise": -2.5, "lateral_recoil": -0.5, "spread": -0.3 },
	})

func _make_red_dot() -> AttachmentData:
	return AttachmentData.from_dict("micro_red_dot", {
		"display_name": "Micro Red Dot",
		"tags": ["universal_optic"],
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
		"display_name": ".45 ACP Extended Mag (13rd)",
		"tags": ["m1911_magazine"],
		"grid_size": [1, 2],
		"weight": 0.22,
		"stat_mods": { "magazine_size": 5, "reload_time": 0.15, "weight": 0.22 },
	})

func _make_pistol_laser() -> AttachmentData:
	return AttachmentData.from_dict("pistol_laser", {
		"display_name": "Pistol Laser",
		"tags": ["pistol_underbarrel"],
		"grid_size": [1, 1],
		"weight": 0.04,
		"stat_mods": { "spread": -0.4, "ergonomics": 0.04, "weight": 0.04 },
	})

func _make_barrel_standard() -> AttachmentData:
	return AttachmentData.from_dict("m1911_barrel_standard", {
		"display_name": "M1911 Standard Barrel",
		"tags": ["m1911_barrel"],
		"grid_size": [1, 2],
		"weight": 0.18,
		"stat_mods": {},
	})

func _make_match_slide() -> AttachmentData:
	return AttachmentData.from_dict("m1911_slide_match", {
		"display_name": "M1911 Match-Grade Slide",
		"tags": ["m1911_slide"],
		"grid_size": [1, 2],
		"weight": 0.24,
		"stat_mods": { "spread": -0.30, "weight": 0.02 },
	})

# ---- Tests ----

func test_attachment_from_dict_loads_fields() -> void:
	var att := _make_suppressor()
	assert(att != null, "from_dict returned null")
	assert(att.item_id == "suppressor_45acp", "item_id mismatch")
	assert(att.tags.has("45acp_muzzle"), "tag not loaded")
	assert(att.stat_mods["sound_level"] == -0.55, "sound_level mod mismatch")
	assert(att.grid_size == Vector2i(1, 3), "grid_size mismatch")

func test_weapon_has_declared_slots() -> void:
	var w := _make_m1911()
	assert(w.has_slot("barrel"), "should have barrel slot")
	assert(w.has_slot("slide"), "should have slide slot")
	assert(w.has_slot("trigger_group"), "should have trigger_group slot")
	assert(w.has_slot("hammer"), "should have hammer slot")
	assert(w.has_slot("grip"), "should have grip slot")
	assert(w.has_slot("muzzle"), "should have muzzle slot")
	assert(w.has_slot("magazine"), "should have magazine slot")
	assert(w.has_slot("optic"), "should have optic slot")
	assert(w.has_slot("underbarrel"), "should have underbarrel slot")
	assert(not w.has_slot("stock"), "should not have stock slot")

func test_vital_slots_identified() -> void:
	var w := _make_m1911()
	assert(w.is_vital("barrel"), "barrel should be vital")
	assert(w.is_vital("slide"), "slide should be vital")
	assert(w.is_vital("trigger_group"), "trigger_group should be vital")
	assert(not w.is_vital("hammer"), "hammer should not be vital")
	assert(not w.is_vital("grip"), "grip should not be vital")
	assert(not w.is_vital("muzzle"), "muzzle should not be vital")

func test_is_functional_with_no_parts() -> void:
	var w := _make_m1911()
	assert(not w.is_functional(), "bare weapon should be non-functional")

func test_is_functional_after_vital_parts_installed() -> void:
	var w := _make_m1911()
	w.attach("barrel", _make_barrel_standard())
	w.attach("slide", _make_match_slide())
	var trigger := AttachmentData.from_dict("m1911_trigger_standard", {
		"display_name": "Standard Trigger", "tags": ["m1911_trigger"],
		"grid_size": [1,1], "weight": 0.04, "stat_mods": {},
	})
	w.attach("trigger_group", trigger)
	assert(w.is_functional(), "gun with all vital parts should be functional")

func test_is_functional_missing_one_vital() -> void:
	var w := _make_m1911()
	w.attach("barrel", _make_barrel_standard())
	# slide still missing
	var trigger := AttachmentData.from_dict("m1911_trigger_standard", {
		"display_name": "Standard Trigger", "tags": ["m1911_trigger"],
		"grid_size": [1,1], "weight": 0.04, "stat_mods": {},
	})
	w.attach("trigger_group", trigger)
	assert(not w.is_functional(), "missing vital slide should disable gun")

func test_can_attach_matching_tag() -> void:
	var w := _make_m1911()
	assert(w.can_attach("muzzle", _make_suppressor()), "45acp suppressor should fit muzzle slot")
	assert(w.can_attach("optic", _make_red_dot()), "red dot should fit optic slot")
	assert(w.can_attach("magazine", _make_extended_mag()), "m1911 extended mag should fit magazine slot")
	assert(w.can_attach("underbarrel", _make_pistol_laser()), "pistol laser should fit underbarrel")

func test_cannot_attach_wrong_tag() -> void:
	var w := _make_m1911()
	assert(not w.can_attach("muzzle", _make_9mm_compensator()), "9mm comp should not fit 45acp muzzle slot")

func test_cannot_attach_to_wrong_slot() -> void:
	var w := _make_m1911()
	var supp := _make_suppressor()
	assert(not w.can_attach("optic", supp), "muzzle device should not fit optic slot")
	assert(not w.can_attach("barrel", supp), "muzzle device should not fit barrel slot")

func test_barrel_part_fits_barrel_slot() -> void:
	var w := _make_m1911()
	assert(w.can_attach("barrel", _make_barrel_standard()), "barrel part should fit barrel slot")

func test_slide_part_does_not_fit_barrel_slot() -> void:
	var w := _make_m1911()
	assert(not w.can_attach("barrel", _make_match_slide()), "slide should not fit barrel slot")

func test_attach_returns_true_on_success() -> void:
	var w := _make_m1911()
	assert(w.attach("muzzle", _make_suppressor()), "attach should succeed")
	assert(w.attach("barrel", _make_barrel_standard()), "barrel attach should succeed")

func test_attach_returns_false_on_incompatible() -> void:
	var w := _make_m1911()
	assert(not w.attach("muzzle", _make_9mm_compensator()), "incompatible attach should fail")

func test_get_attachment_returns_fitted() -> void:
	var w := _make_m1911()
	var att := _make_suppressor()
	w.attach("muzzle", att)
	assert(w.get_attachment("muzzle") == att, "should return fitted attachment")

func test_detach_returns_and_clears() -> void:
	var w := _make_m1911()
	var att := _make_suppressor()
	w.attach("muzzle", att)
	var removed := w.detach("muzzle")
	assert(removed == att, "detach should return the attachment")
	assert(w.get_attachment("muzzle") == null, "slot should be empty after detach")

func test_detach_from_empty_returns_null() -> void:
	var w := _make_m1911()
	assert(w.detach("muzzle") == null, "detach from empty slot should return null")

func test_suppressor_reduces_sound() -> void:
	var w := _make_m1911()
	var base := w.get_effective_sound_level()
	w.attach("muzzle", _make_suppressor())
	assert(w.get_effective_sound_level() < base, "suppressor should reduce sound")

func test_suppressor_increases_spread() -> void:
	var w := _make_m1911()
	var base := w.get_effective_spread()
	w.attach("muzzle", _make_suppressor())
	assert(w.get_effective_spread() > base, "suppressor should increase spread")

func test_laser_reduces_spread() -> void:
	var w := _make_m1911()
	var base := w.get_effective_spread()
	w.attach("underbarrel", _make_pistol_laser())
	assert(w.get_effective_spread() < base, "laser should reduce spread")

func test_extended_mag_increases_magazine_size() -> void:
	var w := _make_m1911()
	assert(w.get_effective_magazine_size() == 8, "base mag should be 8")
	w.attach("magazine", _make_extended_mag())
	assert(w.get_effective_magazine_size() == 13, "extended mag should give 13 rounds")

func test_match_slide_reduces_spread() -> void:
	var w := _make_m1911()
	var base := w.get_effective_spread()
	w.attach("slide", _make_match_slide())
	assert(w.get_effective_spread() < base, "match slide should reduce spread")

func test_multiple_mods_stack() -> void:
	var w := _make_m1911()
	w.attach("muzzle", _make_suppressor())       # spread +0.3
	w.attach("underbarrel", _make_pistol_laser()) # spread -0.4
	var expected := 1.5 + 0.3 + (-0.4)
	assert(absf(w.get_effective_spread() - expected) < 0.001, "stacked mods should sum")

func test_detach_restores_base_stat() -> void:
	var w := _make_m1911()
	var base := w.sound_level
	w.attach("muzzle", _make_suppressor())
	w.detach("muzzle")
	assert(absf(w.get_effective_sound_level() - base) < 0.001, "detach should restore base stat")

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

func test_optic_tightens_fov() -> void:
	var w := _make_m1911()
	var base_fov := w.get_effective_sight().fov_radius
	w.attach("optic", _make_red_dot())
	assert(w.get_effective_sight().fov_radius < base_fov, "red dot should tighten ADS cone")

func test_slot_def_contains_vital_flag() -> void:
	var w := _make_m1911()
	var barrel_def := w.get_slot_def("barrel")
	assert(barrel_def.get("vital", false) == true, "barrel slot def should be vital")
	var muzzle_def := w.get_slot_def("muzzle")
	assert(muzzle_def.get("vital", false) == false, "muzzle slot def should not be vital")

func test_slot_def_contains_ui_pos() -> void:
	var w := _make_m1911()
	var barrel_def := w.get_slot_def("barrel")
	var pos: Vector2 = barrel_def.get("ui_pos", Vector2.ZERO)
	assert(pos != Vector2.ZERO, "barrel slot should have a non-zero ui_pos")

func test_slot_def_contains_accepts_tag() -> void:
	var w := _make_m1911()
	assert(w.get_slot_def("barrel").get("accepts_tag") == "m1911_barrel", "barrel accepts_tag mismatch")
	assert(w.get_slot_def("muzzle").get("accepts_tag") == "45acp_muzzle", "muzzle accepts_tag mismatch")

func test_get_all_attachments_copy() -> void:
	var w := _make_m1911()
	w.attach("muzzle", _make_suppressor())
	var all := w.get_all_attachments()
	all.erase("muzzle")
	assert(w.get_attachment("muzzle") != null, "copy mutation should not affect internal state")

func test_item_attachments_persist_to_dict() -> void:
	var item := Item.new()
	item.item_id = "m1911"
	item.type = "pistol"
	item.attachments["muzzle"] = "suppressor_45acp"
	item.attachments["optic"] = "micro_red_dot"
	var d := item.to_dict()
	assert(d.has("attachments"), "to_dict should include attachments")
	assert((d["attachments"] as Dictionary)["muzzle"] == "suppressor_45acp", "muzzle should round-trip")

func test_item_attachments_restore_from_save() -> void:
	var d := {
		"id": "m1911", "display_name": "M1911", "type": "pistol",
		"grid_size": [1, 2], "weight": 1.1, "max_stack": 1, "quantity": 1,
		"attachments": { "muzzle": "suppressor_45acp", "barrel": "m1911_barrel_threaded" },
	}
	var item := Item.from_save(d)
	assert(item.attachments["muzzle"] == "suppressor_45acp", "muzzle should restore")
	assert(item.attachments["barrel"] == "m1911_barrel_threaded", "barrel should restore")

func test_item_without_attachments_omits_key() -> void:
	var item := Item.new()
	item.item_id = "ammo_45acp_fmj"
	item.type = "ammo"
	assert(not item.to_dict().has("attachments"), "no-attachment item should omit key")
