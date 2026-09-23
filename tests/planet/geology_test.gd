extends SceneTree

class ReadWorker:
	extends RefCounted
	var geology: PlanetGeology
	var directions: Array[Vector3]
	var surfaces: Array[Vector4]
	var checksum := 0.0
	func _init(source: PlanetGeology, points: Array[Vector3], fields: Array[Vector4]) -> void:
		geology = source
		directions = points
		surfaces = fields
	func run() -> void:
		for i in range(directions.size()):
			var result := geology.sample_with_surface(directions[i], surfaces[i])
			checksum += result.x + result.y + result.z

var failures: Array[String] = []
var checks := 0
var fingerprint := ""

func _initialize() -> void:
	var definition: PlanetDefinition = load("res://systems/planet/surface/data/test_planet_100km.tres")
	var shape := PlanetShape.new(definition)
	var before := PackedFloat64Array()
	var directions: Array[Vector3] = []
	var surfaces: Array[Vector4] = []
	for i in range(8192):
		var y := 1.0 - 2.0 * (float(i) + 0.5) / 8192.0
		var a := float(i) * 2.399963229728653
		var r := sqrt(1.0 - y * y)
		var d := Vector3(r * cos(a), y, r * sin(a))
		directions.append(d)
		before.append(shape.sample_base_height(d))
	var started := Time.get_ticks_usec()
	var geology := PlanetGeology.new(definition)
	var construction_ms := (Time.get_ticks_usec() - started) / 1000.0
	var same := PlanetGeology.new(definition)
	var other := PlanetGeology.new(definition, (definition.seed ^ PlanetGeology.SEED_SALT) + 1)
	check(before[0] == shape.sample_base_height(directions[0]), "override geológico não altera seed natural")
	check(geology.descriptors().size() >= 20, "descritores presentes")
	var changed := 0
	var counts := PackedInt32Array()
	counts.resize(9)
	var ocean_province := 0
	var land_province := 0
	var igneous := 0
	var hash_context := HashingContext.new()
	hash_context.start(HashingContext.HASH_SHA256)
	started = Time.get_ticks_usec()
	for i in range(directions.size()):
		var d := directions[i]
		var surface := shape.sample_components(d)
		surfaces.append(surface)
		var sample := geology.sample_with_surface(d, surface)
		var second := same.sample_with_surface(d, surface)
		var different := other.sample(d)
		check(sample == second, "mesma seed %d" % i)
		check(sample == geology.sample(d), "API direta %d" % i)
		check(before[i] == shape.sample_base_height(d), "base_height alterada %d" % i)
		check(not is_nan(sample.y) and not is_inf(sample.y) and sample.y >= 0.0 and sample.y <= 1.0, "maturidade finita %d" % i)
		check(not is_nan(sample.z) and not is_inf(sample.z) and sample.z >= 0.0 and sample.z <= 1.0, "influência finita %d" % i)
		check(PlanetGeology.type_of(int(sample.x)) == int(sample.w), "tipo/ID %d" % i)
		if sample != different:
			changed += 1
		var kind := int(sample.w)
		counts[kind] += 1
		if kind >= PlanetGeology.Type.CRATON and kind <= PlanetGeology.Type.FORMER_MARINE:
			if surface.x <= definition.sea_level_m:
				ocean_province += 1
			else:
				land_province += 1
		if kind == PlanetGeology.Type.IGNEOUS:
			igneous += 1
		if i < 2048:
			hash_context.update(("%d:%.6f:%.6f;" % [int(sample.x), sample.y, sample.z]).to_utf8_buffer())
	var mixed_query_ms := (Time.get_ticks_usec() - started) / 1000.0
	started = Time.get_ticks_usec()
	var query_checksum := 0.0
	for i in range(directions.size()):
		var sample := geology.sample_with_surface(directions[i], surfaces[i])
		query_checksum += sample.x + sample.y + sample.z
	var pure_query_ms := (Time.get_ticks_usec() - started) / 1000.0
	check(query_checksum > 0.0, "consulta precomputada")
	check(changed > 100, "subseed altera distribuição")
	check(land_province > ocean_province * 8, "províncias continentais preferem terra")
	check(igneous > 0 and igneous < directions.size() / 20, "ígneo localizado")
	var types_present := 0
	for count in counts:
		if count > 0:
			types_present += 1
	check(types_present >= 5, "diversidade de tipos")
	var largest := 0
	for count in counts:
		largest = maxi(largest, count)
	check(largest < directions.size() * 0.9, "nenhum tipo domina por bug")
	# Ordem oposta: mesmas amostras em outra sequência.
	for i in range(2047, -1, -1):
		var sample := geology.sample(directions[i])
		check(sample == same.sample(directions[i]), "ordem reversa %d" % i)
	# As doze arestas e oito cantos físicos usam coordenadas de face/LOD distintas.
	var edge_checks := 0
	var corner_checks := 0
	for face in range(6):
		for side in range(4):
			for step in range(33):
				var t := float(step) / 32.0
				var uv := Vector2(0.0, t) if side == 0 else (Vector2(1.0, t) if side == 1 else (Vector2(t, 0.0) if side == 2 else Vector2(t, 1.0)))
				var d := CubeSphereMapping.face_uv_to_direction(face, uv)
				var result := geology.sample(d)
				for adjacent in range(6):
					if adjacent == face:
						continue
					for adjacent_side in range(4):
						for flip in range(2):
							var u := t if flip == 0 else 1.0 - t
							var other_uv := Vector2(0.0, u) if adjacent_side == 0 else (Vector2(1.0, u) if adjacent_side == 1 else (Vector2(u, 0.0) if adjacent_side == 2 else Vector2(u, 1.0)))
							var other_d := CubeSphereMapping.face_uv_to_direction(adjacent, other_uv)
							if d.distance_to(other_d) < 0.000001:
								check(result == geology.sample(other_d), "borda/canto face %d/%d" % [face, adjacent])
								edge_checks += 1
								if step == 0 or step == 32:
									corner_checks += 1
	check(edge_checks >= 12 * 33, "12 arestas cobertas")
	check(corner_checks >= 8 * 3, "8 cantos cobertos")
	# Mesmo ponto físico reaparece em malhas de diferentes profundidades.
	for depth in [0, 1, 2, 4, 8]:
		var d := CubeSphereMapping.face_uv_to_direction(0, Vector2(0.5, 0.5))
		check(geology.sample(d) == geology.sample_with_surface(d, shape.sample_components(d)), "LOD %d" % depth)
	# Suavidade de campos numéricos perto de mudanças discretas de província.
	var boundaries := 0
	for i in range(0, 2048, 2):
		var a := directions[i]
		var b := (a + Vector3(0.025, -0.017, 0.013)).normalized()
		if int(geology.sample(a).x) == int(geology.sample(b).x):
			continue
		for iteration in range(14):
			var mid := (a + b).normalized()
			if int(geology.sample(mid).x) == int(geology.sample(a).x):
				a = mid
			else:
				b = mid
		var left := geology.sample(a)
		var right := geology.sample(b)
		check(absf(left.y - right.y) < 0.005, "idade contínua")
		check(absf(left.z - right.z) < 0.01, "influência contínua")
		boundaries += 1
	check(boundaries >= 10, "fronteiras de província encontradas")
	# Geometria antiga versus nova: atributos naturais, índices e AABB iguais.
	var legacy := PlanetChunkBuilder.new(definition, 0, 2, Vector2i(1, 1), 17)
	legacy.build()
	var integrated := PlanetChunkBuilder.new(definition, 0, 2, Vector2i(1, 1), 17, geology)
	integrated.build()
	for slot in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_COLOR, Mesh.ARRAY_INDEX]:
		check(legacy.result.arrays[slot] == integrated.result.arrays[slot], "malha natural slot %d" % slot)
	check(legacy.result.bounds == integrated.result.bounds, "AABB natural")
	check(legacy.result.error_m == integrated.result.error_m, "erro LOD natural")
	var shared_debug := PackedFloat32Array()
	for depth in [0, 1, 2, 4, 8]:
		var cell: Vector2i = Vector2i.ZERO if depth == 0 else Vector2i.ONE * (1 << (depth - 1))
		var builder := PlanetChunkBuilder.new(definition, 0, depth, cell, 17, geology)
		builder.build()
		var attributes: PackedFloat32Array = builder.result.arrays[Mesh.ARRAY_CUSTOM0]
		var vertex_index := 8 + 8 * 17 if depth == 0 else 0
		var values := attributes.slice(vertex_index * 4, vertex_index * 4 + 4)
		if shared_debug.is_empty():
			shared_debug = values
		else:
			check(values == shared_debug, "mesma direção no payload de chunk/LOD %d" % depth)
	var legacy_times: Array[float] = []
	var integrated_times: Array[float] = []
	for face in range(6):
		for depth in [0, 4]:
			var old_builder := PlanetChunkBuilder.new(definition, face, depth, Vector2i.ZERO, 17)
			old_builder.build()
			var new_builder := PlanetChunkBuilder.new(definition, face, depth, Vector2i.ZERO, 17, geology)
			new_builder.build()
			legacy_times.append(old_builder.result.build_ms)
			integrated_times.append(new_builder.result.build_ms)
	legacy_times.sort()
	integrated_times.sort()
	var worker_directions: Array[Vector3] = []
	var worker_surfaces: Array[Vector4] = []
	for i in range(1024):
		worker_directions.append(directions[i])
		worker_surfaces.append(shape.sample_components(directions[i]))
	var worker_a := ReadWorker.new(geology, worker_directions, worker_surfaces)
	var worker_b := ReadWorker.new(geology, worker_directions, worker_surfaces)
	var task_a := WorkerThreadPool.add_task(worker_a.run)
	var task_b := WorkerThreadPool.add_task(worker_b.run)
	WorkerThreadPool.wait_for_task_completion(task_a)
	WorkerThreadPool.wait_for_task_completion(task_b)
	check(worker_a.checksum == worker_b.checksum, "consultas concorrentes somente leitura")
	fingerprint = hash_context.finish().hex_encode()
	print("GEOLOGY fingerprint=%s" % fingerprint)
	print("GEOLOGY descriptors=%d types=%s land=%d ocean=%d igneous=%d boundaries=%d edges=%d corners=%d" % [geology.descriptors().size(), str(counts), land_province, ocean_province, igneous, boundaries, edge_checks, corner_checks])
	print("GEOLOGY construction_ms=%.3f mixed_8192_ms=%.3f pure_8192_ms=%.3f chunks_12_median_ms=%.3f/%.3f chunks_12_p95_ms=%.3f/%.3f" % [construction_ms, mixed_query_ms, pure_query_ms, legacy_times[5], integrated_times[5], legacy_times[10], integrated_times[10]])
	print("GEOLOGY checks=%d failures=%d" % [checks, failures.size()])
	for failure in failures.slice(0, 20):
		push_error(failure)
	quit(0 if failures.is_empty() else 1)

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
