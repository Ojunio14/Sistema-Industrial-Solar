extends SceneTree

class ReadWorker:
	extends RefCounted
	var climate: PlanetClimate
	var points: Array[Vector3]
	var fields: Array[Vector4]
	var checksum := 0.0
	func _init(source: PlanetClimate, directions: Array[Vector3], surfaces: Array[Vector4]) -> void:
		climate = source
		points = directions
		fields = surfaces
	func run() -> void:
		var output := PlanetClimateSample.new()
		for i in range(points.size()):
			climate.sample_with_surface_into(points[i], fields[i], output)
			checksum += output.temperature_c + output.humidity + output.rain_shadow

var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	var definition: PlanetDefinition = load("res://systems/planet/surface/data/test_planet_100km.tres")
	var shape := PlanetShape.new(definition)
	var directions: Array[Vector3] = []
	var surfaces: Array[Vector4] = []
	var heights := PackedFloat64Array()
	var before_builder := PlanetChunkBuilder.new(definition, 0, 2, Vector2i(1, 1), 17,
		PlanetGeology.new(definition))
	before_builder.build()
	for i in range(8192):
		var y := 1.0 - 2.0 * (float(i) + 0.5) / 8192.0
		var angle := float(i) * 2.399963229728653
		var radial := sqrt(1.0 - y * y)
		var direction := Vector3(cos(angle) * radial, y, sin(angle) * radial)
		directions.append(direction)
		heights.append(shape.sample_base_height(direction))
		surfaces.append(shape.sample_components(direction))
	var started := Time.get_ticks_usec()
	var climate := PlanetClimate.new(definition)
	var build_ms := (Time.get_ticks_usec() - started) / 1000.0
	var same := PlanetClimate.new(definition)
	var other := PlanetClimate.new(definition, (definition.seed ^ PlanetClimate.SEED_SALT) + 1)
	var output := PlanetClimateSample.new()
	var second := PlanetClimateSample.new()
	var alternate := PlanetClimateSample.new()
	var fingerprint := HashingContext.new()
	fingerprint.start(HashingContext.HASH_SHA256)
	var different := 0
	var land := 0
	var coastal := 0
	var inland := 0
	var coastal_ocean := 0.0
	var inland_ocean := 0.0
	var min_temp := INF
	var max_temp := -INF
	var sum_temp := 0.0
	var min_humidity := INF
	var max_humidity := -INF
	var sum_humidity := 0.0
	var min_precip := INF
	var max_precip := -INF
	var sum_precip := 0.0
	var min_continental := INF
	var max_continental := -INF
	var sum_continental := 0.0
	var max_shadow := 0.0
	var latitude_counts := PackedInt32Array([0, 0, 0, 0])
	var latitude_temp := PackedFloat64Array([0, 0, 0, 0])
	var latitude_humidity := PackedFloat64Array([0, 0, 0, 0])
	var altitude_counts := PackedInt32Array([0, 0, 0])
	var altitude_temp := PackedFloat64Array([0, 0, 0])
	var altitude_humidity := PackedFloat64Array([0, 0, 0])
	started = Time.get_ticks_usec()
	for i in range(directions.size()):
		var d := directions[i]
		var surface := surfaces[i]
		climate.sample_with_surface_into(d, surface, output)
		same.sample_with_surface_into(d, surface, second)
		other.sample_with_surface_into(d, surface, alternate)
		check(output.fields() == second.fields() and output.rain_shadow == second.rain_shadow,
			"mesma seed/direção %d" % i)
		check(heights[i] == shape.sample_base_height(d), "base_height intacta %d" % i)
		check(_finite(output.temperature_c) and _finite(output.humidity) and
			_finite(output.precipitation) and _finite(output.ocean_influence) and
			_finite(output.rain_shadow) and _finite(output.altitude_m), "campos finitos %d" % i)
		check(output.humidity >= 0.0 and output.humidity <= 1.0 and
			output.precipitation >= 0.0 and output.precipitation <= 1.0 and
			output.ocean_influence >= 0.0 and output.ocean_influence <= 1.0 and
			output.rain_shadow >= 0.0 and output.rain_shadow <= 1.0, "índices limitados %d" % i)
		if output.fields() != alternate.fields():
			different += 1
		if i < 2048:
			fingerprint.update(("%.5f:%.6f:%.6f:%.6f:%.6f;" % [output.temperature_c,
				output.humidity, output.ocean_influence, output.precipitation,
				output.rain_shadow]).to_utf8_buffer())
		if surface.x <= definition.sea_level_m:
			continue
		land += 1
		min_temp = minf(min_temp, output.temperature_c)
		max_temp = maxf(max_temp, output.temperature_c)
		sum_temp += output.temperature_c
		min_humidity = minf(min_humidity, output.humidity)
		max_humidity = maxf(max_humidity, output.humidity)
		sum_humidity += output.humidity
		min_precip = minf(min_precip, output.precipitation)
		max_precip = maxf(max_precip, output.precipitation)
		sum_precip += output.precipitation
		var continental := 1.0 - output.ocean_influence
		min_continental = minf(min_continental, continental)
		max_continental = maxf(max_continental, continental)
		sum_continental += continental
		max_shadow = maxf(max_shadow, output.rain_shadow)
		var lat_band := mini(3, int(absf(d.y) * 4.0))
		var alt_band := 0 if output.altitude_m < 150.0 else (1 if output.altitude_m < 450.0 else 2)
		latitude_counts[lat_band] += 1
		latitude_temp[lat_band] += output.temperature_c
		latitude_humidity[lat_band] += output.humidity
		altitude_counts[alt_band] += 1
		altitude_temp[alt_band] += output.temperature_c
		altitude_humidity[alt_band] += output.humidity
		if output.ocean_influence > 0.75:
			coastal += 1
			coastal_ocean += output.ocean_influence
		if output.ocean_influence < 0.35:
			inland += 1
			inland_ocean += output.ocean_influence
	var mixed_ms := (Time.get_ticks_usec() - started) / 1000.0
	check(different > 100, "subseed climática altera clima sem alterar relevo")
	check(coastal > 20 and inland > 20 and coastal_ocean / coastal > inland_ocean / inland,
		"costa e interior encontrados no planeta atual")
	check(max_shadow > 0.05, "sombra de chuva observável")
	var north := climate.sample(Vector3.UP)
	var south := climate.sample(Vector3.DOWN)
	print("CLIMATE_POLES north=", north.fields(), " south=", south.fields())
	# Controles causais sem mudar latitude, relevo e superfície natural.
	for ocean in [0.0, 0.5, 1.0]:
		var equator := PlanetClimate.temperature_at(0.0, 200.0, ocean)
		var middle := PlanetClimate.temperature_at(0.55, 200.0, ocean)
		var pole := PlanetClimate.temperature_at(0.95, 200.0, ocean)
		check(equator > middle and middle > pole, "latitude controlada")
		check(absf(PlanetClimate.temperature_at(0.4, 0.0, ocean) -
			PlanetClimate.temperature_at(0.4, 1000.0, ocean) - 6.5) < 0.00001,
			"gradiente altitudinal controlado")
	var interior_direction := Vector3.ZERO
	for i in range(directions.size()):
		climate.sample_with_surface_into(directions[i], surfaces[i], output)
		if surfaces[i].x > 70.0 and output.ocean_influence < 0.35:
			interior_direction = directions[i]
			break
	check(not interior_direction.is_zero_approx(), "controle interior encontrado")
	if not interior_direction.is_zero_approx():
		climate.sample_with_surface_into(interior_direction, Vector4(130, 1, 0, 0), output)
		climate.sample_with_surface_into(interior_direction, Vector4(130, 0.1, 0, 0), second)
		check(second.ocean_influence > output.ocean_influence and second.humidity > output.humidity,
			"influência marítima aumenta umidade no controle")
	# Consulta direta e ordem inversa não mudam estado compartilhado.
	for i in range(1023, -1, -1):
		var q := climate.sample(directions[i])
		climate.sample_with_surface_into(directions[i], surfaces[i], output)
		check(q.fields() == output.fields() and q.rain_shadow == output.rain_shadow,
			"consulta direta/ordem inversa %d" % i)
	var pure_start := Time.get_ticks_usec()
	var checksum := 0.0
	for i in range(directions.size()):
		climate.sample_with_surface_into(directions[i], surfaces[i], output)
		checksum += output.temperature_c + output.humidity + output.rain_shadow
	var pure_ms := (Time.get_ticks_usec() - pure_start) / 1000.0
	check(checksum > 0.0, "consultas puras executadas")
	var direct_start := Time.get_ticks_usec()
	var direct_checksum := 0.0
	for d in directions:
		var direct := climate.sample(d)
		direct_checksum += direct.temperature_c + direct.humidity + direct.rain_shadow
	var direct_ms := (Time.get_ticks_usec() - direct_start) / 1000.0
	check(absf(direct_checksum - checksum) < 0.01, "sample direto equivale à consulta com superfície")
	var edge_checks := 0
	var corner_checks := 0
	for face in range(6):
		for side in range(4):
			for step in range(33):
				var t := float(step) / 32.0
				var uv := _edge_uv(side, t)
				var a := CubeSphereMapping.face_uv_to_direction(face, uv)
				climate.sample_into(a, output)
				for adjacent in range(6):
					if adjacent == face:
						continue
					for adjacent_side in range(4):
						for flip in range(2):
							var b := CubeSphereMapping.face_uv_to_direction(adjacent,
								_edge_uv(adjacent_side, t if flip == 0 else 1.0 - t))
							if a.distance_to(b) < 0.000001:
								climate.sample_into(b, second)
								check(output.fields().distance_to(second.fields()) < 0.0001 and
									absf(output.rain_shadow - second.rain_shadow) < 0.0001,
									"borda/canto sem seam")
								edge_checks += 1
								if step == 0 or step == 32:
									corner_checks += 1
	check(edge_checks >= 12 * 33 and corner_checks >= 8 * 3, "12 bordas e 8 cantos")
	for face in range(6):
		for uv in [Vector2(0.375, 0.625), Vector2(0.5, 0.5), Vector2(0.125, 0.875)]:
			var reference_direction := CubeSphereMapping.face_uv_to_direction(face, uv)
			climate.sample_into(reference_direction, output)
			var expected := output.fields()
			var expected_shadow := output.rain_shadow
			for depth in [0, 1, 2, 4, 8]:
				var patch_count: int = 1 << int(depth)
				var cell := Vector2i(floori(uv.x * patch_count), floori(uv.y * patch_count))
				var local_uv := Vector2(uv.x * patch_count - cell.x, uv.y * patch_count - cell.y)
				var chunk_uv := (Vector2(cell) + local_uv) / float(patch_count)
				var direction := CubeSphereMapping.face_uv_to_direction(face, chunk_uv)
				climate.sample_into(direction, second)
				check(direction.distance_to(reference_direction) < 0.000001 and
					second.fields().distance_to(expected) < 0.0001 and
					absf(second.rain_shadow - expected_shadow) < 0.0001,
					"mesma direção em vértice de face %d LOD %d" % [face, depth])
	# A malha natural e a geologia continuam exatamente as mesmas.
	var after_builder := PlanetChunkBuilder.new(definition, 0, 2, Vector2i(1, 1), 17,
		PlanetGeology.new(definition))
	after_builder.build()
	for slot in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TEX_UV,
		Mesh.ARRAY_COLOR, Mesh.ARRAY_CUSTOM0, Mesh.ARRAY_INDEX]:
		check(before_builder.result.arrays[slot] == after_builder.result.arrays[slot],
			"malha natural/geologia slot %d" % slot)
	check(before_builder.result.bounds == after_builder.result.bounds and
		before_builder.result.error_m == after_builder.result.error_m,
		"bounds/LOD error intactos")
	var worker_directions: Array[Vector3] = []
	var worker_surfaces: Array[Vector4] = []
	for i in range(1024):
		worker_directions.append(directions[i])
		worker_surfaces.append(surfaces[i])
	var worker_a := ReadWorker.new(climate, worker_directions, worker_surfaces)
	var worker_b := ReadWorker.new(climate, worker_directions, worker_surfaces)
	var task_a := WorkerThreadPool.add_task(worker_a.run)
	var task_b := WorkerThreadPool.add_task(worker_b.run)
	WorkerThreadPool.wait_for_task_completion(task_a)
	WorkerThreadPool.wait_for_task_completion(task_b)
	check(worker_a.checksum == worker_b.checksum, "consulta concorrente somente leitura")
	var shadow_result := _find_shadow_pair(climate, definition)
	check(shadow_result.found, "barlavento/sotavento reais reproduzíveis")
	var latitude_summary := []
	var altitude_summary := []
	for i in range(4):
		latitude_summary.append({"count": latitude_counts[i], "temperature_mean_c":
			latitude_temp[i] / maxf(1, latitude_counts[i]), "humidity_mean":
			latitude_humidity[i] / maxf(1, latitude_counts[i])})
	for i in range(3):
		altitude_summary.append({"count": altitude_counts[i], "temperature_mean_c":
			altitude_temp[i] / maxf(1, altitude_counts[i]), "humidity_mean":
			altitude_humidity[i] / maxf(1, altitude_counts[i])})
	print("CLIMATE fingerprint=", fingerprint.finish().hex_encode())
	print("CLIMATE_GLOBAL ", JSON.stringify({"land": land,
		"temperature_min_mean_max_c": [min_temp, sum_temp / land, max_temp],
		"humidity_min_mean_max": [min_humidity, sum_humidity / land, max_humidity],
		"precipitation_min_mean_max": [min_precip, sum_precip / land, max_precip],
		"continentality_min_mean_max": [min_continental, sum_continental / land, max_continental],
		"latitude": latitude_summary, "altitude": altitude_summary, "max_shadow": max_shadow,
		"coastal_samples": coastal, "interior_samples": inland, "shadow_pair": shadow_result}))
	print("CLIMATE_PERFORMANCE construction_ms=%.3f mixed_8192_ms=%.3f pure_8192_ms=%.3f direct_8192_ms=%.3f before_chunk_ms=%.3f after_chunk_ms=%.3f" % [
		build_ms, mixed_ms, pure_ms, direct_ms, before_builder.result.build_ms, after_builder.result.build_ms])
	print("CLIMATE checks=%d failures=%d edges=%d corners=%d" % [checks, failures.size(), edge_checks, corner_checks])
	for failure in failures.slice(0, 20):
		push_error("CLIMATE_TEST_FAILED: " + failure)
	quit(0 if failures.is_empty() else 1)

func _find_shadow_pair(climate: PlanetClimate, definition: PlanetDefinition) -> Dictionary:
	var lee := PlanetClimateSample.new()
	var upwind := PlanetClimateSample.new()
	for y in range(4, PlanetClimate.HEIGHT - 4):
		for x in range(PlanetClimate.WIDTH):
			var i := x + y * PlanetClimate.WIDTH
			if climate._heights[i] < 30.0 or climate._shadow[i] < 0.12:
				continue
			var d := PlanetClimate._grid_direction(x, y)
			if absf(d.y) > 0.8:
				continue
			var other := (d - PlanetClimate.prevailing_wind(d) * 0.10).normalized()
			var other_h := PlanetClimate._sample_grid(climate._heights, other)
			var other_mountain := PlanetClimate._sample_grid(climate._mountains, other)
			if other_h < 30.0 or other_mountain < 0.05:
				continue
			climate.sample_with_surface_into(d, Vector4(climate._heights[i] + definition.sea_level_m,
				climate._land[i], climate._mountains[i], 0.0), lee)
			climate.sample_with_surface_into(other, Vector4(other_h + definition.sea_level_m,
				PlanetClimate._sample_grid(climate._land, other), 0.0, 0.0), upwind)
			if lee.rain_shadow > upwind.rain_shadow + 0.07 and \
				lee.precipitation + 0.03 < upwind.precipitation:
				return {"found": true, "lee": d, "windward": other,
					"lee_altitude_m": climate._heights[i],
					"windward_altitude_m": other_h, "windward_mountain_mask": other_mountain,
					"lee_shadow": lee.rain_shadow, "windward_shadow": upwind.rain_shadow,
					"lee_precip": lee.precipitation, "windward_precip": upwind.precipitation}
	return {"found": false}

static func _edge_uv(side: int, t: float) -> Vector2:
	match side:
		0: return Vector2(0.0, t)
		1: return Vector2(1.0, t)
		2: return Vector2(t, 0.0)
	return Vector2(t, 1.0)

static func _finite(value: float) -> bool:
	return not is_nan(value) and not is_inf(value)

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
