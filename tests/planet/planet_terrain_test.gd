extends SceneTree

const R := 50000.0
const EPS := 0.04 # Float32 position ULPs at 50 km, in meters.
var failures := 0
var assertions := 0
var terrain: PlanetTerrain
var _coast_direction := Vector3.ZERO

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, context: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		if failures <= 20:
			push_error("TERRAIN_TEST_FAILED: " + context)

func _run() -> void:
	var start := Time.get_ticks_usec()
	terrain = PlanetTerrain.new()
	print("TERRAIN_CONSTRUCTION_MS %.3f" % ((Time.get_ticks_usec() - start) / 1000.0))
	test_global()
	test_determinism()
	if OS.get_cmdline_user_args().has("--determinism-only"):
		print("TERRAIN_DETERMINISM_%s" % ("OK" if failures == 0 else "FAILED"))
		quit(0 if failures == 0 else 1)
		return
	test_spatial_index()
	test_sampler_benchmark()
	test_continuity()
	test_mesh_morph()
	test_error_envelope()
	test_terrain_transitions()
	await test_controller()
	if not OS.get_cmdline_user_args().is_empty():
		write_map(OS.get_cmdline_user_args()[0])
	print("TERRAIN_TEST_%s: %d assertions, %d failures" % ["OK" if failures == 0 else "FAILED", assertions, failures])
	quit(0 if failures == 0 else 1)

func test_global() -> void:
	var land := 0
	var land_stats := Vector3(INF, 0, -INF)
	var sea_stats := Vector3(INF, 0, -INF)
	var forms := {}
	var coast_crossings := 0
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	var started := Time.get_ticks_usec()
	for i in range(16384):
		var d := PlanetTerrain.uniform_direction(i, 16384)
		var fields := terrain.sample_fields(d)
		var h := fields.x
		check(is_finite(h) and h >= PlanetTerrain.MIN_HEIGHT and h <= PlanetTerrain.MAX_HEIGHT, "global finite/bounds")
		digest.update(("%.6f;" % h).to_utf8_buffer())
		if h > 0:
			land += 1
			land_stats = Vector3(minf(land_stats.x, h), land_stats.y + h, maxf(land_stats.z, h))
		else:
			sea_stats = Vector3(minf(sea_stats.x, -h), sea_stats.y - h, maxf(sea_stats.z, -h))
		var kind := int(fields.z)
		if not forms.has(kind):
			forms[kind] = {"count": 0, "min": h, "max": h, "sum": 0.0}
		forms[kind].count += 1
		forms[kind].min = minf(forms[kind].min, h)
		forms[kind].max = maxf(forms[kind].max, h)
		forms[kind].sum += h
		# Find brackets without consulting descriptors; bisect actual h=0.
		if i % 8 == 0:
			var b := (d + d.cross(Vector3.UP).normalized() * 0.03).normalized()
			if (h > 0) != (terrain.sample(b) > 0):
				var a := d
				for iteration in range(18):
					var middle := (a + b).normalized()
					if (terrain.sample(a) > 0) == (terrain.sample(middle) > 0):
						a = middle
					else:
						b = middle
				check(absf(terrain.sample(a) - terrain.sample(b)) < 0.10, "continuous sea-level crossing")
				_coast_direction = (a + b).normalized()
				coast_crossings += 1
	var ratio := float(land) / 16384.0
	check(ratio >= 0.42 and ratio <= 0.48, "land ratio 42..48%")
	check(coast_crossings >= 10, "coast crossings actually exercised")
	land_stats.y /= land
	sea_stats.y /= 16384 - land
	for entry: Dictionary in forms.values():
		entry.mean = entry.sum / entry.count
		entry.erase("sum")
	print("TERRAIN_GLOBAL " + JSON.stringify({"seed": terrain.get_seed(), "samples": 16384, "land_percent": ratio * 100, "ocean_percent": (1.0 - ratio) * 100, "land_min_mean_max_m": str(land_stats), "depth_min_mean_max_m": str(sea_stats), "forms": forms, "coast_crossings": coast_crossings, "fingerprint": digest.finish().hex_encode(), "validation_ms": (Time.get_ticks_usec() - started) / 1000.0}))
	started = Time.get_ticks_usec()
	var sum := 0.0
	for i in range(16384):
		sum += terrain.sample(PlanetTerrain.uniform_direction(i, 16384))
	print("TERRAIN_SAMPLE_BENCH us/sample=%.3f checksum=%.3f" % [float(Time.get_ticks_usec() - started) / 16384.0, sum])

func test_determinism() -> void:
	var same := PlanetTerrain.new(terrain.get_seed())
	var other := PlanetTerrain.new(terrain.get_seed() + 1)
	var values := PackedFloat32Array()
	var changed := 0
	for i in range(512):
		var d := PlanetTerrain.uniform_direction(i, 512)
		values.append(terrain.sample(d))
		check(values[i] == same.sample(d), "reconstructed seed exact")
		changed += int(absf(values[i] - other.sample(d)) > 1.0)
	for i in range(511, -1, -1):
		check(values[i] == terrain.sample(PlanetTerrain.uniform_direction(i, 512)), "reverse order exact")
	check(changed > 400, "different seed changes global samples")

func test_continuity() -> void:
	for face in range(6):
		for edge in range(4):
			var transition := PlanetTopology.get_edge_transition(face, edge)
			for i in range(33):
				var t := i / 32.0
				var a := PlanetMath.face_uv_to_direction(face, PlanetTopology.edge_uv(edge, t))
				var b := PlanetMath.face_uv_to_direction(transition.neighbor_face, PlanetTopology.edge_uv(transition.neighbor_edge, 1.0 - t if transition.is_reversed else t))
				check(absf(terrain.sample(a) - terrain.sample(b)) < EPS, "24 directed edges incl 8 physical corners")
				var inside := PlanetTopology.edge_uv(edge, t).lerp(Vector2(0.5, 0.5), 0.000001)
				check(absf(terrain.sample(a) - terrain.sample(PlanetMath.face_uv_to_direction(face, inside))) < 0.2, "one-sided face continuity")
	for face in range(6):
		for level in [0, 1, 2, 4, 6, 17, 24]:
			var divisions: int = 1 << level
			var id := PatchId.new(face, level, divisions / 2, divisions / 2)
			var uv := id.get_uv_bounds().position
			var direct := PlanetMath.face_uv_to_direction(face, uv)
			check(terrain.sample(direct) == terrain.sample(PlanetMath.face_uv_to_direction(face, id.local_uv_to_face_uv(Vector2.ZERO))), "LOD-independent exact shared point")

func test_sampler_benchmark() -> void:
	# Same FINAL descriptors and directions, changing only broad-phase indexing.
	# Reference instance belongs exclusively to this test; production is untouched.
	var reference := PlanetTerrain.new()
	for i in range(512):
		reference._main_buckets[i] = reference._main_field
		reference._minor_buckets[i] = reference._minor_field
		reference._sea_buckets[i] = reference._sea_field
		reference._region_buckets[i] = reference._regions
	var directions := PackedVector3Array()
	var fast := PackedFloat32Array()
	var slow := PackedFloat32Array()
	fast.resize(16384)
	slow.resize(16384)
	for i in range(16384):
		directions.append(PlanetTerrain.uniform_direction(i, 16384))
	var fast_times: Array[float] = []
	var slow_times: Array[float] = []
	for repeat in range(3):
		var started := Time.get_ticks_usec()
		for i in range(16384):
			slow[i] = reference.sample(directions[i])
		slow_times.append(float(Time.get_ticks_usec() - started) / 16384)
		started = Time.get_ticks_usec()
		for i in range(16384):
			fast[i] = terrain.sample(directions[i])
		fast_times.append(float(Time.get_ticks_usec() - started) / 16384)
	for i in range(16384):
		check(fast[i] == slow[i], "optimized full height exactly equals all-descriptor reference")
	fast_times.sort()
	slow_times.sort()
	print("TERRAIN_INDEX_COMPARISON median_us/query reference=%.3f indexed=%.3f samples=16384 repeats=3" % [slow_times[1], fast_times[1]])

func test_spatial_index() -> void:
	var directions := PackedVector3Array()
	for i in range(4096):
		directions.append(PlanetTerrain.uniform_direction(i, 4096))
	# Cartesian bin boundaries and points on both sides, all three axes.
	for axis in range(3):
		for boundary in range(1, 8):
			for delta in [-0.000001, 0.0, 0.000001]:
				var fixed: float = -1.0 + boundary * 0.25 + delta
				for j in range(16):
					var d := Vector3.ZERO
					d[axis] = fixed
					d[(axis + 1) % 3] = sqrt(1.0 - fixed * fixed) * cos(j * TAU / 16.0)
					d[(axis + 2) % 3] = sqrt(1.0 - fixed * fixed) * sin(j * TAU / 16.0)
					directions.append(d)
	for d in directions:
		var expected := minf(maxf(PlanetTerrain._field(d, terrain._main_field) + terrain._warp(d) + terrain._bias, PlanetTerrain._field(d, terrain._minor_field)), -PlanetTerrain._field(d, terrain._sea_field))
		check(expected == terrain.continentality(d), "broad-phase exact versus all descriptors")
		var bucket := PlanetTerrain._bucket(d)
		for region in terrain._regions:
			var x: float = d.dot(region.u) / region.length
			var y: float = d.dot(region.v) / region.width
			if d.dot(region.center) >= 0.93 and x * x + y * y < 1.0:
				check(terrain._region_buckets[bucket].has(region), "region bucket never discards active field")

func test_mesh_morph() -> void:
	var definition := PlanetDefinition.new()
	definition.base_radius_meters = 3000
	check(not definition.is_valid(), "terrain radius cannot invert the deepest surface")
	definition.terrain_enabled = false
	check(definition.is_valid(), "plain sphere retains positive-radius contract")
	var full_scale := PlanetPatchMesh.generate(PatchId.root(0), R, 0, terrain)
	var half_scale := PlanetPatchMesh.generate(PatchId.root(0), R * 0.5, 0, terrain, 2.0)
	for i in range(1089):
		check(half_scale.vertices[i].distance_to(full_scale.vertices[i] * 0.5) < EPS, "height meters converted exactly once")
	var tree := PlanetQuadtree.new()
	var sampler := PlanetSurfaceSampler.new(tree, R, {}, terrain)
	for face in range(6):
		var parent := PatchId.root(face)
		var coarse := PlanetPatchMesh.generate(parent, R, 0, terrain)
		for mask in range(16):
			var data := PlanetPatchMesh.with_mask(coarse, mask)
			for i in range(data.vertices.size()):
				var d := PlanetMath.face_uv_to_direction(face, data.uv[i])
				check(data.vertices[i].is_finite() and absf(data.vertices[i].length() - R - terrain.sample(d)) < EPS, "radius + height")
			for i in range(0, data.indices.size(), 3):
				var ia: int = data.indices[i]
				var ib: int = data.indices[i + 1]
				var ic: int = data.indices[i + 2]
				check(mini(ia, mini(ib, ic)) >= 0 and maxi(ia, maxi(ib, ic)) < 1089, "indices in range")
				var a: Vector3 = data.vertices[ia]
				var b: Vector3 = data.vertices[ib]
				var c: Vector3 = data.vertices[ic]
				check((b - a).cross(c - a).dot(a) < 0.0, "clockwise outward winding all masks")
		for child in parent.get_children_ids():
			var fine := PlanetPatchMesh.generate(child, R, 0, terrain)
			sampler.prepare(fine)
			for i in range(1089):
				var coarse_point := PlanetPatchMesh.sample(coarse, child.local_uv_to_face_uv(fine.uv[i]))
				check(fine.from[i].distance_to(coarse_point) < EPS, "morph0 coarse terrain (split and reverse merge)")
				check(fine.from[i].lerp(fine.vertices[i], 1.0).distance_to(fine.vertices[i]) < EPS, "morph1 fine terrain")
	for i in range(48):
		var d := PlanetTerrain.uniform_direction(i, 48)
		var location := PlanetMath.direction_to_face_uv(d)
		for level in [0, 2, 4, 6]:
			var div: int = 1 << level
			var id := PatchId.new(location.face, level, mini(div - 1, int(location.uv.x * div)), mini(div - 1, int(location.uv.y * div)))
			var data := PlanetPatchMesh.generate(id, R, 0, terrain)
			var error := PlanetSSE.geometric_error(id, R, terrain.patch_error(id))
			var extent := PlanetSSE.extent(id, R) + 3100.0
			for j in range(16):
				var uv := Vector2((j * 7 % 31 + 0.37) / 32.0, (j * 13 % 31 + 0.61) / 32.0)
				var direction := PlanetMath.face_uv_to_direction(id.face, id.local_uv_to_face_uv(uv))
				var actual := direction * (R + terrain.sample(direction))
				check(actual.distance_to(PlanetSSE.center(id, R)) <= extent, "terrain bound contains displaced samples")
				check(actual.distance_to(PlanetPatchMesh.sample(data, uv)) <= error + EPS, "SSE residual %s uv=%s observed=%.5f bound=%.5f field=%.5f" % [id, uv, actual.distance_to(PlanetPatchMesh.sample(data, uv)), error, terrain.continentality(direction)])

func test_controller() -> void:
	var view := PlanetQuadtreeView.new()
	root.add_child(view)
	var config := PlanetLodConfig.new()
	config.max_render_level = 2
	config.cpu_budget_ms = 0.0
	view.initialize(R, config, terrain)
	for distance in [53000.0, 100000000.0]:
		var stable := 0
		for frame in range(3000):
			view.step(Vector3(0, 0, distance), 720, 70, 0.1)
			check(view.commits_last_update <= config.mesh_budget and view.splits_last_update <= config.split_budget and view.merges_last_update <= config.merge_budget, "terrain budgets unchanged")
			stable = stable + 1 if view.state == "idle" else 0
			if stable == 3:
				break
			if frame % 50 == 0:
				await process_frame
		check(stable == 3 and view.tree.is_balanced(), "terrain controller converges and preserves 2:1")
	check(view.tree.leaves.size() == 6, "terrain merges return six roots")
	view.queue_free()
	await process_frame

func test_error_envelope() -> void:
	var worst := 0.0
	for i in range(8192):
		var direction := PlanetTerrain.uniform_direction(i, 8192)
		var location := PlanetMath.direction_to_face_uv(direction)
		var expected := direction * (R + terrain.sample(direction))
		for level: int in [0, 2, 4, 6]:
			var div := 1 << level
			var id := PatchId.new(location.face, level, mini(div - 1, int(location.uv.x * div)), mini(div - 1, int(location.uv.y * div)))
			var bounds := id.get_uv_bounds()
			var local := (location.uv - bounds.position) / bounds.size
			var weights := PlanetPatchMesh.sample_weights(i % 16, local)
			var interpolated := Vector3.ZERO
			for j in range(3):
				var uv := id.local_uv_to_face_uv(PlanetPatchMesh.grid_uv(weights[j]))
				var d := PlanetMath.face_uv_to_direction(id.face, uv)
				interpolated += d * (R + terrain.sample(d)) * weights[j + 3]
			var error := PlanetSSE.geometric_error(id, R, terrain.patch_error(id))
			var residual := expected.distance_to(interpolated)
			worst = maxf(worst, residual / (error + EPS))
			check(residual <= error + EPS, "global SSE %s mask=%d residual=%.4f estimate=%.4f" % [id, i % 16, residual, error])
	print("TERRAIN_SSE_MAX_SAMPLED_RATIO %.5f" % worst)

func test_terrain_transitions() -> void:
	var targets: Array[Dictionary] = []
	for face in range(6):
		targets.append({"name": "face_%d" % face, "direction": PlanetMath.get_face_normal(face), "level": 1})
	for landmark in terrain.debug_landmarks():
		if landmark.name in ["chain", "exceptional", "plateau", "inland_sea"]:
			landmark.level = 3
			targets.append(landmark)
	targets.append({"name": "coast", "direction": _coast_direction, "level": 3})
	for target in targets:
		var at := PlanetMath.direction_to_face_uv(target.direction)
		var coarse := PlanetQuadtree.new()
		for level: int in range(target.level):
			var n := 1 << level
			coarse.split(PatchId.new(at.face, level, mini(n - 1, int(at.uv.x * n)), mini(n - 1, int(at.uv.y * n))), 1000)
		var leaf := coarse.find_leaf(at.face, at.uv)
		var fine := coarse.copy_tree()
		check(fine.split(leaf.id, 1000) > 0 and fine.is_balanced(), "terrain split closure " + target.name)
		var sampler := PlanetSurfaceSampler.new(coarse, R, {}, terrain)
		var geometries := {}
		for patch in fine.active_leaves():
			var data := PlanetPatchMesh.generate(patch.id, R, fine.stitch_mask(patch.id), terrain)
			var original: PackedVector3Array = data.vertices.duplicate()
			sampler.prepare(data)
			check(original == data.vertices, "terrain cache remains immutable")
			geometries[patch.id.stable_key()] = data
			for index in range(0, data.indices.size(), 159):
				var uv: Vector2 = (data.uv[data.indices[index]] + data.uv[data.indices[index + 1]] + data.uv[data.indices[index + 2]]) / 3.0
				check(_morphed(data, uv, 0).distance_to(sampler.sample(patch.id.face, patch.id.local_uv_to_face_uv(uv))) < EPS, "coarse triangle interior endpoint " + target.name)
			# Actual mesh AABB includes both displacement AND reverse-merge endpoints.
			var box: AABB = PlanetPatchMesh.as_array_mesh(data).custom_aabb
			for index in range(0, 1089, 17):
				check(box.has_point(data.vertices[index]) and box.has_point(data.from[index]), "GPU AABB contains morph endpoints")
		for patch in fine.active_leaves():
			var data: Dictionary = geometries[patch.id.stable_key()]
			for edge in range(4):
				var adjacent := PlanetTopology.get_neighbor_patch(patch.id, edge)
				var destination_edge := edge ^ 1
				var reversed := false
				if adjacent.face != patch.id.face:
					var transition := PlanetTopology.get_edge_transition(patch.id.face, edge)
					destination_edge = transition.neighbor_edge
					reversed = transition.is_reversed
				for t in [0.0, 0.125, 0.37, 0.70, 1.0]:
					var uv := PlanetTopology.edge_uv(edge, t)
					var other_uv := adjacent.local_uv_to_face_uv(PlanetTopology.edge_uv(destination_edge, 1.0 - t if reversed else t))
					var neighbor := fine.find_leaf(adjacent.face, other_uv)
					var bounds := neighbor.id.get_uv_bounds()
					var other: Dictionary = geometries[neighbor.id.stable_key()]
					for factor in [0.0, 0.25, 0.5, 0.75, 1.0]:
						var a := _morphed(data, uv, factor)
						var b := _morphed(other, (other_uv - bounds.position) / bounds.size, factor)
						check(a.distance_to(b) < EPS, "watertight terrain/stitch/morph forward+reverse " + target.name)
		print("TERRAIN_MORPH_CASE %s leaves=%d OK" % [target.name, fine.leaves.size()])

func _morphed(data: Dictionary, uv: Vector2, factor: float) -> Vector3:
	var source := data.duplicate()
	source.vertices = data.from
	return PlanetPatchMesh.sample(source, uv).lerp(PlanetPatchMesh.sample(data, uv), factor)

func write_map(path: String) -> void:
	var image := Image.create(1024, 512, false, Image.FORMAT_RGB8)
	# Equal-area longitude/sin(latitude), independent of the quadtree.
	for y in range(512):
		var sy := 1.0 - 2.0 * (y + 0.5) / 512.0
		var r := sqrt(1.0 - sy * sy)
		for x in range(1024):
			var angle := x * TAU / 1024.0
			var h := terrain.sample(Vector3(cos(angle) * r, sy, sin(angle) * r))
			var color := Color(0.03, 0.10, 0.27).lerp(Color(0.16, 0.55, 0.65), clampf(1.0 + h / 3000.0, 0, 1)) if h < 0 else Color(0.34, 0.58, 0.23).lerp(Color(0.95, 0.85, 0.70), clampf(h / 1900.0, 0, 1))
			image.set_pixel(x, y, color)
	image.save_png(path)
	print("TERRAIN_MAP " + path)
