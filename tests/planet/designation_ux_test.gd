extends "res://tests/planet/designation_demo.gd"
## Stage 15 route: published hillside, actual picking, async apply, warm F9, 4096.

func evaluate_preview(plan: TerrainDesignation) -> Dictionary:
	var job := store.begin_evaluation(plan)
	while not store.advance_evaluation(job):
		await process_frame
	return job

func wait_transaction() -> void:
	var deadline := Time.get_ticks_msec() + 30000
	while (not store.running.is_empty() or not store.queued.is_empty()) and Time.get_ticks_msec() < deadline:
		await frame()
	expect(store.running.is_empty() and store.queued.is_empty(), "Async delta preparation converges")

func _run() -> void:
	graphic = DisplayServer.get_name() != "headless"
	output = OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "res://docs/evidence/15_ux_performance_designacao/headless"
	DirAccess.make_dir_recursive_absolute(output)
	Engine.max_fps = 120
	root.size = Vector2i(1100, 760)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	scene = load("res://scenes/planet_lab/planet_lab.tscn").instantiate()
	root.add_child(scene)
	planet = scene.get_node("Planet")
	camera = scene.get_node("Cameras/FreeFlyCamera")
	for controller in scene.get_node("Cameras").get_children():
		controller.set_process(false)
		controller.set_process_input(false)
	camera.current = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	var anchor := Vector3(1, 0.4, 1).normalized()
	if "--land" in OS.get_cmdline_user_args():
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
	metrics.anchor = str(anchor)
	camera.position = anchor * (50000 + planet.sample_base_height(anchor) + 80)
	camera.look_at(anchor * 50000, Vector3.UP)
	var toggles := []
	for i in range(5):
		planet.toggle_mining_debug()
		toggles.append(planet.mining_debug.last_toggle_ms)
		await process_frame
	expect(planet.editable_terrain._zones.is_empty(), "F9 never creates or activates terrain")
	metrics.f9_empty_toggle_ms = toggles
	planet.mining_debug.set_enabled(false)
	var zone := planet.editable_terrain.create_zone("ux-demo", anchor)
	store = planet.designations
	store.datum = TerrainLevelDatum.new(roundf(planet.sample_base_height(anchor)) - 10, 1)
	expect(planet.mining_surface.activate(zone), "Activate local surface explicitly")
	expect(await settle(zone), "Natural local surface published")
	# Deterministic technical hillside: low plateau Level 10, then Current 11..20.
	for y in range(-3, 22):
		for x in range(-3, 25):
			var node := Vector2i(x, y)
			var current := store.datum.height(10) + maxf(0, x - 2) * 0.5
			var natural: float = planet.editable_terrain.published_node(zone.id, node).natural
			expect(planet.editable_terrain.set_node_delta(zone.id, node, current - natural), "Prepare hillside fixture")
	expect(await settle(zone), "Hillside published before interaction")
	tool = TerrainDesignationTool.new()
	tool.add_to_group("terrain_designation")
	planet.add_child(tool)
	tool.configure(store, planet.mining_surface, zone)
	tool.set_process_input(false)
	tool.set_process_unhandled_input(false)
	pose(zone, 32, Vector2(18, 16))
	await physics_frame
	await wait_preview()
	var frozen_pose := camera.transform
	var start_cell := Vector2i(0, 5)
	var end_cell := Vector2i(20, 14)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = camera.unproject_position(zone.local_to_planet((Vector2(start_cell) + Vector2(0.5, 0.5)) * 2, store.datum.height(10)))
	tool._unhandled_input(press)
	expect(tool.dragging and tool.first_cell == start_cell, "Published physics pick starts at low cell")
	expect(root.get_node("CameraManager").designation_dragging, "Drag owns camera input")
	var motion := InputEventMouseMotion.new()
	motion.position = camera.unproject_position(zone.local_to_planet((Vector2(end_cell) + Vector2(0.5, 0.5)) * 2, store.datum.height(19.25)))
	tool._unhandled_input(motion)
	expect(tool.first_cell == start_cell and tool.last_cell == end_cell, "Only end changes across hillside")
	expect(tool.preview.start_level == 10, "Target remains Level 10 from initial cell")
	var jitter := camera.unproject_position(zone.local_to_planet(Vector2(end_cell.x * 2 - 0.05, end_cell.y * 2 + 1), store.datum.height(19)))
	expect(tool.pick_cell(jitter) == end_cell, "15 cm hysteresis prevents edge jitter from changing end")
	press.pressed = false
	press.position = Vector2(1050, 80) # release over HUD
	tool._input(press)
	expect(not tool.dragging and not root.get_node("CameraManager").designation_dragging, "Release over HUD ends drag and releases camera")
	expect(store.plans.is_empty(), "Mouse release never confirms or applies")
	await wait_preview()
	var job: Dictionary = tool.evaluations[-1]
	var low := INF
	var high := -INF
	for cell: Dictionary in job.cells:
		low = minf(low, cell.current_level)
		high = maxf(high, cell.current_level)
		expect(is_equal_approx(cell.planned_level, 10), "All hillside targets stay 10")
	expect(low < 10.1 and high > 19, "Current varies on real hillside independently of target")
	metrics.hillside_current_range = [low, high]
	for instance: MeshInstance3D in tool.overlay.grid.get_children():
		if not instance.visible or instance.mesh.get_surface_count() == 0:
			continue
		var arrays := instance.mesh.surface_get_arrays(0)
		for i in range(arrays[Mesh.ARRAY_VERTEX].size()):
			var node := Vector2i(arrays[Mesh.ARRAY_TEX_UV][i])
			var published := planet.editable_terrain.published_node(zone.id, node)
			var vertex: Vector3 = arrays[Mesh.ARRAY_VERTEX][i] + tool.overlay.position
			expect(vertex.distance_to(published.position) < 0.09, "Every grid vertex follows published Current, never Target")
	await capture("A_hillside_current_target")
	tool.confirm_preview()
	await wait_preview()
	var before := zone._clock
	tool.dev_apply()
	metrics.hillside_apply_handler_ms = tool.last_apply_ms
	expect(zone._clock == before, "Apply handler only queues; no synchronous terrain writes")
	await wait_transaction()
	expect(await settle(zone), "Hillside apply publishes mesh and collision")
	await wait_preview()
	expect(camera.transform == frozen_pose, "Apply preserves camera pose")
	for cell: Dictionary in tool.evaluations[0].cells:
		expect(absf(cell.current_level - 10) < 0.01, "Published Current converges to target 10")
	await capture("B_hillside_applied")
	# F9 retains nodes, materials and meshes. A warm toggle does zero geometry work.
	planet.mining_debug.set_enabled(true)
	for i in range(8):
		await frame()
	var count := planet.mining_debug.rebuilt_chunks
	var identity := planet.mining_debug.get_instance_id()
	toggles = []
	for i in range(6):
		planet.toggle_mining_debug()
		toggles.append(planet.mining_debug.last_toggle_ms)
		await frame()
	expect(planet.mining_debug.get_instance_id() == identity and planet.mining_debug.rebuilt_chunks == count, "Warm F9 is visibility only")
	metrics.f9_warm_toggle_ms = toggles
	metrics.f9_profile = planet.mining_debug.metrics.duplicate()
	planet.mining_debug.set_enabled(false)
	var dirty_node := Vector2i(100, 100)
	expect(planet.editable_terrain.set_node_delta(zone.id, dirty_node, 1), "Dirty exactly one interior chunk")
	expect(await settle(zone), "One dirty chunk publishes")
	planet.mining_debug.set_enabled(true)
	for i in range(8):
		await frame()
	expect(planet.mining_debug.rebuilt_chunks == count + 1, "F9 regenerates only changed chunk geometry")
	metrics.f9_one_dirty_rebuilds = planet.mining_debug.rebuilt_chunks - count
	await capture("C_f9_cached")
	planet.mining_debug.set_enabled(false)
	# Reuse surface tiles and current samples across changes of target and rectangle.
	store.plans.clear()
	store.revision += 1
	tool.cancel_preview()
	pose(zone, 80)
	var selections := {}
	for side in [4, 16, 32, 64]:
		var plan := make_platform(zone, Rect2i(8, 8, side, side), 10)
		var start := Time.get_ticks_usec()
		job = await evaluate_preview(plan)
		var evaluated := Time.get_ticks_usec()
		tool.overlay.begin_build([job])
		while not tool.overlay.advance_build():
			await process_frame
		selections[str(side * side)] = {"event_to_ready_ms": (Time.get_ticks_usec() - start) / 1000.0,
			"evaluation_wall_ms": (evaluated - start) / 1000.0, "glyphs": tool.overlay.glyph_count, "overlay_step_max_ms": tool.overlay.max_step_ms}
	metrics.selections = selections
	var prior_nodes := store.evaluated_nodes
	var prior_cells := store.evaluated_cells
	var grown := make_platform(zone, Rect2i(8, 8, 64, 63), 10)
	job = await evaluate_preview(grown)
	metrics.shrink_evaluated_nodes = store.evaluated_nodes - prior_nodes
	metrics.shrink_evaluated_cells = store.evaluated_cells - prior_cells
	expect(store.evaluated_nodes == prior_nodes and store.evaluated_cells == prior_cells, "Shrinking rectangle reuses all retained records")
	prior_nodes = store.evaluated_nodes
	prior_cells = store.evaluated_cells
	grown.rect.size.y = 64
	job = await evaluate_preview(grown)
	expect(store.evaluated_nodes - prior_nodes == 65 and store.evaluated_cells - prior_cells == 64, "Growing by one strip evaluates only its 65 nodes and 64 cells")
	var queries := store.natural_queries
	var tiles := tool.overlay.tile_builds
	grown.start_level = 11
	job = await evaluate_preview(grown)
	tool.overlay.begin_build([job])
	while not tool.overlay.advance_build():
		await process_frame
	expect(store.natural_queries == queries and tool.overlay.tile_builds == tiles, "Changing target neither samples natural nor rebuilds Current grid geometry")
	metrics.natural_queries_interactive = store.natural_queries
	# Queue full 4096-cell transaction and measure separately from rebuild convergence.
	var plan := make_platform(zone, Rect2i(-32, -32, 64, 64), 10)
	expect(store.confirm(plan), "Confirm 4096-cell technical plan")
	job = await evaluate_preview(plan)
	var start := Time.get_ticks_usec()
	var applied := store.queue_apply([job])
	metrics.apply_4096_handler_ms = (Time.get_ticks_usec() - start) / 1000.0
	expect(applied.ok, "4096-cell apply queued")
	var frames: Array = []
	var deadline := Time.get_ticks_msec() + 120000
	var submitted_revision := store.revision
	var first_new := -1.0
	var gpu_commit := 0.0
	var enqueue := 0.0
	var native_physics := 0.0
	var publication := 0.0
	while Time.get_ticks_msec() < deadline:
		var frame_start := Time.get_ticks_usec()
		await frame()
		frames.append((Time.get_ticks_usec() - frame_start) / 1000.0)
		gpu_commit = maxf(gpu_commit, planet.mining_surface.last_gpu_commit_ms)
		enqueue = maxf(enqueue, planet.mining_surface.last_enqueue_ms)
		native_physics = maxf(native_physics, planet.mining_surface.last_collision_ms)
		publication = maxf(publication, planet.mining_surface.last_publish_ms)
		if store.revision > submitted_revision and tool._surface_ready():
			first_new = (Time.get_ticks_usec() - start) / 1000.0
			break
	expect(first_new >= 0, "4096-cell transaction converges")
	metrics.apply_4096 = store.transaction_metrics.duplicate()
	var mesh_worker_ms := 0.0
	var collision_worker_ms := 0.0
	for interval: Dictionary in planet.mining_surface.job_intervals:
		if interval.kind == "chunk" and interval.start_usec >= start:
			mesh_worker_ms += interval.mesh_prepare_ms
			collision_worker_ms += interval.collision_prepare_ms
	metrics.apply_4096.mesh_worker_total_ms = mesh_worker_ms
	metrics.apply_4096.collision_worker_total_ms = collision_worker_ms
	metrics.apply_4096.merge({"enqueue_frame_max_ms": enqueue, "gpu_commit_frame_max_ms": gpu_commit,
		"atomic_publication_frame_max_ms": publication,
		"native_collision_frame_max_ms": native_physics, "first_visible_mesh_ms": first_new, "all_ready_ms": first_new,
		"frame_p95_ms": percentile(frames, 0.95), "frame_max_ms": frames.max()})
	await wait_preview()
	tool.preview = null
	tool.refresh()
	await wait_preview()
	planet.renderer.set_process(false)
	tool.overlay.visible = false
	await measure_overlay_frames("overlay_hidden")
	tool.overlay.visible = true
	await measure_overlay_frames("overlay_visible")
	metrics.overlay = {"cells": tool.overlay.cells_drawn, "glyphs": tool.overlay.glyph_count, "labels": tool.overlay.label_count,
		"grid_vertices": tool.overlay.grid_vertices, "tile_mesh_builds": tool.overlay.tile_builds, "draw_nodes": tool.overlay.grid.get_child_count() + 2,
		"build_wall_ms": tool.overlay.last_build_ms, "build_step_max_ms": tool.overlay.max_step_ms}
	await capture("D_4096_bounded_numbers")
	# Continuous ramp 10 -> 5 with Current and target shown before/after.
	store.plans.clear()
	store.revision += 1
	plan = make_platform(zone, Rect2i(-5, -2, 10, 4), 10)
	plan.kind = TerrainDesignation.Kind.RAMP
	plan.end_level = 5
	expect(store.confirm(plan), "Ramp 10 to 5 at 25 percent remains valid")
	pose(zone, 24)
	tool.refresh()
	await wait_preview()
	await capture("E_ramp_before")
	tool.dev_apply()
	await wait_transaction()
	expect(await settle(zone), "Ramp publishes")
	await wait_preview()
	for cell: Dictionary in tool.evaluations[0].cells:
		expect(absf(cell.current_final_height - cell.target_height) < 0.01, "Continuous ramp Current equals target after apply")
	await capture("F_ramp_after")
	metrics.checks = checks
	metrics.failures = failures
	metrics.graphic = graphic
	FileAccess.open(output.path_join("metrics.json"), FileAccess.WRITE).store_string(JSON.stringify(metrics, "  "))
	print("DESIGNATION_UX checks=", checks, " failures=", failures, " metrics=", JSON.stringify(metrics))
	scene.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
