extends SceneTree
## Runs unchanged against an isolated copy of the donor and the actual Planet Lab.
## Technical donor material, identical lighting/viewports/poses; no atmosphere.
var renderer: PlanetLODManager
var camera: Camera3D
var scene: Node3D
var shape: PlanetShape
var rows: Array[Dictionary] = []
var output := ""
var reference := false
var failed := false

func _initialize() -> void:
	_run.call_deferred()

func expect(value: bool, message: String) -> void:
	if not value:
		failed = true
		push_error("VISUAL_TEST_FAILED: " + message)

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		quit(1)
		return
	output = args[0]
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1100, 760)
	reference = ResourceLoader.exists("res://systems/planet_generator/data/test_planet_100km.tres")
	if reference:
		scene = Node3D.new()
		root.add_child(scene)
		renderer = PlanetLODManager.new()
		renderer.terrain_layers = 1
		scene.add_child(renderer)
		renderer.configure(load("res://systems/planet_generator/data/test_planet_100km.tres"))
		camera = Camera3D.new()
		camera.fov = 75.0
		camera.far = 500000.0
		scene.add_child(camera)
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-35, -30, 0)
		sun.light_energy = 1.5
		scene.add_child(sun)
		var environment := Environment.new()
		environment.background_mode = Environment.BG_COLOR
		environment.background_color = Color(0.012, 0.017, 0.029)
		environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		environment.ambient_light_color = Color(0.64, 0.71, 0.85)
		environment.ambient_light_energy = 0.25
		environment.ambient_light_sky_contribution = 0.0
		environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
		var world := WorldEnvironment.new()
		world.environment = environment
		scene.add_child(world)
	else:
		scene = load("res://scenes/planet_lab/planet_lab.tscn").instantiate()
		root.add_child(scene)
		var planet = scene.get_node("Planet")
		renderer = planet.renderer
		planet.show_overlay = false
		camera = scene.get_node("Cameras/FreeFlyCamera")
		for child in scene.get_node("Cameras").get_children():
			child.set_process(false)
			child.set_physics_process(false)
			child.set_process_input(false)
		# Runtime has one surface manager and no old procedural authorities.
		expect(planet.get_child_count() == 1 and renderer.get_parent() == planet, "one planetary renderer")
		expect(not FileAccess.file_exists("res://systems/planet/terrain/planet_terrain.gd"), "old sampler outside runtime")
		var classes := ProjectSettings.get_global_class_list()
		for entry in classes:
			expect(entry.class not in ["PlanetTerrain", "PlanetQuadtreeView"], "legacy class excluded: " + entry.class)
		expect(renderer.geology != null and renderer.geology_debug_mode == 0, "independent geology service, natural material")
		expect(renderer.climate != null and renderer.climate_debug_mode == 0, "independent climate service, natural material")
	camera.near = 0.5
	camera.current = true
	renderer.set_process(false)
	shape = PlanetShape.new(renderer._definition)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	var peak := Vector3.ZERO
	var highest := -INF
	# Shared geographic landmark, selected solely from the donor's data.
	for i in range(4096):
		var y := 1.0 - 2.0 * (i + 0.5) / 4096.0
		var r := sqrt(1.0 - y * y)
		var angle := i * PI * (3.0 - sqrt(5.0))
		var d := Vector3(cos(angle) * r, y, sin(angle) * r)
		var h := shape.sample_height_m(d)
		if h > highest:
			highest = h
			peak = d
	var scenarios: Array[Dictionary] = [
		{"name": "01_globe", "direction": Vector3(0, 0, 1), "altitude": 90000.0, "offset": 0.0},
		{"name": "02_low_orbit", "direction": peak, "altitude": 15000.0, "offset": 8000.0},
		{"name": "03_kilometers", "direction": peak, "altitude": 4000.0, "offset": 6000.0},
		{"name": "04_hundreds", "direction": peak, "altitude": 350.0, "offset": 700.0},
		{"name": "05_ground", "direction": peak, "altitude": 30.0, "offset": 100.0},
		{"name": "06_mountains", "direction": peak, "altitude": 1500.0, "offset": 3000.0},
		{"name": "07_horizon", "direction": peak, "altitude": 100.0, "offset": 0.0},
		{"name": "08_cube_edge", "direction": Vector3(1, 0.3, 1).normalized(), "altitude": 4000.0, "offset": 5000.0},
		{"name": "09_retreat", "direction": Vector3(0, 0, 1), "altitude": 130000.0, "offset": 0.0}
	]
	var captures := []
	for scenario in scenarios:
		var d: Vector3 = scenario.direction
		var target := shape.point_on_planet(d)
		var tangent := d.cross(Vector3.UP).normalized()
		camera.position = target + d * scenario.altitude + tangent * scenario.offset
		if scenario.name == "07_horizon":
			camera.look_at(camera.position + tangent * 5000.0 - d * 80.0, d)
		else:
			camera.look_at(Vector3.ZERO if scenario.offset == 0.0 else target, Vector3.UP if scenario.offset == 0.0 else d)
		await settle(scenario.name)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join(scenario.name + ".png"))
		captures.append({"name": scenario.name, "position": str(camera.position), "stats": renderer.get_stats()})
		renderer.debug_lod_colors = true
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join(scenario.name + "_lod.png"))
		renderer.debug_lod_colors = false
		if not reference:
			for mode in range(1, 10 if scenario.name == "01_globe" else 3):
				renderer.set_geology_debug_mode(mode)
				await process_frame
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(output.path_join(scenario.name + "_geology_%02d.png" % mode))
			renderer.set_geology_debug_mode(0)
			for mode in range(1, 6):
				renderer.set_climate_debug_mode(mode)
				await process_frame
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(output.path_join(scenario.name + "_climate_%02d.png" % mode))
			renderer.set_climate_debug_mode(0)
		print("CAPTURE ", scenario.name, " ", renderer.get_stats())
	# Continuous navigation measured separately from convergence and screenshots.
	rows.clear()
	for phase in ["approach", "near_lateral", "retreat"]:
		for frame in range(240):
			var t := frame / 239.0
			var d := peak.rotated(Vector3.UP, t * 0.12 if phase == "near_lateral" else (0.12 if phase == "retreat" else 0.0))
			var altitude := lerpf(90000, 80, t) if phase == "approach" else (80.0 if phase == "near_lateral" else lerpf(80, 130000, t))
			var target := shape.point_on_planet(d)
			camera.position = target + d * altitude
			camera.look_at(target + d.cross(Vector3.UP).normalized() * 500.0, d)
			await tick(phase)
	var report := {"reference": reference, "renderer": RenderingServer.get_current_rendering_method(), "camera_fov": camera.fov,
		"captures": captures, "rows": rows, "failed": failed, "peak": str(peak)}
	FileAccess.open(output.path_join("report.json"), FileAccess.WRITE).store_string(JSON.stringify(report))
	if not reference:
		await capture_climate_targets()
	print("SURFACE_VISUAL_", "FAILED" if failed else "OK", " frames=", rows.size())
	scene.queue_free()
	await process_frame
	quit(1 if failed else 0)

func capture_climate_targets() -> void:
	var coast := Vector3.ZERO
	var interior := Vector3.ZERO
	for i in range(4096):
		var y := 1.0 - 2.0 * (float(i) + 0.5) / 4096.0
		var radial := sqrt(1.0 - y * y)
		var angle := float(i) * 2.399963229728653
		var d := Vector3(cos(angle) * radial, y, sin(angle) * radial)
		if absf(y) > 0.8 or shape.sample_base_height(d) < 30.0:
			continue
		var climate_sample := renderer.climate.sample(d)
		if coast.is_zero_approx() and climate_sample.ocean_influence > 0.85:
			coast = d
		if interior.is_zero_approx() and climate_sample.ocean_influence < 0.20:
			interior = d
		if not coast.is_zero_approx() and not interior.is_zero_approx():
			break
	expect(not coast.is_zero_approx() and not interior.is_zero_approx(), "coast and interior visual targets")
	var targets: Array[Dictionary] = [
		{"name": "equator", "direction": Vector3.RIGHT, "altitude": 20000.0, "offset": 0.0, "modes": [1, 2, 4]},
		{"name": "midlatitude", "direction": Vector3(0.85, 0.5, 0.2).normalized(), "altitude": 12000.0, "offset": 0.0, "modes": [1, 2, 4]},
		{"name": "north_pole", "direction": Vector3.UP, "altitude": 20000.0, "offset": 0.0, "modes": [1, 2, 4]},
		{"name": "south_pole", "direction": Vector3.DOWN, "altitude": 20000.0, "offset": 0.0, "modes": [1, 2, 4]},
		{"name": "coast", "direction": coast, "altitude": 8000.0, "offset": 0.0, "modes": [2, 3, 4]},
		{"name": "interior", "direction": interior, "altitude": 8000.0, "offset": 0.0, "modes": [2, 3, 4]},
		{"name": "windward", "direction": Vector3(0.59688, 0.795306, 0.105938), "altitude": 1800.0, "offset": 2500.0, "modes": [2, 4, 5]},
		{"name": "lee", "direction": Vector3(0.621577, 0.783287, 0.010171), "altitude": 1800.0, "offset": 2500.0, "modes": [2, 4, 5]}
	]
	var results := []
	for target in targets:
		var d: Vector3 = target.direction
		if d.is_zero_approx():
			continue
		d = d.normalized()
		var point := shape.point_on_planet(d)
		var tangent := d.cross(Vector3.UP).normalized()
		if tangent.is_zero_approx():
			tangent = d.cross(Vector3.FORWARD).normalized()
		camera.position = point + d * target.altitude + tangent * target.offset
		camera.look_at(Vector3.ZERO if target.offset == 0.0 else point,
			Vector3.FORWARD if absf(d.y) > 0.92 and target.offset == 0.0 else (Vector3.UP if target.offset == 0.0 else d))
		await settle_debug(target.name)
		var context := renderer.climate.sample(d)
		results.append({"name": target.name, "direction": str(d), "fields": context.fields(),
			"shadow": context.rain_shadow, "altitude_m": context.altitude_m,
			"stats": renderer.get_stats()})
		for mode in target.modes:
			renderer.set_climate_debug_mode(mode)
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(output.path_join("target_" + target.name + "_climate_%02d.png" % mode))
		renderer.set_climate_debug_mode(0)
	FileAccess.open(output.path_join("climate_targets.json"), FileAccess.WRITE).store_string(JSON.stringify(results))
	print("CLIMATE_TARGETS ", results.size())

func settle_debug(label: String) -> void:
	renderer._force_selection = true
	var stable := 0
	for frame in range(3600):
		renderer._process(1.0 / 60.0)
		await process_frame
		var stats := renderer.get_stats()
		stable = stable + 1 if stats.jobs == 0 and stats.queued == 0 else 0
		if stable >= 30:
			return
	expect(false, "climate target convergence " + label)

func tick(phase: String) -> void:
	var start := Time.get_ticks_usec()
	renderer._process(1.0 / 60.0)
	var update_us := Time.get_ticks_usec() - start
	var stats := renderer.get_stats()
	expect(stats.jobs <= 2 and stats.resident <= 510 and stats.cached <= 96, "production budgets")
	expect(renderer._uploads_this_frame <= 2, "upload budget")
	await process_frame
	rows.append({"phase": phase, "frame_us": Time.get_ticks_usec() - start, "update_us": update_us, "stats": stats, "uploads": renderer._uploads_this_frame})

func settle(label: String) -> void:
	renderer._force_selection = true
	var stable := 0
	for frame in range(3600):
		await tick("settle_" + label)
		var stats := renderer.get_stats()
		stable = stable + 1 if stats.jobs == 0 and stats.queued == 0 else 0
		if stable >= 30:
			return
	expect(false, "convergence " + label)
