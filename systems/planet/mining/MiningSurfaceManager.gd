class_name MiningSurfaceManager
extends Node3D
## Main-thread scheduler, bounded detached jobs, staged upload and atomic ownership.
@export_range(1, 2) var max_workers := 1
@export var max_commits_per_frame := 1
@export var commit_budget_ms := 2.0
@export var max_pending_results := 2
@export var max_visual_chunks := 64
var terrain: PlanetEditableTerrain
var global_terrain: PlanetLODManager
var zones: Dictionary = {}
var jobs: Array = []
var pending: Array = []
var queue: Array = []
var discarded := 0
var committed := 0
var last_commit_ms := 0.0
var last_collision_ms := 0.0
var commits_this_frame := 0
var job_times: Array = []
var commit_times: Array = []
var collision_times: Array = []
var job_intervals: Array = []
var _serial := 0
var _global_revision := 0
var _global_workers := 2
var last_update_ms := 0.0
var last_publish_ms := 0.0
var last_activation_error := ""

func configure(source: PlanetEditableTerrain, renderer: PlanetLODManager) -> void:
	terrain = source
	global_terrain = renderer
	_global_revision = renderer.revision
	_global_workers = renderer.max_worker_jobs

func activate(zone: MiningZone) -> bool:
	last_activation_error = ""
	if zones.has(zone.id):
		return true
	var count := zone.chunk_bounds.get_area()
	for entry: Dictionary in zones.values():
		count += entry.zone.chunk_bounds.get_area()
		# Independent collars/LOD captures cannot share a coarse patch in this version.
		if zone.up.angle_to(entry.zone.up) < terrain._cap(zone) + terrain._cap(entry.zone) + 1024.0 / zone.radius_m:
			last_activation_error = "Zonas visuais precisam de separação para seus patches de transição"
			return false
	if count > max_visual_chunks:
		last_activation_error = "Limite de chunks visuais atingido"
		return false
	# A non-editable 4 m guard preserves the collar's natural boundary normal.
	# Refuse incompatible historical edits; never silently discard stored deltas.
	var first := zone.chunk_bounds.position * 128
	var last := zone.chunk_bounds.end * 128
	for x in range(first.x + 1, last.x):
		for y in [first.y + 1, first.y + 2, last.y - 1, last.y - 2]:
			if zone.read_node(Vector2i(x, y)) != 0:
				last_activation_error = "Edição existente na faixa externa protegida de 4 m"
				return false
	for y in range(first.y + 1, last.y):
		for x in [first.x + 1, first.x + 2, last.x - 1, last.x - 2]:
			if zone.read_node(Vector2i(x, y)) != 0:
				last_activation_error = "Edição existente na faixa externa protegida de 4 m"
				return false
	zone.visual_guard_cells = 2
	for y in range(zone.chunk_bounds.position.y, zone.chunk_bounds.end.y):
		for x in range(zone.chunk_bounds.position.x, zone.chunk_bounds.end.x):
			zone.activate_chunk(Vector2i(x, y))
	_serial += 1
	zones[zone.id] = {"zone": zone, "serial": _serial, "started": Time.get_ticks_usec(),
		"first_commit_ms": -1.0, "visible_ms": -1.0, "published": false,
		"meshes": {}, "staged": {}, "originals": {}, "replacement": {},
		"transition_started": false, "transition_ready": false, "transition_left": 0,
		"capture_after_ms": 0,
		"capture_sources": [], "capture_arrays": [],
		"ring": null, "ring_mesh": null, "ring_shape": null, "error": ""}
	global_terrain.mining_regions[zone.id] = zone
	global_terrain.max_worker_jobs = maxi(1, _global_workers - max_workers)
	global_terrain._force_selection = true
	return true

func deactivate(key: String) -> void:
	if not zones.has(key):
		return
	var entry: Dictionary = zones[key]
	# Restore coverage first in the same main-thread transaction.
	for patch_key: String in entry.originals:
		var node: QuadtreeNode = global_terrain._nodes.get(patch_key)
		if node and node.mesh_instance and node.mesh_data.get("mesh") == entry.originals[patch_key]:
			node.mesh_instance.mesh = entry.originals[patch_key]
	for item: Dictionary in entry.meshes.values():
		free_representation(item)
	for staged: Dictionary in entry.staged.values():
		free_representation(staged.prepared)
	if entry.ring != null:
		entry.ring.instance.visible = false
		entry.ring.body.collision_layer = 0
		entry.ring.instance.queue_free()
		entry.ring.body.queue_free()
	entry.zone.deactivate()
	global_terrain.release_mining_pins(key)
	zones.erase(key)
	for p: Dictionary in pending:
		if p.zone_id == key and p.has("prepared"):
			free_representation(p.prepared)
	pending = pending.filter(func(p: Dictionary) -> bool: return p.zone_id != key)
	if zones.is_empty():
		global_terrain.max_worker_jobs = _global_workers

func _process(_delta: float) -> void:
	if terrain == null:
		return
	var update_start := Time.get_ticks_usec()
	if global_terrain.revision != _global_revision:
		for key in zones.keys():
			deactivate(key)
		_global_revision = global_terrain.revision
	for key in zones.keys():
		if not zones[key].zone.active:
			deactivate(key)
	_poll()
	_commit()
	var publish_start := Time.get_ticks_usec()
	_publish()
	last_publish_ms = (Time.get_ticks_usec() - publish_start) / 1000.0
	_schedule()
	last_update_ms = (Time.get_ticks_usec() - update_start) / 1000.0

func current(item: Dictionary) -> bool:
	if not zones.has(item.zone_id) or zones[item.zone_id].serial != item.serial:
		return false
	if item.kind == "chunk":
		return terrain.snapshot_current(item.snapshot)
	return global_terrain.revision == _global_revision

func _poll() -> void:
	for i in range(jobs.size() - 1, -1, -1):
		var job: Dictionary = jobs[i]
		if not WorkerThreadPool.is_task_completed(job.task):
			continue
		if pending.size() >= max_pending_results and current(job):
			continue
		WorkerThreadPool.wait_for_task_completion(job.task)
		jobs.remove_at(i)
		if not current(job):
			discarded += 1
			continue
		job.data = job.builder.result
		job_intervals.append({"kind": job.kind, "start_usec": job.data.started_usec, "end_usec": job.data.ended_usec})
		if job_intervals.size() > 256:
			job_intervals.pop_front()
		job_times.append(job.data.build_ms)
		if job_times.size() > 256:
			job_times.pop_front()
		job.erase("builder")
		pending.append(job)

func _commit() -> void:
	commits_this_frame = 0
	last_collision_ms = 0
	var start := Time.get_ticks_usec()
	while not pending.is_empty() and commits_this_frame < max_commits_per_frame:
		if commits_this_frame > 0 and (Time.get_ticks_usec() - start) / 1000.0 >= commit_budget_ms:
			break
		var item: Dictionary = pending[0]
		if not current(item):
			pending.pop_front()
			if item.has("prepared"):
				free_representation(item.prepared)
			discarded += 1
			continue
		var entry: Dictionary = zones[item.zone_id]
		if item.kind == "transition":
			if not item.data.valid:
				entry.error = "Fronteira global incompleta; cobertura global preservada"
				pending.pop_front()
				continue
			if not item.has("cursor"):
				item.cursor = 0
			if item.cursor < item.data.clipped.size():
				var patch: Dictionary = item.data.clipped[item.cursor]
				entry.replacement[patch.key] = make_mesh(patch.arrays)
				item.cursor += 1
			else:
				entry.ring_mesh = make_mesh(item.data.ring)
				entry.ring_shape = make_collision(item.data.faces)
				entry.transition_ready = true
				pending.pop_front()
		else:
			if not item.has("mesh"):
				item.mesh = make_mesh(item.data.arrays)
				item.prepared = make_instance(item.zone_id + "_" + str(item.snapshot.coordinate))
				item.prepared.instance.mesh = item.mesh
				item.cursor = 0
			else:
				var collision_start := Time.get_ticks_usec()
				var previous_collision_ms := last_collision_ms
				var collision := make_collision(item.data.faces[item.cursor])
				var node := CollisionShape3D.new()
				item.prepared.body.add_child(node)
				node.shape = collision
				item.prepared.collisions.append(node)
				last_collision_ms = previous_collision_ms + (Time.get_ticks_usec() - collision_start) / 1000.0
				item.cursor += 1
				if item.cursor == item.data.faces.size():
					entry.staged[item.snapshot.coordinate] = {"prepared": item.prepared, "snapshot": item.snapshot}
					if entry.first_commit_ms < 0:
						entry.first_commit_ms = (Time.get_ticks_usec() - entry.started) / 1000.0
					pending.pop_front()
		commits_this_frame += 1
		committed += 1
	last_commit_ms = (Time.get_ticks_usec() - start) / 1000.0
	if commits_this_frame > 0:
		commit_times.append(last_commit_ms)
		collision_times.append(last_collision_ms)
		if commit_times.size() > 256:
			commit_times.pop_front()
			collision_times.pop_front()

static func make_mesh(arrays: Array) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if arrays[Mesh.ARRAY_VERTEX].size() > 0:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, MiningBuildJob.FORMAT)
	return mesh

func make_collision(faces: PackedVector3Array) -> ConcavePolygonShape3D:
	var start := Time.get_ticks_usec()
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	last_collision_ms += (Time.get_ticks_usec() - start) / 1000.0
	return shape

func _publish() -> void:
	for entry: Dictionary in zones.values():
		if not entry.transition_ready:
			continue
		var zone: MiningZone = entry.zone
		var ready := true
		for chunk: MiningChunk in zone._chunks.values():
			if not chunk.active:
				ready = false
				break
			if chunk.mesh_dirty() or not entry.meshes.has(chunk.coordinate):
				if not entry.staged.has(chunk.coordinate) or not terrain.snapshot_current(entry.staged[chunk.coordinate].snapshot):
					ready = false
					break
		if not ready:
			continue
		for coord in entry.staged.keys():
			var staged: Dictionary = entry.staged[coord]
			if not terrain.snapshot_current(staged.snapshot):
				free_representation(staged.prepared)
				entry.staged.erase(coord)
				continue
			if entry.meshes.has(coord):
				free_representation(entry.meshes[coord])
			entry.meshes[coord] = staged.prepared
			var item: Dictionary = entry.meshes[coord]
			item.body.collision_layer = 1
			item.instance.visible = true
			terrain.accept_mesh(staged.snapshot)
			zone.chunk_at(coord).collision_revision = staged.snapshot.revision
		entry.staged.clear()
		if not entry.published:
			entry.ring = make_instance(zone.id + "_transition")
			entry.ring.instance.mesh = entry.ring_mesh
			assign_shapes(entry.ring, [entry.ring_shape])
			entry.ring.body.collision_layer = 1
			entry.ring.instance.visible = true
			for key: String in entry.replacement:
				global_terrain._nodes[key].mesh_instance.mesh = entry.replacement[key]
			entry.published = true
			entry.visible_ms = (Time.get_ticks_usec() - entry.started) / 1000.0
		# Debug modes and PBR use the same shared material as the planet.
		for item: Dictionary in entry.meshes.values():
			item.instance.material_override = global_terrain._active_material()
		entry.ring.instance.material_override = global_terrain._active_material()

func make_instance(label: String) -> Dictionary:
	var instance := MeshInstance3D.new()
	instance.name = label.validate_node_name()
	instance.visible = false
	instance.material_override = global_terrain._active_material()
	add_child(instance)
	var body := StaticBody3D.new()
	body.collision_layer = 0
	add_child(body)
	return {"instance": instance, "body": body, "collisions": []}

func assign_shapes(item: Dictionary, shapes: Array) -> void:
	while item.collisions.size() < shapes.size():
		var collision := CollisionShape3D.new()
		item.body.add_child(collision)
		item.collisions.append(collision)
	for i in range(shapes.size()):
		item.collisions[i].shape = shapes[i]

func free_representation(item: Dictionary) -> void:
	item.instance.visible = false
	item.body.collision_layer = 0
	item.instance.queue_free()
	item.body.queue_free()

func _schedule() -> void:
	queue.clear()
	var camera := get_viewport().get_camera_3d()
	var eye := to_local(camera.global_position) if camera else Vector3.ZERO
	for entry: Dictionary in zones.values():
		var zone: MiningZone = entry.zone
		for coord in entry.staged.keys():
			if not terrain.snapshot_current(entry.staged[coord].snapshot):
				free_representation(entry.staged[coord].prepared)
				entry.staged.erase(coord)
		for chunk: MiningChunk in zone._chunks.values():
			if not chunk.active or (not chunk.mesh_dirty() and entry.meshes.has(chunk.coordinate)) or entry.staged.has(chunk.coordinate):
				continue
			var busy := false
			for job: Dictionary in jobs + pending:
				if job.kind == "chunk" and job.zone_id == zone.id and job.serial == entry.serial and job.snapshot.coordinate == chunk.coordinate:
					busy = true
					break
			if busy:
				continue
			var point := zone.local_to_direction((Vector2(chunk.coordinate) + Vector2(0.5, 0.5)) * 256) * zone.radius_m
			var distance := eye.distance_to(point)
			var visible_near := camera != null and distance < 2500 and not camera.is_position_behind(to_global(point))
			queue.append({"kind": "chunk", "zone_id": zone.id, "serial": entry.serial,
				"coordinate": chunk.coordinate, "tier": 0 if visible_near else (1 if chunk.mesh_revision >= 0 else 2),
				"distance": distance, "revision": chunk.revision})
	queue.sort_custom(priority_before)
	while jobs.size() < maxi(1, max_workers) and pending.size() < maxi(1, max_pending_results):
		if not queue.is_empty():
			var item: Dictionary = queue.pop_front()
			item.snapshot = terrain.snapshot_chunk_async(item.zone_id, item.coordinate)
			if item.snapshot.is_empty():
				continue
			item.builder = MiningBuildJob.new(item.snapshot, terrain.shape, terrain.climate, terrain.biomes)
			item.task = WorkerThreadPool.add_task(item.builder.build, false, "Mining " + item.zone_id)
			jobs.append(item)
			continue
		var launched := false
		for entry: Dictionary in zones.values():
			if entry.transition_started:
				continue
			if entry.capture_sources.is_empty():
				if Time.get_ticks_msec() < entry.capture_after_ms:
					continue
				entry.capture_after_ms = Time.get_ticks_msec() + 120
				entry.capture_sources = global_terrain.capture_mining_patches(entry.zone)
				if entry.capture_sources.is_empty():
					continue
			# Metadata only: GPU readback can stall even for a single small patch.
			var source: Dictionary = entry.capture_sources[entry.capture_arrays.size()]
			entry.originals[source.key] = source.mesh
			entry.capture_arrays.append({"key": source.key, "face": source.face, "depth": source.depth,
				"cell": source.cell, "resolution": source.resolution, "surface_indices": source.surface_indices})
			if entry.capture_arrays.size() < entry.capture_sources.size():
				break
			var builder := MiningTransitionJob.new(entry.zone, entry.capture_arrays, terrain.shape, terrain.climate, terrain.biomes)
			entry.capture_sources = []
			entry.capture_arrays = []
			jobs.append({"kind": "transition", "zone_id": entry.zone.id, "serial": entry.serial,
				"builder": builder, "task": WorkerThreadPool.add_task(builder.build, false, "Mining transition")})
			entry.transition_started = true
			launched = true
			break
		if not launched:
			break

static func priority_before(a: Dictionary, b: Dictionary) -> bool:
	if a.tier != b.tier:
		return a.tier < b.tier
	if a.tier == 1 and a.revision != b.revision:
		return a.revision > b.revision
	return a.distance < b.distance

func chunk_status(zone_id: String, coordinate: Vector2i) -> String:
	if not zones.has(zone_id):
		return "inativo"
	var entry: Dictionary = zones[zone_id]
	if entry.staged.has(coordinate):
		return "pronto / aguardando vizinhos"
	for item: Dictionary in pending:
		if item.kind == "chunk" and item.zone_id == zone_id and item.snapshot.coordinate == coordinate:
			return "upload"
	for job: Dictionary in jobs:
		if job.kind == "chunk" and job.zone_id == zone_id and job.snapshot.coordinate == coordinate:
			return "worker"
	var chunk: MiningChunk = entry.zone.chunk_at(coordinate)
	return "fila / dirty" if chunk.mesh_dirty() else "carregado"

func _exit_tree() -> void:
	for key in zones.keys():
		deactivate(key)
	for job: Dictionary in jobs:
		WorkerThreadPool.wait_for_task_completion(job.task)
	jobs.clear()
	pending.clear()
