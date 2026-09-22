extends SceneTree

# Run with a real rendering backend. Output is a caller-supplied directory,
# never an asset in the project. No input injection or editor modifications.
func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var arguments := OS.get_cmdline_user_args()
	if arguments.is_empty():
		push_error("Provide a screenshot directory after --")
		quit(1)
		return
	var output: String = arguments[0]
	DirAccess.make_dir_recursive_absolute(output)
	var lab := (load("res://scenes/planet_lab/planet_lab.tscn") as PackedScene).instantiate()
	# Keep the Stage 2 visual regression a smooth-sphere reference. Stage 3 has
	# its own terrain-safe route, without mutating the shared project resource.
	var definition: PlanetDefinition = lab.get_node("Planet").definition.duplicate()
	definition.terrain_enabled = false
	lab.get_node("Planet").definition = definition
	root.add_child(lab)
	current_scene = lab
	await process_frame
	var planet: PlanetRoot = lab.get_node("Planet")
	planet.set_process(false)
	var view := planet.quadtree_view
	var manager := root.get_node("CameraManager")
	var camera: Camera3D = lab.get_node("Cameras/FreeFlyCamera")
	camera.set_process(false)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	for scenario in [
		{"name": "globe", "position": Vector3(0, 0, 140000)},
		{"name": "near_face", "position": Vector3(0, 0, 50500)},
		{"name": "cross_face", "position": Vector3(1, 0.3, 1).normalized() * 50500.0},
		{"name": "retreat", "position": Vector3(0, 0, 180000)},
	]:
		camera.global_position = scenario.position
		camera.look_at(Vector3.ZERO, Vector3.UP)
		var stable := 0
		var max_splits := 0
		var max_merges := 0
		var max_commits := 0
		for update in range(2000):
			view.update_camera(camera, 0.05)
			max_splits = maxi(max_splits, view.splits_last_update)
			max_merges = maxi(max_merges, view.merges_last_update)
			max_commits = maxi(max_commits, view.commits_last_update)
			stable = stable + 1 if view.state == "idle" else 0
			if stable >= 3:
				break
			if update % 20 == 0:
				await process_frame
		# The debug overlay is throttled in gameplay; screenshots need a fresh snapshot.
		lab.get_node("Debug")._process(0.2)
		await process_frame
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		var path := output.path_join(scenario.name + ".png")
		image.save_png(path)
		print("VISUAL_CAPTURE %s leaves=%d patches=%d state=%s budgets=%d/%d/%d" % [
			path, view.tree.leaves.size(), view.tree.nodes.size(), view.state, max_splits, max_merges, max_commits])
		if stable < 3 or not view.tree.is_balanced():
			push_error("VISUAL_TEST_FAILED: did not stabilize/balance")
			quit(1)
			return
	manager.switch_to(&"Orbital")
	lab.get_node("Debug")._process(0.2)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("orbital.png"))
	print("VISUAL_TEST_OK")
	quit(0)
