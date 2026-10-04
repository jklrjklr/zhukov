extends Node2D
## Simulates and draws all bullets, ejected casings and impact puffs in one node
## (cheap on web). Bullets are ray-stepped each physics tick, so fast rounds never tunnel.
## Targets implement take_hit(hit: Dictionary): damage (after falloff), base_damage,
## armor_penetration, armor_damage, destruction_level, dir, meters, aim_point.
## Aimed (ADS) bullets have a landing point: they stop there (hit the ground) unless
## something is in the way first. aim_point lets targets decide on critical hits.

const PX := Firearm.PX_PER_M
const TRACER_LEN := 140.0

var _bullets: Array[Dictionary] = []
var _casings: Array[Dictionary] = []
var _puffs: Array[Dictionary] = []


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


func _physics_process(delta: float) -> void:
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
		if collider.has_method("take_hit"):
			collider.take_hit({
				"damage": st.damage_at(meters), "base_damage": st.damage,
				"armor_penetration": st.armor_penetration, "armor_damage": st.armor_damage,
				"destruction_level": st.destruction_level,
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
	queue_redraw()


func _draw() -> void:
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
