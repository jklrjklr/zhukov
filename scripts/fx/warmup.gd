class_name Warmup
extends RefCounted
## First-use costs moved to the mission start (hellpod fall): GL compiles a canvas shader variant the
## first time each kind of item is drawn (rect / line / polygon / textured rect / string / MultiMesh /
## premultiplied blend / unshaded), and Sfx loads a slot's files on its first play. Without this the
## first muzzle flash, tracer, explosion, decal or HP bar of a fight stalls a frame mid-combat.
## run() puts one nearly invisible sample of every kind on screen for a few frames.

const SOUNDS := ["bug_alert", "bug_attack", "bug_big_step", "bug_chitter", "bug_death", "bug_hurt", "bile_spit", "bile_splash",
	"charger_charge", "charger_roar", "claw", "debris", "dive", "dry_fire", "eagle_bomb", "eagle_flyby", "explosion", "explosion_big",
	"footstep_run", "hellpod_impact", "hellpod_streak", "hit_armor", "hit_flesh", "hit_metal", "mag_in", "mag_out", "orbital_shot",
	"orbital_whistle", "player_hit", "player_death", "sentry_deploy", "sentry_shot", "smg_shot", "shield_hit", "stim", "strat_error",
	"strat_input", "strat_open", "strat_ready", "throw", "radio_chirp", "reinforce", "breach", "burrow", "objective_progress",
	"objective_complete", "pickup_ammo", "resupply_open", "passage_seal", "nest_hole_destroyed", "ui_click",
	"rifle_shot", "shotgun_shot", "rocket_launch", "plasma_shot", "bolt", "bot_blaster", "reload", "bile_spit", "terminal_beep"]


class Painter extends Node2D:
	var tex: Texture2D

	func _draw() -> void:
		var c := Color(1, 1, 1, 0.012)
		draw_rect(Rect2(0, 0, 2, 2), c)
		draw_line(Vector2(0, 0), Vector2(3, 3), c, 1.0)
		draw_line(Vector2(0, 0), Vector2(3, 3), c, 3.0)
		draw_circle(Vector2(2, 2), 1.5, c)
		draw_arc(Vector2(2, 2), 1.5, 0.0, 3.0, 8, c, 1.0)
		draw_colored_polygon(PackedVector2Array([Vector2(0, 0), Vector2(3, 0), Vector2(0, 3)]), c)
		draw_polyline(PackedVector2Array([Vector2(0, 0), Vector2(3, 0), Vector2(3, 3)]), c, 1.0)
		draw_texture_rect(tex, Rect2(0, 0, 3, 3), false, c)
		draw_texture_rect_region(tex, Rect2(0, 0, 3, 3), Rect2(0, 0, 4, 4), c)
		draw_string(ThemeDB.fallback_font, Vector2(0, 8), "0?!", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, c)


static func run(host: Node) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var layer := CanvasLayer.new()
	layer.layer = 100
	layer.name = "Warmup"
	var tex := Fx.disc_texture()
	var p := Painter.new()
	p.tex = tex
	layer.add_child(p)
	var unshaded := Painter.new()
	unshaded.tex = tex
	var um := CanvasItemMaterial.new()
	um.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	unshaded.material = um
	layer.add_child(unshaded)
	# MultiMesh programs: lit + unshaded shape shaders, the atlas shader.
	var tiny := Transform2D(Vector2(2, 0), Vector2(0, 2), Vector2(4, 4))
	for u in [false, true]:
		var sb := ShapeBatch.new(4, u)
		sb.begin()
		sb.disc(Vector2(4, 4), 1.0, Color(1, 1, 1, 0.012))
		sb.ring(Vector2(4, 4), 1.0, 1.0, Color(1, 1, 1, 0.012))
		sb.end()
		layer.add_child(sb)
	var pbs: Array[ParticleBatch] = []
	for u in [false, true]:
		var pb := ParticleBatch.new(4, u)
		pb.dot(Vector2(4, 4), Vector2(1, 1), 0.5, 1.0, 2.0, Color(1, 1, 1, 0.012), 3.0, true)
		pb.ring(Vector2(4, 4), 1.0, 2.0, 0.5, 1.0, Color(1, 1, 1, 0.012))
		layer.add_child(pb)
		pbs.append(pb)
	var ab := AtlasBatch.new(RigAtlas.texture(), 4)
	ab.frame_begin()
	ab.frame_push(tiny, Color(1, 1, 1, 0.012), Color(0, 0, 0, 0.01))
	ab.frame_end()
	layer.add_child(ab)
	# Premultiplied blend (decal cells) and a plain sprite.
	var spr := Sprite2D.new()
	spr.texture = tex
	var pm := CanvasItemMaterial.new()
	pm.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	spr.material = pm
	spr.modulate = Color(1, 1, 1, 0.012)
	layer.add_child(spr)
	host.add_child.call_deferred(layer)
	# The shared enemy layers and overlay would otherwise be created with the first bug.
	var actors := host.get_node_or_null("Actors")
	if actors != null:
		Rig.attach(actors)
		EnemyOverlay.attach(actors)
	var tree := host.get_tree()
	for i in 6:
		for pb in pbs:
			pb.tick(0.016)
		await tree.process_frame
	if is_instance_valid(layer):
		layer.queue_free()
