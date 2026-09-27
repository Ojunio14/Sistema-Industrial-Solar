extends SceneTree

var failures: Array[String] = []
var checks := 0

func _expect(ok: bool, detail: String) -> void:
	checks += 1
	if not ok:
		failures.append(detail)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var definition: PlanetDefinition = load("res://systems/planet/surface/data/test_planet_100km.tres")
	var geology := PlanetGeology.new(definition)
	var shape := PlanetShape.new(definition, geology)
	var climate := PlanetClimate.new(definition, -1, geology)
	var biomes := PlanetBiomes.new(definition, climate, geology)
	var selector := PlanetMaterialWeights.new(definition, geology)
	_expect(PlanetMaterialWeights.NAMES.size() == 8, "Exatamente oito famílias")
	for family in PlanetMaterialWeights.NAMES:
		for kind in ["albedo", "normal", "roughness"]:
			var path := "res://assets/textures/terrain/%s/%s_%s.png" % [family, family, kind]
			_expect(ResourceLoader.exists(path), "Mapa essencial: " + path)
			var image := (load(path) as Texture2D).get_image()
			_expect(image.get_width() == 2048 and image.get_height() == 2048, "2K: " + path)
			if kind == "normal":
				if image.is_compressed():
					image.decompress()
				var sample := image.get_pixel(1024, 1024)
				var xy := Vector2(sample.r, sample.g) * 2.0 - Vector2.ONE
				var reconstructed_z := sqrt(maxf(1.0 - xy.length_squared(), 0.0))
				_expect(is_finite(reconstructed_z) and reconstructed_z >= 0.0,
					"Normal BC5/RG reconstrói Z positivo: " + family)
	# O referencial T/B/N é destro e o canal azul aponta para fora nos seis eixos.
	var gl_normal := Vector3(0.2, -0.3, sqrt(0.87))
	for sign_value in [-1.0, 1.0]:
		var mapped_x := Vector3(sign_value * gl_normal.z, gl_normal.y,
			-sign_value * gl_normal.x)
		var mapped_y := Vector3(gl_normal.x, sign_value * gl_normal.z,
			-sign_value * gl_normal.y)
		var mapped_z := Vector3(sign_value * gl_normal.x, gl_normal.y,
			sign_value * gl_normal.z)
		_expect(absf(mapped_x.dot(Vector3(sign_value, 0, 0)) - gl_normal.z) < 0.00001,
			"Normal triplanar ±X aponta para fora")
		_expect(absf(mapped_y.dot(Vector3(0, sign_value, 0)) - gl_normal.z) < 0.00001,
			"Normal triplanar ±Y aponta para fora")
		_expect(absf(mapped_z.dot(Vector3(0, 0, sign_value)) - gl_normal.z) < 0.00001,
			"Normal triplanar ±Z aponta para fora")
	var weather := PlanetClimateSample.new()
	var biome := PlanetBiomeSample.new()
	var weights := PackedFloat32Array()
	weights.resize(8)
	var land_count := 0
	var water_count := 0
	var top_pair_counts := PackedInt32Array()
	top_pair_counts.resize(8)
	for i in range(4096):
		var y := 1.0 - 2.0 * (float(i) + 0.5) / 4096.0
		var angle := float(i) * 2.399963229728653
		var direction := Vector3(cos(angle) * sqrt(1.0 - y * y), y,
			sin(angle) * sqrt(1.0 - y * y))
		var surface := shape.sample_components(direction)
		climate.sample_with_surface_into(direction, surface, weather)
		biomes.sample_with_context_into(direction, surface, weather, biome)
		selector.sample_into(direction, surface, direction, weather, biome, weights)
		var total := 0.0
		for weight in weights:
			_expect(is_finite(weight) and weight >= 0.0, "Peso finito e não negativo")
			total += weight
		if surface.x <= definition.sea_level_m:
			water_count += 1
			_expect(is_zero_approx(total), "Água sem material terrestre")
		else:
			land_count += 1
			_expect(absf(total - 1.0) < 0.0001, "Peso terrestre normalizado")
			var ids := PlanetMaterialWeights.top_three(weights)
			top_pair_counts[ids.x] += 1
			top_pair_counts[ids.y] += 1
			_expect(ids.x >= 0 and ids.x < 8 and ids.y >= 0 and ids.y < 8 and ids.z >= 0 and ids.z < 8,
				"Índices top 3 válidos")
			_expect(weights[ids.x] >= weights[ids.y] and weights[ids.y] >= weights[ids.z],
				"Top 3 ordenado")
	_expect(land_count > 100 and water_count > 100, "Amostra contém terra e água")
	# Mesmo ponto radial para as faces +X e +Z: seleção independe de face/LOD.
	var edge := Vector3(1.0, 0.25, 1.0).normalized()
	var surface := shape.sample_components(edge)
	climate.sample_with_surface_into(edge, surface, weather)
	biomes.sample_with_context_into(edge, surface, weather, biome)
	selector.sample_into(edge, surface, PlanetChunkBuilder.surface_normal(shape, edge), weather, biome, weights)
	var duplicate := weights.duplicate()
	selector.sample_into(edge, surface, PlanetChunkBuilder.surface_normal(shape, edge), weather, biome, weights)
	_expect(weights == duplicate, "Pesos estáveis na borda de face e entre LODs")
	# Contratos direcionais com o mesmo bioma/clima, isolando cada influência.
	var controlled := PlanetBiomeSample.new()
	controlled.weights.fill(0.0)
	controlled.weights[PlanetBiomes.Biome.TEMPERATE] = 1.0
	controlled.dominant = PlanetBiomes.Biome.TEMPERATE
	weather.temperature_c = 18.0
	weather.humidity = 0.55
	weather.ocean_influence = 0.0
	weather.altitude_m = 150.0
	var base_surface := Vector4(150.0, 1.0, 0.0, 0.0)
	selector.sample_into(edge, base_surface, edge, weather, controlled, weights)
	var soil_flat := weights[PlanetMaterialWeights.Family.SOIL]
	var rock_flat := weights[PlanetMaterialWeights.Family.ROCK_GENERIC]
	var tangent := edge.cross(Vector3.UP).normalized()
	selector.sample_into(edge, base_surface, (edge + tangent * 0.9).normalized(),
		weather, controlled, weights)
	_expect(weights[PlanetMaterialWeights.Family.SOIL] < soil_flat,
		"Slope reduz solo")
	_expect(weights[PlanetMaterialWeights.Family.ROCK_GENERIC] > rock_flat,
		"Slope aumenta rocha")
	weather.altitude_m = 10.0
	weather.ocean_influence = 1.0
	selector.sample_into(edge, Vector4(10.0, 1.0, 0.0, 0.0), edge, weather,
		controlled, weights)
	var sand_coast := weights[PlanetMaterialWeights.Family.SAND]
	weather.altitude_m = 300.0
	selector.sample_into(edge, Vector4(300.0, 1.0, 0.0, 0.0), edge, weather,
		controlled, weights)
	_expect(sand_coast > weights[PlanetMaterialWeights.Family.SAND],
		"Praia baixa favorece areia")
	controlled.weights.fill(0.0)
	controlled.weights[PlanetBiomes.Biome.POLAR] = 1.0
	controlled.dominant = PlanetBiomes.Biome.POLAR
	weather.temperature_c = -25.0
	weather.altitude_m = 800.0
	selector.sample_into(edge, Vector4(800.0, 1.0, 0.0, 0.0), edge, weather,
		controlled, weights)
	_expect(weights[PlanetMaterialWeights.Family.SNOW_ICE] > 0.45,
		"Frio polar/alto favorece neve")
	var igneous_center := Vector3.ZERO
	for descriptor in geology.descriptors():
		if int(descriptor.type) == PlanetGeology.Type.IGNEOUS:
			igneous_center = descriptor.center
			break
	_expect(not igneous_center.is_zero_approx(), "Província ígnea disponível")
	if not igneous_center.is_zero_approx():
		controlled.weights.fill(0.0)
		controlled.weights[PlanetBiomes.Biome.TEMPERATE] = 1.0
		controlled.dominant = PlanetBiomes.Biome.TEMPERATE
		weather.temperature_c = 18.0
		weather.altitude_m = 150.0
		selector.sample_into(igneous_center, base_surface, igneous_center, weather,
			controlled, weights)
		var volcanic_center := weights[PlanetMaterialWeights.Family.ROCK_VOLCANIC]
		var far := -igneous_center
		selector.sample_into(far, base_surface, far, weather, controlled, weights)
		_expect(volcanic_center > weights[PlanetMaterialWeights.Family.ROCK_VOLCANIC],
			"Província ígnea eleva rocha vulcânica sem bioma novo")
	var legacy := PlanetChunkBuilder.new(definition, 0, 1, Vector2i.ZERO, 9, geology)
	var material_builder := PlanetChunkBuilder.new(definition, 0, 1, Vector2i.ZERO, 9,
		geology, climate, biomes)
	legacy.build()
	material_builder.build()
	_expect(legacy.result.arrays[Mesh.ARRAY_VERTEX] == material_builder.result.arrays[Mesh.ARRAY_VERTEX],
		"Material não altera vértices")
	_expect(legacy.result.arrays[Mesh.ARRAY_NORMAL] == material_builder.result.arrays[Mesh.ARRAY_NORMAL],
		"Material não altera normais geométricas")
	_expect(material_builder.result.arrays[Mesh.ARRAY_CUSTOM1].size() > 0,
		"Dois canais contínuos de pesos na mesh")
	var seam_values := {}
	var seam_matches := 0
	for face in range(6):
		var face_builder := PlanetChunkBuilder.new(definition, face, 0, Vector2i.ZERO, 5,
			geology, climate, biomes)
		face_builder.build()
		var positions: PackedVector3Array = face_builder.result.arrays[Mesh.ARRAY_VERTEX]
		var a: PackedFloat32Array = face_builder.result.arrays[Mesh.ARRAY_CUSTOM1]
		var b: PackedFloat32Array = face_builder.result.arrays[Mesh.ARRAY_CUSTOM2]
		for i in range(25):
			var direction := positions[i].normalized()
			var key := "%d/%d/%d" % [roundi(direction.x * 1000000.0),
				roundi(direction.y * 1000000.0), roundi(direction.z * 1000000.0)]
			var values := PackedFloat32Array()
			values.resize(8)
			for channel in range(4):
				values[channel] = a[i * 4 + channel]
				values[channel + 4] = b[i * 4 + channel]
			if seam_values.has(key):
				seam_matches += 1
				var original: PackedFloat32Array = seam_values[key]
				for channel in range(8):
					_expect(absf(original[channel] - values[channel]) < 0.0001,
						"Pesos contínuos nas faces do cubo")
			else:
				seam_values[key] = values
	_expect(seam_matches >= 48, "Amostras realmente compartilhadas entre faces")
	var child := PlanetChunkBuilder.new(definition, 0, 1, Vector2i.ZERO, 5,
		geology, climate, biomes)
	child.build()
	var child_positions: PackedVector3Array = child.result.arrays[Mesh.ARRAY_VERTEX]
	var child_a: PackedFloat32Array = child.result.arrays[Mesh.ARRAY_CUSTOM1]
	var child_b: PackedFloat32Array = child.result.arrays[Mesh.ARRAY_CUSTOM2]
	var lod_matches := 0
	for i in range(25):
		var direction := child_positions[i].normalized()
		var key := "%d/%d/%d" % [roundi(direction.x * 1000000.0),
			roundi(direction.y * 1000000.0), roundi(direction.z * 1000000.0)]
		if seam_values.has(key):
			lod_matches += 1
			var original: PackedFloat32Array = seam_values[key]
			for channel in range(4):
				_expect(absf(original[channel] - child_a[i * 4 + channel]) < 0.0001,
					"Peso A independe de LOD")
				_expect(absf(original[channel + 4] - child_b[i * 4 + channel]) < 0.0001,
					"Peso B independe de LOD")
	_expect(lod_matches >= 9, "Amostras realmente compartilhadas entre LODs")
	print("MATERIALS land=%d water=%d top_pair=%s checks=%d failures=%d" % [
		land_count, water_count, top_pair_counts, checks, failures.size()])
	for failure in failures:
		push_error(failure)
	quit(0 if failures.is_empty() else 1)
