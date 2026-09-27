extends SceneTree
var failures: Array[String] = []
var checks := 0
var max_error_m := 0.0
var fingerprint := PackedFloat32Array()

func _initialize() -> void:
	_run.call_deferred()

func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok and failures.size() < 40:
		failures.append(message)

func _run() -> void:
	var definition: PlanetDefinition = load("res://systems/planet/surface/data/test_planet_100km.tres")
	var geology := PlanetGeology.new(definition)
	var shape := PlanetShape.new(definition, geology)
	var climate := PlanetClimate.new(definition, -1, geology)
	var biomes := PlanetBiomes.new(definition, climate, geology)
	var terrain := PlanetEditableTerrain.new(shape, climate, biomes)
	expect(terrain._zones.is_empty(), "No zones or edit grid at startup")
	var anchors := [Vector3.UP, Vector3.DOWN, Vector3.RIGHT, Vector3(1, 0, 1).normalized(), Vector3(1, 1, 1).normalized()]
	for a: Vector3 in anchors:
		var coordinates := PlanetEditableTerrain.new(shape)
		var zone := coordinates.create_zone("coordinate-test", a, Rect2i(-4, -4, 8, 8))
		expect(zone != null, "Valid zone at poles/face edge/corner")
		for y in [-1024.0, -768.1, -256.0, -2.0, 0.0, 2.1, 767.1, 1023.9]:
			for x in [-1024.0, -769.1, -256.0, -2.0, 0.0, 2.1, 767.1, 1023.9]:
				var local := Vector2(x, y)
				for height in [-350.0, 0.0, 2000.0]:
					var inverse := zone.planet_to_local(zone.local_to_planet(local, height))
					var error := inverse.distance_to(local)
					max_error_m = maxf(max_error_m, error)
					expect(error < 0.015, "Planet/Zone inverse within 15 mm")
					# Boundary positions have an unavoidable float32 ambiguity; test
					# logical indexing away from that ambiguity, including negative cells.
					if absf(fposmod(x, 2)) > 0.02 and absf(fposmod(y, 2)) > 0.02:
						expect(zone.cell_at(inverse) == zone.cell_at(local), "Roundtrip keeps cell index")
		for c in range(-1024, 1024):
			var cell := Vector2i(c, -c - 1)
			var owner := MiningZone.owner_of(cell)
			var local := MiningZone.local_index(cell)
			expect(local.x >= 0 and local.x < 128 and local.y >= 0 and local.y < 128, "Local indexing range")
			expect(owner * 128 + local == cell, "Chunk/Cell bijection including negative coordinates")
		expect(not zone.planet_to_local(-a).is_finite(), "Back hemisphere is outside chart")
		expect(coordinates.sample_edit_delta(-a) == 0, "No antipodal edit alias")
	var zone := terrain.create_zone("mining-v1:test", Vector3(1, 0, 1).normalized())
	expect(terrain.create_zone(zone.id, Vector3.UP) == null, "Duplicate ID rejected")
	expect(terrain.create_zone("overlap", zone.up) == null, "Overlap rejected independently of activity")
	expect(terrain.create_zone("bad", Vector3.ZERO) == null, "Zero anchor rejected")
	expect(terrain.create_zone("bad", Vector3(1e30, 0, 0)) == null, "Overflowing anchor rejected")
	expect(terrain.create_zone("bad", Vector3.UP, Rect2i(0, 0, 9, 9)) == null, "Oversized zone rejected")
	var lifetime := PlanetEditableTerrain.new(shape)
	var fresh := lifetime.create_zone("persisted-id", Vector3.UP, Rect2i(0, 0, 8, 8))
	for p in [Vector2(2047.9, 2047.9), Vector2(1800.2, 1800.4)]:
		var error := fresh.planet_to_local(fresh.local_to_planet(p, 1500)).distance_to(p)
		max_error_m = maxf(max_error_m, error)
		expect(error < 0.015, "Precision at the furthest allowed chunks")
	fresh.activate_chunk(Vector2i.ZERO)
	var removed_snapshot := lifetime.snapshot_chunk(fresh.id, Vector2i.ZERO)
	expect(lifetime.remove_zone(fresh.id), "Clean zone removable")
	expect(not fresh.active and fresh._chunks.is_empty(), "Removal invalidates retained debug references")
	fresh = lifetime.create_zone("persisted-id", Vector3.UP)
	fresh.activate_chunk(Vector2i.ZERO)
	expect(not lifetime.accept_mesh(removed_snapshot), "Recreated ID rejects prior epoch")
	var deactivated_snapshot := lifetime.snapshot_chunk(fresh.id, Vector2i.ZERO)
	fresh.deactivate_chunk(Vector2i.ZERO)
	expect(not fresh.active and fresh._chunks.is_empty(), "Single clean chunk deactivation releases record")
	fresh.activate_chunk(Vector2i.ZERO)
	expect(not lifetime.accept_mesh(deactivated_snapshot), "Recreated chunk rejects old revision")
	# Same edits in opposite orders produce the same owned samples/interpolation.
	var ordered := PlanetEditableTerrain.new(shape)
	var reverse := PlanetEditableTerrain.new(shape)
	var ordered_zone := ordered.create_zone("order", zone.up)
	var reverse_zone := reverse.create_zone("order", zone.up)
	for i in range(20):
		ordered.set_node_delta("order", Vector2i(i - 10, i - 10), float(i - 10))
	for i in range(19, -1, -1):
		reverse.set_node_delta("order", Vector2i(i - 10, i - 10), float(i - 10))
	for i in range(-20, 20):
		var p := Vector2(i + 0.25, i + 0.5)
		expect(ordered_zone.sample_delta(p) == reverse_zone.sample_delta(p), "Edit order deterministic")
	for y in range(-1, 1):
		for x in range(-1, 1):
			expect(zone.activate_chunk(Vector2i(x, y)), "Chunk activation")
	expect(zone.delta_bytes() == 0 and zone._chunks.size() == 4, "Active untouched zone has zero delta payload")
	expect(not zone.activate_chunk(Vector2i(1, 1)), "Out of bounds activation rejected")
	for i in range(1024):
		var direction := Vector3(sin(i * 0.71), cos(i * 0.39), sin(i * 0.13)).normalized()
		expect(terrain.sample_final_height(direction) == shape.sample_base_height(direction), "Exact zero delta composition")
		fingerprint.append(shape.sample_base_height(direction))
	var snapshots: Array[Dictionary] = []
	for y in range(-1, 1):
		for x in range(-1, 1):
			var snapshot := terrain.snapshot_chunk(zone.id, Vector2i(x, y))
			snapshots.append(snapshot)
			expect(terrain.accept_mesh(snapshot), "Initial snapshot accepted")
	expect(terrain.set_node_delta(zone.id, Vector2i.ZERO, -12), "Negative edit")
	expect(zone.delta_bytes() == 65536, "One buffer owns the shared corner")
	for snapshot in snapshots:
		expect(not terrain.accept_mesh(snapshot), "Four corner jobs invalidated")
		expect(snapshot.deltas[65 * 131 + 65] == 0, "Detached snapshot does not mutate")
	for c: MiningChunk in zone._chunks.values():
		expect(c.mesh_dirty(), "All four chunks dirty at corner")
		expect(c.collision_revision == -1, "Collision remains independently pending")
	expect(zone.sample_delta(Vector2.ZERO) == -12, "Exact stored node")
	var volume := 0.0
	for cell in [Vector2i(-1, -1), Vector2i(-1, 0), Vector2i(0, -1), Vector2i.ZERO]:
		volume += zone.approximate_cell_volume_m3(cell)
	expect(absf(volume + 48) < 0.001, "Single node volume counted once over four cells")
	expect(is_equal_approx(zone.sample_delta(Vector2(0.5, 0.5)), -6), "Triangle interpolation matches mesh diagonal")
	expect(zone.sample_delta(Vector2(1, 1)) == 0, "Mesh diagonal has no bilinear saddle discrepancy")
	for p in [Vector2(-0.001, 0.7), Vector2(0.001, 0.7), Vector2(0.7, -0.001), Vector2(0.7, 0.001)]:
		expect(absf(zone.sample_delta(p) + 7.8) < 0.01, "Continuous left/right and top/bottom")
	var direction := zone.local_to_direction(Vector2.ZERO)
	var natural := shape.sample_base_height(direction)
	expect(absf(terrain.sample_final_height(direction) - natural + 12) < 0.03, "Natural plus radial negative delta")
	expect(terrain.sample_edit_delta(zone.local_to_direction(Vector2(50, 50))) == 0, "Remote location unchanged")
	expect(terrain.set_node_delta(zone.id, Vector2i.ZERO, 9), "Positive fill")
	expect(zone.sample_delta(Vector2.ZERO) == 9, "Positive query")
	expect(terrain.set_node_delta(zone.id, Vector2i.ZERO, 0), "Clear")
	expect(zone.delta_bytes() == 0, "All-zero buffer released")
	expect(terrain.sample_final_height(direction) == natural, "Exact return to natural")
	expect(not terrain.set_node_delta(zone.id, Vector2i(-128, 0), -1), "Zone perimeter locked to zero")
	expect(not terrain.set_node_delta(zone.id, Vector2i(2000, 0), 1), "Out of bounds edit rejected")
	for bad in [NAN, INF, -INF, -101.0, 101.0]:
		expect(not terrain.set_node_delta(zone.id, Vector2i.ZERO, bad), "Unsafe delta rejected")
	terrain.max_cut_m = 1e10
	expect(not terrain.set_node_delta(zone.id, Vector2i.ZERO, -49000), "Hard radial bound remains")
	terrain.max_cut_m = 100
	expect(terrain.set_cell_delta(zone.id, Vector2i(12, 13), -4), "Cell writes its four shared corners")
	expect(zone.sample_delta(Vector2(25, 27)) == -4, "Cell interpolated interior")
	expect(absf(zone.approximate_cell_volume_m3(Vector2i(12, 13)) + 16) < 0.001, "Reference-sphere volume convention")
	var revision := zone.chunk_at(Vector2i.ZERO).revision
	expect(terrain.set_cell_delta(zone.id, Vector2i(12, 13), -4), "Idempotent edit succeeds")
	expect(zone.chunk_at(Vector2i.ZERO).revision == revision, "No revision for identical write")
	expect(not terrain.set_cell_delta(zone.id, Vector2i(127, 0), 3), "Atomic cell edit rejects locked corner")
	expect(zone.read_node(Vector2i(127, 0)) == 0, "Rejected cell makes no partial write")
	expect(not terrain.remove_zone(zone.id), "Cannot silently discard edits")
	var before_unload := terrain.sample_final_height(zone.local_to_direction(Vector2(25, 27)))
	var stale_edited := terrain.snapshot_chunk(zone.id, Vector2i.ZERO)
	zone.deactivate()
	expect(terrain.sample_final_height(zone.local_to_direction(Vector2(25, 27))) == before_unload, "Inactive edit history still sampled")
	expect(terrain.snapshot_chunk(zone.id, Vector2i.ZERO).is_empty(), "Inactive chunk has no mesh job")
	for y in range(-1, 1):
		for x in range(-1, 1):
			zone.activate_chunk(Vector2i(x, y))
	expect(not terrain.accept_mesh(stale_edited), "Reactivation rejects old edited-chunk snapshot")
	var edge_a := CubeSphereMapping.direction_to_face_uv(zone.local_to_direction(Vector2(-100, 0)))
	var edge_b := CubeSphereMapping.direction_to_face_uv(zone.local_to_direction(Vector2(100, 0)))
	expect(edge_a.face != edge_b.face, "Zone really crosses two cube faces")
	var curved := zone.local_to_planet(Vector2(256, 0), 0)
	expect(absf(curved.length() - zone.radius_m) < 0.01, "Patch lies on reference sphere")
	expect(MiningZone.dot64(curved - zone.up * zone.radius_m, zone.up) < -0.6, "Curvature sag is not flattened")
	# Halo invalidation: node x=1 affects the normal at x=0 in the negative chunk.
	for coord in zone._chunks:
		terrain.accept_mesh(terrain.snapshot_chunk(zone.id, coord))
	terrain.set_node_delta(zone.id, Vector2i(1, 50), -2)
	expect(zone.chunk_at(Vector2i(-1, 0)).mesh_dirty(), "Normal halo invalidates neighbour one node beyond boundary")
	expect(not zone.chunk_at(Vector2i(-1, -1)).mesh_dirty(), "Unrelated chunk stays clean")
	# Four high-resolution patches crossing a cube-face edge; compare exact shared
	# positions and normals. Separate workers own samplers and detached inputs.
	terrain.set_node_delta(zone.id, Vector2i.ZERO, -8)
	var meshes: Dictionary = {}
	for y in range(-1, 1):
		for x in range(-1, 1):
			var coord := Vector2i(x, y)
			var snap := terrain.snapshot_chunk(zone.id, coord)
			fingerprint.append_array(snap.deltas)
			var arrays := MiningMeshBuilder.build(snap, shape)
			meshes[coord] = arrays
			expect(arrays[Mesh.ARRAY_VERTEX].size() == 16641, "128 cells -> 129 samples")
			expect(arrays[Mesh.ARRAY_INDEX].size() == 98304, "32768 triangles with valid indexing")
			for index: int in arrays[Mesh.ARRAY_INDEX]:
				expect(index >= 0 and index < 16641, "Valid vertex index")
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			for i in range(vertices.size()):
				expect(vertices[i].is_finite() and normals[i].is_finite() and normals[i].y > 0, "Finite, outward mesh")
			var job := WorkerThreadPool.add_task(func() -> void:
				var local_shape := PlanetShape.new(definition.duplicate(true), geology)
				var worker_arrays := MiningMeshBuilder.build(snap, local_shape)
				snap["worker_vertices"] = worker_arrays[Mesh.ARRAY_VERTEX]
			)
			WorkerThreadPool.wait_for_task_completion(job)
			expect(snap.worker_vertices == vertices, "Worker snapshot matches synchronous mesh")
			terrain.accept_mesh(snap)
	for i in range(129):
		for y in range(-1, 1):
			for attr in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL]:
				expect(meshes[Vector2i(-1, y)][attr][i * 129 + 128] == meshes[Vector2i(0, y)][attr][i * 129], "Shared vertical edge exact")
		for x in range(-1, 1):
			for attr in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL]:
				expect(meshes[Vector2i(x, -1)][attr][128 * 129 + i] == meshes[Vector2i(x, 0)][attr][i], "Shared horizontal edge exact")
	var context := terrain.sample_context(direction * 50000, 20)
	expect(context.geology == geology.sample(direction), "Geology context comes from service")
	expect(context.climate != null and context.biome != null and not context.stratigraphy_available, "Climate/biome on demand, no invented strata")
	for i in range(1024):
		var d := Vector3(sin(i * 0.71), cos(i * 0.39), sin(i * 0.13)).normalized()
		expect(shape.sample_base_height(d) == fingerprint[i], "Natural authority unchanged by edits")
		# Packed float32 comparison above is valid because natural height is Vector4.x.
	var report := benchmark(shape)
	report["max_coordinate_error_m"] = max_error_m
	report["checks"] = checks
	print("MINING_METRICS " + JSON.stringify(report))
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(fingerprint.to_byte_array())
	print("MINING fingerprint=" + hash.finish().hex_encode())
	print("MINING checks=%d failures=%d" % [checks, failures.size()])
	for failure in failures:
		printerr("TEST_FAILED " + failure)
	quit(0 if failures.is_empty() else 1)

func benchmark(shape: PlanetShape) -> Dictionary:
	var measurements := []
	for side in [1, 2, 4, 8]:
		var t0 := Time.get_ticks_usec()
		var terrain := PlanetEditableTerrain.new(shape)
		var zone := terrain.create_zone("benchmark", Vector3.UP, Rect2i(0, 0, side, side))
		for y in range(side):
			for x in range(side):
				zone.activate_chunk(Vector2i(x, y))
		var create_ms := (Time.get_ticks_usec() - t0) / 1000.0
		expect(zone.delta_bytes() == 0, "Lazy allocation before first edit")
		t0 = Time.get_ticks_usec()
		for y in range(side):
			for x in range(side):
				terrain.set_cell_delta(zone.id, Vector2i(x * 128 + 64, y * 128 + 64), -2)
		var edit_ms := (Time.get_ticks_usec() - t0) / 1000.0
		expect(zone.delta_bytes() == side * side * 65536, "Exact sparse buffer payload")
		var d := zone.local_to_direction(Vector2(129, 129))
		t0 = Time.get_ticks_usec()
		for i in range(10000):
			terrain.sample_edit_delta(d)
		var query_us := (Time.get_ticks_usec() - t0) / 10000.0
		t0 = Time.get_ticks_usec()
		for i in range(1000):
			terrain.sample_final_height(d)
		var final_us := (Time.get_ticks_usec() - t0) / 1000.0
		t0 = Time.get_ticks_usec()
		for i in range(100):
			terrain.set_cell_delta(zone.id, Vector2i(64, 64), -3.0 if i % 2 == 0 else 2.0)
		var update_us := (Time.get_ticks_usec() - t0) / 100.0
		measurements.append({"chunks": side * side, "create_ms": create_ms, "edit_ms": edit_ms,
			"delta_bytes": zone.delta_bytes(), "query_delta_us": query_us, "query_final_us": final_us,
			"update_cell_us": update_us})
	return {"chunks": measurements}
