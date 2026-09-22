extends SceneTree

# Identical camera poses and simulation delta on every run, one update per frame.
# Raw telemetry is written once, after capture, outside the repository.
var rows: Array[Dictionary] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("Provide output JSON path after --")
		quit(1)
		return
	var lab := (load("res://scenes/planet_lab/planet_lab.tscn") as PackedScene).instantiate()
	root.add_child(lab)
	current_scene = lab
	var planet: PlanetRoot = lab.get_node("Planet")
	planet.set_process(false)
	var view := planet.quadtree_view
	view.profile.enabled = true
	view.config.show_borders = not args.has("--debug-off")
	view.config.show_overlay = not args.has("--debug-off")
	var camera: Camera3D = lab.get_node("Cameras/FreeFlyCamera")
	camera.set_process(false)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	var phases := {"distant": 60, "approach": 180, "near": 180,
		"lateral": 240, "retreat": 180, "settle": 360}
	for phase: String in phases:
		for frame in range(phases[phase]):
			var t := float(frame) / maxf(1.0, phases[phase] - 1)
			var distance := 140000.0
			var angle := 0.0
			match phase:
				"approach": distance = lerpf(140000.0, 50500.0, t)
				"near": distance = 50500.0
				"lateral":
					distance = 50500.0
					angle = t * PI / 3.0
				"retreat":
					distance = lerpf(50500.0, 180000.0, t)
					angle = PI / 3.0
				"settle":
					distance = 180000.0
					angle = PI / 3.0
			camera.position = Vector3(sin(angle), 0, cos(angle)) * distance
			camera.look_at(Vector3.ZERO, Vector3.UP)
			var started := Time.get_ticks_usec()
			view.update_camera(camera, 0.05)
			await process_frame
			var row: Dictionary = view.profile.times.duplicate()
			row.merge(view.profile.counts)
			row.frame_us = Time.get_ticks_usec() - started
			row.phase = phase
			row.state = view.state
			row.max_level = 0
			for patch: PlanetPatch in view.tree.leaves.values():
				row.max_level = maxi(row.max_level, patch.id.level)
			row.selection_sse_us = maxi(0, int(row.get("selection_total_us", 0)) - int(row.get("balance_us", 0)) - int(row.get("stitch_us", 0)))
			rows.append(row)
		print("PROFILE_PHASE %s leaves=%d state=%s" % [phase, view.tree.leaves.size(), view.state])
	var summary := summarize(rows)
	var report := {"debug": not args.has("--debug-off"), "renderer": RenderingServer.get_current_rendering_method(),
		"summary": summary, "rows": rows}
	var output := FileAccess.open(args[0], FileAccess.WRITE)
	if output == null:
		push_error("Cannot write profile output")
		quit(1)
		return
	output.store_string(JSON.stringify(report))
	output.close()
	print("PROFILE_SUMMARY " + JSON.stringify(summary))
	print("PROFILE_ROUTE_OK " + args[0])
	quit(0)

func summarize(samples: Array[Dictionary]) -> Dictionary:
	var summary := {}
	for row in samples:
		for key: String in row:
			if not key.ends_with("_us"):
				continue
			if not summary.has(key):
				summary[key] = {"max_ms": 0.0, "total_ms": 0.0, "values": [], "peak_phase": ""}
			var entry: Dictionary = summary[key]
			var ms := float(row[key]) / 1000.0
			entry.total_ms += ms
			entry.values.append(ms)
			if ms > entry.max_ms:
				entry.max_ms = ms
				entry.peak_phase = row.phase
	for entry: Dictionary in summary.values():
		entry.values.sort()
		entry.p95_ms = entry.values[int((entry.values.size() - 1) * 0.95)]
		entry.erase("values")
	return summary
