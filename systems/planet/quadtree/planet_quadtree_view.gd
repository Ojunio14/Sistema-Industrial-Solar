class_name PlanetQuadtreeView
extends Node3D

const DEBUG_SHADER = preload("res://systems/planet/quadtree/planet_debug.gdshader")
const COLORS := [Color(0.95, 0.40, 0.30), Color(0.70, 0.30, 0.75),
	Color(0.45, 0.80, 0.40), Color(0.90, 0.70, 0.30),
	Color(0.30, 0.65, 0.95), Color(0.30, 0.80, 0.75)]

var tree := PlanetQuadtree.new()
var config := PlanetLodConfig.new()
var radius: float = 50000.0
var splits_last_update := 0
var merges_last_update := 0
var commits_last_update := 0
var completed_transitions := 0
var balance_ok := true
var state := "initial"
var morph := 1.0
var _active: Dictionary = {}
var _staged: Dictionary = {}
var _merge_final: Dictionary = {}
var _pending: Array[PatchId] = []
var _target: PlanetQuadtree
var _fine: PlanetQuadtree
var _sampler: PlanetSurfaceSampler
var _merging := false
var _building_final := false
var _camera_position := Vector3.ZERO
var _height := 720.0
var _fov := 70.0
var _ortho := 0.0
var _planes: Array[Plane] = []
var profile = preload("res://systems/planet/quadtree/planet_profile.gd").new()
var _geometry: Dictionary = {} # Immutable arrays, bounded to live logical nodes.
var _spatial: Dictionary = {}
var _job: Dictionary = {}
var _validation: Array[PlanetPatch] = []
var _planning: Array[PlanetPatch] = []
var _planning_index := 0
var _last_selection: Array = []
var terrain: PlanetTerrain
var meters_per_unit := 1.0
var debug_mode := 0
const DEBUG_MODES := ["Faces/LOD", "Terra/oceano", "Altitude", "Continentalidade", "Macroformas", "Nivel do mar", "Costas"]

func initialize(p_radius: float, p_config: PlanetLodConfig, p_terrain: PlanetTerrain = null, p_meters_per_unit: float = 1.0) -> void:
	assert(p_radius > 0.0 and p_config.is_valid())
	radius = p_radius
	config = p_config
	terrain = p_terrain
	meters_per_unit = p_meters_per_unit
	debug_mode = 2 if terrain != null else 0
	_target = tree
	_fine = tree
	for patch in tree.active_leaves():
		_pending.append(patch.id)

func update_camera(camera: Camera3D, delta: float) -> void:
	var height := float(camera.get_viewport().get_visible_rect().size.y)
	var aspect := camera.get_viewport().get_visible_rect().size.aspect()
	var vertical_fov := camera.fov
	if camera.keep_aspect == Camera3D.KEEP_WIDTH:
		vertical_fov = rad_to_deg(2.0 * atan(tan(deg_to_rad(camera.fov) * 0.5) / aspect))
	var ortho := 0.0
	if camera.projection == Camera3D.PROJECTION_ORTHOGONAL:
		ortho = camera.size if camera.keep_aspect == Camera3D.KEEP_HEIGHT else camera.size / aspect
	_planes = camera.get_frustum()
	step(to_local(camera.global_position), height, vertical_fov, delta, ortho)

# One coordinator owns structural edits, staged commits and the common morph clock.
func step(camera: Vector3, height: float, fov: float, delta: float, ortho: float = 0.0) -> void:
	profile.begin()
	var started: int = profile.stamp()
	_step(camera, height, fov, delta, ortho)
	profile.finish(&"update_us", started)
	profile.count(&"splits", splits_last_update)
	profile.count(&"merges", merges_last_update)
	profile.count(&"commits", commits_last_update)
	profile.count(&"pending", _pending.size() + int(not _job.is_empty()))
	profile.count(&"leaves", tree.leaves.size())
	profile.count(&"patches", tree.nodes.size())

func _step(camera: Vector3, height: float, fov: float, delta: float, ortho: float = 0.0) -> void:
	splits_last_update = 0
	merges_last_update = 0
	commits_last_update = 0
	_camera_position = camera
	_height = height
	_fov = fov
	_ortho = ortho
	if state == "planning":
		_plan()
		return
	if state == "initial" or state == "building":
		_build()
		return
	if state == "morph":
		var amount := delta / config.morph_seconds
		morph = maxf(0.0, morph - amount) if _merging else minf(1.0, morph + amount)
		_set_morph(_active, morph)
		if (_merging and morph == 0.0) or (not _merging and morph == 1.0):
			if _merging:
				_replace_active(_merge_final)
				_merge_final = {}
				tree = _target
			state = "idle"
			completed_transitions += 1
			_sampler = null
			_prune_caches()
			for entry: Dictionary in _active.values():
				entry.morphing = false
		return
	_select()

func _bounds(id: PatchId) -> Dictionary:
	var key := id.stable_key()
	if not _spatial.has(key):
		var displacement := maxf(-PlanetTerrain.MIN_HEIGHT, PlanetTerrain.MAX_HEIGHT) / meters_per_unit if terrain != null else 0.0
		var error := terrain.patch_error(id) / meters_per_unit if terrain != null else 0.0
		_spatial[key] = {"center": PlanetSSE.center(id, radius), "extent": PlanetSSE.extent(id, radius) + displacement, "error": PlanetSSE.geometric_error(id, radius, error)}
	return _spatial[key]

func _score(id: PatchId) -> float:
	var bounds := _bounds(id)
	return PlanetSSE.project_error(bounds.error, bounds.center, bounds.extent, _camera_position, _height, _fov, _ortho)

func _visible(id: PatchId) -> bool:
	var bounds := _bounds(id)
	var point := to_global(bounds.center)
	for plane in _planes:
		if plane.distance_to(point) > bounds.extent:
			return false
	return true

func _select() -> void:
	var signature := [_camera_position, _height, _fov, _ortho, config.split_pixels, config.merge_pixels, config.max_render_level]
	if signature == _last_selection:
		profile.count(&"selection_skipped")
		return
	var started: int = profile.stamp()
	_select_impl()
	profile.finish(&"selection_total_us", started)
	_last_selection = signature if state == "idle" else []

func _select_impl() -> void:
	var candidates: Array[Dictionary] = []
	for patch: PlanetPatch in tree.leaves.values():
		if patch.id.level >= config.max_render_level:
			continue
		var score := _score(patch.id)
		if score > config.split_pixels:
			candidates.append({"id": patch.id, "key": String(patch.id.stable_key()), "priority": score * (1.0 if _visible(patch.id) else 0.01)})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.key < b.key if a.priority == b.priority else a.priority > b.priority)
	var working := tree
	for patch in candidates:
		var remaining := config.split_budget - splits_last_update
		if remaining <= 0:
			break
		profile.count(&"split_requests")
		var balance_start: int = profile.stamp()
		var plan := working.split_plan(patch.id, remaining, config.max_render_level)
		if plan.is_empty():
			# With a small budget refine one prerequisite now; the requested leaf waits.
			var complete := working.split_plan(patch.id, 1000, config.max_render_level)
			if not complete.is_empty():
				plan = working.split_plan(complete[0], remaining, config.max_render_level)
		if not plan.is_empty():
			for dependency in plan:
				if not dependency.is_equal(patch.id):
					profile.count(&"forced_splits")
			if working == tree:
				working = tree.copy_tree()
			for id in plan:
				var performed := working.split(id, remaining, config.max_render_level)
				assert(performed == 1)
				splits_last_update += performed
		profile.finish(&"balance_us", balance_start)
	if splits_last_update > 0:
		_target = working
		_begin(false)
		return
	var merge_candidates: Array[Dictionary] = []
	for patch: PlanetPatch in tree.nodes.values():
		if patch.is_leaf():
			continue
		var score := _score(patch.id)
		if score >= config.merge_pixels:
			continue
		var balance_start: int = profile.stamp()
		var allowed := tree.can_merge(patch.id)
		profile.finish(&"balance_us", balance_start)
		if allowed:
			merge_candidates.append({"id": patch.id, "key": String(patch.id.stable_key()), "score": score})
	merge_candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.key < b.key if a.score == b.score else a.score < b.score)
	if not merge_candidates.is_empty():
		var balance_start: int = profile.stamp()
		_target = tree.copy_tree()
		for patch in merge_candidates:
			if merges_last_update >= config.merge_budget:
				break
			if _target.merge(patch.id):
				merges_last_update += 1
		profile.finish(&"balance_us", balance_start)
		if merges_last_update > 0:
			_begin(true)

func _begin(merging: bool) -> void:
	_merging = merging
	_building_final = false
	_fine = tree if merging else _target
	_sampler = PlanetSurfaceSampler.new(_target if merging else tree, radius, _geometry, terrain, meters_per_unit)
	_staged = {}
	_merge_final = {}
	_pending.clear()
	_validation = _target.active_leaves()
	_planning = _validation.duplicate() if _fine == _target else _fine.active_leaves()
	_planning_index = 0
	state = "planning"

func _deadline() -> int:
	return Time.get_ticks_usec() + int(config.cpu_budget_ms * 1000.0) if config.cpu_budget_ms > 0.0 else 9223372036854775807

func _plan() -> void:
	var deadline := _deadline()
	while not _validation.is_empty():
		var started: int = profile.stamp()
		var patch: PlanetPatch = _validation.pop_back()
		balance_ok = _target.validate_leaf(patch.id)
		profile.finish(&"balance_us", started)
		assert(balance_ok, "Transaction violated 2:1.")
		if Time.get_ticks_usec() >= deadline:
			return
	while _planning_index < _planning.size():
		var started: int = profile.stamp()
		var patch := _planning[_planning_index]
		_planning_index += 1
		var key := patch.id.stable_key()
		var unchanged := _active.has(key) and _target.leaves.has(key) and tree.leaves.has(key)
		if unchanged and tree.stitch_mask(patch.id) == _target.stitch_mask(patch.id):
			_staged[key] = _active[key]
		else:
			if unchanged:
				profile.count(&"mask_changes")
			_pending.append(patch.id)
		profile.finish(&"stitch_us", started)
		if Time.get_ticks_usec() >= deadline:
			return
	_planning.clear()
	state = "building"

func _prune_caches() -> void:
	for key in _geometry.keys():
		if not tree.nodes.has(key):
			_geometry.erase(key)
	for key in _spatial.keys():
		if not tree.nodes.has(key):
			_spatial.erase(key)

func _build() -> void:
	var deadline := _deadline()
	while commits_last_update < config.mesh_budget and (not _pending.is_empty() or not _job.is_empty()):
		_build_slice()
		if Time.get_ticks_usec() >= deadline:
			break
	if not _pending.is_empty() or not _job.is_empty():
		return
	if state == "initial":
		_replace_active(_staged)
		for entry: Dictionary in _active.values():
			entry.morphing = false
		_staged = {}
		state = "idle"
		return
	if _merging and not _building_final:
		_building_final = true
		for patch in _target.active_leaves():
			var key := patch.id.stable_key()
			if _staged.has(key) and not _staged[key].morphing:
				_merge_final[key] = _staged[key]
			else:
				_pending.append(patch.id)
		return
	morph = 1.0 if _merging else 0.0
	_set_morph(_staged, morph)
	_replace_active(_staged)
	_staged = {}
	if not _merging:
		tree = _target
	state = "morph"

# Each quantum is <= 64 vertices, one topology setup or one indivisible GPU
# commit. The deadline is soft: it cannot preempt a RenderingServer call.
func _build_slice() -> void:
	if _job.is_empty():
		var id: PatchId = _pending.pop_front()
		var key := id.stable_key()
		var source_tree := _target if _building_final else _fine
		var started: int = profile.stamp()
		var mask := source_tree.stitch_mask(id)
		profile.finish(&"stitch_us", started)
		started = profile.stamp()
		var cached := _geometry.has(key)
		var data := PlanetPatchMesh.with_mask(_geometry[key], mask) if cached else PlanetPatchMesh.begin_generate(id, radius, mask, terrain, meters_per_unit)
		profile.finish(&"generate_us", started)
		profile.count(&"geometry_reused" if cached else &"generated")
		_job = {"id": id, "data": data, "phase": "sample_init" if cached else "generate"}
		return
	var data: Dictionary = _job.data
	var started: int = profile.stamp()
	match _job.phase:
		"generate":
			var first_vertex: int = data.next_vertex
			var done := PlanetPatchMesh.advance_generate(data, 64, profile)
			profile.count(&"generated_vertices", int(data.next_vertex) - first_vertex)
			profile.finish(&"generate_us", started)
			if done:
				_geometry[_job.id.stable_key()] = data.duplicate()
				_job.phase = "sample_init"
		"sample_init":
			if _sampler != null and not _building_final:
				var generated := _sampler.generated_count
				_job.context = _sampler.begin_prepare(data)
				profile.count(&"sampler_generated", _sampler.generated_count - generated)
				_job.phase = "sample"
			else:
				_job.phase = "commit"
			profile.finish(&"sample_us", started)
		"sample":
			if _sampler.advance_prepare(data, _job.context, 64):
				_job.phase = "commit"
			profile.finish(&"sample_us", started)
		"commit":
			_commit(data)
			_job = {}

func _commit(data: Dictionary) -> void:
	var started: int = profile.stamp()
	var mesh := PlanetPatchMesh.as_array_mesh(data)
	profile.finish(&"array_mesh_us", started)
	started = profile.stamp()
	var id: PatchId = data.id
	var visual := MeshInstance3D.new()
	visual.name = "Patch_%s" % String(id.stable_key()).replace(":", "_")
	visual.mesh = mesh
	var material := ShaderMaterial.new()
	material.shader = DEBUG_SHADER
	material.set_shader_parameter("face_color", COLORS[id.face])
	material.set_shader_parameter("level", float(id.level))
	material.set_shader_parameter("show_borders", config.show_borders)
	material.set_shader_parameter("debug_mode", debug_mode)
	material.set_shader_parameter("base_radius", radius)
	material.set_shader_parameter("meters_per_unit", meters_per_unit)
	visual.material_override = material
	visual.visible = false
	add_child(visual)
	profile.finish(&"visual_create_us", started)
	profile.count(&"visual_created")
	var entry := {"node": visual, "id": id, "mask": data.mask, "morphing": not _building_final}
	if _building_final:
		_merge_final[id.stable_key()] = entry
	else:
		_staged[id.stable_key()] = entry
	commits_last_update += 1

func _replace_active(replacement: Dictionary) -> void:
	var started: int = profile.stamp()
	for key in _active:
		var entry: Dictionary = _active[key]
		if not replacement.has(key) or replacement[key].node != entry.node:
			entry.node.visible = false
			entry.node.queue_free()
			profile.count(&"visual_removed")
	_active = replacement
	for entry: Dictionary in _active.values():
		entry.node.visible = true
	profile.finish(&"visual_replace_us", started)

func _set_morph(entries: Dictionary, factor: float) -> void:
	for entry: Dictionary in entries.values():
		if entry.morphing:
			entry.node.material_override.set_shader_parameter("morph", factor)

func debug_text() -> String:
	var low := 100
	var high := 0
	var visible_count := 0
	var stitched := 0
	for entry: Dictionary in _active.values():
		if _visible(entry.id):
			visible_count += 1
			low = mini(low, entry.id.level)
			high = maxi(high, entry.id.level)
		if entry.mask != 0:
			stitched += 1
	var face_uv := PlanetMath.direction_to_face_uv(_camera_position)
	var sample := tree.find_leaf(face_uv.face, face_uv.uv) if face_uv != null else tree.roots[0]
	var mask := tree.stitch_mask(sample.id)
	var terrain_info := ""
	if terrain != null and not _camera_position.is_zero_approx():
		var fields := terrain.sample_fields(_camera_position.normalized())
		terrain_info = "Amostra radial: %.1f m | %s | mar 0 m\n" % [fields.x, PlanetTerrain.Form.keys()[int(fields.z)]]
	if debug_mode == 4:
		terrain_info += "0 oceano / 1 planicie / 2 colinas / 3 planalto / 4 serra / 5 cadeia / 6 vale / 7 bacia / 8 excepcional\n"
	return ("F4: %s | seed %s\n" % [DEBUG_MODES[debug_mode], str(terrain.get_seed()) if terrain != null else "sphere"]) + terrain_info + "Leaves %d | total %d | visible~ %d | LOD %d..%d\nSplits %d / merges %d / commits %d | 2:1 %s\nStitched %d | %s | morph %.2f | pending %d\n%s leaf | stitch %s" % [
		tree.leaves.size(), tree.nodes.size(), visible_count, mini(low, high), high,
		splits_last_update, merges_last_update, commits_last_update, "OK" if balance_ok else "FAILED",
		stitched, state, morph, _pending.size() + int(not _job.is_empty()), sample.id, _edge_names(mask)]

func set_debug_mode(mode: int) -> void:
	assert(mode >= 0 and mode < DEBUG_MODES.size())
	debug_mode = mode
	for entries: Dictionary in [_active, _staged, _merge_final]:
		for entry: Dictionary in entries.values():
			entry.node.material_override.set_shader_parameter("debug_mode", mode)

func _edge_names(mask: int) -> String:
	var names: PackedStringArray = []
	for edge in range(4):
		if (mask & (1 << edge)) != 0:
			names.append(PlanetMath.get_edge_name(edge))
	return "none" if names.is_empty() else ", ".join(names)
