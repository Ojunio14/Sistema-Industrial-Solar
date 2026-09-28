class_name TerrainDesignationStore
extends RefCounted
## Orders are separate from terrain edits. All plans share one planetary datum.
## Evaluation/DEV preparation is incremental. Only a validated apply writes deltas.
var terrain: PlanetEditableTerrain
var datum: TerrainLevelDatum
var tolerance_m := 0.05
var max_grade_percent := 30.0
var max_cells_per_plan := 4096
var max_total_cells := 8192
var plans: Array[TerrainDesignation] = []
var revision := 0
var _next_id := 1
var evaluation_cache: Dictionary = {}
var evaluated_nodes := 0
var evaluated_cells := 0
var node_cache: Dictionary = {}
var natural_queries := 0
var published_reads := 0
var cache_hits := 0
var queued: Dictionary = {}
var running: Dictionary = {}
var transaction_sequence := 0
var transaction_status := ""
var transaction_metrics: Dictionary = {}
var rejected_transactions := 0
var allow_worker_evaluation := true
var evaluation_running: Dictionary = {}

func _start_evaluation_worker(job: Dictionary) -> void:
	var source := terrain.zone_by_id(job.plan.zone_id)
	# Detached metadata and copy-on-write buffers; worker never reads live nodes.
	var snapshot := PlanetEditableTerrain.new(terrain.shape)
	var copy := MiningZone.new(source.id, source.up, source.radius_m, source.chunk_bounds, source.epoch)
	copy.up = source.up
	copy.tangent_x = source.tangent_x
	copy.tangent_y = source.tangent_y
	copy.active = source.active
	copy._clock = source._clock
	copy.visual_guard_cells = source.visual_guard_cells
	for coord in source._chunks:
		var original: MiningChunk = source._chunks[coord]
		var chunk := MiningChunk.new(coord)
		chunk.active = original.active
		chunk.revision = original.revision
		chunk.mesh_revision = original.mesh_revision
		chunk.collision_revision = original.collision_revision
		chunk._deltas = original._deltas
		chunk._nonzero = original._nonzero
		copy._chunks[coord] = chunk
	snapshot._zones[source.id] = copy
	snapshot.published_chunks[source.id] = terrain.published_chunks[source.id].duplicate()
	var worker := TerrainDesignationStore.new(snapshot, datum)
	worker.allow_worker_evaluation = false
	worker.tolerance_m = tolerance_m
	for key in node_cache:
		if not String(key).begins_with(source.id + "/"):
			continue
		var cache: Dictionary = node_cache[key].duplicate()
		cache.nodes = cache.nodes.duplicate() # Samples are immutable records.
		worker.node_cache[key] = cache
	var detached := job.duplicate()
	detached.nodes = job.nodes.duplicate()
	detached.cell_map = job.cell_map.duplicate()
	job.evaluating = true
	evaluation_running = {"job": job, "detached": detached, "worker": worker}
	evaluation_running.task = WorkerThreadPool.add_task(func(): worker.advance_evaluation(detached, 100000, INF), false, "Designation evaluation")

func _poll_evaluation() -> void:
	if evaluation_running.is_empty() or not WorkerThreadPool.is_task_completed(evaluation_running.task):
		return
	var poll_start := Time.get_ticks_usec()
	WorkerThreadPool.wait_for_task_completion(evaluation_running.task)
	var worker: TerrainDesignationStore = evaluation_running.worker
	var job: Dictionary = evaluation_running.job
	var zone := terrain.zone_by_id(job.plan.zone_id)
	var publication_matches := true
	for coord in worker.terrain.published_chunks[job.plan.zone_id]:
		if terrain.published_chunks.get(job.plan.zone_id, {}).get(coord, {}).get("revision", -1) != worker.terrain.published_chunks[job.plan.zone_id][coord].revision:
			publication_matches = false
	if zone and zone.epoch == worker.terrain.zone_by_id(zone.id).epoch and zone._clock == job.clock and publication_matches:
		var main_step: float = job.max_step_ms
		job.merge(evaluation_running.detached, true)
		job.worker_ms = job.max_step_ms
		job.max_step_ms = main_step
		evaluated_nodes += worker.evaluated_nodes
		evaluated_cells += worker.evaluated_cells
		natural_queries += worker.natural_queries
		published_reads += worker.published_reads
		cache_hits += worker.cache_hits
		node_cache.merge(worker.node_cache, true)
		evaluation_cache[job.key] = job
	else:
		job.error = "Superfície mudou; atualize o preview"
		job.safe = false
		job.done = true
	job.evaluating = false
	job.max_step_ms = maxf(job.max_step_ms, (Time.get_ticks_usec() - poll_start) / 1000.0)
	evaluation_running = {}

func current_node(zone: MiningZone, node: Vector2i) -> Dictionary:
	var owner := MiningZone.owner_of(node).clamp(zone.chunk_bounds.position, zone.chunk_bounds.end - Vector2i.ONE)
	var chunk := zone.chunk_at(owner)
	var data_revision := chunk.revision if chunk else 0
	var published: Dictionary = terrain.published_chunks.get(zone.id, {}).get(owner, {})
	var pub_revision: int = published.get("revision", -1)
	var key := "%s/%s" % [zone.id, owner]
	var cache: Dictionary = node_cache.get(key, {})
	if cache.get("data_revision", -2) != data_revision or cache.get("published_revision", -2) != pub_revision:
		cache = {"data_revision": data_revision, "published_revision": pub_revision, "nodes": {}}
		node_cache[key] = cache
	if cache.nodes.has(node):
		cache_hits += 1
		return cache.nodes[node]
	var sample := terrain.published_node(zone.id, node)
	if sample.is_empty():
		natural_queries += 1
		var natural := terrain.sample_natural_height(zone.local_to_direction(Vector2(node) * 2))
		sample = {"natural": natural, "current": natural + zone.read_node(node)}
	else:
		published_reads += 1
	sample.live_current = sample.natural + zone.read_node(node)
	sample.pending = pub_revision >= 0 and pub_revision != data_revision
	cache.nodes[node] = sample
	return sample

func _init(source: PlanetEditableTerrain, reference: TerrainLevelDatum = null) -> void:
	terrain = source
	datum = reference if reference else TerrainLevelDatum.new()

func plan_at(zone_id: String, cell: Vector2i) -> TerrainDesignation:
	for plan in plans:
		if plan.zone_id == zone_id and plan.rect.has_point(cell):
			return plan
	return null

func validate(plan: TerrainDesignation) -> String:
	var zone := terrain.zone_by_id(plan.zone_id)
	if zone == null or plan.rect.size.x < 1 or plan.rect.size.y < 1:
		return "Área inválida"
	if plan.axis not in [0, 1] or plan.kind not in [0, 1] or plan.operation not in [0, 1, 2]:
		return "Tipo de plano inválido"
	if absi(plan.start_level) > 1000000 or absi(plan.end_level) > 1000000:
		return "Nível fora do envelope técnico"
	if plan.rect.get_area() > max_cells_per_plan:
		return "Máximo técnico: %d células por seleção" % max_cells_per_plan
	if not zone.editable_node(plan.rect.position) or not zone.editable_node(plan.rect.end):
		return "Seleção fora da zona ou na faixa protegida"
	if plan.grade_percent(datum) > max_grade_percent:
		return "Rampa inválida: %.1f%% > limite técnico %.1f%%" % [plan.grade_percent(datum), max_grade_percent]
	var total := plan.rect.get_area()
	for other in plans:
		if other.id == plan.id:
			continue
		total += other.rect.get_area()
		if other.zone_id != plan.zone_id:
			continue
		if other.rect.intersects(plan.rect):
			return "Área já designada; clique sem arrastar para editar"
		# Adjacent plans must prescribe the same shared vertices. No cracks or
		# hidden last-writer-wins at a platform/ramp connection.
		var lo := plan.rect.position.max(other.rect.position)
		var hi := plan.rect.end.min(other.rect.end)
		if lo.x <= hi.x and lo.y <= hi.y:
			for point in [lo, hi]:
				if absf(plan.target_height(Vector2(point), datum) - other.target_height(Vector2(point), datum)) > 0.000001:
					return "Níveis incompatíveis na borda compartilhada"
	return "Limite total de células atingido" if total > max_total_cells else ""

func confirm(plan: TerrainDesignation) -> bool:
	if not validate(plan).is_empty():
		return false
	if plan.id == 0:
		plan.id = _next_id
		_next_id += 1
	else:
		for i in range(plans.size()):
			if plans[i].id == plan.id:
				plans.remove_at(i)
				break
	plans.append(plan.duplicate_plan())
	revision += 1
	return true

func remove(id: int) -> void:
	for i in range(plans.size()):
		if plans[i].id == id:
			evaluation_cache.erase("%s/%d" % [plans[i].zone_id, id])
			plans.remove_at(i)
			revision += 1
			return

func detect_ramp_anchors(plan: TerrainDesignation) -> Array:
	var anchors: Array = []
	for side in range(2):
		var found: Variant = null
		var valid := true
		for transverse in range(plan.rect.position[1 - plan.axis], plan.rect.end[1 - plan.axis]):
			var cell := plan.rect.position
			cell[1 - plan.axis] = transverse
			cell[plan.axis] = plan.rect.position[plan.axis] - 1 if side == 0 else plan.rect.end[plan.axis]
			var neighbor := plan_at(plan.zone_id, cell)
			if neighbor == null:
				valid = false
				break
			var edge := Vector2(cell) + Vector2(0.5, 0.5)
			edge[plan.axis] = plan.rect.position[plan.axis] if side == 0 else plan.rect.end[plan.axis]
			var level := neighbor.level_at(edge)
			if not is_equal_approx(level, roundf(level)) or (found != null and not is_equal_approx(found, level)):
				valid = false
				break
			found = level
		anchors.append(roundi(found) if valid and found != null else null)
	if plan.reverse:
		anchors.reverse()
	return anchors

func begin_evaluation(plan: TerrainDesignation) -> Dictionary:
	var zone := terrain.zone_by_id(plan.zone_id)
	var safe := zone != null and plan.axis in [0, 1] and plan.rect.size.x > 0 and plan.rect.size.y > 0 and plan.rect.get_area() <= max_cells_per_plan
	if safe:
		safe = zone.editable_node(plan.rect.position) and zone.editable_node(plan.rect.end) and absi(plan.start_level) <= 1000000 and absi(plan.end_level) <= 1000000
	var key := "%s/%d" % [plan.zone_id, plan.id]
	var signature := [plan.kind, plan.operation, plan.start_level, plan.end_level, plan.axis, plan.reverse, plan.started]
	if plan.kind == TerrainDesignation.Kind.RAMP:
		signature.append(plan.rect)
	var old: Dictionary = evaluation_cache.get(key, {})
	var nodes: Dictionary = old.get("nodes", {}).duplicate()
	var cells: Dictionary = old.get("cell_map", {}).duplicate()
	var node_work: Array[Vector2i] = []
	var cell_work: Array[Vector2i] = []
	var chunk_stamps := {}
	var same_target: bool = old.get("signature", []) == signature
	if safe:
		var node_rect := Rect2i(plan.rect.position, plan.rect.size + Vector2i.ONE)
		var old_rect: Rect2i = old.plan.rect if not old.is_empty() else Rect2i()
		var old_nodes := Rect2i(old_rect.position, old_rect.size + Vector2i.ONE) if not old.is_empty() else Rect2i()
		for band: Rect2i in rectangle_difference(old_nodes, node_rect):
			for y in range(band.position.y, band.end.y):
				for x in range(band.position.x, band.end.x):
					nodes.erase(Vector2i(x, y))
		for band: Rect2i in rectangle_difference(old_rect, plan.rect):
			for y in range(band.position.y, band.end.y):
				for x in range(band.position.x, band.end.x):
					cells.erase(Vector2i(x, y))
		var bands: Array = rectangle_difference(node_rect, old_nodes) if same_target else [node_rect]
		var first := MiningZone.owner_of(node_rect.position)
		var last := MiningZone.owner_of(node_rect.end - Vector2i.ONE)
		for y in range(first.y, last.y + 1):
			for x in range(first.x, last.x + 1):
				var owner := Vector2i(x, y)
				var chunk := zone.chunk_at(owner)
				var stamp := [chunk.revision if chunk else 0, terrain.published_chunks.get(zone.id, {}).get(owner, {}).get("revision", -1)]
				chunk_stamps[owner] = stamp
				if same_target and old.get("chunk_stamps", {}).get(owner, []) != stamp:
					bands.append(Rect2i(owner * 128, Vector2i(128, 128)).intersection(node_rect))
		var pending_nodes := {}
		var pending_cells := {}
		for band: Rect2i in bands:
			for y in range(band.position.y, band.end.y):
				for x in range(band.position.x, band.end.x):
					var node := Vector2i(x, y)
					pending_nodes[node] = true
					for offset in [Vector2i.ZERO, Vector2i.LEFT, Vector2i.UP, -Vector2i.ONE]:
						if plan.rect.has_point(node + offset):
							pending_cells[node + offset] = true
		# A coalesced drag can interrupt evaluation. Carry unfinished strips forward.
		if same_target and not old.get("done", true):
			for i in range(old.cursor, old.node_work.size()):
				if node_rect.has_point(old.node_work[i]):
					pending_nodes[old.node_work[i]] = true
			for i in range(old.cell_cursor, old.cell_work.size()):
				if plan.rect.has_point(old.cell_work[i]):
					pending_cells[old.cell_work[i]] = true
		for node: Vector2i in pending_nodes:
			nodes.erase(node)
			node_work.append(node)
		for cell: Vector2i in pending_cells:
			cells.erase(cell)
			cell_work.append(cell)
	return {"plan": plan.duplicate_plan(), "clock": zone._clock if zone else -1, "store_revision": revision,
		"key": key, "signature": signature, "chunk_stamps": chunk_stamps, "node_work": node_work, "cell_work": cell_work, "cell_map": cells,
		"cursor": 0, "cell_cursor": 0, "nodes": nodes, "cells": [], "cut_m3": 0.0,
		"fill_m3": 0.0, "current_min": INF, "current_max": -INF, "complete": 0, "in_progress": 0, "done": false, "safe": safe, "error": validate(plan), "max_step_ms": 0.0}

static func rectangle_difference(area: Rect2i, retained: Rect2i) -> Array:
	if area.get_area() <= 0:
		return []
	var middle := area.intersection(retained)
	if middle.get_area() <= 0:
		return [area]
	var result: Array = []
	for band in [Rect2i(area.position, Vector2i(area.size.x, middle.position.y - area.position.y)),
		Rect2i(Vector2i(area.position.x, middle.end.y), Vector2i(area.size.x, area.end.y - middle.end.y)),
		Rect2i(Vector2i(area.position.x, middle.position.y), Vector2i(middle.position.x - area.position.x, middle.size.y)),
		Rect2i(Vector2i(middle.end.x, middle.position.y), Vector2i(area.end.x - middle.end.x, middle.size.y))]:
		if band.get_area() > 0:
			result.append(band)
	return result

func advance_evaluation(job: Dictionary, max_items := 4096, budget_ms := 6.0) -> bool:
	_poll_evaluation()
	if job.done:
		return true
	if allow_worker_evaluation and job.safe and terrain.published_chunks.has(job.plan.zone_id) and job.node_work.size() + job.cell_work.size() > 128:
		if not job.get("evaluating", false) and evaluation_running.is_empty():
			var snapshot_start := Time.get_ticks_usec()
			_start_evaluation_worker(job)
			job.max_step_ms = maxf(job.max_step_ms, (Time.get_ticks_usec() - snapshot_start) / 1000.0)
		return false
	var started := Time.get_ticks_usec()
	var plan: TerrainDesignation = job.plan
	var zone := terrain.zone_by_id(plan.zone_id)
	if zone == null or zone._clock != job.clock:
		job.error = "Terreno mudou durante a avaliação; atualize o preview"
		job.safe = false
	if not job.safe:
		job.done = true
		return true
	var processed := 0
	while processed < max_items and not job.done:
		if job.cursor < job.node_work.size():
			var node: Vector2i = job.node_work[job.cursor]
			var sample := current_node(zone, node)
			var owner := MiningZone.owner_of(node).clamp(zone.chunk_bounds.position, zone.chunk_bounds.end - Vector2i.ONE)
			var chunk := zone.chunk_at(owner)
			job.nodes[node] = {"natural": sample.natural, "current": sample.current, "live_current": sample.live_current,
				"pending": sample.pending, "target": plan.target_height(Vector2(node), datum),
				"stamp": [chunk.revision if chunk else 0, terrain.published_chunks.get(zone.id, {}).get(owner, {}).get("revision", -1)]}
			job.cursor += 1
			evaluated_nodes += 1
		elif job.cell_cursor < job.cell_work.size():
			var cell: Vector2i = job.cell_work[job.cell_cursor]
			job.cell_map[cell] = cell_status(plan, cell, job.nodes)
			job.cell_cursor += 1
			evaluated_cells += 1
		else:
			job.cells = job.cell_map.values()
			for status: Dictionary in job.cells:
				job.current_min = minf(job.current_min, status.current_level)
				job.current_max = maxf(job.current_max, status.current_level)
				job.cut_m3 += status.cut_m3
				job.fill_m3 += status.fill_m3
				job.complete += int(status.work_state == TerrainDesignation.WorkState.COMPLETE)
				job.in_progress += int(status.work_state == TerrainDesignation.WorkState.IN_PROGRESS)
			job.done = true
			evaluation_cache[job.key] = job
		processed += 1
		if (Time.get_ticks_usec() - started) / 1000.0 >= budget_ms:
			break
	evaluation_cache[job.key] = job
	job.max_step_ms = maxf(job.max_step_ms, (Time.get_ticks_usec() - started) / 1000.0)
	return job.done

func cell_status(plan: TerrainDesignation, cell: Vector2i, nodes: Dictionary) -> Dictionary:
	var points := [cell, cell + Vector2i.RIGHT, cell + Vector2i.DOWN, cell + Vector2i.ONE]
	var current := 0.0
	var cut := 0.0
	var fill := 0.0
	var maximum_error := 0.0
	var pending_surface := false
	for i in range(4):
		var data: Dictionary = nodes[points[i]]
		pending_surface = pending_surface or data.get("pending", false)
		var diff: float = data.current - data.target
		maximum_error = maxf(maximum_error, absf(diff))
		var weight := 1.0 / 6.0 if i == 0 or i == 3 else 2.0 / 6.0
		cut += maxf(diff, 0) * weight
		fill += maxf(-diff, 0) * weight
		if i == 1 or i == 2:
			current += data.current * 0.5
	var target := datum.height(plan.planned_level(cell))
	var difference := current - target
	var state := TerrainDesignation.HeightState.AT_TARGET
	if difference > tolerance_m:
		state = TerrainDesignation.HeightState.CUT_REQUIRED
	elif difference < -tolerance_m:
		state = TerrainDesignation.HeightState.FILL_REQUIRED
	var work := TerrainDesignation.WorkState.COMPLETE if maximum_error <= tolerance_m else (TerrainDesignation.WorkState.IN_PROGRESS if plan.started else TerrainDesignation.WorkState.PLANNED)
	if pending_surface:
		work = TerrainDesignation.WorkState.IN_PROGRESS
	var area := terrain.zone_by_id(plan.zone_id).cell_area_m2(cell)
	return {"cell": cell, "planned_level": plan.planned_level(cell), "target_height": target,
		"current_level": datum.height_to_level(current), "rebuild_pending": pending_surface,
		"current_final_height": current, "height_difference": difference, "height_state": state,
		"work_state": work, "operation": plan.operation, "max_error_m": maximum_error,
		"mixed_cut_fill": cut > tolerance_m and fill > tolerance_m, "cut_m3": cut * area, "fill_m3": fill * area}

func _prepare_transaction(evaluations: Array, max_change_m: float) -> Dictionary:
	if evaluations.is_empty() or is_nan(max_change_m) or max_change_m <= 0:
		return {"ok": false, "error": "Passo ou seleção inválida"}
	var zone := terrain.zone_by_id(evaluations[0].plan.zone_id)
	for job: Dictionary in evaluations:
		var plan: TerrainDesignation = job.plan
		if zone == null or plan.zone_id != zone.id or not zone.active or not job.done or not job.error.is_empty() or zone._clock != job.clock or job.store_revision != revision or not validate(plan).is_empty() or plan.id == 0:
			return {"ok": false, "error": "Preview inválido, obsoleto, não confirmado ou zona inativa"}
	var worker := DesignationTransaction.new()
	worker.evaluations = evaluations.duplicate() # Finished jobs are immutable snapshots.
	worker.bounds = zone.chunk_bounds
	worker.max_cut = minf(maxf(terrain.max_cut_m, 0), minf(1000, zone.radius_m * 0.1))
	worker.max_fill = minf(maxf(terrain.max_fill_m, 0), minf(1000, zone.radius_m * 0.1))
	worker.max_change = max_change_m
	for coord in zone._chunks:
		var chunk: MiningChunk = zone._chunks[coord]
		worker.source_buffers[coord] = {"values": chunk._deltas, "nonzero": chunk._nonzero}
	return {"ok": true, "worker": worker, "zone_id": zone.id, "clock": zone._clock, "epoch": zone.epoch, "revision": revision}

func queue_apply(evaluations: Array, max_change_m := INF) -> Dictionary:
	var request := _prepare_transaction(evaluations, max_change_m)
	if not request.ok:
		return request
	transaction_sequence += 1
	request.sequence = transaction_sequence
	request.queued_usec = Time.get_ticks_usec()
	queued = request
	transaction_status = "Dados pendentes · preparando deltas em worker"
	return {"ok": true, "error": "", "sequence": transaction_sequence}

func advance_transactions() -> void:
	_poll_evaluation()
	if not running.is_empty() and WorkerThreadPool.is_task_completed(running.task):
		WorkerThreadPool.wait_for_task_completion(running.task)
		if running.sequence != transaction_sequence:
			rejected_transactions += 1
		else:
			_finish_transaction(running)
		running = {}
	if running.is_empty() and not queued.is_empty():
		running = queued
		queued = {}
		running.task = WorkerThreadPool.add_task(running.worker.build, false, "Designation delta transaction")

func finish_workers() -> void:
	if not evaluation_running.is_empty():
		WorkerThreadPool.wait_for_task_completion(evaluation_running.task)
		evaluation_running = {}
	if not running.is_empty():
		WorkerThreadPool.wait_for_task_completion(running.task)
		running = {}
	queued = {}

func _finish_transaction(request: Dictionary) -> Dictionary:
	var zone := terrain.zone_by_id(request.zone_id)
	if zone == null or zone.epoch != request.epoch or zone._clock != request.clock or revision != request.revision:
		rejected_transactions += 1
		transaction_status = "Transação obsoleta descartada; atualize e aplique novamente"
		return {"ok": false, "error": transaction_status}
	var result: Dictionary = request.worker.result
	if not result.ok:
		transaction_status = result.error
		return result
	var commit := terrain.commit_delta_buffers(zone.id, result.buffers, request.clock, result.dirty)
	if not commit.ok:
		return commit
	transaction_metrics = result.duplicate()
	transaction_metrics.erase("buffers")
	transaction_metrics.erase("dirty")
	transaction_metrics.merge(commit, true)
	transaction_metrics.data_ready_ms = (Time.get_ticks_usec() - request.get("queued_usec", Time.get_ticks_usec())) / 1000.0
	transaction_metrics.data_ready_usec = Time.get_ticks_usec()
	for job: Dictionary in request.worker.evaluations:
		for plan in plans:
			if plan.id == job.plan.id:
				plan.started = true
	revision += 1
	transaction_status = "Dados aplicados · aguardando mesh e colisão"
	return {"ok": true, "error": "", "nodes": result.nodes}

func apply_evaluations(evaluations: Array, max_change_m := INF) -> Dictionary:
	# Synchronous compatibility API for offline tests. The UI ONLY uses queue_apply.
	var request := _prepare_transaction(evaluations, max_change_m)
	if not request.ok:
		return request
	request.worker.build()
	return _finish_transaction(request)
