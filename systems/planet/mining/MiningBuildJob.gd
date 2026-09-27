class_name MiningBuildJob
extends RefCounted
## Detached input, immutable shared services. Worker produces arrays only.
const FORMAT := (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) | (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT) | (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM2_SHIFT)
var snapshot: Dictionary
var definition: PlanetDefinition
var geology: PlanetGeology
var climate: PlanetClimate
var biomes: PlanetBiomes
var result: Dictionary = {}

func _init(source: Dictionary, natural: PlanetShape, weather: PlanetClimate, habitats: PlanetBiomes) -> void:
	snapshot = source
	definition = natural.definition.duplicate(true)
	geology = natural.geology
	climate = weather
	biomes = habitats

static func expand_snapshot(s: Dictionary) -> Dictionary:
	if s.has("deltas"):
		return s
	var expanded := s.duplicate()
	var deltas := PackedFloat32Array()
	deltas.resize(131 * 131)
	var bounds: Rect2i = s.chunk_bounds
	for y in range(131):
		for x in range(131):
			var node: Vector2i = s.coordinate * 128 + Vector2i(x - 1, y - 1)
			if node.x <= bounds.position.x * 128 or node.y <= bounds.position.y * 128 or node.x >= bounds.end.x * 128 or node.y >= bounds.end.y * 128:
				continue
			var owner := MiningZone.owner_of(node)
			if s.owners.has(owner):
				var local := MiningZone.local_index(node)
				deltas[y * 131 + x] = s.owners[owner][local.y * 128 + local.x]
	expanded.deltas = deltas
	expanded.erase("owners")
	return expanded

func build() -> void:
	var start := Time.get_ticks_usec()
	var s := expand_snapshot(snapshot)
	var natural := PlanetShape.new(definition, geology)
	var halo := PackedVector3Array()
	var surfaces := PackedVector4Array()
	halo.resize(131 * 131)
	surfaces.resize(131 * 131)
	for y in range(131):
		for x in range(131):
			var xy := Vector2(s.coordinate * 128 + Vector2i(x - 1, y - 1)) * 2.0
			var d: Vector3 = (s.up + s.tangent_x * (xy.x / s.radius_m) + s.tangent_y * (xy.y / s.radius_m)).normalized()
			var surface := natural.sample_components(d)
			surfaces[y * 131 + x] = surface
			halo[y * 131 + x] = d * (s.radius_m + surface.x + s.deltas[y * 131 + x])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uv := PackedVector2Array()
	vertices.resize(129 * 129)
	normals.resize(129 * 129)
	colors.resize(129 * 129)
	uv.resize(129 * 129)
	var payload := MiningAppearance.new(natural, climate, biomes)
	var g := PackedFloat32Array()
	var a := PackedFloat32Array()
	var b := PackedFloat32Array()
	g.resize(vertices.size() * 4)
	a.resize(vertices.size() * 4)
	b.resize(vertices.size() * 4)
	for y in range(129):
		for x in range(129):
			var i := y * 129 + x
			var xy := Vector2(s.coordinate * 128 + Vector2i(x, y)) * 2.0
			var d: Vector3 = (s.up + s.tangent_x * (xy.x / s.radius_m) + s.tangent_y * (xy.y / s.radius_m)).normalized()
			var hi := (y + 1) * 131 + x + 1
			var surface := surfaces[hi]
			vertices[i] = halo[hi]
			normals[i] = (halo[hi + 1] - halo[hi - 1]).cross(halo[hi + 131] - halo[hi - 131]).normalized()
			uv[i] = xy
			var context := payload.sample(d, surface, normals[i])
			colors[i] = context.c
			for ch in range(4):
				g[i * 4 + ch] = context.g[ch]
				a[i * 4 + ch] = context.a[ch]
				b[i * 4 + ch] = context.b[ch]
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_CUSTOM0] = g
	arrays[Mesh.ARRAY_CUSTOM1] = a
	arrays[Mesh.ARRAY_CUSTOM2] = b
	arrays[Mesh.ARRAY_TEX_UV] = uv
	var indices := PackedInt32Array()
	indices.resize(128 * 128 * 6)
	var cursor := 0
	for y in range(128):
		for x in range(128):
			var index := y * 129 + x
			for vertex: int in [index, index + 129, index + 1, index + 1, index + 129, index + 130]:
				indices[cursor] = vertex
				cursor += 1
	arrays[Mesh.ARRAY_INDEX] = indices
	var faces := collision_faces(arrays)
	result = {"arrays": arrays, "faces": split_collision(faces), "format": FORMAT,
		"started_usec": start, "ended_usec": Time.get_ticks_usec(),
		"build_ms": (Time.get_ticks_usec() - start) / 1000.0}

static func collision_faces(arrays: Array) -> PackedVector3Array:
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var faces := PackedVector3Array()
	faces.resize(indices.size())
	for i in range(indices.size()):
		faces[i] = vertices[indices[i]]
	return faces

static func split_collision(faces: PackedVector3Array) -> Array:
	var parts := []
	# 2,048 triangles per shape; same full-resolution triangles, no simplification.
	for first in range(0, faces.size(), 6144):
		parts.append(faces.slice(first, mini(first + 6144, faces.size())))
	return parts
