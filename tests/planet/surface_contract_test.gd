extends SceneTree

var checks := 0
var failures := 0
var reference := false

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		if failures < 15:
			push_error("SURFACE_TEST_FAILED: " + message)

func digest(bytes: PackedByteArray) -> String:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	return hash.finish().hex_encode()

func direction_at(i: int, n: int) -> Vector3:
	var y := 1.0 - 2.0 * (i + 0.5) / n
	var r := sqrt(1.0 - y * y)
	var angle := i * PI * (3.0 - sqrt(5.0))
	return Vector3(cos(angle) * r, y, sin(angle) * r)

func _run() -> void:
	reference = ResourceLoader.exists("res://systems/planet_generator/data/test_planet_100km.tres")
	var preset := "res://systems/planet_generator/data/test_planet_100km.tres" if reference else "res://systems/planet/surface/data/test_planet_100km.tres"
	var definition: PlanetDefinition = load(preset)
	check(definition.radius_m == 50000.0 and definition.seed == 12051965, "actual donor scale and seed")
	check(definition.continent_scale == 1.3 and definition.continent_threshold == -0.06 and definition.coast_blend == 0.15 and definition.mountain_height_m == 620.0, "actual runtime preset")
	var shape := PlanetShape.new(definition)
	var values := PackedVector4Array()
	var heights := PackedFloat64Array()
	for i in range(8192):
		var d := direction_at(i, 8192)
		var fields := shape.sample_components(d)
		values.append(fields)
		heights.append(shape.sample_height_m(d))
		check(fields.is_finite(), "finite components")
		check(fields.x >= -350.0 and fields.x <= 900.0, "height bounds")
		check(absf(shape.point_on_planet(d).length() - 50000.0 - fields.x) < 0.015, "metric radius plus height")
	for i in range(8191, -1, -1):
		check(values[i] == shape.sample_components(direction_at(i, 8192)), "query order independent")
	var changed: PlanetDefinition = definition.duplicate(true)
	changed.continent_scale += 0.1
	var altered := PlanetShape.new(changed)
	var differences := 0
	for i in range(128):
		differences += int(shape.sample_height_m(direction_at(i, 128)) != altered.sample_height_m(direction_at(i, 128)))
	check(differences > 64, "configuration changes the natural authority")
	for seed_value in [0, 1, 42, 73129, 12051965]:
		changed.seed = seed_value
		var a := PlanetShape.new(changed.duplicate(true))
		var b := PlanetShape.new(changed.duplicate(true))
		for i in range(256):
			var d := direction_at(i, 256)
			check(a.sample_components(d) == b.sample_components(d), "multi-seed determinism")
	var mesh_fingerprints := {}
	var roots: Array[Dictionary] = []
	for face in range(6):
		for level in [0, 1, 4, 8]:
			var cell := Vector2i.ZERO if level == 0 else Vector2i((1 << level) / 2, (1 << level) / 2)
			var builder := PlanetChunkBuilder.new(definition, face, level, cell, 17)
			builder.build()
			var data := builder.result
			var arrays: Array = data.arrays
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			check(vertices.size() == 17 * 17 + 4 * 17, "donor topology dimensions")
			check(indices.size() == (16 * 16 * 2 + 16 * 8) * 3, "surface and skirt index counts")
			for i in range(vertices.size()):
				check(vertices[i].is_finite() and normals[i].is_finite(), "finite mesh")
				check(absf(normals[i].length() - 1) < 0.00001 and normals[i].dot(vertices[i]) > 0.0, "unit outward normals")
				if not reference:
					check(data.bounds.grow(0.01).has_point(vertices[i]), "bounds include skirts")
			for offset in range(0, 16 * 16 * 6, 3):
				var ia := indices[offset]
				var ib := indices[offset + 1]
				var ic := indices[offset + 2]
				check(mini(ia, mini(ib, ic)) >= 0 and maxi(ia, maxi(ib, ic)) < vertices.size(), "valid indices")
				check((vertices[ib] - vertices[ia]).cross(vertices[ic] - vertices[ia]).dot(vertices[ia]) < 0, "clockwise external winding")
			mesh_fingerprints["%d:%d" % [face, level]] = [digest(vertices.to_byte_array()), digest(normals.to_byte_array()), digest(indices.to_byte_array())]
			if level == 0:
				roots.append(data)
	# All 24 directed cube edges, including corners: equal positions/normals.
	for face in range(6):
		var arrays: Array = roots[face].arrays
		for y in range(17):
			for x in range(17):
				if x != 0 and x != 16 and y != 0 and y != 16:
					continue
				var i := y * 17 + x
				var p: Vector3 = arrays[Mesh.ARRAY_VERTEX][i]
				var found := false
				for other in range(6):
					if other == face:
						continue
					var other_arrays: Array = roots[other].arrays
					for j in range(17 * 17):
						if p.distance_to(other_arrays[Mesh.ARRAY_VERTEX][j]) < 0.005:
							found = true
							check(arrays[Mesh.ARRAY_NORMAL][i].distance_to(other_arrays[Mesh.ARRAY_NORMAL][j]) < 0.005, "cube-face normals coincide")
				check(found, "cube-face positions coincide")
	var report := {"shape": digest(values.to_byte_array()), "heights": digest(heights.to_byte_array()), "meshes": mesh_fingerprints, "checks": checks, "failures": failures}
	if not reference:
		var oracle: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/planet/donor_contracts.json"))
		check(report.shape == oracle.shape and report.heights == oracle.heights, "exact donor natural surface fingerprint")
		for key in mesh_fingerprints:
			check(mesh_fingerprints[key] == oracle.meshes[key], "exact donor geometry/normals/indices " + key)
		report.checks = checks
		report.failures = failures
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		var file := FileAccess.open(args[0], FileAccess.WRITE)
		file.store_string(JSON.stringify(report, "\t"))
	print("SURFACE_CONTRACT ", report.shape, " checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)
