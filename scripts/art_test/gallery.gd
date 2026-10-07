extends Node2D
## Art review sheet: every rig at several rotations (checks that shading follows the fixed top-left key light),
## props, decals, fx. Render: gd --path . res://scenes/art_test/gallery.tscn --write-movie ...

const Lib = preload("res://scripts/art_test/art_lib.gd")
var rigs: Array = []
var shadow_layer: Node2D


func _ready() -> void:
	Lib.init_lib()
	scale = Vector2.ONE * (get_viewport_rect().size.y / 720.0)
	var g := Sprite2D.new()
	g.texture = Lib.tex("ground_tile")
	g.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	g.centered = false
	g.region_enabled = true
	g.region_rect = Rect2(0, 0, 2560, 1440)
	g.scale = Vector2(0.5, 0.5)
	g.z_index = -100
	add_child(g)
	shadow_layer = Node2D.new()
	shadow_layer.z_index = -60
	add_child(shadow_layer)
	var Bug := preload("res://scripts/art_test/bug_rig.gd")
	var Pl := preload("res://scripts/art_test/player_rig.gd")
	for i in 4:
		var p := Pl.new()
		add_child(p)
		p.position = Vector2(80 + i * 95, 70)
		p.setup(shadow_layer)
		p.facing = i * PI / 2.0 + 0.3
		p.update(0.0, Vector2.ZERO)
		rigs.append(p)
	for i in 4:
		var b := Bug.new()
		add_child(b)
		b.position = Vector2(80 + i * 95, 170)
		b.setup("scav", shadow_layer, Vector2(4, 5), 2.0)
		b.facing = i * PI / 2.0 + 0.3
		b.update(0.0, Vector2.ZERO)
		b.reset_feet()
		b.update(0.0, Vector2.ZERO)
		rigs.append(b)
	for i in 3:
		var b := Bug.new()
		add_child(b)
		b.position = Vector2(200 + i * 330, 420)
		b.setup("chg", shadow_layer, Vector2(10, 12), 5.0)
		b.facing = [0.0, PI * 0.5 + 0.3, PI][i]
		b.set_damage(i)
		b.mand_open = 0.2 + 0.2 * i
		b.update(0.0, Vector2.ZERO)
		b.reset_feet()
		b.update(0.0, Vector2.ZERO)
		rigs.append(b)
	# props
	var x := 520.0
	for n in ["rock0", "rock1", "rock2", "rock3", "wall0", "wall1", "wall2", "debris1", "debris5", "pickup_crate", "pickup_stim", "grenade"]:
		var p := Lib.part(n)
		add_child(p)
		p.position = Vector2(x if x < 1250 else x - 700, 70 if x < 1250 else 170)
		p.rotation = 0.0
		x += 110
		var h := Lib.shadow_for(p, 3.0)
		shadow_layer.add_child(h)
		rigs.append({"p": p, "h": h})
	var dx := 560.0
	for n in ["goo0", "goo1", "goo2", "goo3", "goo_big", "scorch", "pock", "dust", "smoke0", "fireball0", "fireball1", "chip_plate0"]:
		var s := Lib.flat(n)
		s.position = Vector2(dx if dx < 1250 else dx - 700, 280 if dx < 1250 else 340) 
		add_child(s)
		dx += 110
	set_process(true)


func _process(_dt: float) -> void:
	for r in rigs:
		if r is Dictionary:
			var xf: Transform2D = r["p"].global_transform
			xf.origin += Vector2(5, 6)
			r["h"].global_transform = xf
		else:
			r.sync_shadows()
