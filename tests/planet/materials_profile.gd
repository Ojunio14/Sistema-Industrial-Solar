extends SceneTree
## Same camera positions/material, usable in the frozen Stage 9 and current tree.
var renderer: PlanetLODManager
var camera: Camera3D
var scene: Node3D
var output: String
var rows: Array = []
var failed := false
var samples := 17
var depth := 8

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	output = args[0]
	samples = int(args[1]) if args.size() > 1 else 17
	depth = int(args[2]) if args.size() > 2 else 9
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1100, 760)
	if "--uncapped" in args:
		Engine.max_fps=0
		OS.low_processor_usage_mode=false
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	scene = load("res://scenes/planet_lab/planet_lab.tscn").instantiate()
	root.add_child(scene)
	var planet = scene.get_node("Planet")
	planet.show_overlay = false
	renderer = planet.renderer
	renderer.set_process(false)
	renderer.chunk_resolution = samples
	renderer.max_depth = depth
	renderer.configure(planet.definition)
	renderer.set_technical_material_enabled("--technical" in args)
	camera = scene.get_node("Cameras/FreeFlyCamera")
	for child in scene.get_node("Cameras").get_children():
		child.set_process(false)
		child.set_physics_process(false)
		child.set_process_input(false)
	camera.near = 0.5
	camera.current = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	# Generate terrain targets once; both versions reuse exactly these world poses.
	# Fixed orbit/coast targets preserve the original continental comparison.
	var shape := PlanetShape.new(planet.definition)
	var landmarks := {}
	var targets_path := output.get_base_dir().path_join("landmarks.json")
	if FileAccess.file_exists(targets_path):
		landmarks = JSON.parse_string(FileAccess.get_file_as_string(targets_path))
	else:
		var best := {"mountain": -INF, "plateau": -INF, "plain": -INF, "coast": -INF}
		for i in range(8192):
			var y := 1.0 - 2.0 * (i + 0.5) / 8192.0
			var r := sqrt(1.0-y*y)
			var d := Vector3(cos(i*2.399963229728653)*r,y,sin(i*2.399963229728653)*r)
			var s := shape.sample_components(d)
			var scores := {"mountain": s.x, "plateau": s.w * (1.0-s.z),
				"plain": (1.0-s.z)*(1.0-s.w) if s.x > 40 and s.x < 100 else -INF,
				"coast": -absf(s.x-8.0)}
			for key in best:
				if scores[key] > best[key]:
					best[key] = scores[key]
					landmarks[key] = [d.x,d.y,d.z,s.x]
		landmarks["orbit"] = [0.4819113910,-0.5169677734,0.7074642777,889.0755005]
		landmarks["coast"] = [-0.9559755325,0.2542724609,-0.1464796364,8.04616165]
		if ResourceLoader.exists("res://tests/planet/fixtures/stage9_shape.gd"):
			var old = load("res://tests/planet/fixtures/stage9_shape.gd").new(planet.definition)
			for key in landmarks:
				var lm: Array = landmarks[key]
				lm[3]=maxf(lm[3],old.sample_height_m(Vector3(lm[0],lm[1],lm[2])))
		FileAccess.open(targets_path,FileAccess.WRITE).store_string(JSON.stringify(landmarks))
	# Alvos adicionais da Etapa 11; a rota temporal abaixo permanece idêntica.
	var extra_best := {"desert": -INF, "wet": -INF, "igneous": -INF, "polar": -INF, "plain": -INF}
	var axis_directions := {"axis_pos_x": Vector3.RIGHT, "axis_neg_x": Vector3.LEFT,
		"axis_pos_y": Vector3.UP, "axis_neg_y": Vector3.DOWN,
		"axis_pos_z": Vector3.BACK, "axis_neg_z": Vector3.FORWARD}
	var axis_best := {}
	for axis_name in axis_directions:
		axis_best[axis_name] = -INF
	var weather := PlanetClimateSample.new()
	var biome := PlanetBiomeSample.new()
	for i in range(4096):
		var y := 1.0 - 2.0 * (float(i) + 0.5) / 4096.0
		var angle := float(i) * 2.399963229728653
		var d := Vector3(cos(angle) * sqrt(1.0 - y * y), y,
			sin(angle) * sqrt(1.0 - y * y))
		var s := renderer.shape.sample_components(d)
		if s.x <= planet.definition.sea_level_m:
			continue
		for axis_name in axis_directions:
			var axis_score: float = d.dot(axis_directions[axis_name])
			if axis_score > axis_best[axis_name]:
				axis_best[axis_name] = axis_score
				landmarks[axis_name] = [d.x, d.y, d.z, s.x]
		renderer.climate.sample_with_surface_into(d, s, weather)
		renderer.biomes.sample_with_context_into(d, s, weather, biome)
		var province := renderer.geology.sample_with_surface(d, s)
		var scores := {"desert": biome.weights[PlanetBiomes.Biome.DESERT],
			"wet": biome.weights[PlanetBiomes.Biome.TROPICAL_WET] + biome.weights[PlanetBiomes.Biome.WETLAND],
			"igneous": province.z if int(province.w) == PlanetGeology.Type.IGNEOUS else -1.0,
			"polar": biome.weights[PlanetBiomes.Biome.POLAR],
			"plain": biome.weights[PlanetBiomes.Biome.TEMPERATE] * (1.0 - s.z) * (1.0 - s.w) if absf(d.y) < 0.65 and s.x < 160.0 else -1.0}
		for key in extra_best:
			if scores[key] > extra_best[key]:
				extra_best[key] = scores[key]
				landmarks[key] = [d.x, d.y, d.z, s.x]
	FileAccess.open(targets_path,FileAccess.WRITE).store_string(JSON.stringify(landmarks))
	var captures := []
	var specs := [["globe","orbit",90000.0,0.0],["continent","orbit",15000.0,8000.0],
		["mountains","mountain",1500.0,3000.0],["mountains_lateral","mountain",400.0,4500.0],["chain","mountain",500.0,2500.0],["plateau","plateau",900.0,1800.0],
		["plain","plain",250.0,650.0],["coast","coast",1200.0,2000.0],
		["desert","desert",300.0,750.0],["wet","wet",300.0,750.0],["igneous","igneous",250.0,600.0],["polar","polar",450.0,700.0],
		["axis_pos_x","axis_pos_x",500.0,1100.0],["axis_neg_x","axis_neg_x",500.0,1100.0],
		["axis_pos_y","axis_pos_y",500.0,1100.0],["axis_neg_y","axis_neg_y",500.0,1100.0],
		["axis_pos_z","axis_pos_z",500.0,1100.0],["axis_neg_z","axis_neg_z",500.0,1100.0],
		["hundreds","mountain",350.0,700.0],["ground","mountain",30.0,100.0],
		["horizon","mountain",100.0,0.0]]
	if "--route-only" in args:
		specs = [["horizon","mountain",100.0,0.0]]
	if "--debug-ground" in args:
		specs = [["ground","mountain",30.0,100.0]]
	if "--visual-plain" in args:
		specs = [["plain","plain",250.0,650.0]]
	if "--visual-coast" in args:
		specs = [["coast","coast",1200.0,2000.0]]
	if "--visual-continent" in args:
		specs = [["continent","orbit",15000.0,8000.0]]
	if "--visual-comparison" in args:
		specs = [["plain","plain",250.0,650.0],["coast","coast",1200.0,2000.0],
			["mountains","mountain",1500.0,3000.0],["desert","desert",300.0,750.0],
			["hundreds","mountain",350.0,700.0],["ground","mountain",30.0,100.0]]
	if "--visual-arid-close" in args:
		specs = [["desert_close","desert",60.0,150.0],
			["wet_close","wet",80.0,180.0]]
	if "--relative-only" in args:
		specs = [["ground_relative","mountain",30.0,0.0]]
	for spec in specs:
		var landmark: Array = landmarks[spec[1]]
		var d := Vector3(landmark[0],landmark[1],landmark[2])
		var point := d*(50000.0+float(landmark[3]))
		var tangent := d.cross(Vector3.UP).normalized()
		if spec[0]=="ground_relative":
			camera.position=shape.point_on_planet(d)+d*30.0
			camera.look_at(camera.position+tangent*250.0-d*20.0,d)
		else:
			camera.position = point+d*spec[2]+tangent*spec[3]
			camera.look_at(camera.position+tangent*5000.0-d*80.0 if spec[0]=="horizon" else point,
				Vector3.UP if spec[0]=="globe" else d)
		if "--sun-follow" in args:
			var sun := scene.get_node("Sun") as DirectionalLight3D
			sun.position = point + d * 100000.0 + tangent * 55000.0
			sun.look_at(point, Vector3.UP)
		await settle()
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join(spec[0]+".png"))
		var captured_stats := metrics()
		captured_stats.camera_clearance_m = camera.position.length()-50000.0-shape.sample_height_m(camera.position.normalized())
		captures.append({"name":spec[0],"position":[camera.position.x,camera.position.y,camera.position.z],"stats":captured_stats})
		renderer.debug_lod_colors = true
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join(spec[0]+"_lod.png"))
		renderer.debug_lod_colors = false
		if spec[0] == "ground":
			for debug_mode in range(1, 7):
				renderer.set_material_debug_mode(debug_mode)
				await process_frame
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(output.path_join("ground_f8_%d.png" % debug_mode))
			renderer.set_material_debug_mode(0)
		print("RELIEF_CAPTURE ",spec[0]," ",metrics())
	if "--relative-only" in args or "--visual-only" in args or "--debug-ground" in args or \
		"--visual-plain" in args or "--visual-coast" in args or "--visual-continent" in args or \
		"--visual-comparison" in args or "--visual-arid-close" in args:
		var capture_file := "relative.json" if "--relative-only" in args else "captures.json"
		FileAccess.open(output.path_join(capture_file), FileAccess.WRITE).store_string(JSON.stringify(captures))
		scene.queue_free()
		await process_frame
		quit(1 if failed else 0)
		return
	rows.clear()
	var lm: Array = landmarks.mountain
	var peak := Vector3(lm[0],lm[1],lm[2])
	var phases := ["orbit","approach","kilometers","hundreds","near","lateral","retreat"]
	for phase in phases:
		for frame in range(120):
			var t := frame/119.0
			var d := peak.rotated(Vector3.UP,t*0.04 if phase=="lateral" else 0.0)
			var altitude := 90000.0
			match phase:
				"approach": altitude = lerpf(90000,4000,t)
				"kilometers": altitude = 4000.0
				"hundreds": altitude = lerpf(1500,150,t)
				"near", "lateral": altitude = 80.0
				"retreat": altitude = lerpf(80,130000,t)
			# Identical path for all alternatives, independent of revised surface.
			camera.position = d*(50000.0+float(lm[3])+altitude)
			camera.look_at(camera.position+d.cross(Vector3.UP).normalized()*500.0-d*80.0,d)
			await tick(phase)
	var report := {"resolution":samples,"max_depth":depth,"rows":rows,"captures":captures,
		"spacing":spacing_table(),"failed":failed,"renderer":RenderingServer.get_current_rendering_method(),
		"uncapped": "--uncapped" in args, "route_only": "--route-only" in args,
		"vsync_mode":DisplayServer.window_get_vsync_mode(), "max_fps":Engine.max_fps}
	FileAccess.open(output.path_join("profile.json"),FileAccess.WRITE).store_string(JSON.stringify(report))
	if "--transitions" in args:
		await capture_transitions(peak)
	print("RELIEF_PROFILE_", "FAILED" if failed else "OK", " frames=", rows.size())
	scene.queue_free()
	await process_frame
	quit(1 if failed else 0)

func metrics() -> Dictionary:
	var s := renderer.get_stats()
	var surface_vertices := samples*samples
	var vertices := surface_vertices+4*samples
	var indices := (2*(samples-1)*(samples-1)+8*(samples-1))*3
	var bytes := vertices*96+indices*4 # posição, normal, UV, cor, geologia, oito pesos + índices
	s.active_vertices = vertices*s.visible
	s.mesh_payload_mib = float(bytes*(s.resident+s.cached))/1048576.0
	s.static_mib = Performance.get_monitor(Performance.MEMORY_STATIC)/1048576.0
	s.video_mib = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)/1048576.0
	s.render_cpu_ms = RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid())
	s.render_gpu_ms = RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid())
	var address := CubeSphereMapping.direction_to_face_uv(camera.position.normalized())
	for node: QuadtreeNode in renderer._nodes.values():
		if not node.mesh_instance or not node.mesh_instance.visible or node.face != address.face:
			continue
		var cell := Vector2i((address.uv * float(1<<node.depth)).floor())
		if cell == node.cell:
			var uv: Vector2 = address.uv
			var step := 1.0/float((1<<node.depth)*(samples-1))
			var d := CubeSphereMapping.face_uv_to_direction(node.face,uv)
			s.ground_depth = node.depth
			s.ground_spacing_m = 50000.0*d.distance_to(CubeSphereMapping.face_uv_to_direction(node.face,uv+Vector2(step,0)))
	return s

func tick(phase: String) -> void:
	var started := Time.get_ticks_usec()
	renderer._process(1.0/60.0)
	var cpu := Time.get_ticks_usec()-started
	var s := metrics()
	if s.jobs>2 or s.resident>510 or s.cached>96 or renderer._uploads_this_frame>2:
		failed = true
	await process_frame
	rows.append({"phase":phase,"frame_ms":(Time.get_ticks_usec()-started)/1000.0,
		"update_ms":cpu/1000.0,"uploads":renderer._uploads_this_frame,"stats":s})

func settle() -> void:
	renderer._force_selection = true
	var stable := 0
	var deadline := Time.get_ticks_msec()+120000
	while Time.get_ticks_msec()<deadline:
		await tick("settle")
		var s := renderer.get_stats()
		stable = stable+1 if s.jobs==0 and s.queued==0 else 0
		if stable>=30:
			return
	failed = true
	push_error("RELIEF_PROFILE_FAILED: convergence")

func spacing_table() -> Array:
	var result := []
	for level in [0,4,6,7,8,9]:
		var n: int = 1<<level
		for site in ["center","edge","corner"]:
			var origin := Vector2(0.5,0.5) if site=="center" else (Vector2(0,0.5) if site=="edge" else Vector2.ZERO)
			origin = (origin*float(n)).floor()/float(n) if level>0 else Vector2.ZERO
			var shortest := INF
			var longest := 0.0
			var width := 0.0
			for y in range(17):
				for x in range(16):
					var uv := origin+Vector2(x,y)/float(16*n)
					var a := CubeSphereMapping.face_uv_to_direction(0,uv)
					var b := CubeSphereMapping.face_uv_to_direction(0,uv+Vector2(1.0/float(16*n),0))
					var length := a.distance_to(b)*50000.0
					shortest = minf(shortest,length)
					longest = maxf(longest,length)
					if y==8: width+=length
					# Also measure the other axis: edge patches are anisotropic.
					var vertical_uv := origin+Vector2(y,x)/float(16*n)
					var va := CubeSphereMapping.face_uv_to_direction(0,vertical_uv)
					var vb := CubeSphereMapping.face_uv_to_direction(0,vertical_uv+Vector2(0,1.0/float(16*n)))
					var vertical := va.distance_to(vb)*50000.0
					shortest=minf(shortest,vertical)
					longest=maxf(longest,vertical)
			result.append({"lod":level,"site":site,"patch_width_m":width,"vertex_min_m":shortest,"vertex_max_m":longest})
	return result

## Visual motion evidence is separate from the measured performance route:
## PNG readbacks must not be counted as runtime stutter.
func capture_transitions(peak: Vector3) -> void:
	var frames := []
	var folder := output.path_join("transitions")
	DirAccess.make_dir_recursive_absolute(folder)
	for frame in range(180):
		var t := frame/179.0
		var d := peak.rotated(Vector3.UP,t*0.012)
		var tangent := d.cross(Vector3.UP).normalized()
		var altitude := lerpf(500.0,35.0,minf(t*2.0,1.0))
		camera.position=renderer.shape.point_on_planet(d)+d*altitude
		camera.look_at(camera.position+tangent*400.0-d*60.0,d)
		renderer._process(1.0/60.0)
		await process_frame
		if frame%6==0:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(folder.path_join("frame_%03d.png" % frame))
			frames.append({"frame":frame,"stats":metrics()})
	FileAccess.open(folder.path_join("frames.json"),FileAccess.WRITE).store_string(JSON.stringify(frames))
