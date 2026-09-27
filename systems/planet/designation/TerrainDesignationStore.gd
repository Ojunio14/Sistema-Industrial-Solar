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
	return {"plan": plan.duplicate_plan(), "clock": zone._clock if zone else -1, "store_revision": revision,
		"cursor": 0, "cell_cursor": 0, "nodes": {}, "cells": [], "cut_m3": 0.0,
		"fill_m3": 0.0, "complete": 0, "in_progress": 0, "done": false, "safe": safe, "error": validate(plan), "max_step_ms": 0.0}

func advance_evaluation(job: Dictionary, max_items := 256, budget_ms := 1.5) -> bool:
	var started := Time.get_ticks_usec()
	var plan: TerrainDesignation = job.plan
	var zone := terrain.zone_by_id(plan.zone_id)
	if zone == null or zone._clock != job.clock:
		job.error = "Terreno mudou durante a avaliação; atualize o preview"
		job.safe = false
	if not job.safe:
		job.done = true
		return true
	var size := plan.rect.size + Vector2i.ONE
	var count := size.x * size.y
	var processed := 0
	while processed < max_items and not job.done:
		if job.cursor < count:
			var node := plan.rect.position + Vector2i(job.cursor % size.x, job.cursor / size.x)
			var natural := terrain.sample_natural_height(zone.local_to_direction(Vector2(node) * 2))
			var target := plan.target_height(Vector2(node), datum)
			job.nodes[node] = {"natural": natural, "current": natural + zone.read_node(node), "target": target}
			job.cursor += 1
		elif job.cell_cursor < plan.rect.get_area():
			var cell := plan.rect.position + Vector2i(job.cell_cursor % plan.rect.size.x, job.cell_cursor / plan.rect.size.x)
			var status := cell_status(plan, cell, job.nodes)
			job.cells.append(status)
			job.cut_m3 += status.cut_m3
			job.fill_m3 += status.fill_m3
			job.complete += int(status.work_state == TerrainDesignation.WorkState.COMPLETE)
			job.in_progress += int(status.work_state == TerrainDesignation.WorkState.IN_PROGRESS)
			job.cell_cursor += 1
		else:
			job.done = true
		processed += 1
		if (Time.get_ticks_usec() - started) / 1000.0 >= budget_ms:
			break
	job.max_step_ms = maxf(job.max_step_ms, (Time.get_ticks_usec() - started) / 1000.0)
	return job.done

func cell_status(plan: TerrainDesignation, cell: Vector2i, nodes: Dictionary) -> Dictionary:
	var points := [cell, cell + Vector2i.RIGHT, cell + Vector2i.DOWN, cell + Vector2i.ONE]
	var current := 0.0
	var cut := 0.0
	var fill := 0.0
	var maximum_error := 0.0
	for i in range(4):
		var data: Dictionary = nodes[points[i]]
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
	var area := terrain.zone_by_id(plan.zone_id).cell_area_m2(cell)
	return {"cell": cell, "planned_level": plan.planned_level(cell), "target_height": target,
		"current_final_height": current, "height_difference": difference, "height_state": state,
		"work_state": work, "operation": plan.operation, "max_error_m": maximum_error,
		"mixed_cut_fill": cut > tolerance_m and fill > tolerance_m, "cut_m3": cut * area, "fill_m3": fill * area}

func apply_evaluations(evaluations: Array, max_change_m := INF) -> Dictionary:
	# DEV only: validate the complete transaction before the first write. Future
	# machines can call with a finite step; targets remain fixed as work advances.
	if is_nan(max_change_m) or max_change_m <= 0:
		return {"ok": false, "error": "Passo inválido"}
	var writes := {}
	for job: Dictionary in evaluations:
		var plan: TerrainDesignation = job.plan
		var zone := terrain.zone_by_id(plan.zone_id)
		if zone == null or not zone.active or not job.done or not job.error.is_empty() or zone._clock != job.clock or job.store_revision != revision or not validate(plan).is_empty():
			return {"ok": false, "error": "Preview inválido, obsoleto ou zona inativa"}
		if plan.id == 0:
			return {"ok": false, "error": "Confirme a designação antes de DEV APPLY"}
		for node: Vector2i in job.nodes:
			var data: Dictionary = job.nodes[node]
			var desired: float = data.target
			if plan.operation == TerrainDesignation.Operation.CUT_ONLY:
				desired = minf(desired, data.current)
			elif plan.operation == TerrainDesignation.Operation.FILL_ONLY:
				desired = maxf(desired, data.current)
			desired = move_toward(data.current, desired, max_change_m)
			var delta: float = desired - data.natural
			if not zone.editable_node(node) or not terrain._valid_delta(delta):
				return {"ok": false, "error": "Target excede o envelope de deltas; nenhuma alteração aplicada"}
			var key := Vector3i(node.x, node.y, zone.epoch)
			if writes.has(key) and absf(writes[key].delta - delta) > 0.00001:
				return {"ok": false, "error": "Operações conflitantes no vértice compartilhado"}
			writes[key] = {"zone": zone, "node": node, "delta": delta}
	for data: Dictionary in writes.values():
		# Same validated authority/envelope as set_node_delta, avoiding a second
		# expensive natural sample. No yields inside the atomic DEV transaction.
		data.zone._write_node(data.node, data.delta)
	for job: Dictionary in evaluations:
		for plan in plans:
			if plan.id == job.plan.id:
				plan.started = true
	revision += 1
	return {"ok": true, "nodes": writes.size(), "error": ""}
