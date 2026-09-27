extends SceneTree
## Permanent integration/physics tests and reproducible real-world captures.
var failures := 0
var checks := 0
var output := ""
var graphic := false
var planet: PlanetRoot
var camera: Camera3D
var scene: Node3D
var samples: Array = []
var max_jobs := 0
var max_queue := 0
var max_pending := 0
var max_upload := 0.0
var max_collision := 0.0
var metrics := {}
var slow_frames: Array = []
var gpu_samples: Array = []
var local_samples: Array = []

func _initialize() -> void:
	_run.call_deferred()

func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		if failures < 25:
			printerr("TEST_FAILED " + message)

func frame() -> void:
	var start := Time.get_ticks_usec()
	await process_frame
	samples.append((Time.get_ticks_usec() - start) / 1000.0)
	var m := planet.mining_surface
	local_samples.append(m.last_update_ms)
	gpu_samples.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
	if samples[-1] > 40:
		slow_frames.append({"frame_ms": samples[-1], "local_update_ms": m.last_update_ms, "publish_ms": m.last_publish_ms, "commit_ms": m.last_commit_ms, "global_upload_ms": planet.renderer.last_upload_ms})
	max_jobs = maxi(max_jobs, m.jobs.size())
	max_queue = maxi(max_queue, m.queue.size())
	max_pending = maxi(max_pending, m.pending.size())
	max_upload = maxf(max_upload, m.last_commit_ms)
	max_collision = maxf(max_collision, m.last_collision_ms)
	expect(m.jobs.size() <= m.max_workers, "Worker bound")
	expect(m.pending.size() <= m.max_pending_results, "Pending result bound")
	expect(m.queue.size() <= m.max_visual_chunks, "Bounded deduplicated queue")
	expect(m.commits_this_frame <= m.max_commits_per_frame, "Upload count budget")
	if m.commit_budget_ms < 0.01:
		expect(m.commits_this_frame <= 1, "Time budget stops after one indivisible commit")

func settle(zone: MiningZone) -> bool:
	var deadline := Time.get_ticks_msec() + 120000
	var next_report := Time.get_ticks_msec() + 10000
	while Time.get_ticks_msec() < deadline:
		await frame()
		if Time.get_ticks_msec() >= next_report:
			next_report += 10000
			print("WAIT ", zone.id, " global=", planet.renderer.get_stats(), " mining jobs=", planet.mining_surface.jobs.size(), " pending=", planet.mining_surface.pending.size(), " queue=", planet.mining_surface.queue.size())
		var entry: Dictionary = planet.mining_surface.zones.get(zone.id, {})
		if not entry.is_empty() and not entry.error.is_empty():
			expect(false, entry.error)
			return false
		if entry.is_empty() or not entry.published:
			continue
		var ready := true
		for chunk: MiningChunk in zone._chunks.values():
			if chunk.active and (chunk.mesh_dirty() or chunk.collision_revision != chunk.revision):
				ready = false
		if ready:
			return true
	expect(false, "Zone converges within 120 seconds")
	print("TIMEOUT ", planet.renderer.get_stats(), " mining=", planet.mining_surface.queue, " jobs=", planet.mining_surface.jobs.size())
	return false

func capture(label: String) -> void:
	if graphic:
		await RenderingServer.frame_post_draw
		expect(root.get_texture().get_image().save_png(output.path_join(label + ".png")) == OK, "PNG " + label)

func pose(zone: MiningZone, distance: float, offset := Vector2.ZERO) -> void:
	var d := zone.local_to_direction(offset)
	var target := d * (zone.radius_m + planet.sample_final_height(d))
	camera.position = target + zone.up * distance + zone.tangent_y * distance * 0.8
	camera.look_at(target, zone.up)

func brush(zone: MiningZone, centre: Vector2, radius: float, delta: float) -> void:
	var first := Vector2i((centre - Vector2.ONE * radius) / 2)
	var last := Vector2i((centre + Vector2.ONE * radius) / 2)
	for y in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			var r := (Vector2(x, y) * 2 - centre).length() / radius
			if r < 1:
				expect(planet.editable_terrain.set_node_delta(zone.id, Vector2i(x, y), delta * pow(1 - r * r, 2)), "Technical radial edit")

func arrays_for(zone: MiningZone, coord: Vector2i) -> Array:
	return planet.mining_surface.zones[zone.id].meshes[coord].instance.mesh.surface_get_arrays(0)

func check_meshes(zone: MiningZone, natural: bool) -> void:
	var grid := {}
	for coord in planet.mining_surface.zones[zone.id].meshes:
		var arrays := arrays_for(zone, coord)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		expect(vertices.size() == 129 * 129, "129 squared vertices retained")
		expect(arrays[Mesh.ARRAY_INDEX].size() == 98304, "Full 128 squared cells retained")
		for y in range(129):
			for x in range(129):
				var index := y * 129 + x
				var node: Vector2i = coord * 128 + Vector2i(x, y)
				if x == 0 or x == 128 or y == 0 or y == 128:
					if grid.has(node):
						expect(vertices[index] == grid[node][0], "Exact shared side/corner position")
						expect(normals[index].distance_to(grid[node][1]) < 0.0002, "Shared final normal")
					else:
						grid[node] = [vertices[index], normals[index]]
				if x % 8 == 0 and y % 8 == 0:
					var d := zone.local_to_direction(Vector2(node) * 2)
					var h := planet.sample_base_height(d) + zone.read_node(node)
					expect(vertices[index].distance_to(d * (zone.radius_m + h)) < 0.02, "Final height equality")
					expect(absf(normals[index].length() - 1) < 0.001 and normals[index].dot(d) > 0.2, "Outward unit normal")
					if natural:
						expect(zone.read_node(node) == 0, "Zero delta baseline")
		var stored_faces := PackedVector3Array()
		for collision: CollisionShape3D in planet.mining_surface.zones[zone.id].meshes[coord].collisions:
			stored_faces.append_array(collision.shape.get_faces())
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for i in range(0, indices.size(), 97):
			expect(stored_faces[i].distance_to(vertices[indices[i]]) < 0.01, "Collision is final render triangle")

func check_ownership(zone: MiningZone) -> void:
	var outer := Rect2(Vector2(zone.chunk_bounds.position) * 256, Vector2(zone.chunk_bounds.size) * 256).grow(16)
	var entry: Dictionary = planet.mining_surface.zones[zone.id]
	var cut_points := PackedVector3Array()
	for key: String in entry.replacement:
		var mesh: ArrayMesh = entry.replacement[key]
		if mesh.get_surface_count() == 0:
			continue
		var arrays := mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for i in range(0, indices.size(), 3):
			var centre := (vertices[indices[i]] + vertices[indices[i + 1]] + vertices[indices[i + 2]]) / 3
			expect(not outer.grow(-0.03).has_point(zone.planet_to_local(centre)), "No global triangle beneath local ownership")
		for v in vertices:
			var xy := zone.planet_to_local(v)
			if absf(xy.x - outer.position.x) < 0.03 or absf(xy.x - outer.end.x) < 0.03 or absf(xy.y - outer.position.y) < 0.03 or absf(xy.y - outer.end.y) < 0.03:
				cut_points.append(v)
	var ring_arrays: Array = entry.ring.instance.mesh.surface_get_arrays(0)
	var maximum := 0.0
	for v: Vector3 in ring_arrays[Mesh.ARRAY_VERTEX]:
		var xy := zone.planet_to_local(v)
		if absf(xy.x - outer.position.x) < 0.03 or absf(xy.x - outer.end.x) < 0.03 or absf(xy.y - outer.position.y) < 0.03 or absf(xy.y - outer.end.y) < 0.03:
			var nearest := INF
			for cut in cut_points:
				nearest = minf(nearest, cut.distance_to(v))
			maximum = maxf(maximum, nearest)
			expect(nearest < 0.03, "Global/collar cut polyline matches within 3 cm")
	metrics.collar_seam_max_m = maximum

func physics_checks(zone: MiningZone) -> void:
	await physics_frame
	await physics_frame
	var max_error := 0.0
	for xy in [Vector2.ZERO, Vector2(0.7, 1.1), Vector2(10, 0), Vector2(60, 40), Vector2(-80, 30)]:
		var d := zone.local_to_direction(xy)
		var h := planet.sample_final_height(d)
		var expected := d * (zone.radius_m + h)
		var query := PhysicsRayQueryParameters3D.create(expected + d * 50, expected - d * 50)
		var hit := root.world_3d.direct_space_state.intersect_ray(query)
		expect(not hit.is_empty(), "Ray hits edited local surface")
		if not hit.is_empty():
			var error: float = hit.position.distance_to(expected)
			max_error = maxf(max_error, error)
			expect(error < 0.05, "Ray agrees with final sampler within 5 cm")
	metrics.physics_max_error_m = max_error

func percentile(values: Array, fraction: float) -> float:
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[mini(sorted.size() - 1, int(sorted.size() * fraction))] if not sorted.is_empty() else 0.0

func _run() -> void:
	print("INTEGRATION boot")
	graphic = DisplayServer.get_name() != "headless"
	var args := OS.get_cmdline_user_args()
	output = args[0] if not args.is_empty() else "res://docs/evidence/13_integracao_terreno_editavel/headless"
	DirAccess.make_dir_recursive_absolute(output)
	Engine.max_fps = 120
	root.size = Vector2i(1100, 760)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	scene = load("res://scenes/planet_lab/planet_lab.tscn").instantiate()
	root.add_child(scene)
	print("INTEGRATION scene ready")
	planet = scene.get_node("Planet")
	camera = scene.get_node("Cameras/FreeFlyCamera")
	for node in scene.get_node("Cameras").get_children():
		node.set_process(false)
		node.set_physics_process(false)
		node.set_process_input(false)
	camera.current = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	var manager := planet.mining_surface
	manager.max_workers = 2 if "--two-workers" in args else 1
	expect(MiningSurfaceManager.priority_before({"tier": 0, "distance": 1000, "revision": 1}, {"tier": 1, "distance": 10, "revision": 100}), "Visible nearby before edited distant")
	expect(MiningSurfaceManager.priority_before({"tier": 1, "distance": 1000, "revision": 100}, {"tier": 1, "distance": 10, "revision": 1}), "Newest distant edit before older distant edit")
	var anchor := Vector3(1, 0.4, 1).normalized()
	# Select a smooth land point exactly at a cube-face boundary.
	var best := INF
	for axis in range(3):
		for sign_a in [-1.0, 1.0]:
			for sign_b in [-1.0, 1.0]:
				for i in range(-8, 9):
					var d := Vector3(sign_a, sign_b, i / 10.0)
					if axis == 1:
						d = Vector3(sign_a, i / 10.0, sign_b)
					elif axis == 2:
						d = Vector3(i / 10.0, sign_a, sign_b)
					d = d.normalized()
					var score := absf(planet.sample_base_height(d) - 100)
					if score < best:
						best = score
						anchor = d
	var zone := planet.editable_terrain.create_zone("integration-edge", anchor)
	pose(zone, 650)
	# Wait for the global renderer before comparing steady-state frames.
	var warmup := Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < warmup:
		await process_frame
	await capture("01_global_natural")
	print("INTEGRATION warmup ready")
	samples.clear()
	var revision := planet.renderer.revision
	expect(manager.activate(zone), "Activate integrated zone")
	if not await settle(zone):
		finish()
		return
	metrics.first_chunk_commit_ms = manager.zones[zone.id].first_commit_ms
	metrics.zone_visible_ms = manager.zones[zone.id].visible_ms
	metrics.activation_frame_p50_ms = percentile(samples, 0.5)
	metrics.activation_frame_p95_ms = percentile(samples, 0.95)
	metrics.activation_frame_max_ms = percentile(samples, 1)
	check_meshes(zone, true)
	check_ownership(zone)
	if graphic:
		var first_mesh: ArrayMesh = manager.zones[zone.id].meshes.values()[0].instance.mesh
		var device_buffers := RenderingServer.mesh_get_surface(first_mesh.get_rid(), 0)
		var byte_count := 0
		for key in ["vertex_data", "attribute_data", "index_data", "skin_data"]:
			if device_buffers.has(key):
				byte_count += device_buffers[key].size()
		metrics.arraymesh_device_buffer_bytes = byte_count
		metrics.process_static_mib = Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
		metrics.process_video_mib = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0
	for item: Dictionary in manager.zones[zone.id].meshes.values():
		expect(item.instance.get_world_3d() == planet.get_world_3d(), "Local surface lives in the real planet world")
	expect(planet.renderer.revision == revision, "No global rebuild on activation")
	await capture("02_integrated_natural")
	pose(zone, 150)
	await capture("03_natural_close")
	var old := planet.editable_terrain.snapshot_chunk_async(zone.id, Vector2i.ZERO)
	manager.max_commits_per_frame = 8
	manager.commit_budget_ms = 0.001
	brush(zone, Vector2.ZERO, 42, -12)
	brush(zone, Vector2(60, 40), 22, 8)
	brush(zone, Vector2(-80, 30), 16, -4)
	expect(not planet.editable_terrain.snapshot_current(old), "Old revision rejected")
	expect(not planet.editable_terrain.set_cell_delta(zone.id, Vector2i(-127, 0), -5), "Protected outer band rejects atomic cell edit")
	# Start a real worker and supersede its snapshot while it is running.
	manager._schedule()
	expect(not manager.jobs.is_empty(), "Real asynchronous job started")
	for job: Dictionary in manager.jobs:
		if job.kind == "chunk":
			var node: Vector2i = job.snapshot.coordinate * 128 + Vector2i(60, 60)
			planet.editable_terrain.set_node_delta(zone.id, node, -1)
	var stale_before := manager.discarded
	var edit_start := Time.get_ticks_usec()
	samples.clear()
	if not await settle(zone):
		finish()
		return
	metrics.edit_wall_ms = (Time.get_ticks_usec() - edit_start) / 1000.0
	metrics.edit_frame_p50_ms = percentile(samples, 0.5)
	metrics.edit_frame_p95_ms = percentile(samples, 0.95)
	metrics.edit_frame_max_ms = percentile(samples, 1)
	expect(manager.discarded > stale_before, "Completed stale job discarded before upload")
	manager.max_commits_per_frame = 1
	manager.commit_budget_ms = 2.0
	metrics.edit_including_stale_wall_ms = metrics.edit_wall_ms
	# Comparable four-chunk rebuild without a deliberately discarded fifth job.
	brush(zone, Vector2.ZERO, 42, -14)
	samples.clear()
	edit_start = Time.get_ticks_usec()
	await settle(zone)
	metrics.four_chunk_edit_wall_ms = (Time.get_ticks_usec() - edit_start) / 1000.0
	metrics.four_chunk_frame_p50_ms = percentile(samples, 0.5)
	metrics.four_chunk_frame_p95_ms = percentile(samples, 0.95)
	metrics.four_chunk_frame_max_ms = percentile(samples, 1)
	check_meshes(zone, false)
	await physics_checks(zone)
	await capture("04_edited_close")
	if graphic:
		var target := anchor * (zone.radius_m + planet.sample_base_height(anchor))
		camera.position = target + zone.up * 35 + zone.tangent_y * 125
		camera.look_at(target - zone.up * 7, zone.up)
		for i in range(5):
			await process_frame
		await capture("04b_edited_profile")
	pose(zone, 650)
	await capture("05_edited_zone")
	var debug := MiningDebugView.new()
	planet.add_child(debug)
	debug.configure(manager, zone)
	for i in range(30):
		await process_frame
	await capture("06_f9_states")
	debug.queue_free()
	# Unrelated chunk resources must survive an interior edit.
	var before := {}
	for coord in manager.zones[zone.id].meshes:
		before[coord] = manager.zones[zone.id].meshes[coord].instance.mesh
	planet.editable_terrain.set_node_delta(zone.id, Vector2i(60, 60), 2)
	await settle(zone)
	for coord in before:
		if coord != Vector2i.ZERO:
			expect(before[coord] == manager.zones[zone.id].meshes[coord].instance.mesh, "Only dirty region rebuilt")
	# A second chart across the planet must coexist, including orbital rendering.
	var second := planet.editable_terrain.create_zone("integration-second", -anchor, Rect2i(0, 0, 1, 1))
	expect(second != null and manager.activate(second), "Second independent zone activation")
	await settle(second)
	expect(manager.zones[zone.id].published and manager.zones[second.id].published, "Two zones own their separate regions")
	camera.position = anchor * 140000
	camera.look_at(Vector3.ZERO, Vector3.UP)
	for i in range(90):
		await process_frame
	await capture("07_orbit_active")
	var bytes_before := zone.delta_bytes()
	var originals: Dictionary = manager.zones[zone.id].originals.duplicate()
	manager.deactivate(zone.id)
	for key in originals:
		if planet.renderer._nodes.has(key):
			expect(planet.renderer._nodes[key].mesh_instance.mesh == originals[key], "Original global mesh restored")
	expect(zone.delta_bytes() == bytes_before and zone.sample_delta(Vector2.ZERO) == -14, "Deactivation retains edits")
	manager.deactivate(second.id)
	expect(planet.renderer.mining_pins.is_empty(), "All LOD pins released")
	await capture("08_orbit_inactive")
	pose(zone, 180)
	expect(manager.activate(zone), "Reactivation accepted")
	await settle(zone)
	await physics_checks(zone)
	await capture("09_reactivated_edits")
	manager.deactivate(zone.id)
	# Deactivation during generation invalidates epoch/session and never uploads.
	manager.activate(zone)
	manager._schedule()
	manager.deactivate(zone.id)
	var committed_before := manager.committed
	var deadline := Time.get_ticks_msec() + 30000
	while not manager.jobs.is_empty() and Time.get_ticks_msec() < deadline:
		await frame()
	expect(manager.committed == committed_before and manager.zones.is_empty(), "Cancelled session cannot commit")
	var debug_anchor := anchor.cross(Vector3.UP).normalized()
	camera.position = debug_anchor * (zone.radius_m + planet.sample_base_height(debug_anchor) + 400)
	planet.toggle_mining_debug()
	expect(is_instance_valid(planet.mining_debug), "F9 creates in-world diagnostics")
	expect(planet.mining_debug.get_world_3d() == planet.get_world_3d(), "F9 has no isolated World3D")
	planet.toggle_mining_debug()
	expect(planet.mining_debug == null and manager.zones.is_empty(), "F9 closes diagnostics and representation")
	finish()

func finish() -> void:
	var m := planet.mining_surface
	metrics.merge({"workers": m.max_workers, "checks": checks, "failures": failures,
		"logical_processors": OS.get_processor_count(), "pool_max_threads_setting": ProjectSettings.get_setting("threading/worker_pool/max_threads", -1),
		"job_intervals": m.job_intervals,
		"slow_frames": slow_frames,
		"local_update_p95_ms": percentile(local_samples, 0.95), "local_update_max_ms": percentile(local_samples, 1),
		"gpu_p95_ms": percentile(gpu_samples, 0.95),
		"max_jobs": max_jobs, "max_pending": max_pending, "max_queue": max_queue,
		"max_commit_ms": max_upload, "max_collision_commit_ms": max_collision,
		"job_p50_ms": percentile(m.job_times, 0.5), "job_p95_ms": percentile(m.job_times, 0.95),
		"commit_p95_ms": percentile(m.commit_times, 0.95), "collision_p95_ms": percentile(m.collision_times, 0.95),
		"discarded": m.discarded, "graphic": graphic, "job_times_ms": m.job_times})
	FileAccess.open(output.path_join("metrics.json"), FileAccess.WRITE).store_string(JSON.stringify(metrics, "  "))
	var summary := metrics.duplicate()
	summary.erase("slow_frames")
	summary.erase("job_times_ms")
	summary.erase("job_intervals")
	print("MINING_INTEGRATION " + JSON.stringify(summary))
	scene.queue_free()
	await process_frame
	quit(1 if failures else 0)
