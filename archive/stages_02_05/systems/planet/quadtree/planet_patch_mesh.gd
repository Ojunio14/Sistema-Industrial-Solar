class_name PlanetPatchMesh
extends RefCounted

const SEGMENTS := 32
const WIDTH := 33
static var _indices: Dictionary = {}
static var _bins: Dictionary = {}
static var _uv := PackedVector2Array()
static var _stencils: Dictionary = {} # <= 16 masks × (same patch + 4 children).

static func stencil(mask: int, quadrant: int) -> Dictionary:
	var key := mask * 5 + quadrant + 1
	if not _stencils.has(key):
		var indices := PackedInt32Array()
		var weights := PackedVector3Array()
		var ready := PackedByteArray()
		indices.resize(WIDTH * WIDTH * 3)
		weights.resize(WIDTH * WIDTH)
		ready.resize(WIDTH * WIDTH)
		_stencils[key] = {"indices": indices, "weights": weights, "ready": ready}
	return _stencils[key]

static func grid() -> PackedVector2Array:
	if _uv.is_empty():
		_uv.resize(WIDTH * WIDTH)
		for i in range(_uv.size()):
			_uv[i] = grid_uv(i)
	return _uv

# Each 2x2 block is a center fan. Its checkerboard diagonals are nested
# under dyadic subdivision. Stitching removes odd boundary points from
# the fan polygon, preserving 45-degree diagonals and exact parent morph.
static func indices(mask: int) -> PackedInt32Array:
	assert(mask >= 0 and mask < 16)
	if _indices.has(mask):
		return _indices[mask]
	var result := PackedInt32Array()
	for y in range(0, SEGMENTS, 2):
		for x in range(0, SEGMENTS, 2):
			var polygon: Array[int] = []
			for offset in [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2),
					Vector2i(1, 2), Vector2i(2, 2), Vector2i(2, 1),
					Vector2i(2, 0), Vector2i(1, 0)]:
				var px: int = x + offset.x
				var py: int = y + offset.y
				if _remap(px, py, mask) == py * WIDTH + px:
					polygon.append(py * WIDTH + px)
			var center := (y + 1) * WIDTH + x + 1
			for i in range(polygon.size()):
				# The fan has strictly clockwise, nondegenerate triangles for all 16 masks.
				result.append(center)
				result.append(polygon[i])
				result.append(polygon[(i + 1) % polygon.size()])
	_indices[mask] = result
	return result

static func _remap(x: int, y: int, mask: int) -> int:
	if (x == 0 and (mask & 1) != 0) or (x == SEGMENTS and (mask & 2) != 0):
		y -= y & 1
	if (y == 0 and (mask & 4) != 0) or (y == SEGMENTS and (mask & 8) != 0):
		x -= x & 1
	return y * WIDTH + x

static func grid_uv(index: int) -> Vector2:
	return Vector2(index % WIDTH, index / WIDTH) / float(SEGMENTS)

static func _add_triangle(result: PackedInt32Array, a: int, b: int, c: int) -> void:
	var area := (grid_uv(b) - grid_uv(a)).cross(grid_uv(c) - grid_uv(a))
	if area < 0.0:
		result.append_array(PackedInt32Array([a, b, c]))

static func generate(id: PatchId, radius: float, mask: int, terrain: PlanetTerrain = null, meters_per_unit: float = 1.0, climate: PlanetClimate = null, smooth_normals: bool = false) -> Dictionary:
	var data := begin_generate(id, radius, mask, terrain, meters_per_unit, climate, smooth_normals)
	advance_generate(data, WIDTH * WIDTH)
	return data

static func begin_generate(id: PatchId, radius: float, mask: int, terrain: PlanetTerrain = null, meters_per_unit: float = 1.0, climate: PlanetClimate = null, smooth_normals: bool = false) -> Dictionary:
	assert(id.is_valid() and radius > 0.0)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	vertices.resize(WIDTH * WIDTH)
	normals.resize(WIDTH * WIDTH)
	var colors := PackedColorArray()
	colors.resize(WIDTH * WIDTH)
	var geology := PackedFloat32Array()
	geology.resize(WIDTH * WIDTH * 4)
	var climate_fields := PackedFloat32Array()
	climate_fields.resize(WIDTH * WIDTH * 4)
	var biomes := PackedFloat32Array()
	biomes.resize(WIDTH * WIDTH * 4)
	var material_factors := PackedVector2Array()
	material_factors.resize(WIDTH * WIDTH)
	var bounds := id.get_uv_bounds()
	# Cube-face mapping is affine. Obtain the patch frame from the Stage 1 API
	# once; interpolate that frame, then normalize per vertex. No face bases or
	# topology conventions are duplicated here.
	var origin := PlanetMath.face_uv_to_cube(id.face, bounds.position)
	var axis_u := PlanetMath.face_uv_to_cube(id.face, bounds.position + Vector2(bounds.size.x, 0)) - origin
	var axis_v := PlanetMath.face_uv_to_cube(id.face, bounds.position + Vector2(0, bounds.size.y)) - origin
	return {"id": id, "mask": mask, "vertices": vertices, "normals": normals, "uv": grid(),
		"indices": indices(mask), "radius": radius, "next_vertex": 0,
		"cube_origin": origin, "cube_u": axis_u, "cube_v": axis_v,
		"terrain": terrain, "meters_per_unit": meters_per_unit, "colors": colors,
		"geology": geology, "climate_fields": climate_fields, "biomes": biomes,
		"material_factors": material_factors, "smooth_normals": smooth_normals,
		"climate": climate, "sample_output": PlanetTerrainSample.new(),
		"climate_output": PlanetClimateSample.new() if climate != null else null,
		"normal_output": PlanetTerrainSample.new() if smooth_normals and terrain != null else null}

# Bounded CPU slice. The synchronous API above uses exactly the same generator.
static func advance_generate(data: Dictionary, count: int, profiler: RefCounted = null) -> bool:
	var vertices: PackedVector3Array = data.vertices
	var normals: PackedVector3Array = data.normals
	var uv: PackedVector2Array = data.uv
	var origin: Vector3 = data.cube_origin
	var axis_u: Vector3 = data.cube_u
	var axis_v: Vector3 = data.cube_v
	var radius: float = data.radius
	var terrain: PlanetTerrain = data.terrain
	var colors: PackedColorArray = data.colors
	var geology: PackedFloat32Array = data.geology
	var climate_fields: PackedFloat32Array = data.climate_fields
	var biomes: PackedFloat32Array = data.biomes
	var material_factors: PackedVector2Array = data.material_factors
	var climate: PlanetClimate = data.climate
	var climate_output: PlanetClimateSample = data.climate_output
	var output: PlanetTerrainSample = data.sample_output
	var normal_output: PlanetTerrainSample = data.normal_output
	var meters_per_unit: float = data.meters_per_unit
	var smooth_normals: bool = data.smooth_normals
	var end := mini(WIDTH * WIDTH, int(data.next_vertex) + count)
	for i in range(data.next_vertex, end):
		normals[i] = (origin + axis_u * uv[i].x + axis_v * uv[i].y).normalized()
	var started: int = profiler.stamp() if profiler != null else 0
	for i in range(data.next_vertex, end):
		var direction := normals[i]
		if terrain != null:
			terrain.sample_into(direction, output)
		var fields := output.terrain
		vertices[i] = direction * (radius + fields.x / meters_per_unit)
		colors[i] = Color(clampf(fields.y + 0.5, 0.0, 1.0), fields.z / 8.0, fields.w, 1.0)
		geology[i * 4] = output.geology.x
		geology[i * 4 + 1] = output.geology.y
		geology[i * 4 + 2] = output.geology.z
		geology[i * 4 + 3] = output.geology.w
		if climate != null:
			climate.sample_into(direction, fields, climate_output)
			var c := climate_output.climate
			# Store normalized floats in the incremental loop, then let Image
			# quantize the complete patch in native code once at finalization.
			climate_fields[i * 4] = clampf((c.x + 40.0) / 80.0, 0.0, 1.0)
			climate_fields[i * 4 + 1] = c.y
			climate_fields[i * 4 + 2] = c.z
			climate_fields[i * 4 + 3] = c.w
			biomes[i * 4] = climate_output.rain_shadow
			biomes[i * 4 + 1] = (climate_output.dominant + 1) / 11.0
			biomes[i * 4 + 2] = (climate_output.secondary + 1) / 11.0
			biomes[i * 4 + 3] = climate_output.top_pair_mix
			if smooth_normals:
				var factors := PlanetSurfaceSelection.factors(output.geology, climate_output)
				material_factors[i] = Vector2(factors.x, factors.y)
				var color: Color = colors[i]
				color.a = factors.z
				colors[i] = color
		if smooth_normals and terrain != null:
			# A fixed metric stencil is independent of patch size, face and LOD.
			# Two extra height queries are paid only by the PBR material path.
			var reference := Vector3.RIGHT if absf(direction.y) > 0.92 else Vector3.UP
			var tangent_u := reference.cross(direction).normalized()
			var tangent_v := direction.cross(tangent_u)
			var epsilon := 10.0 / (radius * meters_per_unit)
			var du := (direction + tangent_u * epsilon).normalized()
			var dv := (direction + tangent_v * epsilon).normalized()
			terrain.sample_into(du, normal_output)
			var position_u := du * (radius + normal_output.terrain.x / meters_per_unit)
			terrain.sample_into(dv, normal_output)
			var position_v := dv * (radius + normal_output.terrain.x / meters_per_unit)
			var smooth_normal := (position_u - vertices[i]).cross(position_v - vertices[i]).normalized()
			normals[i] = smooth_normal if smooth_normal.dot(direction) > 0.0 else -smooth_normal
	if profiler != null:
		profiler.finish(&"terrain_displace_us", started)
	data.vertices = vertices
	data.normals = normals
	data.colors = colors
	data.geology = geology
	data.climate_fields = climate_fields
	data.biomes = biomes
	data.material_factors = material_factors
	data.next_vertex = end
	if end == WIDTH * WIDTH:
		data.from = vertices
		var climate_image := Image.create_from_data(WIDTH, WIDTH, false, Image.FORMAT_RGBAF, climate_fields.to_byte_array())
		climate_image.convert(Image.FORMAT_RGBA8)
		data.climate_fields = climate_image.get_data()
		var biome_image := Image.create_from_data(WIDTH, WIDTH, false, Image.FORMAT_RGBAF, biomes.to_byte_array())
		biome_image.convert(Image.FORMAT_RGBA8)
		data.biomes = biome_image.get_data()
	return end == WIDTH * WIDTH

static func with_mask(data: Dictionary, mask: int) -> Dictionary:
	var result := data.duplicate() # Packed arrays are shared, never mutated here.
	result.mask = mask
	result.indices = indices(mask)
	result.from = result.vertices
	return result

# Cache UV-space triangle bins once per one of the 16 index masks.
# Interpolation samples the actual stitched coarse triangles, including corners.
static func sample(data: Dictionary, local_uv: Vector2) -> Vector3:
	var interpolation := sample_weights(data.mask, local_uv)
	var vertices: PackedVector3Array = data.vertices
	return vertices[interpolation[0]] * interpolation[3] + vertices[interpolation[1]] * interpolation[4] + vertices[interpolation[2]] * interpolation[5]

# Geometry-independent barycentric stencil for the real stitched topology.
static func sample_weights(mask: int, local_uv: Vector2) -> Array:
	if not _bins.has(mask):
		var bins: Array = []
		bins.resize(SEGMENTS * SEGMENTS)
		for i in range(bins.size()):
			bins[i] = []
		var topology := indices(mask)
		for offset in range(0, topology.size(), 3):
			var a := grid_uv(topology[offset]) * SEGMENTS
			var b := grid_uv(topology[offset + 1]) * SEGMENTS
			var c := grid_uv(topology[offset + 2]) * SEGMENTS
			var lower := a.min(b).min(c)
			var upper := a.max(b).max(c)
			# Only cells with positive-area intersection; boundary samples belong
			# to the selected cell's closed triangles, including UV == 1.
			for y in range(int(lower.y), int(upper.y)):
				for x in range(int(lower.x), int(upper.x)):
					bins[y * SEGMENTS + x].append(offset)
		_bins[mask] = bins
	var cell := Vector2i(clampi(int(local_uv.x * SEGMENTS), 0, SEGMENTS - 1),
		clampi(int(local_uv.y * SEGMENTS), 0, SEGMENTS - 1))
	var topology := indices(mask)
	var uv := grid()
	for offset: int in _bins[mask][cell.y * SEGMENTS + cell.x]:
		var ia := topology[offset]
		var ib := topology[offset + 1]
		var ic := topology[offset + 2]
		var a := uv[ia]
		var b := uv[ib]
		var c := uv[ic]
		var det := (b - a).cross(c - a)
		var wb := (local_uv - a).cross(c - a) / det
		var wc := (b - a).cross(local_uv - a) / det
		var wa := 1.0 - wb - wc
		if minf(wa, minf(wb, wc)) >= -0.000001:
			return [ia, ib, ic, wa, wb, wc]
	assert(false, "UV outside stitched topology: %s mask=%d" % [local_uv, mask])
	return [0, 0, 0, 1.0, 0.0, 0.0]

static func as_array_mesh(data: Dictionary) -> ArrayMesh:
	var vertices: PackedVector3Array = data.vertices
	var from: PackedVector3Array = data.from
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = data.vertices
	arrays[Mesh.ARRAY_NORMAL] = data.normals
	arrays[Mesh.ARRAY_TEX_UV] = data.uv
	arrays[Mesh.ARRAY_TEX_UV2] = data.material_factors
	arrays[Mesh.ARRAY_INDEX] = data.indices
	arrays[Mesh.ARRAY_COLOR] = data.colors
	var delta := PackedFloat32Array()
	delta.resize(vertices.size() * 3)
	for i in range(vertices.size()):
		var offset := from[i] - vertices[i]
		delta[i * 3] = offset.x
		delta[i * 3 + 1] = offset.y
		delta[i * 3 + 2] = offset.z
	arrays[Mesh.ARRAY_CUSTOM0] = delta
	arrays[Mesh.ARRAY_CUSTOM1] = data.geology
	arrays[Mesh.ARRAY_CUSTOM2] = data.climate_fields
	arrays[Mesh.ARRAY_CUSTOM3] = data.biomes
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {},
		(Mesh.ARRAY_CUSTOM_RGB_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) |
		(Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT) |
		(Mesh.ARRAY_CUSTOM_RGBA8_UNORM << Mesh.ARRAY_FORMAT_CUSTOM2_SHIFT) |
		(Mesh.ARRAY_CUSTOM_RGBA8_UNORM << Mesh.ARRAY_FORMAT_CUSTOM3_SHIFT))
	var bounds := AABB(vertices[0], Vector3.ZERO)
	for i in range(vertices.size()):
		bounds = bounds.expand(vertices[i]).expand(from[i])
	mesh.custom_aabb = bounds.grow(0.05)
	return mesh
