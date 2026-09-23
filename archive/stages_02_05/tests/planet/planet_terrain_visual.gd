extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("Provide output directory")
		quit(1)
		return
	var output: String = args[0]
	DirAccess.make_dir_recursive_absolute(output)
	var lab := (load("res://scenes/planet_lab/planet_lab.tscn") as PackedScene).instantiate()
	var definition: PlanetDefinition = lab.get_node("Planet").definition.duplicate()
	definition.geology_enabled = args.has("--geology") or args.has("--climate") or args.has("--materials")
	definition.climate_enabled = args.has("--climate") or args.has("--materials")
	definition.materials_enabled = args.has("--materials")
	lab.get_node("Planet").definition = definition
	root.add_child(lab)
	current_scene = lab
	var planet: PlanetRoot = lab.get_node("Planet")
	planet.set_process(false)
	var view := planet.quadtree_view
	var camera: Camera3D = lab.get_node("Cameras/FreeFlyCamera")
	camera.set_process(false)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	var scenarios: Array[Dictionary] = []
	for i in range(6):
		scenarios.append({"name": "globe_%d" % i, "direction": PlanetMath.get_face_normal(i), "orbital": true})
	for landmark in planet.terrain.debug_landmarks():
		scenarios.append(landmark)
	if definition.geology_enabled:
		var selected := {}
		for province in planet.terrain.geology.descriptors():
			var key := str(province.type)
			if province.type == PlanetGeology.Type.OROGEN:
				key += "_young" if province.age < 0.45 else "_old"
			if not selected.has(key):
				selected[key] = true
				scenarios.append({"name": "geology_" + key, "direction": province.direction,
					"mode": 8 + province.type, "id": province.id})
	if definition.climate_enabled:
		var selected_biomes := {}
		var best_shadow := -1.0
		var best_dry := INF
		var best_wet := -1.0
		var shadow_direction := Vector3.ZERO
		var dry_direction := Vector3.ZERO
		var wet_direction := Vector3.ZERO
		for i in range(8192):
			var direction := PlanetTerrain.uniform_direction(i, 8192)
			if planet.terrain.sample(direction) <= 0:
				continue
			var sample := planet.climate.query_direction(direction)
			if not selected_biomes.has(sample.dominant):
				selected_biomes[sample.dominant] = direction
			if sample.rain_shadow > best_shadow:
				best_shadow = sample.rain_shadow
				shadow_direction = direction
			if sample.climate.w < best_dry:
				best_dry = sample.climate.w
				dry_direction = direction
			if sample.climate.w > best_wet:
				best_wet = sample.climate.w
				wet_direction = direction
		for biome in selected_biomes:
			scenarios.append({"name": "biome_%d" % biome, "direction": selected_biomes[biome], "climate": true})
		scenarios.append({"name": "rain_shadow", "direction": shadow_direction, "climate": true})
		scenarios.append({"name": "driest", "direction": dry_direction, "climate": true})
		scenarios.append({"name": "wettest", "direction": wet_direction, "climate": true})
	scenarios.append({"name": "cube_edge", "direction": Vector3(1, 0.3, 1).normalized()})
	scenarios.append({"name": "retreat", "direction": Vector3(0, 0, 1), "orbital": true})
	for scenario in scenarios:
		if args.has("--debug-only") and scenario.name != "cube_edge":
			continue
		if definition.materials_enabled and not args.has("--debug-only") and not scenario.name in [
			"globe_0", "globe_1", "globe_2", "globe_3", "globe_4", "globe_5",
			"chain", "plateau", "valley", "basin", "archipelago", "inland_sea",
			"geology_4", "biome_2", "biome_4", "biome_5", "biome_8", "biome_9",
			"cube_edge", "retreat"]:
			continue
		var direction: Vector3 = scenario.direction
		var target := direction * (50000.0 + planet.terrain.sample(direction))
		var up := Vector3.UP if absf(direction.y) < 0.95 else Vector3.FORWARD
		if scenario.get("orbital", false):
			camera.position = direction * 140000.0
			camera.look_at(Vector3.ZERO, up)
		else:
			var tangent := direction.cross(up).normalized()
			camera.position = target + direction * 6500.0 + tangent * 9500.0
			camera.look_at(target, direction)
		view.set_debug_mode(23 if definition.materials_enabled else 2)
		var stable := 0
		for frame in range(12000):
			view.update_camera(camera, 0.05)
			stable = stable + 1 if view.state == "idle" else 0
			if stable >= 3:
				break
			if frame % 20 == 0:
				await process_frame
		if stable < 3 or not view.tree.is_balanced():
			push_error("TERRAIN_VISUAL_FAILED: convergence/balance " + scenario.name)
			quit(1)
			return
		if definition.materials_enabled:
			lab.get_node("Debug")._process(0.2)
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(output.path_join(scenario.name + "_material.png"))
			for mode in ([24, 25, 26, 27, 28, 29, 30, 31] if scenario.name == "cube_edge" else [24, 25, 26, 28] if scenario.get("orbital", false) else [24, 25, 27]):
				view.set_debug_mode(mode)
				lab.get_node("Debug")._process(0.2)
				await process_frame
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(output.path_join(scenario.name + "_material_mode%d.png" % mode))
			if scenario.name in ["chain", "biome_2", "biome_4"]:
				view.set_debug_mode(23)
				var near_tangent := direction.cross(up).normalized()
				for close_distance in [650.0, 140.0]:
					camera.position = target + direction * (close_distance * 0.55) + near_tangent * close_distance
					camera.look_at(target, direction)
					var close_stable := 0
					for frame in range(12000):
						view.update_camera(camera, 0.05)
						close_stable = close_stable + 1 if view.state == "idle" else 0
						if close_stable >= 3:
							break
						if frame % 20 == 0:
							await process_frame
					if close_stable < 3 or not view.tree.is_balanced():
						push_error("TERRAIN_VISUAL_FAILED: close convergence " + scenario.name)
						quit(1)
						return
					lab.get_node("Debug")._process(0.2)
					await process_frame
					await RenderingServer.frame_post_draw
					root.get_texture().get_image().save_png(output.path_join(scenario.name + "_near%d_material.png" % int(close_distance)))
			print("TERRAIN_VISUAL_CAPTURE %s leaves=%d state=%s" % [scenario.name, view.tree.leaves.size(), view.state])
			continue
		# Main captures omit border ink; an explicit topology capture preserves it.
		for entry: Dictionary in view._active.values():
			entry.node.material_override.set_shader_parameter("show_borders", false)
		lab.get_node("Debug")._process(0.2)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join(scenario.name + ".png"))
		print("TERRAIN_VISUAL_CAPTURE %s leaves=%d state=%s" % [scenario.name, view.tree.leaves.size(), view.state])
		if definition.geology_enabled:
			var modes: Array = [7, 8] if scenario.get("orbital", false) else [scenario.get("mode", 7)]
			if scenario.name == "cube_edge":
				modes = [7, 8, 9, 10, 11, 12, 13, 14, 15]
			for mode in modes:
				view.set_debug_mode(mode)
				lab.get_node("Debug")._process(0.2)
				await process_frame
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(output.path_join(scenario.name + "_mode%d.png" % mode))
		if definition.climate_enabled:
			var climate_modes: Array = [16, 17, 18, 19, 20, 21, 22] if scenario.get("orbital", false) or scenario.name == "cube_edge" else [20, 21, 22] if scenario.get("climate", false) else []
			for mode in climate_modes:
				view.set_debug_mode(mode)
				lab.get_node("Debug")._process(0.2)
				await process_frame
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(output.path_join(scenario.name + "_mode%d.png" % mode))
		if scenario.name == "cube_edge":
			for mode in [0, 1, 3, 4, 5, 6]:
				view.set_debug_mode(mode)
				for entry: Dictionary in view._active.values():
					entry.node.material_override.set_shader_parameter("show_borders", mode == 0)
				lab.get_node("Debug")._process(0.2)
				await process_frame
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(output.path_join("debug_%d.png" % mode))
	print("TERRAIN_VISUAL_OK " + output)
	quit(0)
