extends SceneTree

var failures := 0
var assertions := 0
var terrain: PlanetTerrain
var geology: PlanetGeology

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, context: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		if failures <= 24:
			push_error("GEOLOGY_TEST_FAILED: " + context)

func _run() -> void:
	terrain = PlanetTerrain.new(73129, true)
	geology = terrain.geology
	test_global()
	if not OS.get_cmdline_user_args().has("--determinism-only"):
		test_determinism()
		test_continuity()
		test_descriptors()
		test_seed_contracts()
		test_spatial_index()
		test_integration()
		test_benchmark()
	print("GEOLOGY_TEST_%s: %d assertions; failures=%d" % ["OK" if failures == 0 else "FAILED", assertions, failures])
	quit(0 if failures == 0 else 1)

func test_global() -> void:
	var counts := PackedInt32Array()
	counts.resize(PlanetGeology.TYPE_NAMES.size())
	var ids := {}
	var ages := Vector3(INF, 0, -INF)
	var change := Vector3(INF, 0, -INF)
	var delta_count := 0
	var land := 0
	var continental := 0
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	for i in range(16384):
		var d := PlanetTerrain.uniform_direction(i, 16384)
		var c := terrain.continentality(d)
		var q := geology.query_direction(d)
		var kind := PlanetGeology.type_of(int(q.x))
		check(q.is_finite() and kind >= 0 and kind < counts.size(), "finite/valid classification")
		check(q.y >= 0 and q.y <= 1 and q.z > 0 and q.z <= 1, "maturity and dominant normalized influence")
		check(q.w >= PlanetGeology.MIN_DISPLACEMENT and q.w <= PlanetGeology.MAX_DISPLACEMENT, "bounded structural deformation")
		check(not geology.describe(int(q.x)).is_empty(), "stable identity resolves descriptor")
		if c <= 0:
			check(kind == PlanetGeology.Type.OCEANIC and q.w == 0, "ocean domain not arbitrarily assigned continental geology")
		else:
			continental += 1
			check(kind != PlanetGeology.Type.OCEANIC, "continental structural domain")
		if kind == PlanetGeology.Type.CRATON:
			# A dominant province is not necessarily a majority of the blend.
			# Its intrinsic age is old; boundary maturity may include young belts.
			check(c > 0.02 and geology.describe(int(q.x)).age >= 0.82, "old interiors on suitable continental interior")
		counts[kind] += 1
		ids[int(q.x)] = true
		ages = Vector3(minf(ages.x, q.y), ages.y + q.y, maxf(ages.z, q.y))
		change = Vector3(minf(change.x, q.w), change.y + q.w, maxf(change.z, q.w))
		delta_count += int(absf(q.w) > 0.1)
		var h := terrain.sample(d)
		land += int(h > 0)
		check(is_finite(h) and h >= PlanetTerrain.MIN_HEIGHT and h <= PlanetTerrain.MAX_HEIGHT, "final height safe")
		digest.update(("%.0f/%.7f/%.7f/%.5f;" % [q.x, q.y, q.z, q.w]).to_utf8_buffer())
	var percentages := {}
	for kind in range(counts.size()):
		percentages[PlanetGeology.TYPE_NAMES[kind]] = counts[kind] * 100.0 / 16384
		check(counts[kind] > 0, "default fixture exercises " + PlanetGeology.TYPE_NAMES[kind])
		if kind != PlanetGeology.Type.OCEANIC:
			check(counts[kind] < continental, "no continental category monopolizes land")
	check(counts[PlanetGeology.Type.IGNEOUS] < 16384 * 0.04, "volcanism localized, structural support not global noise")
	check(land > 16384 * 0.42 and land < 16384 * 0.48, "continental macrostructure retained")
	check(delta_count > 100, "geology actually modifies terrain")
	ages.y /= 16384
	change.y /= 16384
	print("GEOLOGY_GLOBAL " + JSON.stringify({"fingerprint": digest.finish().hex_encode(),
		"percentages": percentages, "observed_ids": ids.size(), "descriptors": geology.descriptors().size(),
		"age_min_mean_max": str(ages), "delta_min_mean_max_m": str(change),
		"modified_samples": delta_count, "land_percent": land * 100.0 / 16384}))

func test_determinism() -> void:
	var same := PlanetTerrain.new(73129, true)
	var other := PlanetTerrain.new(73130, true)
	var samples := PackedVector4Array()
	var changed := 0
	for i in range(1024):
		var d := PlanetTerrain.uniform_direction(i, 1024)
		var q := geology.query_direction(d)
		samples.append(q)
		check(q == same.geology.query_direction(d), "same seed exact query")
		check(q == geology.query_with_continentality(d, terrain.continentality(d)), "shared continental context exact")
		changed += int(q != other.geology.query_direction(d))
	for i in range(1023, -1, -1):
		var d := PlanetTerrain.uniform_direction(i, 1024)
		check(samples[i] == geology.query_direction(d), "query order independence")
	check(changed > 300, "different seed different distribution")
	check(geology.stable_key(0) != other.geology.stable_key(0), "seed namespaces identities")
	# Geology remains a valid authority after its constructing terrain is freed.
	var standalone := same.geology
	same = null
	check(standalone.query_direction(Vector3.UP) == geology.query_direction(Vector3.UP), "no lifetime cycle or terrain dependency")

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
				var qa := geology.query_direction(a)
				var qb := geology.query_direction(b)
				check(qa == qb, "12 physical edges / exact classification and continuous fields")
				check(absf(terrain.sample(a) - terrain.sample(b)) < 0.04, "height across faces")
				if i == 0 or i == 32:
					corners[str(a.sign())] = true
				var inside := PlanetTopology.edge_uv(edge, t).lerp(Vector2(0.5, 0.5), 0.000001)
				var qc := geology.query_direction(PlanetMath.face_uv_to_direction(face, inside))
				check(absf(qa.y - qc.y) < 0.001 and absf(qa.w - qc.w) < 0.2, "one-sided continuous age/deformation")
	check(corners.size() == 8, "eight physical corners covered")
	for face in range(6):
		for level: int in [0, 1, 2, 4, 6, 17, 24]:
			var n := 1 << level
			for uv: Vector2 in [Vector2(0.25, 0.75), Vector2(0.5, 0.5), Vector2(1, 1)]:
				var index := Vector2i(mini(int(uv.x * n), n - 1), mini(int(uv.y * n), n - 1))
				var id := PatchId.new(face, level, index.x, index.y)
				var local := uv * n - Vector2(index)
				var d := PlanetMath.face_uv_to_direction(face, id.local_uv_to_face_uv(local))
				check(geology.query_direction(d) == geology.query_direction(PlanetMath.face_uv_to_direction(face, uv)), "same direction across all LODs")
	# Continuous properties remain smooth across real (discrete) province changes.
	var transitions := 0
	for i in range(4096):
		var a := PlanetTerrain.uniform_direction(i, 4096)
		var b := (a + a.cross(Vector3.UP).normalized() * 0.01).normalized()
		if geology.query_direction(a).x == geology.query_direction(b).x:
			continue
		for iteration in range(16):
			var middle := (a + b).normalized()
			if geology.query_direction(a).x == geology.query_direction(middle).x:
				a = middle
			else:
				b = middle
		var qa := geology.query_direction(a)
		var qb := geology.query_direction(b)
		check(absf(qa.y - qb.y) < 0.001 and absf(qa.w - qb.w) < 0.1, "no enum-driven height/age jump at province boundary")
		transitions += 1
	check(transitions > 10, "real geological boundaries exercised")
	print("GEOLOGY_BOUNDARIES ", transitions)

func test_descriptors() -> void:
	var keys := {}
	var young := 0
	var old := 0
	for descriptor in geology.descriptors():
		check(not keys.has(descriptor.key), "unique versioned province identity")
		keys[descriptor.key] = true
		var kind: int = descriptor.type
		if kind == PlanetGeology.Type.OROGEN:
			check(descriptor.source_form in [PlanetTerrain.Form.CHAIN, PlanetTerrain.Form.RANGE], "belts reuse macro chains")
			check(descriptor.length > descriptor.width, "orogen elongated")
			young += int(descriptor.age < 0.45)
			old += int(descriptor.age > 0.60)
		if kind == PlanetGeology.Type.SEDIMENTARY or kind == PlanetGeology.Type.CLOSED_BASIN:
			check(descriptor.source_form in [PlanetTerrain.Form.BASIN, PlanetTerrain.Form.VALLEY], "basins tied to macro depressions")
		if kind == PlanetGeology.Type.FORMER_MARINE:
			check(terrain._base_fields(descriptor.direction, terrain.continentality(descriptor.direction)).x > 20, "former marine now emerged region")
			check(terrain.sample(descriptor.direction) > 0, "former marine remains emerged after structural modification")
		if kind == PlanetGeology.Type.IGNEOUS:
			check(descriptor.source_form in [PlanetTerrain.Form.PLATEAU, PlanetTerrain.Form.EXCEPTIONAL], "localized igneous context")
	check(young > 0 and old > 0, "young and old mountain structures")
	check(geology.describe(-1).is_empty(), "unknown identity rejected")
	# Age changes profile shape, not a uniform enum-based height offset.
	for source in geology._provinces:
		if source.kind != PlanetGeology.Type.OROGEN:
			continue
		var p := PlanetGeology.Province.new()
		p.kind = source.kind
		p.amplitude = source.amplitude
		p.phase = source.phase
		p.age = 0.15
		var young_profile := Vector2(geology._deformation(p, 0.05, 0.0, 0.0025), geology._deformation(p, 0.05, 0.50, 0.2525))
		p.age = 0.85
		var old_profile := Vector2(geology._deformation(p, 0.05, 0.0, 0.0025), geology._deformation(p, 0.05, 0.50, 0.2525))
		check(young_profile.x - young_profile.y > old_profile.x - old_profile.y + 1.0, "young belt has stronger crest/shoulder contrast")
		check(old_profile.y > young_profile.y, "old belt has broader shoulders")

func test_seed_contracts() -> void:
	# No fixed category counts/land ratio for arbitrary seeds. Check contracts,
	# IDs and finite fields, independently of the default visual fixture.
	for seed_value: int in [0, 1, 2, 42, 73128, 73129, 73130, 999983]:
		var world := PlanetTerrain.new(seed_value, true)
		var keys := {}
		for descriptor in world.geology.descriptors():
			check(not keys.has(descriptor.key), "multi-seed unique descriptors")
			keys[descriptor.key] = true
		for i in range(1024):
			var d := PlanetTerrain.uniform_direction(i, 1024)
			var q := world.geology.query_direction(d)
			check(q.is_finite() and q.y >= 0 and q.y <= 1 and q.z > 0 and q.z <= 1, "multi-seed finite fields")
			check(not world.geology.describe(int(q.x)).is_empty(), "multi-seed identity resolves")
			check(q.w >= PlanetGeology.MIN_DISPLACEMENT and q.w <= PlanetGeology.MAX_DISPLACEMENT, "multi-seed bounded delta")
			if world.continentality(d) <= 0:
				check(q.x == 0 and q.w == 0, "multi-seed ocean remains oceanic")

func test_spatial_index() -> void:
	var reference := PlanetTerrain.new(73129, true).geology
	for i in range(512):
		reference._buckets[i] = reference._provinces
	for i in range(8192):
		var d := PlanetTerrain.uniform_direction(i, 8192)
		check(geology.query_direction(d) == reference.query_direction(d), "spatial broad phase exact")
	for axis in range(3):
		for boundary in range(1, 8):
			for offset in [-0.000001, 0.0, 0.000001]:
				var value: float = -1.0 + boundary * 0.25 + offset
				for i in range(16):
					var d := Vector3.ZERO
					d[axis] = value
					d[(axis + 1) % 3] = sqrt(1.0 - value * value) * cos(i * TAU / 16)
					d[(axis + 2) % 3] = sqrt(1.0 - value * value) * sin(i * TAU / 16)
					check(geology.query_direction(d) == reference.query_direction(d), "closed-cell boundaries exact")

func test_integration() -> void:
	var base := PlanetTerrain.new(73129)
	var output := PlanetTerrainSample.new()
	for i in range(2048):
		var d := PlanetTerrain.uniform_direction(i, 2048)
		terrain.sample_into(d, output)
		check(output.terrain == terrain.sample_fields(d) and output.geology == geology.query_direction(d), "one-query output consistent with public APIs")
		var expected := clampf(base.sample(d) + output.geology.w, PlanetTerrain.MIN_HEIGHT, PlanetTerrain.MAX_HEIGHT)
		check(absf(terrain.sample(d) - expected) < 0.001, "macro base plus controlled modifier")
		check(absf(base.continentality(d) - terrain.continentality(d)) < 0.000001, "continental structure unchanged")
		var position_query := geology.query_position(d * 50000.0)
		check(absf(position_query.w - output.geology.w) < 0.1 and absf(position_query.y - output.geology.y) < 0.001, "surface position API")
	for face in range(6):
		var mesh := PlanetPatchMesh.generate(PatchId.root(face), 50000, 0, terrain)
		for i in range(1089):
			var d := mesh.normals[i] as Vector3
			var q := geology.query_direction(d)
			check(mesh.geology[i * 4] == q.x and mesh.geology[i * 4 + 1] == q.y, "renderer uses authoritative geological attributes")

func test_benchmark() -> void:
	var base := PlanetTerrain.new(73129)
	var directions := PackedVector3Array()
	for i in range(16384):
		directions.append(PlanetTerrain.uniform_direction(i, 16384))
	var baseline: Array[float] = []
	var structural: Array[float] = []
	var queries: Array[float] = []
	var checksum := 0.0
	for repeat in range(3):
		var start := Time.get_ticks_usec()
		for d in directions:
			checksum += base.sample(d)
		baseline.append(float(Time.get_ticks_usec() - start) / directions.size())
		start = Time.get_ticks_usec()
		for d in directions:
			checksum += terrain.sample(d)
		structural.append(float(Time.get_ticks_usec() - start) / directions.size())
		start = Time.get_ticks_usec()
		for d in directions:
			checksum += geology.query_direction(d).w
		queries.append(float(Time.get_ticks_usec() - start) / directions.size())
	baseline.sort()
	structural.sort()
	queries.sort()
	print("GEOLOGY_BENCH median_us base=%.3f integrated=%.3f standalone_query=%.3f checksum=%.3f" % [baseline[1], structural[1], queries[1], checksum])
