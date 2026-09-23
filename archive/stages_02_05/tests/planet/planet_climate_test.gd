extends SceneTree

var failures := 0
var assertions := 0
var terrain: PlanetTerrain
var climate: PlanetClimate

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, context: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		if failures <= 20:
			push_error("CLIMATE_TEST_FAILED: " + context)

func _run() -> void:
	terrain = PlanetTerrain.new(73129, true)
	climate = PlanetClimate.new(73129, terrain)
	test_global()
	if not OS.get_cmdline_user_args().has("--determinism-only"):
		test_controls()
		test_determinism()
		test_ocean()
		test_shadow()
		test_biome_rules()
		test_controlled_biomes()
		test_continuity()
		test_mesh()
		await test_controller()
	print("CLIMATE_TEST_%s: %d assertions; failures=%d" % ["OK" if failures == 0 else "FAILED", assertions, failures])
	quit(0 if failures == 0 else 1)

func test_global() -> void:
	var counts := PackedInt32Array()
	counts.resize(10)
	var lat_counts := PackedInt32Array()
	lat_counts.resize(4)
	var high_counts := PackedInt32Array()
	high_counts.resize(3)
	var by_lat: Array[PackedInt32Array] = []
	var by_alt: Array[PackedInt32Array] = []
	for j in range(4):
		var row := PackedInt32Array()
		row.resize(10)
		by_lat.append(row)
	for j in range(3):
		var row := PackedInt32Array()
		row.resize(10)
		by_alt.append(row)
	var min_t := INF
	var max_t := -INF
	var mean_t := 0.0
	var min_h := INF
	var max_h := -INF
	var mean_h := 0.0
	var dry := 0
	var wet := 0
	var land := 0
	var max_salar_weight := 0.0
	var basin_land := 0
	var basin_min_rain := INF
	var fingerprint := HashingContext.new()
	fingerprint.start(HashingContext.HASH_SHA256)
	for i in range(16384):
		var d := PlanetTerrain.uniform_direction(i, 16384)
		var surface := terrain.sample_fields(d)
		var q := climate.query_direction(d)
		check(q.climate.is_finite() and is_finite(q.rain_shadow), "global climate finite")
		check(q.climate.y >= 0 and q.climate.y <= 1 and q.climate.z >= 0 and q.climate.z <= 1 and q.climate.w >= 0 and q.climate.w <= 1 and q.rain_shadow >= 0 and q.rain_shadow <= 1, "bounded climatic indices")
		if surface.x <= 0:
			check(q.dominant == -1 and q.secondary == -1, "water has no terrestrial biome")
		else:
			land += 1
			check(q.dominant >= 0 and q.dominant < 10, "land biome valid")
			var sum := 0.0
			for weight in q.weights:
				check(weight >= 0 and weight <= 1, "weight bounded")
				sum += weight
			check(absf(sum - 1.0) < 0.00001, "terrestrial weights normalized")
			counts[q.dominant] += 1
			var lat_band := mini(3, int(absf(d.y) * 4))
			var alt_band := 0 if surface.x < 250 else (1 if surface.x < 900 else 2)
			lat_counts[lat_band] += 1
			high_counts[alt_band] += 1
			by_lat[lat_band][q.dominant] += 1
			by_alt[alt_band][q.dominant] += 1
			max_salar_weight = maxf(max_salar_weight, q.weights[PlanetClimate.Biome.SALAR])
			for cap in climate._basins:
				if d.distance_to(Vector3(cap.x, cap.y, cap.z)) < cap.w * 0.7:
					basin_land += 1
					basin_min_rain = minf(basin_min_rain, q.climate.w)
			min_t = minf(min_t, q.climate.x)
			max_t = maxf(max_t, q.climate.x)
			mean_t += q.climate.x
			min_h = minf(min_h, q.climate.y)
			max_h = maxf(max_h, q.climate.y)
			mean_h += q.climate.y
			dry += int(q.climate.w < 0.18)
			wet += int(q.climate.w > 0.75)
		fingerprint.update(("%.4f/%.5f/%.5f/%.5f/%.5f/%d;" % [q.climate.x, q.climate.y, q.climate.z, q.climate.w, q.rain_shadow, q.dominant]).to_utf8_buffer())
	var percentages := {}
	for i in range(10):
		percentages[PlanetClimate.BIOME_NAMES[i]] = counts[i] * 100.0 / maxf(1, land)
		check(counts[i] < land * 0.85, "no biome dominates almost all land")
	print("CLIMATE_GLOBAL " + JSON.stringify({"fingerprint": fingerprint.finish().hex_encode(),
		"land": land, "biome_percent": percentages, "latitude_band_counts": lat_counts,
		"altitude_band_counts": high_counts, "biomes_by_latitude": by_lat, "biomes_by_altitude": by_alt,
		"temperature_min_mean_max_c": [min_t, mean_t / land, max_t],
		"humidity_min_mean_max": [min_h, mean_h / land, max_h], "very_dry": dry, "very_wet": wet,
		"closed_basin_land_samples": basin_land, "closed_basin_min_precipitation": basin_min_rain,
		"max_salar_weight": max_salar_weight}))

func test_controls() -> void:
	for ocean in [0.0, 0.5, 1.0]:
		for altitude in [0.0, 600.0, 1500.0]:
			var equator := PlanetClimate.temperature_at(0.0, altitude, ocean)
			var middle := PlanetClimate.temperature_at(0.55, altitude, ocean)
			var pole := PlanetClimate.temperature_at(1.0, altitude, ocean)
			check(equator > middle and middle > pole, "latitude cools at controlled altitude/ocean")
		for latitude in [0.0, 0.5, 1.0]:
			var sea_level := PlanetClimate.temperature_at(latitude, 0.0, ocean)
			check(absf(PlanetClimate.temperature_at(latitude, 1000.0, ocean) - (sea_level - 9.0)) < 0.00001, "explicit 9 C per km lapse")
	check(PlanetClimate.ocean_influence(-0.1) == 1.0, "ocean influence at sea")
	check(PlanetClimate.ocean_influence(0.01) > PlanetClimate.ocean_influence(0.3), "coast exceeds interior ocean influence")

func test_determinism() -> void:
	var same := PlanetClimate.new(73129, PlanetTerrain.new(73129, true))
	var other := PlanetClimate.new(73130, PlanetTerrain.new(73130, true))
	var samples: Array[PlanetClimateSample] = []
	var different := 0
	for i in range(1024):
		var d := PlanetTerrain.uniform_direction(i, 1024)
		var a := climate.query_direction(d)
		var b := same.query_direction(d)
		check(a.climate == b.climate and a.rain_shadow == b.rain_shadow and a.weights == b.weights and a.dominant == b.dominant, "same seed exact climate and weights")
		samples.append(a)
		different += int(a.climate != other.query_direction(d).climate)
	for i in range(1023, -1, -1):
		var d := PlanetTerrain.uniform_direction(i, 1024)
		var q := climate.query_direction(d)
		check(q.climate == samples[i].climate and q.weights == samples[i].weights, "order independent")
	check(different > 300, "different seed changes climate distribution")

func test_ocean() -> void:
	var coast_h := 0.0
	var interior_h := 0.0
	var coasts := 0
	var interiors := 0
	for i in range(8192):
		var d := PlanetTerrain.uniform_direction(i, 8192)
		var surface := terrain.sample_fields(d)
		if surface.x <= 0 or absf(d.y) > 0.6 or surface.x > 350:
			continue
		var q := climate.query_direction(d)
		if q.climate.z > 0.85:
			coasts += 1
			coast_h += q.climate.y
		elif q.climate.z < 0.20:
			interiors += 1
			interior_h += q.climate.y
	check(coasts > 40 and interiors > 40, "actual coastal and interior samples found")
	check(coast_h / maxf(1, coasts) > interior_h / maxf(1, interiors), "maritime moisture trend")
	# Causal control: same latitude/direction/elevation/wind, only signed
	# continental context changes. Coast must increase maritime humidity.
	var direction := Vector3(1.0, 0.2, 0.4).normalized()
	var near := PlanetClimateSample.new()
	var inland := PlanetClimateSample.new()
	climate.sample_into(direction, Vector4(180, .015, PlanetTerrain.Form.PLAIN, 0), near)
	climate.sample_into(direction, Vector4(180, .40, PlanetTerrain.Form.PLAIN, 0), inland)
	check(near.climate.z > inland.climate.z and near.climate.y > inland.climate.y,
		"same controlled terrain and latitude gain moisture from ocean context")

func test_shadow() -> void:
	var directional := 0
	for belt: PlanetClimate.Belt in climate._belts:
		for side: float in [-1.0, 1.0]:
			var a: Vector3 = (belt.center + belt.v * belt.width * side).normalized()
			var b: Vector3 = (belt.center - belt.v * belt.width * side).normalized()
			var qa := climate.query_direction(a)
			var qb := climate.query_direction(b)
			if qa.rain_shadow > qb.rain_shadow + 0.12 and qa.climate.w < qb.climate.w:
				directional += 1
	check(directional > 0, "real oriented belts produce drier lee than windward")

func test_biome_rules() -> void:
	var seen := {}
	var volcanic := 0
	for i in range(16384):
		var d := PlanetTerrain.uniform_direction(i, 16384)
		var surface := terrain.sample_fields(d)
		if surface.x <= 0:
			continue
		var q := climate.query_direction(d)
		seen[q.dominant] = true
		if q.dominant == PlanetClimate.Biome.POLAR:
			check(absf(d.y) > 0.65 and q.climate.x < -5.0, "polar requires cold high latitude")
		if q.dominant == PlanetClimate.Biome.ALPINE:
			check(surface.x > 580, "alpine requires mountain altitude")
		if q.dominant == PlanetClimate.Biome.SALAR:
			check(q.climate.w < 0.39, "salar requires aridity")
		if q.dominant == PlanetClimate.Biome.WETLAND:
			check(surface.x < 330 and q.climate.w > 0.5, "wetlands require low wet land")
		if PlanetGeology.type_of(int(terrain.geology.query_direction(d).x)) == PlanetGeology.Type.IGNEOUS:
			volcanic += 1
			check(q.dominant != -1 and q.dominant < 10, "igneous region retains climate biome")
	check(volcanic > 0, "igneous and climate overlap sampled")
	check(not PlanetClimate.BIOME_NAMES.has("Volcanic"), "no volcanic biome")
	print("CLIMATE_BIOMES_OBSERVED " + str(seen.keys()))

func test_controlled_biomes() -> void:
	# Controlled temperature, precipitation and terrain context. These cases
	# validate mechanisms rather than demanding arbitrary global percentages.
	var examples := [
		[30.0, .87, 500.0, .1, 1.0, 0.0, PlanetClimate.Biome.TROPICAL_WET],
		[27.0, .48, 400.0, .25, 0.0, 0.0, PlanetClimate.Biome.SAVANNA],
		[28.0, .20, 350.0, .4, 0.0, 0.0, PlanetClimate.Biome.DESERT],
		[27.0, .04, 150.0, .4, 0.0, 1.0, PlanetClimate.Biome.SALAR],
		[12.0, .58, 400.0, .5, 0.0, 0.0, PlanetClimate.Biome.TEMPERATE],
		[20.0, .92, 100.0, .2, 0.0, 0.0, PlanetClimate.Biome.WETLAND],
		[-3.0, .50, 200.0, .65, 0.0, 0.0, PlanetClimate.Biome.TAIGA],
		[-17.0, .40, 200.0, .7, 0.0, 0.0, PlanetClimate.Biome.TUNDRA],
		[0.0, .50, 1400.0, .4, 0.0, 0.0, PlanetClimate.Biome.ALPINE],
		[-27.0, .30, 100.0, .95, 0.0, 0.0, PlanetClimate.Biome.POLAR]
	]
	for example in examples:
		var result := PlanetClimateSample.new()
		result.climate = Vector4(example[0], example[1], .5, example[1])
		climate._classify(result, example[2], example[3], example[4], example[5])
		check(result.dominant == example[6], "controlled biome %s observed %s" % [PlanetClimate.BIOME_NAMES[example[6]], PlanetClimate.BIOME_NAMES[result.dominant]])
	var dry := PlanetClimateSample.new()
	dry.climate = Vector4(27, .05, .1, .05)
	climate._classify(dry, 150, .4, 0, 0)
	var basin := PlanetClimateSample.new()
	basin.climate = dry.climate
	climate._classify(basin, 150, .4, 0, 1)
	check(basin.weights[PlanetClimate.Biome.SALAR] > dry.weights[PlanetClimate.Biome.SALAR], "closed basin favors saline extreme desert under equal dry climate")
	var steep := PlanetClimateSample.new()
	steep.climate = Vector4(20, .95, .8, .95)
	climate._classify(steep, 100, .2, 1, 0)
	check(steep.weights[PlanetClimate.Biome.WETLAND] == 0, "wet steep terrain cannot become wetland")

func test_continuity() -> void:
	var corners := {}
	for face in range(6):
		for edge in range(4):
			var transition := PlanetTopology.get_edge_transition(face, edge)
			for i in range(33):
				var t := i / 32.0
				var a := PlanetMath.face_uv_to_direction(face, PlanetTopology.edge_uv(edge, t))
				var b := PlanetMath.face_uv_to_direction(transition.neighbor_face,
					PlanetTopology.edge_uv(transition.neighbor_edge, 1.0 - t if transition.is_reversed else t))
				var qa := climate.query_direction(a)
				var qb := climate.query_direction(b)
				check(qa.climate == qb.climate and qa.rain_shadow == qb.rain_shadow and qa.weights == qb.weights and qa.dominant == qb.dominant, "cube edge exact climate")
				if i == 0 or i == 32:
					corners[str(a.sign())] = true
	check(corners.size() == 8, "eight physical corners")
	for face in range(6):
		for level: int in [0, 1, 2, 4, 6, 17, 24]:
			var n := 1 << level
			for uv: Vector2 in [Vector2(.25, .75), Vector2(.5, .5), Vector2(1, 1)]:
				var ix := mini(int(uv.x * n), n - 1)
				var iy := mini(int(uv.y * n), n - 1)
				var id := PatchId.new(face, level, ix, iy)
				var local := uv * n - Vector2(ix, iy)
				var a := PlanetMath.face_uv_to_direction(face, id.local_uv_to_face_uv(local))
				var b := PlanetMath.face_uv_to_direction(face, uv)
				var qa := climate.query_direction(a)
				var qb := climate.query_direction(b)
				check(qa.climate == qb.climate and qa.weights == qb.weights, "same direction across LODs")
	var boundaries := 0
	for i in range(4096):
		var a := PlanetTerrain.uniform_direction(i, 4096)
		var tangent := a.cross(Vector3.UP)
		if tangent.length_squared() < 0.00001:
			continue
		var b := (a + tangent.normalized() * 0.02).normalized()
		if climate.query_direction(a).dominant == climate.query_direction(b).dominant:
			continue
		for iteration in range(16):
			var middle := (a + b).normalized()
			if climate.query_direction(a).dominant == climate.query_direction(middle).dominant:
				a = middle
			else:
				b = middle
		var qa := climate.query_direction(a)
		var qb := climate.query_direction(b)
		if qa.dominant < 0 or qb.dominant < 0:
			continue
		check(qa.climate.distance_to(qb.climate) < 0.1, "continuous climate across biome switch")
		for j in range(10):
			check(absf(qa.weights[j] - qb.weights[j]) < 0.02, "continuous biome weights at dominant switch")
		boundaries += 1
	check(boundaries > 10, "actual biome transitions exercised")
	print("CLIMATE_BOUNDARIES ", boundaries)

func test_mesh() -> void:
	var output := PlanetClimateSample.new()
	for face in range(6):
		var mesh := PlanetPatchMesh.generate(PatchId.root(face), 50000, 0, terrain, 1.0, climate)
		var rendered := PlanetPatchMesh.as_array_mesh(mesh)
		check(rendered.get_surface_count() == 1, "climate custom channels accepted by ArrayMesh")
		for i in range(1089):
			var d: Vector3 = mesh.normals[i]
			climate.sample_into(d, terrain.sample_fields(d), output)
			var debug_temp := float(mesh.climate_fields[i * 4]) * 80.0 / 255.0 - 40.0
			var debug_moisture := float(mesh.climate_fields[i * 4 + 1]) / 255.0
			var debug_biome := int(round(float(mesh.biomes[i * 4 + 1]) * 11.0 / 255.0)) - 1
			# Godot Image.convert truncates RGBAF to UNORM8. Error is at most
			# one byte quantum, while the query API remains full precision.
			check(absf(debug_temp - output.climate.x) < 0.315 and absf(debug_moisture - output.climate.y) < 0.004 and debug_biome == output.dominant, "quantized debug derives from full-precision climate authority")

func test_controller() -> void:
	var view := PlanetQuadtreeView.new()
	root.add_child(view)
	var config := PlanetLodConfig.new()
	config.max_render_level = 2
	config.cpu_budget_ms = 0.0
	view.initialize(50000, config, terrain, 1.0, climate)
	for distance in [53000.0, 100000000.0]:
		var stable := 0
		for frame in range(3000):
			view.step(Vector3(0, 0, distance), 720, 70, 0.1)
			check(view.commits_last_update <= config.mesh_budget and view.splits_last_update <= config.split_budget and view.merges_last_update <= config.merge_budget, "climate controller budgets unchanged")
			stable = stable + 1 if view.state == "idle" else 0
			if stable == 3:
				break
			if frame % 50 == 0:
				await process_frame
		check(stable == 3 and view.tree.is_balanced(), "climate controller converges with 2:1")
	check(view.tree.leaves.size() == 6, "climate-enabled renderer returns six roots")
	view.queue_free()
	await process_frame
