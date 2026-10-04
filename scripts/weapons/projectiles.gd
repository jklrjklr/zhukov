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


func _physics_process(delta: float) -> void:
	_update_grenades(delta)
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


func _update_grenades(delta: float) -> void:
	for g in _grenades:
		g.t += delta
		var k := clampf(g.t / g.flight, 0.0, 1.0)
		g.pos = (g.from as Vector2).lerp(g.to, 1.0 - pow(1.0 - k, 2.0))
		if g.t >= GRENADE_FUSE:
			_explode(g.pos)
	_grenades = _grenades.filter(func(g): return g.t < GRENADE_FUSE)


func _explode(center: Vector2) -> void:
	var r := GRENADE_RADIUS_M * PX
	_blasts.append({"pos": center, "t": 0.0, "r": r})
	_scorches.append({"pos": center, "t": 0.0, "r": r * 0.35})
	get_tree().call_group("enemies", "hear", center, GRENADE_SOUND, GRENADE_SOUND_FALLOFF)
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
			body.take_damage(GRENADE_DAMAGE * fall * 0.6, center) # own grenades hurt
		elif body.has_method("take_hit"):
			if body.is_in_group("enemies"):
				Game.add_stat("hits")
			body.take_hit({
				"damage": GRENADE_DAMAGE * fall, "base_damage": GRENADE_DAMAGE,
				"armor_penetration": GRENADE_AP, "armor_damage": GRENADE_ARMOR_DAMAGE * fall,
				"destruction_level": GRENADE_DESTRUCTION, "stagger": GRENADE_STAGGER * fall,
				"dir": dir, "meters": d / PX, "aim_point": null, "explosive": true,
			})


func _draw() -> void:
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
		if head.distance_to(tail) > TRACER_LEN:
			tail = head - (head - tail).normalized() * TRACER_LEN
		draw_line(tail, head, Color(1, 0.85, 0.45, 0.25), 3.0)
		draw_line(head.lerp(tail, 0.4), head, Color(1, 0.95, 0.7, 0.9), 1.5)
	for p in _puffs:
		var k: float = p.t / 0.25
		if p.get("ground", false):
			draw_circle(p.pos, 2.0 + k * 6.0, Color(0.55, 0.45, 0.3, 0.7 * (1.0 - k)))
		else:
			draw_circle(p.pos, 3.0 + k * 9.0, Color(0.9, 0.85, 0.7, 0.6 * (1.0 - k)))
