class_name Combat
## Shared hit rules for anything that can be shot.


## Critical hit: an aimed bullet whose landing point is on the head (within head_radius
## sideways and not more than crit_depth px past the head centre).
static func is_crit(hit: Dictionary, head: Vector2, head_radius: float, crit_depth: float) -> bool:
	if hit.get("aim_point") == null:
		return false
	var rel: Vector2 = hit.aim_point - head
	var dir: Vector2 = hit.dir
	return absf(rel.cross(dir)) <= head_radius and rel.dot(dir) <= crit_depth
