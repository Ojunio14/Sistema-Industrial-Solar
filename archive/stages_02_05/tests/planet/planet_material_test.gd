extends SceneTree

var assertions := 0
var failures := 0
var terrain: PlanetTerrain
var climate: PlanetClimate

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, context: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		if failures <= 20:
			push_error("MATERIAL_TEST_FAILED: " + context)

func _run() -> void:
	test_assets()
	terrain = PlanetTerrain.new(73129, true)
	climate = PlanetClimate.new(73129, terrain)
	test_mapping()
	test_distribution()
	test_continuity()
	test_normals_and_mesh()
	print("MATERIAL_TEST_%s: %d assertions; failures=%d" % ["OK" if failures == 0 else "FAILED", assertions, failures])
	quit(0 if failures == 0 else 1)

func test_assets() -> void:
	var errors := PlanetMaterialLibrary.validate_assets()
	for error in errors:
		check(false, error)
	check(errors.is_empty(), "all eight families have 2K albedo/Normal GL/roughness and 3D import settings")
	check(PlanetMaterialLibrary.FAMILIES.size() == 8, "exactly eight official families")
	var expected := ["rock_generic", "rock_sedimentary", "rock_volcanic", "soil",
		"sand", "arid_ground", "snow_ice", "gravel"]
	for i in range(expected.size()):
		check(PlanetMaterialLibrary.FAMILIES[i] == expected[i], "stable family index %d" % i)
		for role in ["albedo", "normal", "roughness"]:
			check(ResourceLoader.exists(PlanetMaterialLibrary.path_for(i, role)), "imported texture reference exists")
	var library := PlanetMaterialLibrary.shared()
	check(library != null, "three arrays created")
	if library == null:
		return
	for texture: Texture2DArray in [library.albedo, library.normal, library.roughness]:
		check(texture != null and texture.get_layers() == 8 and texture.get_width() == 2048 and texture.get_height() == 2048,
			"array has eight 2K layers")
		check(texture.has_mipmaps(), "array contains distance mipmaps")

func _weights(altitude: float, slope_value: float, coast: float, temperature: float,
		humidity: float, precipitation: float, volcanic: float, sedimentary: float, dry_biome: float) -> PackedFloat32Array:
	return PlanetSurfaceSelection.weights(altitude, slope_value, coast, temperature,
		humidity, precipitation, Vector3(volcanic, sedimentary, dry_biome))

func test_mapping() -> void:
	var temperate := _weights(180, 0.01, 0.0, 16, 0.7, 0.65, 0, 0, 0.05)
	var steep := _weights(180, 0.7, 0.0, 16, 0.7, 0.65, 0, 0, 0.05)
	check(steep[0] > temperate[0] and steep[3] < temperate[3], "slope exposes rock and reduces soil")
	var sediment := _weights(180, 0.25, 0.0, 16, 0.7, 0.65, 0, 1, 0.05)
	var volcanic := _weights(180, 0.25, 0.0, 16, 0.7, 0.65, 1, 0, 0.05)
	check(sediment[1] > temperate[1] and volcanic[2] > temperate[2], "geological rock families respond to their own province")
	var beach := _weights(20, 0.0, 1.0, 24, 0.55, 0.5, 0, 0, 0.2)
	var rocky_coast := _weights(20, 0.7, 1.0, 24, 0.55, 0.5, 0, 0, 0.2)
	check(beach[4] > rocky_coast[4] and rocky_coast[0] > beach[0], "coast favors sand but steep shore exposes rock")
	var arid := _weights(160, 0.02, 0, 30, 0.12, 0.08, 0, 0, 0.9)
	var humid := _weights(160, 0.02, 0, 30, 0.9, 0.9, 0, 0, 0.05)
	check(arid[5] > humid[5] and arid[4] > humid[4], "dry biome/climate favors arid material and sand")
	var polar := _weights(150, 0.02, 0, -24, 0.5, 0.45, 0, 0, 0)
	var alpine := _weights(1200, 0.3, 0, -8, 0.5, 0.45, 0, 0, 0)
	check(polar[6] > temperate[6] and alpine[6] > temperate[6], "polar and high cold terrain gain snow")
	var loose := _weights(180, 0.3, 0, 16, 0.5, 0.5, 0, 0, 0.1)
	var seen := PackedByteArray()
	seen.resize(8)
	for specimen in [temperate, steep, sediment, volcanic, beach, arid, polar, alpine, loose]:
		var total := 0.0
		var dominant := 0
		for i in range(8):
			check(is_finite(specimen[i]) and specimen[i] >= 0 and specimen[i] <= 1, "finite bounded surface weight")
			total += specimen[i]
			if specimen[i] > specimen[dominant]:
				dominant = i
		check(absf(total - 1.0) < 0.00001, "surface weights sum to one")
		seen[dominant] = 1
	check(seen[0] == 1 and seen[1] == 1 and seen[2] == 1 and seen[3] == 1 and seen[4] == 1 and seen[5] == 1 and seen[6] == 1 and seen[7] == 1,
		"controlled contexts can expose all eight families")
	var submerged := PlanetSurfaceSelection.weights(-5, 0, 0, 10, .5, .5, Vector3.ZERO)
	var submerged_sum := 0.0
	for value in submerged:
		submerged_sum += value
	check(submerged_sum == 0.0, "submerged terrain receives no terrestrial material weight")

func test_continuity() -> void:
	for face in range(6):
		for edge in range(4):
			var transition := PlanetTopology.get_edge_transition(face, edge)
			for i in range(17):
				var t := i / 16.0
				var a := PlanetMath.face_uv_to_direction(face, PlanetTopology.edge_uv(edge, t))
				var b := PlanetMath.face_uv_to_direction(transition.neighbor_face,
					PlanetTopology.edge_uv(transition.neighbor_edge, 1.0 - t if transition.is_reversed else t))
				var qa := climate.query_direction(a)
				var qb := climate.query_direction(b)
				var fa := PlanetSurfaceSelection.factors(terrain.geology.query_direction(a), qa)
				var fb := PlanetSurfaceSelection.factors(terrain.geology.query_direction(b), qb)
				check(fa.distance_to(fb) < 0.00001, "same surface factors across cube faces")
		for level in [0, 1, 2, 4, 6, 17, 24]:
			var n: int = 1 << level
			for uv in [Vector2(.25, .75), Vector2(.5, .5), Vector2(1, 1)]:
				var id := PatchId.new(face, level, mini(int(uv.x * n), n - 1), mini(int(uv.y * n), n - 1))
				var local: Vector2 = uv * n - Vector2(id.x, id.y)
				var a := PlanetMath.face_uv_to_direction(face, id.local_uv_to_face_uv(local))
				var b := PlanetMath.face_uv_to_direction(face, uv)
				check(PlanetSurfaceSelection.factors(terrain.geology.query_direction(a), climate.query_direction(a)).distance_to(
					PlanetSurfaceSelection.factors(terrain.geology.query_direction(b), climate.query_direction(b))) < 0.00001,
					"surface factors are independent of LOD")

func test_distribution() -> void:
	var counts := PackedInt32Array()
	counts.resize(8)
	var land := 0
	var min_top_two := 1.0
	var mean_top_two := 0.0
	var below_seventy := 0
	var terrain_output := PlanetTerrainSample.new()
	var climate_output := PlanetClimateSample.new()
	for i in range(4096):
		var direction := PlanetTerrain.uniform_direction(i, 4096)
		terrain.sample_into(direction, terrain_output)
		if terrain_output.terrain.x <= 0.0:
			continue
		climate.sample_into(direction, terrain_output.terrain, climate_output)
		var inputs := PlanetSurfaceSelection.factors(terrain_output.geology, climate_output)
		var surface := PlanetSurfaceSelection.weights(terrain_output.terrain.x, 0.0,
			terrain_output.terrain.w, climate_output.climate.x, climate_output.climate.y,
			climate_output.climate.w, inputs)
		var first := 0.0
		var second := 0.0
		var dominant := 0
		for family in range(8):
			var weight := surface[family]
			if weight > first:
				second = first
				first = weight
				dominant = family
			elif weight > second:
				second = weight
		var retained := first + second
		min_top_two = minf(min_top_two, retained)
		mean_top_two += retained
		below_seventy += int(retained < 0.7)
		counts[dominant] += 1
		land += 1
	check(land > 1000, "global material distribution samples terrestrial surface")
	for count in counts:
		check(count < land * 0.9, "no single material dominates almost all sampled land")
	print("MATERIAL_GLOBAL " + JSON.stringify({"land": land, "dominant_counts": counts,
		"top_two_min": min_top_two, "top_two_mean": mean_top_two / land,
		"top_two_below_0_7": below_seventy}))

func test_normals_and_mesh() -> void:
	var meshes := []
	var max_slope := 0.0
	for face in range(6):
		var data := PlanetPatchMesh.generate(PatchId.root(face), 50000, 0, terrain, 1.0, climate, true)
		meshes.append(data)
		var mesh := PlanetPatchMesh.as_array_mesh(data)
		check(mesh.get_surface_count() == 1, "smooth material mesh accepted")
		for i in range(1089):
			var n: Vector3 = data.normals[i]
			var d: Vector3 = data.vertices[i].normalized()
			max_slope = maxf(max_slope, PlanetSurfaceSelection.slope(n, d))
			check(n.is_finite() and absf(n.length() - 1.0) < 0.0001 and n.dot(d) > 0.25, "finite outward normalized terrain normal")
			var dry_from_color: float = data.colors[i].a
			check(dry_from_color >= 0 and dry_from_color <= 1 and data.material_factors[i].is_finite(), "material factors packed and finite")
	check(max_slope > 0.02, "global heightfield normals respond to real terrain slope")
	print("MATERIAL_NORMAL_MAX_SLOPE ", max_slope)
	for face in range(6):
		for edge in range(4):
			var transition := PlanetTopology.get_edge_transition(face, edge)
			for i in range(33):
				var a_index := _edge_index(edge, i)
				var b_index := _edge_index(transition.neighbor_edge, 32 - i if transition.is_reversed else i)
				var a: Vector3 = meshes[face].normals[a_index]
				var b: Vector3 = meshes[transition.neighbor_face].normals[b_index]
				check(a.distance_to(b) < 0.02, "smooth normal across face/edge including corners")
				check(meshes[face].material_factors[a_index].distance_to(meshes[transition.neighbor_face].material_factors[b_index]) < 0.0001,
					"material factors across face/edge")
				var d: Vector3 = meshes[face].vertices[a_index].normalized()
				var fields := terrain.sample_fields(d)
				var c := climate.query_direction(d)
				var factors := PlanetSurfaceSelection.factors(terrain.geology.query_direction(d), c)
				var wa := PlanetSurfaceSelection.weights(fields.x, PlanetSurfaceSelection.slope(a, d), fields.w,
					c.climate.x, c.climate.y, c.climate.w, factors)
				var wb := PlanetSurfaceSelection.weights(fields.x, PlanetSurfaceSelection.slope(b, d), fields.w,
					c.climate.x, c.climate.y, c.climate.w, factors)
				for family in range(8):
					check(absf(wa[family] - wb[family]) < 0.03, "material weight continuous across face edge")
	var child := PlanetPatchMesh.generate(PatchId.new(0, 1, 0, 0), 50000, 0, terrain, 1.0, climate, true)
	for y in range(0, 33, 2):
		for x in range(0, 33, 2):
			var coarse: Vector3 = meshes[0].normals[int(y / 2) * 33 + int(x / 2)]
			var fine: Vector3 = child.normals[y * 33 + x]
			check(coarse.distance_to(fine) < 0.02, "fixed metric normal stable across LOD")

func _edge_index(edge: int, index: int) -> int:
	match edge:
		0: return index * 33
		1: return index * 33 + 32
		2: return index
		_: return 32 * 33 + index
