extends SceneTree

var failures := 0
var assertions := 0
const R := 50000.0
const POSITION_EPS := 0.04 # A few float32 ULPs at 50 km.

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, context: String) -> void:
	assertions += 1
	if not value:
		failures += 1
		if failures <= 30:
			push_error("QUADTREE_TEST_FAILED: " + context)

func _run() -> void:
	test_structure()
	test_balance()
	test_sse()
	test_mesh_masks()
	test_cross_face_edges()
	test_morph()
	test_incremental_geometry()
	if not OS.get_cmdline_user_args().has("--geometry-only"):
		await test_cpu_slices()
		await test_controller()
		await test_controller(8, 2)
	if failures:
		push_error("QUADTREE_TEST_FAILED: %d / %d" % [failures, assertions])
		quit(1)
	else:
		print("QUADTREE_TEST_OK: %d assertions; structure/2:1/SSE/16 masks/cross-face/morph/budgets" % assertions)
		quit(0)

func test_structure() -> void:
	var tree := PlanetQuadtree.new()
	check(tree.roots.size() == 6 and tree.leaves.size() == 6, "exactly six roots")
	for face in range(6):
		var id := PatchId.root(face)
		check(tree.roots[face].id.is_equal(id), "root ID")
		check(tree.split(id) == 1, "single split")
		var parent: PlanetPatch = tree.nodes[id.stable_key()]
		check(parent.children.size() == 4 and not parent.is_leaf(), "four children")
		var area := 0.0
		for i in range(4):
			var child := parent.children[i]
			check(child.id.is_equal(id.get_children_ids()[i]), "child ID quadrant")
			check(child.id.get_parent_id().is_equal(id), "child-parent identity")
			area += child.id.get_uv_bounds().get_area()
			check(tree.find_leaf(face, child.id.get_uv_bounds().get_center()) == child, "region lookup")
		check(is_equal_approx(area, 1.0), "coverage")
		check(tree.merge(id), "merge permitted")
		check(tree.roots[face].is_leaf(), "merge restores leaf")
	check(tree.nodes.size() == 6, "no orphan logical children")

func test_balance() -> void:
	for face in range(6):
		for edge in range(4):
			var tree := PlanetQuadtree.new()
			tree.split(PatchId.root(face))
			var first := _edge_child(face, edge)
			var before := tree.leaves.size()
			check(tree.split(first, 1) == 0 and tree.leaves.size() == before, "atomic insufficient budget")
			var operations := tree.split(first, 8)
			check(operations > 1, "cross-face forced splits face=%d edge=%d" % [face, edge])
			check(tree.is_balanced(), "cross-face 2:1 after closure")
			var transition := PlanetTopology.get_edge_transition(face, edge)
			check(not tree.can_merge(PatchId.root(transition.neighbor_face)), "merge blocked across face")
			for patch in tree.active_leaves():
				for e in range(4):
					for neighbor in tree.neighbors(patch.id, e):
						check(absi(patch.id.level - neighbor.id.level) <= 1, "all leaf neighbors 2:1")
	var internal := PlanetQuadtree.new()
	internal.split(PatchId.root(4))
	internal.split(PatchId.new(4, 1, 0, 0))
	check(internal.split(PatchId.new(4, 2, 1, 1)) > 1, "same-face balancing forces neighbors")
	check(internal.is_balanced(), "internal 2:1")
	check(not internal.can_merge(PatchId.new(4, 1, 1, 0)), "same-face merge blocked")

func _edge_child(face: int, edge: int) -> PatchId:
	return PatchId.new(face, 1, 1 if edge == 1 else 0, 1 if edge == 3 else 0)

func test_sse() -> void:
	var id := PatchId.new(4, 3, 4, 4)
	var center := PlanetSSE.center(id, R)
	var direction := center.normalized()
	var near_pos := center + direction * 20000.0
	var far_pos := center + direction * 100000.0
	var near_sse := PlanetSSE.pixels(id, R, near_pos, 720, 70)
	check(near_sse > PlanetSSE.pixels(id, R, far_pos, 720, 70), "approach increases SSE")
	check(PlanetSSE.pixels(id, R, near_pos, 1440, 70) > near_sse, "viewport height")
	check(PlanetSSE.pixels(id, R, near_pos, 720, 40) > near_sse, "narrow FOV")
	check(PlanetSSE.geometric_error(id.get_children_ids()[0], R) < PlanetSSE.geometric_error(id, R), "refinement error decreases")
	check(PlanetSSE.pixels(id, R, near_pos, 720, 70, 1000) == PlanetSSE.pixels(id, R, far_pos, 720, 70, 1000), "orthographic independent of distance")
	check(PlanetSSE.pixels(id, R, near_pos, 720, 70, 0, 1) > near_sse, "future additive error")
	for face in range(6):
		for level in [0, 1, 3]:
			var p := PatchId.new(face, level, 0, 0)
			for uv in [Vector2.ZERO, Vector2.ONE, Vector2(0, 1), Vector2(1, 0), Vector2(0.37, 0.76)]:
				var point := PlanetMath.face_uv_to_position(face, p.local_uv_to_face_uv(uv), R)
				check(point.distance_to(PlanetSSE.center(p, R)) <= PlanetSSE.extent(p, R), "bounds contain curved patch")

func test_mesh_masks() -> void:
	for mask in range(16):
		var data := PlanetPatchMesh.generate(PatchId.new(4, 2, 1, 2), R, mask)
		check(data.vertices.size() == 1089 and data.normals.size() == 1089, "33x33")
		var area := 0.0
		var edges := {}
		for i in range(data.vertices.size()):
			check(absf(data.vertices[i].length() - R) < 0.02, "sphere radius")
			check(data.normals[i].distance_to(data.vertices[i].normalized()) < 0.000001, "radial normals")
		var indices: PackedInt32Array = data.indices
		for i in range(0, indices.size(), 3):
			var a := indices[i]
			var b := indices[i + 1]
			var c := indices[i + 2]
			check(mini(a, mini(b, c)) >= 0 and maxi(a, maxi(b, c)) < 1089, "valid indices")
			var uv_a := PlanetPatchMesh.grid_uv(a)
			var uv_b := PlanetPatchMesh.grid_uv(b)
			var uv_c := PlanetPatchMesh.grid_uv(c)
			var signed_area := (uv_b - uv_a).cross(uv_c - uv_a)
			check(signed_area < 0, "nondegenerate clockwise winding mask=%d" % mask)
			area -= signed_area * 0.5
			var va: Vector3 = data.vertices[a]
			var vb: Vector3 = data.vertices[b]
			var vc: Vector3 = data.vertices[c]
			check((vb - va).cross(vc - va).dot(va) < 0, "Godot outward winding")
			for pair in [Vector2i(a, b), Vector2i(b, c), Vector2i(c, a)]:
				var key := Vector2i(mini(pair.x, pair.y), maxi(pair.x, pair.y))
				edges[key] = int(edges.get(key, 0)) + 1
		check(absf(area - 1.0) < 0.000001, "UV area covers whole patch mask=%d area=%f" % [mask, area])
		for key: Vector2i in edges:
			check(edges[key] <= 2, "manifold triangle edge")
			if edges[key] == 1:
				var a := PlanetPatchMesh.grid_uv(key.x)
				var b := PlanetPatchMesh.grid_uv(key.y)
				check((a.x == b.x and (a.x == 0 or a.x == 1)) or (a.y == b.y and (a.y == 0 or a.y == 1)),
					"no internal hole mask=%d edge=%s" % [mask, key])
				for edge in range(4):
					if (mask & (1 << edge)) != 0 and _on_edge(a, edge) and _on_edge(b, edge):
						var ta := int(round((a.y if edge < 2 else a.x) * 32))
						var tb := int(round((b.y if edge < 2 else b.x) * 32))
						check((ta & 1) == 0 and (tb & 1) == 0 and absi(ta - tb) == 2, "stitched boundary skips odd vertices")

func _on_edge(uv: Vector2, edge: int) -> bool:
	return [uv.x == 0.0, uv.x == 1.0, uv.y == 0.0, uv.y == 1.0][edge]

func test_cross_face_edges() -> void:
	for face in range(6):
		for edge in range(4):
			var tree := PlanetQuadtree.new()
			tree.split(PatchId.root(face))
			var coarse_sampler := PlanetSurfaceSampler.new(tree, R)
			for patch in tree.active_leaves():
				if patch.id.face != face or (tree.stitch_mask(patch.id) & (1 << edge)) == 0:
					continue
				var data := PlanetPatchMesh.generate(patch.id, R, tree.stitch_mask(patch.id))
				var transition := PlanetTopology.get_edge_transition(face, edge)
				# Compare every rendered fine boundary segment against the coarse face.
				for segment in range(16):
					var t0 := float(segment * 2) / 32.0
					var t1 := float(segment * 2 + 2) / 32.0
					var a_uv := patch.id.local_uv_to_face_uv(PlanetTopology.edge_uv(edge, t0))
					var b_uv := patch.id.local_uv_to_face_uv(PlanetTopology.edge_uv(edge, t1))
					var a := PlanetMath.face_uv_to_position(face, a_uv, R)
					var b := PlanetMath.face_uv_to_position(face, b_uv, R)
					for weight in [0.0, 0.37, 1.0]:
						var uv := a_uv.lerp(b_uv, weight)
						var parameter: float = uv.y if edge < 2 else uv.x
						if transition.is_reversed:
							parameter = 1.0 - parameter
						var expected := coarse_sampler.sample(transition.neighbor_face,
							PlanetTopology.edge_uv(transition.neighbor_edge, parameter))
						check(a.lerp(b, weight).distance_to(expected) < POSITION_EPS,
							"stitched cross-face position face=%d edge=%d reverse=%s" % [face, edge, transition.is_reversed])
				check(not data.indices.is_empty(), "edge data exists")

func test_morph() -> void:
	var coarse := PlanetQuadtree.new()
	coarse.split(PatchId.root(4))
	var fine := coarse.copy_tree()
	fine.split(PatchId.new(4, 1, 0, 0))
	var sampler := PlanetSurfaceSampler.new(coarse, R)
	var data_by_id := {}
	for patch in fine.active_leaves():
		var data := PlanetPatchMesh.generate(patch.id, R, fine.stitch_mask(patch.id))
		sampler.prepare(data)
		data_by_id[patch.id.stable_key()] = data
		for i in range(1089):
			var from: Vector3 = data.from[i]
			var to: Vector3 = data.vertices[i]
			check(from.is_finite() and to.is_finite(), "finite morph endpoints")
			check(from.distance_to(sampler.sample(patch.id.face, patch.id.local_uv_to_face_uv(data.uv[i]))) < POSITION_EPS, "morph zero samples actual parent")
			check(absf(to.length() - R) < 0.02, "morph one on sphere")
			check(from.lerp(to, 0.5).is_finite(), "finite intermediate")
		# Endpoints must reproduce the coarse triangles, not just their vertices.
		for i in range(0, data.indices.size(), 57):
			var local: Vector2 = (data.uv[data.indices[i]] + data.uv[data.indices[i + 1]] + data.uv[data.indices[i + 2]]) / 3.0
			var actual := _sample_morphed(data, local, 0.0)
			var expected := sampler.sample(patch.id.face, patch.id.local_uv_to_face_uv(local))
			check(actual.distance_to(expected) < POSITION_EPS, "morph coarse triangle endpoint %s mask=%d error=%.6f" % [patch.id, data.mask, actual.distance_to(expected)])
	# Sample common edges during the transition, on both faces and same face.
	for patch in fine.active_leaves():
		var data: Dictionary = data_by_id[patch.id.stable_key()]
		for edge in range(4):
			var other_id := PlanetTopology.get_neighbor_patch(patch.id, edge)
			var destination_edge := edge ^ 1
			var reversed := false
			if other_id.face != patch.id.face:
				var transition := PlanetTopology.get_edge_transition(patch.id.face, edge)
				destination_edge = transition.neighbor_edge
				reversed = transition.is_reversed
			for t in [0.0, 0.125, 0.375, 0.7, 1.0]:
				var local := PlanetTopology.edge_uv(edge, t)
				var neighbor_uv := other_id.local_uv_to_face_uv(PlanetTopology.edge_uv(destination_edge, 1.0 - t if reversed else t))
				var neighbor := fine.find_leaf(other_id.face, neighbor_uv)
				var other: Dictionary = data_by_id[neighbor.id.stable_key()]
				var bounds := neighbor.id.get_uv_bounds()
				var other_local := (neighbor_uv - bounds.position) / bounds.size
				for factor in [0.0, 0.25, 0.5, 0.75, 1.0]:
					var a := _sample_morphed(data, local, factor)
					var b := _sample_morphed(other, other_local, factor)
					check(a.distance_to(b) < POSITION_EPS, "watertight morph %s edge=%d t=%.3f morph=%.2f delta=%.6f" % [patch.id, edge, t, factor, a.distance_to(b)])

func _sample_morphed(data: Dictionary, uv: Vector2, factor: float) -> Vector3:
	var start := data.duplicate()
	start.vertices = data.from
	return PlanetPatchMesh.sample(start, uv).lerp(PlanetPatchMesh.sample(data, uv), factor)

func test_controller(split_budget: int = 1, merge_budget: int = 1) -> void:
	var config := PlanetLodConfig.new()
	config.cpu_budget_ms = 0.0 # Deterministic operation-budget regression; slicing tested separately.
	config.max_render_level = 2
	config.mesh_budget = 3
	config.split_budget = split_budget
	config.merge_budget = merge_budget
	config.morph_seconds = 0.02
	var first := PlanetQuadtreeView.new()
	root.add_child(first)
	first.initialize(R, config)
	first.profile.enabled = true
	var camera := Vector3(0, 0, 51000)
	var peak := 6
	var peak_splits := 0
	var peak_merges := 0
	var stable := 0
	var previous := ""
	for update in range(1500):
		first.step(camera, 720, 70, 0.05)
		check(first.splits_last_update <= split_budget and first.merges_last_update <= merge_budget and first.commits_last_update <= 3, "budgets")
		peak_splits = maxi(peak_splits, first.splits_last_update)
		check(first.tree.is_balanced(), "2:1 in every controller state")
		check(int(first.profile.counts.get("sampler_generated", 0)) == 0, "coarse geometry reused, no hidden unbudgeted generation")
		peak = maxi(peak, first.tree.leaves.size())
		var signature := _signature(first.tree)
		stable = stable + 1 if first.state == "idle" and signature == previous else 0
		previous = signature
		if stable > 10:
			break
		if update % 200 == 0:
			print("QUADTREE_PROGRESS: update=%d leaves=%d state=%s" % [update, first.tree.leaves.size(), first.state])
		if update % 20 == 0:
			await process_frame
	check(stable > 10 and peak > 6, "stationary convergence with hysteresis")
	check(first.profile.counts.get("selection_skipped", 0) == 1, "stationary selection reused")
	check(first._geometry.size() <= first.tree.nodes.size(), "geometry cache bounded by logical nodes")
	var near_signature := _signature(first.tree)
	var second := PlanetQuadtreeView.new()
	root.add_child(second)
	second.initialize(R, config)
	for update in range(1500):
		second.step(camera, 720, 70, 0.05)
		if second.state == "idle" and _signature(second.tree) == near_signature:
			break
		if update % 20 == 0:
			await process_frame
	check(_signature(second.tree) == near_signature, "deterministic LOD selection")
	for update in range(1500):
		first.step(Vector3(0, 0, 2000000), 720, 70, 0.05)
		check(first.splits_last_update <= split_budget and first.merges_last_update <= merge_budget and first.commits_last_update <= 3, "merge budgets")
		peak_merges = maxi(peak_merges, first.merges_last_update)
		check(first.tree.is_balanced(), "2:1 during batched merge")
		check(int(first.profile.counts.get("sampler_generated", 0)) == 0, "merge reuses parent geometry")
		if first.state == "idle" and first.tree.leaves.size() == 6:
			break
		if update % 20 == 0:
			await process_frame
	check(first.tree.leaves.size() == 6 and first.state == "idle", "retreat merges to roots")
	check(first._geometry.size() == 6, "merge prunes obsolete geometry")
	check(peak_splits > 1 if split_budget > 1 else peak_splits == 1, "split batch exercised")
	check(peak_merges > 1 if merge_budget > 1 else peak_merges == 1, "merge batch exercised")
	print("QUADTREE_STATS: peak_leaves=%d final_leaves=%d transitions=%d peak_ops=%d/%d" % [peak, first.tree.leaves.size(), first.completed_transitions, peak_splits, peak_merges])
	first.queue_free()
	second.queue_free()
	await process_frame

func _signature(tree: PlanetQuadtree) -> String:
	var keys: Array = tree.leaves.keys()
	keys.sort()
	return str(keys)

func test_incremental_geometry() -> void:
	for face in range(6):
		for level: int in [0, 1, 6]:
			var n := 1 << level
			for xy in [Vector2i.ZERO, Vector2i(n - 1, n - 1), Vector2i(n / 2, n / 2)]:
				var id := PatchId.new(face, level, xy.x, xy.y)
				var data := PlanetPatchMesh.begin_generate(id, R, 0)
				while not PlanetPatchMesh.advance_generate(data, 64):
					check(data.next_vertex < 1089, "generation yields before completion")
				var center := PlanetSSE.center(id, R)
				for i in range(1089):
					var expected := PlanetMath.face_uv_to_position(face, id.local_uv_to_face_uv(data.uv[i]), R)
					check(data.vertices[i].distance_to(expected) < 0.02, "affine frame matches Stage 1 oracle")
					check(expected.distance_to(center) <= PlanetSSE.extent(id, R) + 0.02, "tight bound contains curved patch")
	# Every mask, grid point and cell center exercises exact bin boundaries.
	for mask in range(16):
		var id := PatchId.root(4)
		var data := PlanetPatchMesh.generate(id, R, mask)
		var saved: PackedVector3Array = data.vertices.duplicate()
		var restitched := PlanetPatchMesh.with_mask(data, mask ^ 15)
		var sampler := PlanetSurfaceSampler.new(PlanetQuadtree.new(), R)
		sampler.prepare(restitched)
		check(data.vertices == saved and data.from == saved, "morph cannot mutate shared geometry")
		for y in range(65):
			for x in range(65):
				check(PlanetPatchMesh.sample(data, Vector2(x, y) / 64.0).is_finite(), "all mask bin boundaries covered")
		for quadrant in range(-1, 4):
			var fine_id: PatchId = id if quadrant == -1 else id.get_children_ids()[quadrant]
			var fine := PlanetPatchMesh.generate(fine_id, R, 0)
			fine.from = fine.vertices.duplicate()
			var offset := Vector2.ZERO if quadrant == -1 else Vector2(quadrant & 1, quadrant >> 1) * 0.5
			var scale := Vector2.ONE if quadrant == -1 else Vector2.ONE * 0.5
			var context := {"source": data, "stencil": PlanetPatchMesh.stencil(mask, quadrant), "offset": offset, "scale": scale, "next_vertex": 0}
			sampler.advance_prepare(fine, context, 1089)
			var cold: PackedVector3Array = fine.from.duplicate()
			context.next_vertex = 0
			sampler.advance_prepare(fine, context, 1089)
			for i in range(1089):
				var expected := PlanetPatchMesh.sample(data, offset + fine.uv[i] * scale)
				check(fine.from[i].distance_to(expected) < POSITION_EPS, "all 80 stencil templates match real triangles")
				check(fine.from[i] == cold[i], "cold/warm stencil equivalence")
	check(PlanetPatchMesh._stencils.size() <= 80, "bounded stencil cache")

func test_cpu_slices() -> void:
	var config := PlanetLodConfig.new()
	config.max_render_level = 0
	config.cpu_budget_ms = 0.000001 # One indivisible quantum, independent of machine speed.
	var view := PlanetQuadtreeView.new()
	root.add_child(view)
	view.initialize(R, config)
	view.profile.enabled = true
	var generated := 0
	for update in range(400):
		view.step(Vector3(0, 0, 140000), 720, 70, 0.05)
		generated += int(view.profile.counts.get("generated", 0))
		check(int(view.profile.counts.get("generated_vertices", 0)) <= 64, "CPU budget yields within one vertex block")
		check(view.commits_last_update <= 1, "CPU deadline stops extra commits")
		if view.state == "idle":
			break
	check(view.state == "idle" and generated == 6, "all roots complete under tiny CPU budget")
	var nodes := view._active.values().map(func(entry: Dictionary) -> int: return entry.node.get_instance_id())
	for update in range(20):
		view.step(Vector3(0, 0, 140000), 720, 70, 0.05)
		check(view.commits_last_update == 0 and view.profile.counts.get("generated", 0) == 0, "idle meshes never regenerated")
	check(nodes == view._active.values().map(func(entry: Dictionary) -> int: return entry.node.get_instance_id()), "idle visuals reused")
	view.queue_free()
	await process_frame
