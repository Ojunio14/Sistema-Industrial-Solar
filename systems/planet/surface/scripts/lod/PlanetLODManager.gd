extends Node3D
class_name PlanetLODManager

@export_group("LOD")
@export_range(5, 65, 2) var chunk_resolution: int = 17
@export_range(0, 12) var max_depth: int = 9
@export_range(0.5, 64.0, 0.5) var split_error_pixels: float = 8.0
@export_range(2.0, 64.0, 1.0) var max_quad_pixels: float = 10.0
@export_range(0.1, 0.9, 0.05) var merge_ratio: float = 0.55
@export_range(6, 4096) var max_resident_chunks: int = 510
@export_range(0, 512) var max_cached_chunks: int = 96
@export_range(1, 8) var max_worker_jobs: int = 2
@export_range(1, 8) var max_uploads_per_frame: int = 2
@export_range(0.1, 16.0, 0.1) var upload_budget_ms: float = 2.0
@export_range(0.02, 1.0, 0.01) var selection_interval: float = 0.12
@export_flags_3d_render var terrain_layers: int = 1
@export var terrain_material: Material
@export var debug_lod_colors: bool = false:
	set(value):
		debug_lod_colors = value
		if _debug_material:
			_debug_material.set_shader_parameter("show_lod", value)
		if _runtime_material is ShaderMaterial:
			(_runtime_material as ShaderMaterial).set_shader_parameter("show_lod", value)

var shape: PlanetShape
var geology: PlanetGeology
var geology_debug_mode := 0
var climate: PlanetClimate
var climate_debug_mode := 0
var biomes: PlanetBiomes
var biome_debug_mode := 0
var material_debug_mode := 0
var use_technical_material := false
var roots: Array[QuadtreeNode] = []
var revision: int = 0
var cache_hits: int = 0
var discarded_jobs: int = 0
var generated_chunks: int = 0
var last_build_ms: float = 0.0
var last_upload_ms: float = 0.0
var _definition: PlanetDefinition
var _nodes: Dictionary = {}
var _queue: Array[QuadtreeNode] = []
var _jobs: Array[Dictionary] = []
var _cache: Dictionary = {}
var _elapsed: float = 0.0
var _debug_material: ShaderMaterial
var _runtime_material: Material
var _geology_material: ShaderMaterial
var _climate_material: ShaderMaterial
var _climate_textures: Array[Texture2D] = []
var _biome_material: ShaderMaterial
var _biome_textures: Array[Texture2D] = []
var biome_debug_create_ms := 0.0
var _force_selection := true
var _sample_resolution: int = 17
var _split_candidates: Array[QuadtreeNode] = []
var _merge_candidates: Array[QuadtreeNode] = []
var budget_rebalances := 0
var _uploads_this_frame := 0
var mining_regions: Dictionary = {}
var mining_pins: Dictionary = {}
var mining_protected: Dictionary = {}


func configure(source: PlanetDefinition) -> void:
	# A revisão invalida tarefas em voo sem esperar por elas durante o frame.
	revision += 1
	mining_regions.clear()
	mining_pins.clear()
	mining_protected.clear()
	for root in roots:
		_remove_subtree(root, false)
	roots.clear()
	_queue.clear()
	_cache.clear()
	_definition = source.duplicate(true) as PlanetDefinition if source else null
	geology = PlanetGeology.new(_definition) if _definition else null
	shape = PlanetShape.new(_definition, geology) if _definition else null
	climate = PlanetClimate.new(_definition, -1, geology) if _definition else null
	biomes = PlanetBiomes.new(_definition, climate, geology) if _definition else null
	if not _definition:
		return
	_sample_resolution = clampi(chunk_resolution, 5, 65)
	if _sample_resolution % 2 == 0:
		_sample_resolution += 1
	if not _debug_material:
		_debug_material = ShaderMaterial.new()
		_debug_material.shader = preload("res://systems/planet/surface/materials/planet_lod_debug.gdshader")
		_debug_material.set_shader_parameter("show_lod", debug_lod_colors)
	_runtime_material = terrain_material.duplicate(true) if terrain_material else _create_terrain_material()
	var shader_material := _runtime_material as ShaderMaterial
	if shader_material:
		shader_material.set_shader_parameter("show_lod", debug_lod_colors)
		shader_material.set_shader_parameter("sea_normalized",
			_definition.ocean_depth_m / maxf(_definition.ocean_depth_m + _definition.max_terrain_height_m, 0.01))
		shader_material.set_shader_parameter("height_range_m",
			_definition.ocean_depth_m + _definition.max_terrain_height_m)
		shader_material.set_shader_parameter("material_debug_mode", material_debug_mode)
	_debug_material.set_shader_parameter("sea_normalized",
		_definition.ocean_depth_m / maxf(_definition.ocean_depth_m + _definition.max_terrain_height_m, 0.01))
	_geology_material = ShaderMaterial.new()
	_geology_material.shader = preload("res://systems/planet/geology/geology_debug.gdshader")
	_geology_material.set_shader_parameter("debug_mode", geology_debug_mode)
	_climate_material = ShaderMaterial.new()
	_climate_material.shader = preload("res://systems/planet/climate/climate_debug.gdshader")
	_climate_material.set_shader_parameter("debug_mode", climate_debug_mode)
	_climate_textures.clear()
	_biome_material = ShaderMaterial.new()
	_biome_material.shader = preload("res://systems/planet/biomes/biome_debug.gdshader")
	_biome_material.set_shader_parameter("debug_mode", biome_debug_mode)
	_biome_textures.clear()
	biome_debug_create_ms = 0.0
	for face in range(6):
		var node := _create_node(face, 0, Vector2i.ZERO)
		roots.append(node)
		_request(node, 1.0e12)
	_force_selection = true


func _process(delta: float) -> void:
	_poll_jobs()
	_elapsed += delta
	if _force_selection or _elapsed >= selection_interval:
		_elapsed = 0.0
		_force_selection = false
		var camera := get_viewport().get_camera_3d()
		if is_instance_valid(camera) and camera.cull_mask & terrain_layers:
			var eye := to_local(camera.global_position)
			var screen_size := get_viewport().get_visible_rect().size
			var span := screen_size.y if camera.keep_aspect == Camera3D.KEEP_HEIGHT else screen_size.x
			var focal_pixels := span / (2.0 * tan(deg_to_rad(camera.fov) * 0.5))
			var ortho := span / maxf(camera.size, 0.01) if camera.projection == Camera3D.PROJECTION_ORTHOGONAL else 0.0
			select_lod(eye, focal_pixels, ortho)
	_dispatch_jobs()


## Entrada determinística também utilizada pelos testes, no referencial do planeta.
func select_lod(local_eye: Vector3, focal_pixels: float, ortho_pixels_per_m: float = 0.0) -> void:
	_split_candidates.clear()
	_merge_candidates.clear()
	for root in roots:
		_select(root, local_eye, focal_pixels, ortho_pixels_per_m)
	_split_candidates.sort_custom(func(a: QuadtreeNode, b: QuadtreeNode) -> bool: return a.priority > b.priority)
	_merge_candidates.sort_custom(func(a: QuadtreeNode, b: QuadtreeNode) -> bool: return a.priority < b.priority)
	# Merge candidates are sorted: once eviction is too expensive, all remaining
	# victims are too expensive too. This bounds rejected-split work at capacity.
	for candidate in _split_candidates:
		if not candidate.alive or not candidate.children.is_empty():
			continue
		if _nodes.size() + 4 > maxi(6, max_resident_chunks):
			# Transferir orçamento de regiões menos importantes ao mudar de posição.
			for victim in _merge_candidates:
				if not victim.alive or not victim.is_split:
					continue
				if _mining_locked_subtree(victim):
					continue
				if candidate.priority <= victim.priority * 2.0:
					break
				if _contains(victim, candidate):
					continue
				if victim.children.any(func(child: QuadtreeNode) -> bool: return not child.children.is_empty()):
					continue
				_merge(victim)
				budget_rebalances += 1
				break
		if _nodes.size() + 4 <= maxi(6, max_resident_chunks):
			_split(candidate)
	_queue.sort_custom(func(a: QuadtreeNode, b: QuadtreeNode) -> bool: return a.priority > b.priority)


func _select(node: QuadtreeNode, eye: Vector3, focal: float, ortho: float) -> void:
	if mining_pins.has(node.key):
		return
	if not node.mesh_instance:
		_request(node, 1.0e12 / float(node.depth + 1))
		return
	var error := projected_error(node, eye, focal, ortho)
	# A altura do relevo não pode ser o único critério: num planeta maior e
	# relativamente mais liso, poucos triângulos ainda deixam clima e luz
	# facetados. Este termo limita o tamanho aparente de cada quad da malha.
	var sample_pixels := projected_sample_size(node, eye, focal, _sample_resolution, ortho)
	error = maxf(error, sample_pixels * split_error_pixels / maxf(max_quad_pixels, 1.0))
	if ortho == 0.0 and _behind_horizon(node, eye):
		error = 0.0
	for zone: MiningZone in mining_regions.values():
		if mining_intersects(node, zone) and node.depth < mini(8, max_depth):
			error = maxf(error, 1000000.0 / (node.depth + 1))
	node.priority = error
	if node.is_split:
		if error < split_error_pixels * merge_ratio and not _mining_locked_subtree(node):
			_merge(node)
		else:
			for child in node.children:
				_select(child, eye, focal, ortho)
			if node.children.all(func(child: QuadtreeNode) -> bool: return child.children.is_empty()):
				_merge_candidates.append(node)
	elif not node.children.is_empty():
		# Filhos em preparação: pai continua cobrindo toda a região.
		if error < split_error_pixels * merge_ratio:
			_merge(node)
		else:
			for child in node.children:
				if not child.mesh_instance:
					_request(child, error)
			_try_activate(node)
	elif error > split_error_pixels and node.depth < max_depth:
		_split_candidates.append(node)


func _split(node: QuadtreeNode) -> void:
	for y in range(2):
		for x in range(2):
			var child := _create_node(node.face, node.depth + 1, node.cell * 2 + Vector2i(x, y))
			node.children.append(child)
			_request(child, node.priority)


static func _contains(region: QuadtreeNode, node: QuadtreeNode) -> bool:
	if region.face != node.face or region.depth > node.depth:
		return false
	var shift := node.depth - region.depth
	return Vector2i(node.cell.x >> shift, node.cell.y >> shift) == region.cell


func _behind_horizon(node: QuadtreeNode, eye: Vector3) -> bool:
	var inner_radius := _definition.radius_m + _definition.sea_level_m - _definition.ocean_depth_m
	var outer_radius := _definition.radius_m + _definition.sea_level_m + _definition.natural_max_height_m()
	if eye.length() <= inner_radius or inner_radius <= 0.0:
		return false
	var center := node.bounds.get_center()
	var extent := node.bounds.size.length() * 0.5
	var patch_angle := asin(clampf(extent / maxf(center.length(), 0.01), 0.0, 1.0))
	var horizon := acos(clampf(inner_radius / eye.length(), 0.0, 1.0))
	horizon += acos(clampf(inner_radius / outer_radius, 0.0, 1.0))
	return eye.angle_to(center) > horizon + patch_angle + 0.02


static func projected_error(node: QuadtreeNode, eye: Vector3, focal: float, ortho: float = 0.0) -> float:
	if ortho > 0.0:
		return node.error_m * ortho
	var closest := eye.clamp(node.bounds.position, node.bounds.end)
	return node.error_m * focal / maxf(eye.distance_to(closest), 1.0)


static func projected_sample_size(node: QuadtreeNode, eye: Vector3, focal: float,
		resolution: int, ortho: float = 0.0) -> float:
	var quad_span := node.bounds.size.length() / maxf(float(resolution - 1), 1.0)
	if ortho > 0.0:
		return quad_span * ortho
	return quad_span * focal / maxf(eye.distance_to(node.bounds.get_center()), 1.0)


func _create_node(face: int, depth: int, cell: Vector2i) -> QuadtreeNode:
	var node := QuadtreeNode.new(face, depth, cell)
	_nodes[node.key] = node
	return node


func _request(node: QuadtreeNode, priority: float) -> void:
	node.priority = priority
	if node.pending or node.mesh_instance:
		return
	node.pending = true
	_queue.append(node)


func _dispatch_jobs() -> void:
	var started := Time.get_ticks_usec()
	while not _queue.is_empty() and _jobs.size() < maxi(1, max_worker_jobs):
		if _uploads_this_frame >= maxi(1, max_uploads_per_frame) or (Time.get_ticks_usec() - started) / 1000.0 + last_upload_ms > upload_budget_ms:
			break
		var node: QuadtreeNode = _queue.pop_front()
		if not node.alive:
			continue
		if _cache.has(node.key):
			var cached: Dictionary = _cache[node.key]
			_cache.erase(node.key)
			_attach(node, cached)
			cache_hits += 1
			_uploads_this_frame += 1
			continue
		var builder := PlanetChunkBuilder.new(_definition, node.face, node.depth, node.cell,
			_sample_resolution, geology, climate, biomes)
		var task := WorkerThreadPool.add_task(builder.build, false, "Planet " + node.key)
		_jobs.append({"task": task, "builder": builder, "node": node, "revision": revision})


func _poll_jobs() -> void:
	var started := Time.get_ticks_usec()
	_uploads_this_frame = 0
	for i in range(_jobs.size() - 1, -1, -1):
		if _uploads_this_frame >= maxi(1, max_uploads_per_frame):
			break
		if (Time.get_ticks_usec() - started) / 1000.0 > upload_budget_ms:
			break
		var job := _jobs[i]
		if not WorkerThreadPool.is_task_completed(job.task):
			continue
		WorkerThreadPool.wait_for_task_completion(job.task)
		_jobs.remove_at(i)
		var node: QuadtreeNode = job.node
		if job.revision != revision or not node.alive:
			discarded_jobs += 1
			continue
		var data: Dictionary = job.builder.result
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, data.arrays, [], {}, data.format)
		data.erase("arrays")
		data["mesh"] = mesh
		_attach(node, data)
		last_build_ms = data.build_ms
		generated_chunks += 1
		_uploads_this_frame += 1
	last_upload_ms = (Time.get_ticks_usec() - started) / 1000.0
	# Troca atômica dos quatro irmãos, sem um frame vazio no meio.
	for root in roots:
		_activate_ready(root)


func _attach(node: QuadtreeNode, data: Dictionary) -> void:
	node.mesh_data = data
	node.error_m = data.error_m
	node.bounds = data.bounds
	node.pending = false
	var instance := MeshInstance3D.new()
	instance.name = "Chunk_" + node.key.replace("/", "_")
	instance.layers = terrain_layers
	instance.mesh = data.mesh
	instance.custom_aabb = data.bounds.grow(0.01)
	instance.material_override = _active_material()
	instance.set_instance_shader_parameter("lod_color",
		Color.from_hsv(fmod(float(node.depth) * 0.14 + float(node.face) * 0.015, 1.0), 0.62, 0.9))
	instance.visible = node.depth == 0
	add_child(instance)
	node.mesh_instance = instance


func _activate_ready(node: QuadtreeNode) -> void:
	if node.is_split:
		for child in node.children:
			_activate_ready(child)
	else:
		_try_activate(node)


func _try_activate(node: QuadtreeNode) -> void:
	if mining_pins.has(node.key):
		return
	if node.children.size() != 4 or node.is_split:
		return
	for child in node.children:
		if not child.mesh_instance:
			return
	node.mesh_instance.visible = false
	for child in node.children:
		child.mesh_instance.visible = true
	node.is_split = true
	_force_selection = true


func _merge(node: QuadtreeNode) -> void:
	if _mining_locked_subtree(node):
		return
	node.mesh_instance.visible = true
	for child in node.children:
		_remove_subtree(child, true)
	node.children.clear()
	node.is_split = false
	_queue = _queue.filter(func(item: QuadtreeNode) -> bool: return item.alive)


func _remove_subtree(node: QuadtreeNode, cache_mesh: bool) -> void:
	node.alive = false
	for child in node.children:
		_remove_subtree(child, cache_mesh)
	node.children.clear()
	_nodes.erase(node.key)
	if is_instance_valid(node.mesh_instance):
		if cache_mesh and max_cached_chunks > 0:
			_cache.erase(node.key)
			_cache[node.key] = node.mesh_data
			while _cache.size() > max_cached_chunks:
				_cache.erase(_cache.keys()[0])
		node.mesh_instance.visible = false
		node.mesh_instance.queue_free()
		node.mesh_instance = null
	node.mesh_data = {}


func get_stats() -> Dictionary:
	var visible_count := 0
	var deepest := 0
	var triangles := 0
	for node: QuadtreeNode in _nodes.values():
		if node.mesh_instance and node.mesh_instance.visible:
			visible_count += 1
			deepest = maxi(deepest, node.depth)
			triangles += (2 * (_sample_resolution - 1) * (_sample_resolution - 1) + 8 * (_sample_resolution - 1))
	return {"visible": visible_count, "resident": _nodes.size(), "queued": _queue.size(),
		"jobs": _jobs.size(), "cached": _cache.size(), "depth": deepest, "triangles": triangles,
		"generated": generated_chunks, "cache_hits": cache_hits, "discarded": discarded_jobs,
		"build_ms": last_build_ms, "upload_ms": last_upload_ms, "revision": revision,
		"rebalances": budget_rebalances}

func set_geology_debug_mode(mode: int) -> void:
	geology_debug_mode = posmod(mode, 10)
	if geology_debug_mode > 0:
		climate_debug_mode = 0
		biome_debug_mode = 0
		set_material_debug_mode(0)
	if _geology_material:
		_geology_material.set_shader_parameter("debug_mode", geology_debug_mode)
	_refresh_chunk_materials()

func set_climate_debug_mode(mode: int) -> void:
	climate_debug_mode = posmod(mode, 6)
	if climate_debug_mode > 0:
		geology_debug_mode = 0
		biome_debug_mode = 0
		set_material_debug_mode(0)
		if _climate_textures.is_empty() and climate:
			_climate_textures = climate.create_debug_textures()
			_climate_material.set_shader_parameter("climate_fields", _climate_textures[0])
			_climate_material.set_shader_parameter("climate_shadow", _climate_textures[1])
	if _climate_material:
		_climate_material.set_shader_parameter("debug_mode", climate_debug_mode)
	_refresh_chunk_materials()

func set_biome_debug_mode(mode: int) -> void:
	biome_debug_mode = posmod(mode, 4)
	if biome_debug_mode > 0:
		geology_debug_mode = 0
		climate_debug_mode = 0
		set_material_debug_mode(0)
		if _biome_textures.is_empty() and biomes:
			var started := Time.get_ticks_usec()
			_biome_textures = biomes.create_debug_textures()
			_biome_material.set_shader_parameter("biome_dominant", _biome_textures[0])
			_biome_material.set_shader_parameter("biome_blend", _biome_textures[1])
			biome_debug_create_ms = (Time.get_ticks_usec() - started) / 1000.0
	if _biome_material:
		_biome_material.set_shader_parameter("debug_mode", biome_debug_mode)
	_refresh_chunk_materials()

func set_material_debug_mode(mode: int) -> void:
	material_debug_mode = posmod(mode, 7)
	if material_debug_mode > 0:
		geology_debug_mode = 0
		climate_debug_mode = 0
		biome_debug_mode = 0
		debug_lod_colors = false
	if _runtime_material is ShaderMaterial:
		(_runtime_material as ShaderMaterial).set_shader_parameter("material_debug_mode", material_debug_mode)
	_refresh_chunk_materials()

func set_technical_material_enabled(enabled: bool) -> void:
	use_technical_material = enabled
	_refresh_chunk_materials()

func _create_terrain_material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = preload("res://systems/planet/surface/materials/planet_terrain_pbr.gdshader")
	for family in PlanetMaterialWeights.NAMES:
		for map_name in ["albedo", "normal", "roughness"]:
			var path := "res://assets/textures/terrain/%s/%s_%s.png" % [family, family, map_name]
			var texture := load(path) as Texture2D
			assert(texture != null, "Mapa essencial ausente: " + path)
			material.set_shader_parameter("%s_%s" % [family, map_name], texture)
	return material

func _active_material() -> Material:
	if biome_debug_mode > 0:
		return _biome_material
	if climate_debug_mode > 0:
		return _climate_material
	if geology_debug_mode > 0:
		return _geology_material
	if use_technical_material:
		return _debug_material
	return _runtime_material

func _refresh_chunk_materials() -> void:
	var active := _active_material()
	for node: QuadtreeNode in _nodes.values():
		if is_instance_valid(node.mesh_instance):
			node.mesh_instance.material_override = active


func _exit_tree() -> void:
	# Cada tarefa precisa ser aguardada uma vez para liberar recursos do pool.
	for job in _jobs:
		WorkerThreadPool.wait_for_task_completion(job.task)
	_jobs.clear()

func mining_intersects(node: QuadtreeNode, zone: MiningZone) -> bool:
	if node.mining_region_hits.has(zone.id):
		return node.mining_region_hits[zone.id]
	var size := 1.0 / float(1 << node.depth)
	var centre := CubeSphereMapping.face_uv_to_direction(node.face, (Vector2(node.cell) + Vector2(0.5, 0.5)) * size)
	var angle := 0.0
	for offset in [Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN]:
		angle = maxf(angle, centre.angle_to(CubeSphereMapping.face_uv_to_direction(node.face, (Vector2(node.cell) + offset) * size)))
	var bounds := Rect2(Vector2(zone.chunk_bounds.position) * 256, Vector2(zone.chunk_bounds.size) * 256).grow(MiningTransitionJob.COLLAR_M + 4.0)
	var reach := maxf(bounds.position.length(), maxf(bounds.end.length(), maxf(Vector2(bounds.position.x, bounds.end.y).length(), Vector2(bounds.end.x, bounds.position.y).length())))
	var intersects := centre.angle_to(zone.up) <= angle + atan(reach / zone.radius_m) + 0.00001
	node.mining_region_hits[zone.id] = intersects
	return intersects

func _mining_locked_subtree(node: QuadtreeNode) -> bool:
	return mining_protected.has(node.key)

func capture_mining_patches(zone: MiningZone) -> Array:
	var selected: Array[QuadtreeNode] = []
	for node: QuadtreeNode in _nodes.values():
		if not node.mesh_instance or not node.mesh_instance.visible or not mining_intersects(node, zone):
			continue
		if node.depth < mini(8, max_depth) or (mining_pins.has(node.key) and mining_pins[node.key] != zone.id):
			return []
		selected.append(node)
	if selected.is_empty():
		return []
	var sources := []
	for node in selected:
		mining_pins[node.key] = zone.id
		for depth in range(node.depth + 1):
			var shift := node.depth - depth
			mining_protected["%d/%d/%d/%d" % [node.face, depth, node.cell.x >> shift, node.cell.y >> shift]] = true
		sources.append({"key": node.key, "mesh": node.mesh_instance.mesh,
			"face": node.face, "depth": node.depth, "cell": node.cell, "resolution": _sample_resolution,
			"surface_indices": 6 * (_sample_resolution - 1) * (_sample_resolution - 1)})
	return sources

func release_mining_pins(zone_id: String) -> void:
	mining_regions.erase(zone_id)
	for key in mining_pins.keys():
		if mining_pins[key] == zone_id:
			mining_pins.erase(key)
	mining_protected.clear()
	for key: String in mining_pins:
		var node: QuadtreeNode = _nodes[key]
		for depth in range(node.depth + 1):
			var shift := node.depth - depth
			mining_protected["%d/%d/%d/%d" % [node.face, depth, node.cell.x >> shift, node.cell.y >> shift]] = true
	for node: QuadtreeNode in _nodes.values():
		node.mining_region_hits.erase(zone_id)
	_force_selection = true
