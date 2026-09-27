extends RefCounted
class_name PlanetChunkBuilder

## Um job possui sua própria definição e ruídos. Apenas arrays são produzidos
## no worker; nós e ArrayMesh são criados pelo gerenciador na thread principal.
var definition: PlanetDefinition
var face: CubeSphereMapping.Face
var depth: int
var cell: Vector2i
var resolution: int
var result: Dictionary
var geology: PlanetGeology
var climate: PlanetClimate
var biomes: PlanetBiomes


func _init(source: PlanetDefinition, face_id: int, level: int, address: Vector2i, samples: int,
		geology_source: PlanetGeology = null, climate_source: PlanetClimate = null,
		biome_source: PlanetBiomes = null) -> void:
	definition = source.duplicate(true) as PlanetDefinition
	face = face_id as CubeSphereMapping.Face
	depth = level
	cell = address
	resolution = samples
	geology = geology_source
	climate = climate_source
	biomes = biome_source


func build() -> void:
	var started := Time.get_ticks_usec()
	var shape := PlanetShape.new(definition, geology)
	var size := 1.0 / float(1 << depth)
	var origin := Vector2(cell) * size
	var count := resolution * resolution
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var geology_debug := PackedFloat32Array()
	var material_a := PackedFloat32Array()
	var material_b := PackedFloat32Array()
	var material_selector: PlanetMaterialWeights = null
	var climate_sample: PlanetClimateSample = null
	var biome_sample: PlanetBiomeSample = null
	var material_weights := PackedFloat32Array()
	if climate and biomes and geology:
		material_selector = PlanetMaterialWeights.new(definition, geology)
		climate_sample = PlanetClimateSample.new()
		biome_sample = PlanetBiomeSample.new()
		material_weights.resize(8)
		material_a.resize(count * 4)
		material_b.resize(count * 4)
	vertices.resize(count)
	normals.resize(count)
	uvs.resize(count)
	colors.resize(count)
	if geology:
		geology_debug.resize(count * 4)
	var bounds := AABB()
	var min_height := INF
	var max_height := -INF
	var land_samples := 0
	for y in range(resolution):
		for x in range(resolution):
			var i := x + y * resolution
			var uv := origin + CubeSphereMapping.grid_uv(x, y, resolution) * size
			var direction := CubeSphereMapping.face_uv_to_direction(face, uv)
			var terrain := shape.sample_components(direction)
			vertices[i] = direction * (definition.radius_m + terrain.x)
			# Mesmo passo físico e mesma base em todos os LODs e faces.
			normals[i] = surface_normal(shape, direction, vertices[i])
			uvs[i] = CubeSphereMapping.grid_uv(x, y, resolution)
			# Altura, terra, montanha e planalto alimentam o material técnico.
			colors[i] = Color(shape.normalize_height(terrain.x), terrain.y, terrain.z, terrain.w)
			if geology:
				# Payload descartável para o shader técnico; autoridade fica no serviço.
				var context := geology.sample_with_surface(direction, terrain)
				geology_debug[i * 4] = context.x
				geology_debug[i * 4 + 1] = context.y
				geology_debug[i * 4 + 2] = context.z
				geology_debug[i * 4 + 3] = context.w
			if material_selector:
				climate.sample_with_surface_into(direction, terrain, climate_sample)
				biomes.sample_with_context_into(direction, terrain, climate_sample, biome_sample)
				material_selector.sample_into(direction, terrain, normals[i], climate_sample,
					biome_sample, material_weights)
				for channel in range(4):
					material_a[i * 4 + channel] = material_weights[channel]
					material_b[i * 4 + channel] = material_weights[channel + 4]
			min_height = minf(min_height, terrain.x)
			max_height = maxf(max_height, terrain.x)
			land_samples += 1 if terrain.y >= 0.5 else 0
			bounds = AABB(vertices[i], Vector3.ZERO) if i == 0 else bounds.expand(vertices[i])
			if x < resolution - 1 and y < resolution - 1:
				indices.append_array(PackedInt32Array([i + resolution, i + resolution + 1, i,
					i + resolution + 1, i + 1, i]))

	# Estimativa geométrica: comparar pontos médios da malha com o terreno real.
	# Não é uma prova de limite de erro para qualquer ruído futuro.
	var error_m := 0.01
	for y in range(resolution - 1):
		for x in range(resolution - 1):
			var i := x + y * resolution
			var uv := origin + Vector2(x + 0.5, y + 0.5) / float(resolution - 1) * size
			var actual := shape.point_on_planet(CubeSphereMapping.face_uv_to_direction(face, uv))
			error_m = maxf(error_m, actual.distance_to((vertices[i] + vertices[i + resolution + 1]) * 0.5))
			for offset in [Vector2(0.5, 0.0), Vector2(0.0, 0.5)]:
				uv = origin + (Vector2(x, y) + offset) / float(resolution - 1) * size
				actual = shape.point_on_planet(CubeSphereMapping.face_uv_to_direction(face, uv))
				var other := i + 1 if offset.x > 0.0 else i + resolution
				error_m = maxf(error_m, actual.distance_to((vertices[i] + vertices[other]) * 0.5))
	# Saias: ocultação de T-junctions do protótipo; não fazem parte da colisão.
	# A saia cobre apenas a pequena diferença entre LODs. Uma fração grande do
	# espaçamento vira uma parede visível em silhueta, principalmente em montanhas.
	var spacing := 2.0 * definition.radius_m * size / float(resolution - 1)
	if definition.relief_enabled:
		# Sampling can miss a crest on a coarse grid; include an analytic envelope
		# in SSE, without changing the terrain function according to LOD.
		error_m = maxf(error_m, TerrainRelief.unresolved_error(spacing))
	var skirt_m := maxf(2.0, maxf(error_m * 1.5, spacing * 0.04))
	var edges: Array[PackedInt32Array] = []
	for edge in range(4):
		var row := PackedInt32Array()
		for step in range(resolution):
			match edge:
				0: row.append(step)
				1: row.append(step * resolution + resolution - 1)
				2: row.append((resolution - 1) * resolution + resolution - 1 - step)
				3: row.append((resolution - 1 - step) * resolution)
		edges.append(row)
	for edge in edges:
		var start := vertices.size()
		for index in edge:
			vertices.append(vertices[index] - vertices[index].normalized() * skirt_m)
			bounds = bounds.expand(vertices[vertices.size() - 1])
			normals.append(normals[index])
			uvs.append(uvs[index])
			colors.append(colors[index])
			if geology:
				for channel in range(4):
					geology_debug.append(geology_debug[index * 4 + channel])
			if material_selector:
				for channel in range(4):
					material_a.append(material_a[index * 4 + channel])
					material_b.append(material_b[index * 4 + channel])
		for j in range(resolution - 1):
			indices.append_array(PackedInt32Array([edge[j], edge[j + 1], start + j,
				edge[j + 1], start + j + 1, start + j]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	if geology:
		arrays[Mesh.ARRAY_CUSTOM0] = geology_debug
	if material_selector:
		arrays[Mesh.ARRAY_CUSTOM1] = material_a
		arrays[Mesh.ARRAY_CUSTOM2] = material_b
	arrays[Mesh.ARRAY_INDEX] = indices
	var custom_format := (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) if geology else 0
	if material_selector:
		custom_format |= Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT
		custom_format |= Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM2_SHIFT
	# Float32 AABB position + size can lose a few ULPs at 50 km.
	result = {"arrays": arrays, "format": custom_format,
		"bounds": bounds.grow(0.05 + (TerrainRelief.unresolved_error(spacing) if definition.relief_enabled else 0.0)), "error_m": error_m * 1.5,
		"skirt_m": skirt_m, "build_ms": (Time.get_ticks_usec() - started) / 1000.0,
		"min_height_m": min_height, "max_height_m": max_height,
		"land_fraction": float(land_samples) / float(count)}
static func surface_normal(shape: PlanetShape, direction: Vector3, center: Vector3 = Vector3.ZERO) -> Vector3:
	var reference := Vector3.UP if absf(direction.y) < 0.9 else Vector3.RIGHT
	var tangent := reference.cross(direction).normalized()
	var bitangent := direction.cross(tangent).normalized()
	var step := 2.0 / shape.definition.radius_m
	if center.is_zero_approx():
		center = shape.point_on_planet(direction)
	var a := shape.point_on_planet((direction + tangent * step).normalized())
	var b := shape.point_on_planet((direction + bitangent * step).normalized())
	return (a - center).cross(b - center).normalized()
