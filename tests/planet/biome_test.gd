extends SceneTree

class ReadWorker:
	extends RefCounted
	var biomes: PlanetBiomes
	var directions: Array[Vector3]
	var surfaces: Array[Vector4]
	var climates: Array[PlanetClimateSample]
	var checksum := 0.0
	func _init(service: PlanetBiomes, points: Array[Vector3], fields: Array[Vector4],
			weather: Array[PlanetClimateSample]) -> void:
		biomes = service
		directions = points
		surfaces = fields
		climates = weather
	func run() -> void:
		var result := PlanetBiomeSample.new()
		for i in range(directions.size()):
			biomes.sample_with_context_into(directions[i], surfaces[i], climates[i], result)
			checksum += result.dominant_weight + result.secondary_weight + result.regional_slope

var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	var definition: PlanetDefinition = load("res://systems/planet/surface/data/test_planet_100km.tres")
	var shape := PlanetShape.new(definition)
	var geology := PlanetGeology.new(definition)
	var climate := PlanetClimate.new(definition)
	var directions: Array[Vector3] = []
	var surfaces: Array[Vector4] = []
	var heights := PackedFloat64Array()
	var before_builder := PlanetChunkBuilder.new(definition, 0, 2, Vector2i(1, 1), 17, geology)
	before_builder.build()
	for i in range(8192):
		var y := 1.0 - 2.0 * (float(i) + 0.5) / 8192.0
		var angle := float(i) * 2.399963229728653
		var radial := sqrt(1.0 - y * y)
		var d := Vector3(cos(angle) * radial, y, sin(angle) * radial)
		directions.append(d)
		surfaces.append(shape.sample_components(d))
		heights.append(shape.sample_base_height(d))
	var start := Time.get_ticks_usec()
	var biomes := PlanetBiomes.new(definition, climate, geology)
	var construction_ms := (Time.get_ticks_usec() - start) / 1000.0
	var same := PlanetBiomes.new(definition, climate, geology)
	var weather := PlanetClimateSample.new()
	var result := PlanetBiomeSample.new()
	var second := PlanetBiomeSample.new()
	var fingerprint := HashingContext.new()
	fingerprint.start(HashingContext.HASH_SHA256)
	var counts := PackedInt32Array()
	counts.resize(10)
	var lat_counts: Array[PackedInt32Array] = []
	var alt_counts: Array[PackedInt32Array] = []
	var temp_counts: Array[PackedInt32Array] = []
	var humidity_counts: Array[PackedInt32Array] = []
	for i in range(4):
		var row := PackedInt32Array()
		row.resize(10)
		lat_counts.append(row)
		alt_counts.append(row.duplicate())
		temp_counts.append(row.duplicate())
		humidity_counts.append(row.duplicate())
	var worker_points: Array[Vector3] = []
	var worker_surfaces: Array[Vector4] = []
	var worker_weather: Array[PlanetClimateSample] = []
	var land := 0
	var ocean := 0
	var max_slope := 0.0
	var max_wetland_slope := 0.0
	var max_wetland_altitude := 0.0
	var min_alpine_altitude := INF
	var min_polar_latitude := INF
	var salar_in_basin := 0
	var igneous_land := 0
	start = Time.get_ticks_usec()
	for i in range(directions.size()):
		var d := directions[i]
		var surface := surfaces[i]
		climate.sample_with_surface_into(d, surface, weather)
		var geological := geology.sample_with_surface(d, surface)
		biomes.sample_with_context_into(d, surface, weather, result)
		same.sample_with_context_into(d, surface, weather, second)
		check(_same(result, second), "determinismo %d" % i)
		check(heights[i] == shape.sample_base_height(d), "base_height intacta %d" % i)
		if i < 1024:
			worker_points.append(d)
			worker_surfaces.append(surface)
			var copied := PlanetClimateSample.new()
			copied.temperature_c = weather.temperature_c
			copied.humidity = weather.humidity
			copied.precipitation = weather.precipitation
			copied.ocean_influence = weather.ocean_influence
			copied.altitude_m = weather.altitude_m
			worker_weather.append(copied)
		if i < 2048:
			fingerprint.update(("%d:%d:%.6f:%.6f:%s;" % [result.dominant,
				result.secondary, result.dominant_weight, result.secondary_weight,
				str(result.weights)]).to_utf8_buffer())
		if surface.x <= definition.sea_level_m:
			ocean += 1
			check(result.is_water() and result.weights.count(0.0) == 10,
				"água sem bioma terrestre %d" % i)
			continue
		land += 1
		if int(geological.w) == PlanetGeology.Type.IGNEOUS:
			igneous_land += 1
		var total := 0.0
		for score in result.weights:
			check(_finite(score) and score >= 0.0 and score <= 1.0,
				"peso finito/limitado %d" % i)
			total += score
		check(absf(total - 1.0) < 0.00001, "pesos normalizados %d" % i)
		check(result.dominant >= 0 and result.dominant < 10 and
			result.secondary >= 0 and result.secondary < 10 and
			result.dominant_weight >= result.secondary_weight, "top dois válidos %d" % i)
		max_slope = maxf(max_slope, result.regional_slope)
		counts[result.dominant] += 1
		if result.dominant == PlanetBiomes.Biome.WETLAND:
			max_wetland_slope = maxf(max_wetland_slope, result.regional_slope)
			max_wetland_altitude = maxf(max_wetland_altitude, weather.altitude_m)
		elif result.dominant == PlanetBiomes.Biome.ALPINE:
			min_alpine_altitude = minf(min_alpine_altitude, weather.altitude_m)
		elif result.dominant == PlanetBiomes.Biome.POLAR:
			min_polar_latitude = minf(min_polar_latitude, absf(d.y))
		elif result.dominant == PlanetBiomes.Biome.SALAR and int(geological.w) == PlanetGeology.Type.CLOSED_BASIN:
			salar_in_basin += 1
		lat_counts[mini(3, int(absf(d.y) * 4.0))][result.dominant] += 1
		var alt_band := 0 if weather.altitude_m < 150.0 else (1 if weather.altitude_m < 350.0 else (2 if weather.altitude_m < 550.0 else 3))
		alt_counts[alt_band][result.dominant] += 1
		var temp_band := 0 if weather.temperature_c < -15.0 else (1 if weather.temperature_c < 0.0 else (2 if weather.temperature_c < 15.0 else 3))
		temp_counts[temp_band][result.dominant] += 1
		humidity_counts[mini(3, int(weather.humidity * 4.0))][result.dominant] += 1
	var mixed_ms := (Time.get_ticks_usec() - start) / 1000.0
	check(land > 3000 and ocean > 3000, "amostragem global plausível")
	var pure_start := Time.get_ticks_usec()
	var checksum := 0.0
	for i in range(directions.size()):
		climate.sample_with_surface_into(directions[i], surfaces[i], weather)
		biomes.sample_with_context_into(directions[i], surfaces[i], weather, result)
		checksum += result.dominant_weight + result.secondary_weight
	var context_ms := (Time.get_ticks_usec() - pure_start) / 1000.0
	check(checksum > 0.0, "consulta de contexto executada")
	pure_start = Time.get_ticks_usec()
	checksum = 0.0
	for i in range(worker_points.size()):
		biomes.sample_with_context_into(worker_points[i], worker_surfaces[i],
			worker_weather[i], result)
		checksum += result.dominant_weight
	var isolated_1024_ms := (Time.get_ticks_usec() - pure_start) / 1000.0
	check(checksum > 0.0, "bioma isolado executado")
	pure_start = Time.get_ticks_usec()
	checksum = 0.0
	for i in range(1024):
		var direct := biomes.sample(directions[i])
		checksum += direct.dominant_weight
	var direct_1024_ms := (Time.get_ticks_usec() - pure_start) / 1000.0
	check(checksum > 0.0, "API completa executada")
	for i in range(1023, -1, -1):
		biomes.sample_with_context_into(worker_points[i], worker_surfaces[i],
			worker_weather[i], result)
		biomes.sample_into(worker_points[i], second)
		check(_same(result, second), "ordem de consulta/API direta %d" % i)
	_test_controls(biomes)
	var edges := 0
	var corners := 0
	for face in range(6):
		for side in range(4):
			for step in range(33):
				var t := float(step) / 32.0
				var a := CubeSphereMapping.face_uv_to_direction(face, _edge_uv(side, t))
				biomes.sample_into(a, result)
				for adjacent in range(6):
					if adjacent == face:
						continue
					for adjacent_side in range(4):
						for flip in range(2):
							var b := CubeSphereMapping.face_uv_to_direction(adjacent,
								_edge_uv(adjacent_side, t if flip == 0 else 1.0 - t))
							if a.distance_to(b) < 0.000001:
								biomes.sample_into(b, second)
								check(_weights_near(result, second, 0.0003), "borda/canto sem seam")
								edges += 1
								if step == 0 or step == 32:
									corners += 1
	check(edges >= 12 * 33 and corners >= 8 * 3, "12 bordas/8 cantos")
	for face in range(6):
		for uv in [Vector2(0.375, 0.625), Vector2(0.5, 0.5), Vector2(0.125, 0.875)]:
			var reference := CubeSphereMapping.face_uv_to_direction(face, uv)
			biomes.sample_into(reference, result)
			for depth in [0, 1, 2, 4, 8, 9]:
				var patch_count: int = 1 << int(depth)
				var cell := Vector2i(floori(uv.x * patch_count), floori(uv.y * patch_count))
				var local_uv := Vector2(uv.x * patch_count - cell.x, uv.y * patch_count - cell.y)
				var d := CubeSphereMapping.face_uv_to_direction(face,
					(Vector2(cell) + local_uv) / float(patch_count))
				biomes.sample_into(d, second)
				check(d.distance_to(reference) < 0.000001 and _weights_near(result, second, 0.0003),
					"mesma direção no LOD %d" % depth)
	var worker_a := ReadWorker.new(biomes, worker_points, worker_surfaces, worker_weather)
	var worker_b := ReadWorker.new(biomes, worker_points, worker_surfaces, worker_weather)
	var task_a := WorkerThreadPool.add_task(worker_a.run)
	var task_b := WorkerThreadPool.add_task(worker_b.run)
	WorkerThreadPool.wait_for_task_completion(task_a)
	WorkerThreadPool.wait_for_task_completion(task_b)
	check(worker_a.checksum == worker_b.checksum, "workers simultâneos somente leitura")
	var after_builder := PlanetChunkBuilder.new(definition, 0, 2, Vector2i(1, 1), 17, geology)
	after_builder.build()
	for slot in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TEX_UV,
			Mesh.ARRAY_COLOR, Mesh.ARRAY_CUSTOM0, Mesh.ARRAY_INDEX]:
		check(before_builder.result.arrays[slot] == after_builder.result.arrays[slot],
			"malha natural slot %d" % slot)
	check(before_builder.result.bounds == after_builder.result.bounds and
		before_builder.result.error_m == after_builder.result.error_m,
		"bounds/erro LOD intactos")
	var present := 0
	for count in counts:
		if count > 0:
			present += 1
	check(present >= 7, "diversidade coerente de biomas no planeta atual")
	check(counts[PlanetBiomes.Biome.POLAR] < land / 2, "polar não domina a terra")
	check(counts[PlanetBiomes.Biome.DESERT] > 0, "deserto emerge da aridez real")
	check(max_wetland_slope < 0.15 and max_wetland_altitude < 300.0,
		"pântano dominante localizado em planície")
	check(min_alpine_altitude > 320.0, "alpino dominante acima de planície")
	check(min_polar_latitude > 0.57, "polar dominante fora de baixa latitude")
	check(igneous_land > 0, "região ígnea mantém bioma climático normal")
	print("BIOME fingerprint=", fingerprint.finish().hex_encode())
	print("BIOME_GLOBAL ", JSON.stringify({"land": land, "ocean": ocean,
		"names": PlanetBiomes.NAMES, "counts": counts, "percent": _percent(counts, land),
		"present": present, "max_regional_slope": max_slope,
		"max_wetland_slope": max_wetland_slope,
		"max_wetland_altitude_m": max_wetland_altitude,
		"min_alpine_altitude_m": min_alpine_altitude,
		"min_polar_abs_y": min_polar_latitude,
		"salar_in_closed_basin": salar_in_basin,
		"igneous_land_samples": igneous_land,
		"latitude": lat_counts, "altitude": alt_counts,
		"temperature": temp_counts, "humidity": humidity_counts}))
	print("BIOME_PERFORMANCE construction_ms=%.3f mixed_8192_ms=%.3f context_8192_ms=%.3f isolated_1024_ms=%.3f direct_1024_ms=%.3f chunk_before_ms=%.3f chunk_after_ms=%.3f" % [
		construction_ms, mixed_ms, context_ms, isolated_1024_ms, direct_1024_ms,
		before_builder.result.build_ms, after_builder.result.build_ms])
	print("BIOME checks=%d failures=%d edges=%d corners=%d" % [checks, failures.size(), edges, corners])
	for failure in failures.slice(0, 20):
		push_error("BIOME_TEST_FAILED: " + failure)
	quit(0 if failures.is_empty() else 1)

func _test_controls(biomes: PlanetBiomes) -> void:
	var weather := PlanetClimateSample.new()
	var result := PlanetBiomeSample.new()
	var other := PlanetBiomeSample.new()
	var d := Vector3(0.86, 0.35, 0.36).normalized()
	var land := Vector4(80.0, 1.0, 0.0, 0.0)
	var tropical_land := Vector4(280.0, 1.0, 0.0, 0.0)
	weather.temperature_c = 28.0
	weather.humidity = 0.95
	weather.precipitation = 0.82
	weather.ocean_influence = 0.5
	biomes.classify_with_slope_into(d, tropical_land, weather, 0.0, 0.01, result)
	check(result.dominant == PlanetBiomes.Biome.TROPICAL_WET, "tropical quente/úmido")
	weather.humidity = 0.14
	weather.precipitation = 0.10
	biomes.classify_with_slope_into(d, tropical_land, weather, 0.0, 0.01, other)
	check(other.weights[PlanetBiomes.Biome.TROPICAL_WET] < result.weights[PlanetBiomes.Biome.TROPICAL_WET],
		"tropical exige água")
	weather.temperature_c = 18.0
	weather.humidity = 0.24
	weather.precipitation = 0.17
	biomes.classify_with_slope_into(d, land, weather, 0.0, 0.01, result)
	check(result.dominant == PlanetBiomes.Biome.DESERT, "deserto árido, não só quente")
	weather.humidity = 0.01
	weather.precipitation = 0.01
	biomes.classify_with_slope_into(d, land, weather, 0.90, 0.01, result)
	biomes.classify_with_slope_into(d, land, weather, 0.0, 0.01, other)
	check(result.dominant == PlanetBiomes.Biome.SALAR and
		result.weights[PlanetBiomes.Biome.SALAR] > other.weights[PlanetBiomes.Biome.SALAR],
		"salar exige aridez extrema e favorece bacia fechada")
	weather.humidity = 0.95
	weather.precipitation = 0.80
	biomes.classify_with_slope_into(d, land, weather, 0.90, 0.01, other)
	check(other.weights[PlanetBiomes.Biome.SALAR] < result.weights[PlanetBiomes.Biome.SALAR],
		"bacia úmida não vira salar")
	weather.temperature_c = 18.0
	biomes.classify_with_slope_into(d, land, weather, 0.0, 0.01, result)
	biomes.classify_with_slope_into(d, land, weather, 0.0, 0.30, other)
	check(result.dominant == PlanetBiomes.Biome.WETLAND and
		other.weights[PlanetBiomes.Biome.WETLAND] < result.weights[PlanetBiomes.Biome.WETLAND],
		"pântano exige planície baixa, plana e úmida")
	biomes.classify_with_slope_into(d, Vector4(500.0, 1.0, 0.0, 0.0), weather, 0.0, 0.01, other)
	check(other.weights[PlanetBiomes.Biome.WETLAND] < result.weights[PlanetBiomes.Biome.WETLAND],
		"pântano não ocupa alto planalto")
	weather.temperature_c = -5.0
	weather.humidity = 0.45
	weather.precipitation = 0.35
	biomes.classify_with_slope_into(d, Vector4(760.0, 1.0, 0.9, 0.0), weather, 0.0, 0.23, result)
	biomes.classify_with_slope_into(d, land, weather, 0.0, 0.01, other)
	check(result.dominant == PlanetBiomes.Biome.ALPINE and
		other.weights[PlanetBiomes.Biome.ALPINE] == 0.0,
		"alpino exige altitude e montanha")
	weather.temperature_c = -27.0
	biomes.classify_with_slope_into(Vector3(0.1, 0.97, 0.2), land, weather, 0.0, 0.01, result)
	biomes.classify_with_slope_into(Vector3(0.86, 0.1, 0.36), land, weather, 0.0, 0.01, other)
	check(result.dominant == PlanetBiomes.Biome.POLAR and
		other.weights[PlanetBiomes.Biome.POLAR] < result.weights[PlanetBiomes.Biome.POLAR],
		"polar exige frio extremo e latitude coerente")
	biomes.classify_with_slope_into(d, Vector4(-2.0, 0.0, 0.0, 0.0), weather, 0.0, 0.01, result)
	check(result.is_water() and result.weights.count(0.0) == 10, "oceano sem bioma")
	# Fronteira de bacia estrutural usa queda contínua, mesmo que o ID de
	# província geológica dominante troque naquele ponto.
	weather.temperature_c = 20.0
	weather.humidity = 0.01
	weather.precipitation = 0.01
	for i in range(biomes._basin_centers.size()):
		var center := biomes._basin_centers[i]
		var axis := center.cross(Vector3.UP)
		if axis.length_squared() < 0.000001:
			axis = center.cross(Vector3.RIGHT)
		axis = axis.normalized()
		var radius := biomes._basin_radii[i]
		var angle := 2.0 * asin(radius * 0.5)
		var inside := center.rotated(axis, angle - 0.0001)
		var outside := center.rotated(axis, angle + 0.0001)
		var basin_inside := biomes._basin_influence(inside)
		var basin_outside := biomes._basin_influence(outside)
		biomes.classify_with_slope_into(inside, land, weather, basin_inside, 0.01, result)
		biomes.classify_with_slope_into(outside, land, weather, basin_outside, 0.01, other)
		check(absf(basin_inside - basin_outside) < 0.01 and \
			_weights_near(result, other, 0.01), "peso contínuo na borda da bacia %d" % i)

static func _same(a: PlanetBiomeSample, b: PlanetBiomeSample) -> bool:
	return a.dominant == b.dominant and a.secondary == b.secondary and \
		a.weights == b.weights and a.regional_slope == b.regional_slope

static func _weights_near(a: PlanetBiomeSample, b: PlanetBiomeSample, tolerance: float) -> bool:
	for i in range(10):
		if absf(a.weights[i] - b.weights[i]) > tolerance:
			return false
	return true

static func _edge_uv(side: int, t: float) -> Vector2:
	match side:
		0: return Vector2(0.0, t)
		1: return Vector2(1.0, t)
		2: return Vector2(t, 0.0)
	return Vector2(t, 1.0)

static func _percent(values: PackedInt32Array, total: int) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	for value in values:
		result.append(100.0 * value / float(total))
	return result

static func _finite(value: float) -> bool:
	return not is_nan(value) and not is_inf(value)

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
