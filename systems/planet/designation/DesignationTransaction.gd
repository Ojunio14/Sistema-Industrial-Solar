class_name DesignationTransaction
extends RefCounted
## Detached chunk-aware preparation. No Node, PhysicsServer, GPU or live edits.
var evaluations: Array
var source_buffers: Dictionary
var bounds: Rect2i
var max_cut: float
var max_fill: float
var max_change := INF
var result: Dictionary = {}

func build() -> void:
	var start := Time.get_ticks_usec()
	var writes := {}
	for job: Dictionary in evaluations:
		var plan: TerrainDesignation = job.plan
		for node: Vector2i in job.nodes:
			var data: Dictionary = job.nodes[node]
			var current: float = data.get("live_current", data.current)
			var desired: float = data.target
			if plan.operation == TerrainDesignation.Operation.CUT_ONLY:
				desired = minf(desired, current)
			elif plan.operation == TerrainDesignation.Operation.FILL_ONLY:
				desired = maxf(desired, current)
			desired = move_toward(current, desired, max_change)
			var delta := PackedFloat32Array([desired - data.natural])[0]
			if not is_finite(delta) or delta < -max_cut or delta > max_fill:
				result = {"ok": false, "error": "Target excede o envelope de deltas; nenhuma alteração aplicada"}
				return
			if writes.has(node) and absf(writes[node] - delta) > 0.00001:
				result = {"ok": false, "error": "Operações conflitantes no vértice compartilhado"}
				return
			writes[node] = delta
	var calculated := Time.get_ticks_usec()
	var groups := {}
	var dirty := {}
	var changed_nodes: Array[Vector2i] = []
	for node: Vector2i in writes:
		var owner := MiningZone.owner_of(node)
		if not groups.has(owner):
			var source: Dictionary = source_buffers.get(owner, {"values": PackedFloat32Array(), "nonzero": 0})
			var copy: PackedFloat32Array = source.values.duplicate()
			if copy.is_empty():
				copy.resize(128 * 128)
			groups[owner] = {"values": copy, "nonzero": source.nonzero, "changed": false}
		var local := MiningZone.local_index(node)
		var i := local.y * 128 + local.x
		var group: Dictionary = groups[owner]
		var previous: float = group.values[i]
		var value: float = writes[node]
		if previous == value:
			continue
		group.nonzero += int(value != 0.0) - int(previous != 0.0)
		group.values[i] = value
		group.changed = true
		changed_nodes.append(node)
	var buffers_end := Time.get_ticks_usec()
	for node: Vector2i in changed_nodes:
		var first := MiningZone.owner_of(node - Vector2i(2, 2))
		var last := MiningZone.owner_of(node + Vector2i.ONE)
		for y in range(first.y, last.y + 1):
			for x in range(first.x, last.x + 1):
				if bounds.has_point(Vector2i(x, y)):
					dirty[Vector2i(x, y)] = true
	var prepared := Time.get_ticks_usec()
	for coord in groups.keys():
		if not groups[coord].changed:
			groups.erase(coord)
		elif groups[coord].nonzero == 0:
			groups[coord].values = PackedFloat32Array()
	result = {"ok": true, "error": "", "buffers": groups, "dirty": dirty, "nodes": writes.size(),
		"calculate_deltas_ms": (calculated - start) / 1000.0,
		"buffer_prepare_ms": (buffers_end - calculated) / 1000.0,
		"dirty_mark_ms": (prepared - buffers_end) / 1000.0,
		"prepare_arrays_and_dirty_ms": (prepared - calculated) / 1000.0,
		"worker_total_ms": (Time.get_ticks_usec() - start) / 1000.0}
