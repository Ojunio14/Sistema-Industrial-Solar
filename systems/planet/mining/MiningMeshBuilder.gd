class_name MiningMeshBuilder
extends RefCounted
## Pure array builder. A worker must own its PlanetShape and the detached snapshot.
## No live Zone, Node, ArrayMesh, RenderingServer or collision access here.
static func build(snapshot: Dictionary, natural: PlanetShape) -> Array:
	var up: Vector3 = snapshot.up
	var tx: Vector3 = snapshot.tangent_x
	var ty: Vector3 = snapshot.tangent_y
	var radius: float = snapshot.radius_m
	var origin := up * radius
	var coordinate: Vector2i = snapshot.coordinate
	var deltas: PackedFloat32Array = snapshot.deltas
	var halo := PackedVector3Array()
	halo.resize(131 * 131)
	for y in range(131):
		for x in range(131):
			var local := Vector2(coordinate * 128 + Vector2i(x - 1, y - 1)) * 2.0
			var direction := (up + tx * (local.x / radius) + ty * (local.y / radius)).normalized()
			var height := PlanetEditableTerrain.compose_height(natural.sample_base_height(direction), deltas[y * 131 + x])
			var relative := direction * (radius + height) - origin
			halo[y * 131 + x] = Vector3(MiningZone.dot64(relative, tx), MiningZone.dot64(relative, up), -MiningZone.dot64(relative, ty))
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uv := PackedVector2Array()
	var colors := PackedColorArray()
	vertices.resize(129 * 129)
	normals.resize(129 * 129)
	uv.resize(129 * 129)
	colors.resize(129 * 129)
	for y in range(129):
		for x in range(129):
			var index := y * 129 + x
			var hi := (y + 1) * 131 + x + 1
			vertices[index] = halo[hi]
			normals[index] = (halo[hi + 1] - halo[hi - 1]).cross(halo[hi + 131] - halo[hi - 131]).normalized()
			uv[index] = Vector2(coordinate * 128 + Vector2i(x, y)) * 2.0
			var delta := deltas[hi]
			var base := Color(0.36, 0.46, 0.39)
			colors[index] = base.lerp(Color(0.22, 0.57, 0.95) if delta < 0 else Color(0.95, 0.53, 0.17), minf(absf(delta) / 12.0, 1.0))
	var indices := PackedInt32Array()
	indices.resize(128 * 128 * 6)
	var cursor := 0
	for y in range(128):
		for x in range(128):
			var a := y * 129 + x
			for vertex: int in [a, a + 129, a + 1, a + 1, a + 129, a + 130]:
				indices[cursor] = vertex
				cursor += 1
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	return arrays
