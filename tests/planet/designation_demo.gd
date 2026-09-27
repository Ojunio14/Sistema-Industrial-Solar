extends "res://tests/planet/mining_integration_test.gd"
## Real Planet Lab: Level 10 platform -> continuous ramp -> Level 5 platform.
## Also exercises the real mouse handlers and benchmarks 4,096 batched cells.
var store: TerrainDesignationStore
var tool: TerrainDesignationTool

func make_platform(zone: MiningZone, rect: Rect2i, level: int) -> TerrainDesignation:
	var plan := TerrainDesignation.new()
	plan.zone_id = zone.id
	plan.rect = rect
	plan.start_level = level
	return plan

func wait_preview() -> void:
	var deadline := Time.get_ticks_msec() + 120000
	while (tool._pending or tool.overlay.building) and Time.get_ticks_msec() < deadline:
		await frame()
	expect(not tool._pending and not tool.overlay.building, "Incremental preview completes")

func measure_overlay_frames(label: String) -> void:
	var frames: Array = []
	var gpu: Array = []
	for i in range(90):
		var start := Time.get_ticks_usec()
		await process_frame
		frames.append((Time.get_ticks_usec() - start) / 1000.0)
		gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
	metrics[label] = {"frame_p50_ms": percentile(frames, 0.5), "frame_p95_ms": percentile(frames, 0.95), "gpu_p95_ms": percentile(gpu, 0.95)}

func _run() -> void:
	graphic = DisplayServer.get_name() != "headless"
	var args := OS.get_cmdline_user_args()
	output = args[0] if not args.is_empty() else "res://docs/evidence/14_grid_levels/headless"
	DirAccess.make_dir_recursive_absolute(output)
	Engine.max_fps = 120
	root.size = Vector2i(1100, 760)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	scene = load("res://scenes/planet_lab/planet_lab.tscn").instantiate()
	root.add_child(scene)
	planet = scene.get_node("Planet")
	camera = scene.get_node("Cameras/FreeFlyCamera")
	for node in scene.get_node("Cameras").get_children():
		node.set_process(false)
		node.set_physics_process(false)
		node.set_process_input(false)
	camera.current = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	var anchor := Vector3(1, 0.4, 1).normalized()
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
	var zone := planet.editable_terrain.create_zone("designation-demo", anchor)
	# A single explicit DEMO datum for the whole planet, chosen once before any
	# plan exists. Normal Lab defaults remain origin=0, step=1, never per selection.
	var origin := roundf(planet.sample_base_height(anchor)) - 7
	store = TerrainDesignationStore.new(planet.editable_terrain, TerrainLevelDatum.new(origin, 1.0))
	planet.designations = store
	metrics.datum_origin_m = origin
	pose(zone, 400)
	var warmup := Time.get_ticks_msec() + 6000
	while Time.get_ticks_msec() < warmup:
		await process_frame
	expect(planet.mining_surface.activate(zone), "Activate demo in real planet")
	if not await settle(zone):
		finish()
		return
	planet.toggle_designation()
	tool = planet.designation_tool
	expect(is_instance_valid(tool) and tool.zone == zone, "F10 reuses the existing zone")
	if not is_instance_valid(tool):
		finish()
		return
	# Automated captures must not accept desktop mouse/key events while running.
	# The interaction test below calls the exact input handlers explicitly.
	tool.set_process_input(false)
	tool.set_process_unhandled_input(false)
	tool.set_process_unhandled_key_input(false)
	root.gui_disable_input = true
	var target := zone.local_to_planet(Vector2.ZERO, origin + 7)
	camera.position = target + zone.up * 45 + zone.tangent_y * 18
	camera.look_at(target, zone.up)
	camera.fov = 55
	camera.h_offset = 8
	await wait_preview()
	# Screen -> physics ray -> grid -> drag/release -> preview -> confirmation.
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	var d1 := zone.local_to_direction(Vector2(-17, -3))
	down.position = camera.unproject_position(d1 * (zone.radius_m + planet.sample_final_height(d1)))
	tool.level = 10
	tool.level_input.set_value_no_signal(10)
	tool._unhandled_input(down)
	var motion := InputEventMouseMotion.new()
	var d2 := zone.local_to_direction(Vector2(-11, 3))
	motion.position = camera.unproject_position(d2 * (zone.radius_m + planet.sample_final_height(d2)))
	tool._unhandled_input(motion)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = motion.position
	tool._unhandled_input(up)
	await wait_preview()
	expect(tool.preview != null and tool.preview.rect == Rect2i(-9, -2, 4, 4), "Mouse drag selects exact 2 m rectangle")
	expect(zone.delta_bytes() == 0 and store.plans.is_empty(), "Mouse-up does not alter terrain or confirm")
	tool.confirm_preview()
	expect(store.plans.size() == 1, "Explicit confirmation saves platform A")
	var b := make_platform(zone, Rect2i(5, -2, 4, 4), 5)
	expect(store.confirm(b), "Platform B Level 5")
	tool.mode = TerrainDesignation.Kind.RAMP
	tool.mode_input.select(TerrainDesignation.Kind.RAMP)
	tool.width_cells = 4
	tool.width_input.set_value_no_signal(4)
	tool.first_cell = Vector2i(-5, 0)
	tool._drag_to(Vector2i(4, 0))
	var ramp := tool.preview
	var anchors := store.detect_ramp_anchors(ramp)
	expect(anchors == [10, 5], "Ramp detects both designated levels")
	ramp.start_level = anchors[0]
	ramp.end_level = anchors[1]
	await wait_preview()
	await capture("00_ramp_preview_anchors")
	tool.confirm_preview()
	expect(store.plans.size() == 3, "20 m ramp with 8 m width / 25% technical grade")
	tool.refresh()
	await wait_preview()
	await capture("01_grid_levels_before")
	# Zoom the glyphs independently of the wide overview to verify their legibility.
	var previous_position := camera.position
	tool.canvas.visible = false
	camera.h_offset = 0
	camera.position = target + zone.up * 25 + zone.tangent_y * 9
	camera.look_at(target, zone.up)
	await capture("01b_levels_close")
	tool.canvas.visible = true
	camera.h_offset = 8
	camera.position = previous_position
	camera.look_at(target, zone.up)
	expect(tool.overlay.cells_drawn == 72 and tool.overlay.get_child_count() == 2, "72 cells use two batched rendering nodes")
	tool.dev_apply()
	metrics.dev_apply_ms = tool.last_apply_ms
	await wait_preview()
	await settle(zone)
	await physics_frame
	check_meshes(zone, false)
	for x in range(-4, 5):
		var node := Vector2i(x, 0)
		var coord := MiningZone.owner_of(node)
		var vertex_arrays := arrays_for(zone, coord)
		var local_node := MiningZone.local_index(node)
		var actual: Vector3 = vertex_arrays[Mesh.ARRAY_NORMAL][local_node.y * 129 + local_node.x]
		var dx := zone.local_to_planet(Vector2(node + Vector2i.RIGHT) * 2, ramp.target_height(Vector2(node + Vector2i.RIGHT), store.datum)) - zone.local_to_planet(Vector2(node - Vector2i.RIGHT) * 2, ramp.target_height(Vector2(node - Vector2i.RIGHT), store.datum))
		var dy := zone.local_to_planet(Vector2(node + Vector2i.DOWN) * 2, ramp.target_height(Vector2(node + Vector2i.DOWN), store.datum)) - zone.local_to_planet(Vector2(node - Vector2i.DOWN) * 2, ramp.target_height(Vector2(node - Vector2i.DOWN), store.datum))
		expect(actual.dot(dx.cross(dy).normalized()) > 0.999, "Final ramp normal follows its continuous target plane")
	tool.refresh()
	await wait_preview()
	await capture("02_grid_levels_complete")
	tool.canvas.visible = false
	camera.h_offset = 0
	camera.position = target + zone.up * 25 + zone.tangent_y * 9
	camera.look_at(target, zone.up)
	await capture("02b_levels_complete_close")
	tool.canvas.visible = true
	var max_error := 0.0
	var max_raycast := 0.0
	for job: Dictionary in tool.evaluations:
		expect(job.complete == job.cells.size(), "All designated cells COMPLETE")
		for cell: Dictionary in job.cells:
			var local := (Vector2(cell.cell) + Vector2(0.5, 0.5)) * 2
			var direction := zone.local_to_direction(local)
			max_error = maxf(max_error, absf(planet.sample_final_height(direction) - cell.target_height))
			var query := PhysicsRayQueryParameters3D.create(direction * (zone.radius_m + cell.target_height + 50), direction * (zone.radius_m + cell.target_height - 50))
			var hit := planet.get_world_3d().direct_space_state.intersect_ray(query)
			expect(not hit.is_empty(), "Every designated cell has raycast collision")
			if not hit.is_empty():
				var error: float = hit.position.distance_to(direction * (zone.radius_m + cell.target_height))
				max_raycast = maxf(max_raycast, error)
				expect(error < 0.05, "Rendered/physical surface reaches cell target within 5 cm")
	expect(max_error < 0.05, "FinalTerrain sampler matches planned surface")
	metrics.target_max_error_m = max_error
	metrics.raycast_max_error_m = max_raycast
	# Profile: overlay hidden to inspect the actual sculpted terrain.
	tool.overlay.visible = false
	camera.h_offset = 0
	camera.position = target + zone.tangent_y * 47 + zone.up * 13
	camera.look_at(target, zone.up)
	await capture("03_applied_profile")
	if "--skip-benchmark" in args:
		metrics.demo_plans = 3
		finish()
		return
	# A dense diagnostic selection is not applied. Its CPU/GPU cost is measured.
	tool.preview = make_platform(zone, Rect2i(30, 30, 64, 64), 10)
	var dense_target := zone.local_to_planet(Vector2(124, 124), origin + 10)
	camera.position = dense_target + zone.up * 100 + zone.tangent_y * 30
	camera.look_at(dense_target, zone.up)
	camera.fov = 75
	tool.overlay.number_distance_m = 250
	tool.refresh()
	await wait_preview()
	# Hold the global leaf selection fixed for the paired overlay measurement.
	planet.renderer.set_process(false)
	await measure_overlay_frames("overlay_hidden")
	tool.overlay.visible = true
	await measure_overlay_frames("overlay_visible")
	planet.renderer.set_process(true)
	metrics.overlay_cells = tool.overlay.cells_drawn
	metrics.overlay_glyphs = tool.overlay.glyph_count
	metrics.overlay_multimesh_buffer_bytes = tool.overlay.numbers.multimesh.buffer.size() * 4
	metrics.overlay_nodes = tool.overlay.get_child_count()
	metrics.overlay_build_wall_ms = tool.overlay.last_build_ms
	metrics.overlay_build_max_step_ms = tool.overlay.max_step_ms
	metrics.evaluation_max_step_ms = 0.0
	for job: Dictionary in tool.evaluations:
		metrics.evaluation_max_step_ms = maxf(metrics.evaluation_max_step_ms, job.max_step_ms)
	expect(tool.overlay.cells_drawn == 4168 and tool.overlay.get_child_count() == 2, "4096-cell preview has constant Node count")
	await capture("04_batched_4096_cells")
	camera.position = dense_target + zone.up * 1000 + zone.tangent_y * 300
	camera.look_at(dense_target, zone.up)
	await process_frame
	await process_frame
	expect(not tool.overlay.numbers.visible, "Numbers hidden at distance")
	await capture("05_distant_no_numbers")
	tool.cancel_preview()
	await wait_preview()
	planet.toggle_designation()
	expect(store.plans.size() == 3 and zone.delta_bytes() > 0, "Closing F10 retains plans and terrain")
	metrics.demo_plans = 3
	finish()
