extends RefCounted
## Art-test asset helpers: texture/material cache and sprite-part factory.
## Parts are Node2D pivots with a Sprite2D child (2 texels per design unit, offset so the pivot is the node origin).

const DIR := "res://art/test/"
const LIGHT := Vector2(-0.7071, -0.7071)   # fixed key light: toward top-left

static var layout: Dictionary = {}
static var _tex: Dictionary = {}
static var _lit: Dictionary = {}
static var _lit_shader: Shader
static var _flash_mat: ShaderMaterial
static var _shadow_mats: Dictionary = {}
static var _add_mat: CanvasItemMaterial


static func init_lib() -> void:
	if not layout.is_empty():
		return
	var f := FileAccess.open(DIR + "layout.json", FileAccess.READ)
	layout = JSON.parse_string(f.get_as_text())
	_lit_shader = load(DIR + "lit.gdshader")
	_flash_mat = ShaderMaterial.new()
	_flash_mat.shader = load(DIR + "flash.gdshader")
	_add_mat = CanvasItemMaterial.new()
	_add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD


static func tex(name: String) -> Texture2D:
	if not _tex.has(name):
		_tex[name] = load(DIR + name + ".png")
	return _tex[name]


static func lit_mat(name: String) -> ShaderMaterial:
	if not _lit.has(name):
		var m := ShaderMaterial.new()
		m.shader = _lit_shader
		m.set_shader_parameter("hmap", tex(name + "_h"))
		m.set_shader_parameter("light_dir", LIGHT)
		_lit[name] = m
	return _lit[name]


static func flash_mat() -> ShaderMaterial:
	return _flash_mat


static func add_mat() -> CanvasItemMaterial:
	return _add_mat


static func shadow_mat(radius: float) -> ShaderMaterial:
	var key := str(radius)
	if not _shadow_mats.has(key):
		var m := ShaderMaterial.new()
		m.shader = load(DIR + "shadow.gdshader")
		m.set_shader_parameter("radius", radius)
		_shadow_mats[key] = m
	return _shadow_mats[key]


## A lit rig/prop part: Node2D pivot + Sprite2D. meta "spr" = the sprite, "mat" = its normal material.
static func part(name: String) -> Node2D:
	var n := Node2D.new()
	n.name = name
	var s := Sprite2D.new()
	s.centered = false
	s.texture = tex(name)
	var L: Dictionary = layout["parts"][name]
	s.scale = Vector2(0.5, 0.5)
	s.position = Vector2(L["ox"], L["oy"])
	s.material = lit_mat(name)
	n.add_child(s)
	n.set_meta("spr", s)
	n.set_meta("part", name)
	_add_glows(n, name)
	return n


static func _add_glows(n: Node2D, name: String) -> void:
	if not layout["glows"].has(name):
		return
	var arr: Array = []
	for g in layout["glows"][name]:
		var gs := Sprite2D.new()
		gs.texture = tex("glow")
		gs.material = _add_mat
		var r: float = g[2]
		gs.scale = Vector2.ONE * (r * 2.0 / 32.0)
		gs.position = Vector2(g[0], g[1])
		var c: Array = g[3]
		gs.modulate = Color(c[0] / 255.0, c[1] / 255.0, c[2] / 255.0, 0.5)
		n.add_child(gs)
		arr.append(gs)
	n.set_meta("glows", arr)


## Shadow twin pivot for a part (same texture, soft black silhouette). Synced to the part by the director.
static func shadow_for(src: Node2D, radius: float = 2.4) -> Node2D:
	var spr: Sprite2D = src.get_meta("spr")
	var s := Sprite2D.new()
	s.centered = false
	s.texture = spr.texture
	s.scale = Vector2(0.5, 0.5)
	s.position = spr.position
	s.material = shadow_mat(radius)
	var holder := Node2D.new()
	holder.add_child(s)
	return holder


## Plain flat sprite (decals, fx): centred, 2 texels per unit.
static func flat(name: String, centered: bool = true) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = tex(name)
	s.scale = Vector2(0.5, 0.5)
	s.centered = centered
	return s
