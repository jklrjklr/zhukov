class_name QuadMesh2D
extends RefCounted
## Shared unit quads for the batched renderers (MultiMesh instances map them with a Transform2D).

static var _centered: ArrayMesh
static var _corner: ArrayMesh


## Quad from (-1,-1) to (1,1), uv 0..1 (the canvas y axis points down, uv matches).
static func centered() -> ArrayMesh:
	if _centered == null:
		_centered = _make(Vector2(-1, -1), Vector2(1, 1))
	return _centered


## Quad from (0,0) to (1,1), uv 0..1.
static func corner() -> ArrayMesh:
	if _corner == null:
		_corner = _make(Vector2(0, 0), Vector2(1, 1))
	return _corner


static func _make(a: Vector2, b: Vector2) -> ArrayMesh:
	var m := ArrayMesh.new()
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = PackedVector2Array([Vector2(a.x, a.y), Vector2(b.x, a.y), Vector2(b.x, b.y), Vector2(a.x, b.y)])
	arr[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	arr[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m
