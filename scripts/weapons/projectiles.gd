extends Node2D
## Simulates and draws all bullets, ejected casings and impact puffs in one node
## (cheap on web). Bullets are ray-stepped each physics tick, so fast rounds never tunnel.
## Targets implement take_hit(hit: Dictionary): damage (after falloff), base_damage,
## armor_penetration, armor_damage, destruction_level, stagger (after falloff), dir,
## meters, aim_point.
## Aimed (ADS) bullets have a landing point: they stop there (hit the ground) unless
## something is in the way first. aim_point lets targets decide on critical hits.
## Grenades: thrown in an arc to a point (stopped by walls), explode after the fuse.
## Explosion damage falls off with distance and needs line of sight from the blast;
## it hurts the thrower too.

const PX := Firearm.PX_PER_M
const TRACER_LEN := 140.0

var _bullets: Array[Dictionary] = []
var _casings: Array[Dictionary] = []
var _puffs: Array[Dictionary] = []
var _grenades: Array[Dictionary] = []
var _blasts: Array[Dictionary] = []
var _scorches: Array[Dictionary] = []
var _biles: Array[Dictionary] = []
## Automaton laser bolts: slow enough to see and dodge; cover stops them.
var _bolts: Array[Dictionary] = []
var _acid: Array[Dictionary] = []

## Bile Spitter acid: lobbed blob -> pool that burns the player while inside.
const BILE_FLIGHT := 0.9
const BILE_SPLASH_DAMAGE := 18.0
const ACID_RADIUS_M := 1.8
const ACID_DPS := 10.0
const ACID_TIME := 3.5

## Frag grenade.
const GRENADE_FUSE := 2.2
const GRENADE_RADIUS_M := 6.0
const GRENADE_DAMAGE := 320.0
const GRENADE_AP := 3
const GRENADE_ARMOR_DAMAGE := 60.0
const GRENADE_DESTRUCTION := 30
const GRENADE_STAGGER := 160.0
const GRENADE_SOUND := 140.0
const GRENADE_SOUND_FALLOFF := 8.0
## Explosion parameters for explode().
const GRENADE_BLAST := {
	"radius_m": GRENADE_RADIUS_M, "damage": GRENADE_DAMAGE, "ap": GRENADE_AP,
	"armor_damage": GRENADE_ARMOR_DAMAGE, "destruction": GRENADE_DESTRUCTION,
	"stagger": GRENADE_STAGGER, "sound": GRENADE_SOUND, "sound_falloff": GRENADE_SOUND_FALLOFF,
	"self_mult": 0.6,
}


func _ready() -> void:
	add_to_group("projectiles")


func spawn_bullet(pos: Vector2, vel: Vector2, stats: FirearmStats, shooter: CollisionObject2D, land: Variant = null) -> void:
	_bullets.append({
		"pos": pos, "tail": pos, "vel": vel, "dist": 0.0, "stats": stats,
		"exclude": [shooter.get_rid()], "dead": false,
		"land": land, "land_dist": pos.distance_to(land) if land != null else INF,
	})


## Casing flies out to the right of the weapon.
func spawn_casing(pos: Vector2, rot: float) -> void:
	_casings.append({
		"pos": pos, "vel": Vector2(randf_range(110, 170), randf_range(-10, 40)).rotated(rot),
		"rot": randf() * TAU, "spin": randf_range(-25, 25), "t": 0.0,
		"size": Vector2(2.4, 5), "color": Color(0.85, 0.65, 0.25), "life": 3.0,
	})


## Generic dropped object (e.g. empty magazine) that slides to a stop and fades.
func spawn_debris(pos: Vector2, vel: Vector2, rot: float, size: Vector2, color: Color, life: float) -> void:
	_casings.append({
		"pos": pos, "vel": vel, "rot": rot, "spin": randf_range(-4, 4), "t": 0.0,
		"size": size, "color": color, "life": life,
	})


## Throw a grenade from `from` toward `to` (stops short of walls).
func spawn_grenade(from: Vector2, to: Vector2, thrower: CollisionObject2D) -> void:
	var q := PhysicsRayQueryParameters2D.create(from, to, 1)
	q.exclude = [thrower.get_rid()]
	var hit := get_world_2d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		to = (hit.position as Vector2) - (to - from).normalized() * 12.0
	var flight := clampf(from.distance_to(to) / 600.0, 0.35, 0.9)
	_grenades.append({"from": from, "to": to, "pos": from, "t": 0.0, "flight": flight, "spin": randf() * TAU})


func spawn_bolt(from: Vector2, vel: Vector2, damage: float, shooter: CollisionObject2D) -> void:
	_bolts.append({"pos": from, "tail": from, "vel": vel, "damage": damage, "t": 0.0,
		"exclude": [shooter.get_rid()]})


## Dust/smoke puff (e.g. a bot falling apart).
func add_puff(pos: Vector2, scale := 1.0) -> void:
	_puffs.append({"pos": pos, "t": 0.0, "scale": scale})


func _update_bolts(delta: float) -> void:
	var space := get_world_2d().direct_space_state
	for b in _bolts:
		b.t += delta
		var pos: Vector2 = b.pos
		var step: Vector2 = b.vel * delta
		var q := PhysicsRayQueryParameters2D.create(pos, pos + step, 1)
		q.exclude = b.exclude
		var hit := space.intersect_ray(q)
		b.tail = pos
		if hit.is_empty():
			b.pos = pos + step
			continue
		var body := hit.collider as Node
		if body.has_method("take_damage"):
			if body.is_diving() and randf() < 0.6:
				# Diving Helldivers are hard to hit: let it fly past.
				(b.exclude as Array).append((body as CollisionObject2D).get_rid())
				b.pos = pos + step
				continue
			body.take_damage(b.damage, pos - (b.vel as Vector2).normalized() * 40.0)
		_puffs.append({"pos": hit.position, "t": 0.0, "bolt": true})
		b.t = 99.0
	_bolts = _bolts.filter(func(b): return b.t < 3.0)


func spawn_bile(from: Vector2, to: Vector2) -> void:
	_biles.append({"from": from, "to": to, "pos": from, "t": 0.0})


func _update_bile(delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	for b in _biles:
		b.t += delta
		b.pos = (b.from as Vector2).lerp(b.to, clampf(b.t / BILE_FLIGHT, 0.0, 1.0))
		if b.t >= BILE_FLIGHT:
			_acid.append({"pos": b.to, "t": 0.0})
			if player and player.global_position.distance_to(b.to) < ACID_RADIUS_M * PX:
				player.take_damage(BILE_SPLASH_DAMAGE, b.to)
	_biles = _biles.filter(func(b): return b.t < BILE_FLIGHT)
	for a in _acid:
		a.t += delta
		if player and not player.dead and player.global_position.distance_to(a.pos) < ACID_RADIUS_M * PX:
			player.take_damage(ACID_DPS * delta, a.pos, false)
	_acid = _acid.filter(func(a): return a.t < ACID_TIME)


func _physics_process(delta: float) -> void:
	_update_grenades(delta)
	_update_bile(delta)
	_update_bolts(delta)
	var space := get_world_2d().direct_space_state
	for i in range(_bullets.size() - 1, -1, -1):
		var b: Dictionary = _bullets[i]
		if b.dead:
			_bullets.remove_at(i) # removed one tick after hitting so the tracer gets drawn
			continue
		var st: FirearmStats = b.stats
		var pos: Vector2 = b.pos
		var step: Vector2 = b.vel * delta
		var remain: float = minf(st.range_max * PX, b.land_dist) - b.dist
		if step.length() >= remain:
			step = step.limit_length(remain)
			b.dead = true
		var q := PhysicsRayQueryParameters2D.create(pos, pos + step)
		q.exclude = b.exclude
		var hit := space.intersect_ray(q)
		b.tail = pos
		if hit.is_empty():
			b.pos = pos + step
			b.dist += step.length()
			if b.dead and b.land != null:
				_puffs.append({"pos": b.pos, "t": 0.0, "ground": true})
			if b.dead:
				_rocket_blast(st, b.pos)
			continue
		var hit_pos: Vector2 = hit.position
		var meters: float = (b.dist + pos.distance_to(hit_pos)) / PX
		var collider: Object = hit.collider
		if (collider as Node).is_in_group("enemies"):
			Game.add_stat("hits")
		if collider.has_method("take_hit"):
			collider.take_hit({
				"damage": st.damage_at(meters), "base_damage": st.damage,
				"armor_penetration": st.armor_penetration, "armor_damage": st.armor_damage,
				"destruction_level": st.destruction_level,
				"stagger": st.stagger * st.damage_at(meters) / st.damage,
				"dir": (b.vel as Vector2).normalized(), "meters": meters, "aim_point": b.land,
			})
		_puffs.append({"pos": hit_pos, "t": 0.0})
		b.pos = hit_pos
		b.dead = true
		_rocket_blast(st, hit_pos)

	for c in _casings:
		c.t += delta
		var damp := exp(-7.0 * delta)
		c.vel *= damp
		c.spin *= damp
		c.pos += c.vel * delta
		c.rot += c.spin * delta
	_casings = _casings.filter(func(c): return c.t < c.life)
	if _casings.size() > 150:
		_casings = _casings.slice(_casings.size() - 150)

	for p in _puffs:
		p.t += delta
	_puffs = _puffs.filter(func(p): return p.t < 0.25)
	for b in _blasts:
		b.t += delta
	_blasts = _blasts.filter(func(b): return b.t < 0.5)
	for s in _scorches:
		s.t += delta
	_scorches = _scorches.filter(func(s): return s.t < 40.0)
	queue_redraw()


func _rocket_blast(st: FirearmStats, at: Vector2) -> void:
	if st.bullet_type != FirearmStats.BulletType.ROCKET or st.blast_radius <= 0.0:
		return
	explode(at, {"radius_m": st.blast_radius, "damage": st.blast_damage, "ap": st.armor_penetration,
		"armor_damage": st.armor_damage * 0.3, "destruction": st.destruction_level, "stagger": st.stagger * 0.5,
		"sound": st.sound, "sound_falloff": st.sound_falloff, "self_mult": 0.6})


func _update_grenades(delta: float) -> void:
	for g in _grenades:
		g.t += delta
		var k := clampf(g.t / g.flight, 0.0, 1.0)
		g.pos = (g.from as Vector2).lerp(g.to, 1.0 - pow(1.0 - k, 2.0))
		if g.t >= GRENADE_FUSE:
			explode(g.pos, GRENADE_BLAST)
	_grenades = _grenades.filter(func(g): return g.t < GRENADE_FUSE)


## Blast at center. p: radius_m, damage, ap, armor_damage, destruction, stagger,
## sound, sound_falloff, self_mult (fraction of damage the player takes).
func explode(center: Vector2, p: Dictionary) -> void:
	var r: float = p.radius_m * PX
	_blasts.append({"pos": center, "t": 0.0, "r": r})
	_scorches.append({"pos": center, "t": 0.0, "r": r * 0.35})
	get_tree().call_group("enemies", "hear", center, p.sound, p.sound_falloff)
	var space := get_world_2d().direct_space_state
	var shape := CircleShape2D.new()
	shape.radius = r
	var q := PhysicsShapeQueryParameters2D.new()
	q.shape = shape
	q.transform = Transform2D(0.0, center)
	var seen := {}
	for res in space.intersect_shape(q, 64):
		var body := res.collider as Node2D
		if body == null or seen.has(body):
			continue
		seen[body] = true
		var d := center.distance_to(body.global_position)
		# Blast needs line of sight (walls/rocks shield).
		var los := PhysicsRayQueryParameters2D.create(center, body.global_position, 1)
		los.exclude = [(body as CollisionObject2D).get_rid()]
		if not space.intersect_ray(los).is_empty():
			continue
		var fall := clampf(1.0 - d / r, 0.0, 1.0)
		var dir := (body.global_position - center).normalized()
		if dir == Vector2.ZERO:
			dir = Vector2.UP
		if body.has_method("take_damage"):
			body.take_damage(p.damage * fall * p.get("self_mult", 0.6), center) # friendly fire is real
		elif body.has_method("take_hit"):
			if body.is_in_group("enemies"):
				Game.add_stat("hits")
			body.take_hit({
				"damage": p.damage * fall, "base_damage": p.damage,
				"armor_penetration": p.ap, "armor_damage": p.armor_damage * fall,
				"destruction_level": p.destruction, "stagger": p.stagger * fall,
				"dir": dir, "meters": d / PX, "aim_point": null, "explosive": true,
			})


func _draw() -> void:
	for a in _acid:
		var fade := clampf(ACID_TIME - a.t, 0.0, 1.0)
		draw_circle(a.pos, ACID_RADIUS_M * PX, Color(0.55, 0.75, 0.1, 0.35 * fade))
		draw_circle(a.pos, ACID_RADIUS_M * PX * 0.6, Color(0.75, 0.95, 0.2, 0.3 * fade))
	for b in _biles:
		var k: float = b.t / BILE_FLIGHT
		var lift := sin(k * PI) * 40.0
		draw_circle(b.pos, 4.0, Color(0, 0, 0, 0.3))
		draw_circle(b.pos + Vector2(0, -lift), 6.0, Color(0.7, 0.95, 0.2, 0.9))
	for s in _scorches:
		draw_circle(s.pos, s.r, Color(0.05, 0.04, 0.03, 0.45 * clampf(40.0 - s.t, 0.0, 1.0)))
	for g in _grenades:
		var k := clampf(g.t / g.flight, 0.0, 1.0)
		var lift := sin(k * PI) * 18.0
		draw_circle(g.pos, 5.0, Color(0, 0, 0, 0.35)) # shadow
		var p: Vector2 = g.pos + Vector2(0, -lift)
		draw_circle(p, 5.5 + lift * 0.1, Color(0.08, 0.08, 0.08))
		draw_circle(p, 4.0 + lift * 0.1, Color(0.3, 0.38, 0.22))
		if g.t > GRENADE_FUSE - 0.6 and int(g.t * 12.0) % 2 == 0:
			draw_circle(p, 2.0, Color(1, 0.2, 0.1))
	for b in _blasts:
		var k: float = b.t / 0.5
		draw_circle(b.pos, b.r * (0.3 + k * 0.7), Color(1, 0.75, 0.3, 0.55 * (1.0 - k)))
		draw_circle(b.pos, b.r * 0.35 * (1.0 - k), Color(1, 0.95, 0.7, 0.9 * (1.0 - k)))
	for b in _bolts:
		var head: Vector2 = b.pos
		var dir := (b.vel as Vector2).normalized()
		draw_line(head - dir * 26.0, head, Color(1, 0.2, 0.15, 0.35), 6.0)
		draw_line(head - dir * 18.0, head, Color(1, 0.55, 0.45, 0.95), 2.5)
	for c in _casings:
		var size: Vector2 = c.size
		var col: Color = c.color
		col.a = clampf(c.life - c.t, 0.0, 1.0)
		draw_set_transform(c.pos, c.rot)
		draw_rect(Rect2(-size / 2.0, size), col)
	draw_set_transform(Vector2.ZERO)
	for b in _bullets:
		var head: Vector2 = b.pos
		var tail: Vector2 = b.tail
		if (b.stats as FirearmStats).bullet_type == FirearmStats.BulletType.ROCKET:
			var dir := (b.vel as Vector2).normalized()
			draw_line(head - dir * 70.0, head, Color(0.8, 0.8, 0.8, 0.35), 6.0) # smoke
			draw_line(head - dir * 14.0, head, Color(0.25, 0.28, 0.2), 5.0)
			draw_circle(head - dir * 15.0, 3.5, Color(1, 0.7, 0.2))
			continue
		if head.distance_to(tail) > TRACER_LEN:
			tail = head - (head - tail).normalized() * TRACER_LEN
		draw_line(tail, head, Color(1, 0.85, 0.45, 0.25), 3.0)
		draw_line(head.lerp(tail, 0.4), head, Color(1, 0.95, 0.7, 0.9), 1.5)
	for p in _puffs:
		var k: float = p.t / 0.25
		if p.get("bolt", false):
			draw_circle(p.pos, 2.0 + k * 6.0, Color(1, 0.35, 0.25, 0.8 * (1.0 - k)))
		elif p.has("scale"):
			draw_circle(p.pos, (6.0 + k * 20.0) * (p.scale as float), Color(0.3, 0.3, 0.3, 0.6 * (1.0 - k)))
		elif p.get("ground", false):
			draw_circle(p.pos, 2.0 + k * 6.0, Color(0.55, 0.45, 0.3, 0.7 * (1.0 - k)))
		else:
			draw_circle(p.pos, 3.0 + k * 9.0, Color(0.9, 0.85, 0.7, 0.6 * (1.0 - k)))
