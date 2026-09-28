extends "res://tests/planet/designation_demo.gd"
## Identical script runs on the Stage 14 baseline and Stage 15 implementation.
## Fixed seed, pose, natural published surface, 120 FPS cap, same plans.
func _run() -> void:
	output = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(output)
	Engine.max_fps = 120
	root.size = Vector2i(1100, 760)
	scene = load("res://scenes/planet_lab/planet_lab.tscn").instantiate()
	root.add_child(scene)
	planet = scene.get_node("Planet")
	camera = scene.get_node("Cameras/FreeFlyCamera")
	for controller in scene.get_node("Cameras").get_children():
		controller.set_process(false)
		controller.set_process_input(false)
	camera.current = true
	var anchor := Vector3(1, 0.4, 1).normalized()
	camera.position = anchor * (50000 + planet.sample_base_height(anchor) + 80)
	camera.look_at(anchor * (50000 + planet.sample_base_height(anchor)), Vector3.UP)
	var zone := planet.editable_terrain.create_zone("matched-benchmark", anchor)
	expect(planet.mining_surface.activate(zone), "Activate identical natural zone")
	expect(await settle(zone), "Benchmark starts only with published mesh and collision")
	planet.renderer.set_process(false)
	store = planet.designations
	var batched = TerrainDesignationOverlay.new()
	planet.add_child(batched)
	var asynchronous := store.has_method("queue_apply")
	if asynchronous:
		batched.set("store", store)
	batched.configure(zone, 0)
	var selections := {}
	var level := store.datum.nearest_level(planet.sample_base_height(anchor))
	for side in [4, 16, 32, 64]:
		var plan := make_platform(zone, Rect2i(8, 8, side, side), level)
		var started := Time.get_ticks_usec()
		var job := store.begin_evaluation(plan)
		while not store.advance_evaluation(job):
			await process_frame
		var evaluated := Time.get_ticks_usec()
		batched.begin_build([job])
		while not batched.advance_build():
			await process_frame
		expect(not asynchronous or batched.glyph_count > 0, "Near visible selection generates Current labels")
		selections[str(side * side)] = {"evaluation_ms": (evaluated - started) / 1000.0,
			"event_to_ready_ms": (Time.get_ticks_usec() - started) / 1000.0, "glyphs": batched.glyph_count}
	var plan := make_platform(zone, Rect2i(-32, -32, 64, 64), level)
	expect(store.confirm(plan), "Confirm identical 4096-cell apply")
	var job := store.begin_evaluation(plan)
	while not store.advance_evaluation(job):
		await process_frame
	var prior_revision := store.revision
	var started := Time.get_ticks_usec()
	var applied: Dictionary = store.call("queue_apply", [job]) if asynchronous else store.apply_evaluations([job])
	var handler_ms := (Time.get_ticks_usec() - started) / 1000.0
	expect(applied.ok, "Apply accepted")
	var frames: Array = []
	var deadline := Time.get_ticks_msec() + 120000
	var ready_ms := -1.0
	while Time.get_ticks_msec() < deadline:
		var frame_start := Time.get_ticks_usec()
		await process_frame
		frames.append((Time.get_ticks_usec() - frame_start) / 1000.0)
		var ready := store.revision > prior_revision
		for chunk: MiningChunk in zone._chunks.values():
			ready = ready and chunk.mesh_revision == chunk.revision and chunk.collision_revision == chunk.revision
		if ready:
			ready_ms = (Time.get_ticks_usec() - started) / 1000.0
			break
	expect(ready_ms >= 0, "Rebuild converges")
	var report := {"asynchronous": asynchronous, "selections": selections, "apply_handler_ms": handler_ms,
		"all_ready_ms": ready_ms, "frame_p95_ms": percentile(frames, 0.95), "frame_max_ms": frames.max(),
		"level": level, "checks": checks, "failures": failures, "fps_cap": Engine.max_fps}
	if asynchronous:
		report.apply_phases = store.get("transaction_metrics")
	FileAccess.open(output.path_join("metrics.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	print("DESIGNATION_MATCHED_BENCHMARK ", JSON.stringify(report))
	scene.queue_free()
	await process_frame
	quit(1 if failures else 0)
