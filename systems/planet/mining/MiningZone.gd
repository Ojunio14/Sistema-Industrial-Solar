class_name MiningZone
extends RefCounted
## A face-independent gnomonic chart. Configuration is immutable after creation.
## Mutation and reads of live chunks belong to the main thread only.
var id: String
var epoch: int
var radius_m: float
var up: Vector3
var tangent_x: Vector3
var tangent_y: Vector3
var chunk_bounds: Rect2i
var active := false
var _chunks: Dictionary = {}
var _clock := 0
var visual_guard_cells := 0

func _init(key: String, direction: Vector3, radius: float, bounds: Rect2i, generation: int) -> void:
	id = key
	epoch = generation
	radius_m = radius
	up = direction.normalized()
	var reference := Vector3.UP if absf(up.y) < 0.9 else Vector3.RIGHT
	tangent_x = reference.cross(up).normalized()
	tangent_y = up.cross(tangent_x).normalized()
	chunk_bounds = bounds

static func dot64(a: Vector3, b: Vector3) -> float:
	return float(a.x) * b.x + float(a.y) * b.y + float(a.z) * b.z

func local_to_direction(local_m: Vector2) -> Vector3:
	return (up + tangent_x * (local_m.x / radius_m) + tangent_y * (local_m.y / radius_m)).normalized()

func planet_to_local(position: Vector3) -> Vector2:
	var denominator := dot64(position, up)
	if denominator <= 0.0 or not position.is_finite():
		return Vector2(INF, INF)
	return Vector2(radius_m * dot64(position, tangent_x) / denominator,
		radius_m * dot64(position, tangent_y) / denominator)

func local_to_planet(local_m: Vector2, height_m: float) -> Vector3:
	return local_to_direction(local_m) * (radius_m + height_m)

func contains_local(local_m: Vector2) -> bool:
	return local_m.is_finite() and Rect2(Vector2(chunk_bounds.position) * MiningChunk.SIZE_M,
		Vector2(chunk_bounds.size) * MiningChunk.SIZE_M).has_point(local_m)

func cell_at(local_m: Vector2) -> Vector2i:
	return Vector2i(floori(local_m.x / MiningChunk.CELL_M), floori(local_m.y / MiningChunk.CELL_M))

static func owner_of(node: Vector2i) -> Vector2i:
	return Vector2i(floori(float(node.x) / MiningChunk.CELLS), floori(float(node.y) / MiningChunk.CELLS))

static func local_index(node: Vector2i) -> Vector2i:
	return node - owner_of(node) * MiningChunk.CELLS

func ensure_chunk(coord: Vector2i) -> MiningChunk:
	if not chunk_bounds.has_point(coord):
		return null
	if not _chunks.has(coord):
		var chunk := MiningChunk.new(coord)
		_clock += 1
		chunk.revision = _clock
		_chunks[coord] = chunk
	return _chunks[coord]

func chunk_at(coord: Vector2i) -> MiningChunk:
	return _chunks.get(coord)

func activate_chunk(coord: Vector2i) -> bool:
	var chunk := ensure_chunk(coord)
	if chunk == null:
		return false
	if not chunk.active:
		_clock += 1
		chunk.revision = _clock
	chunk.active = true
	active = true
	return true

func deactivate() -> void:
	active = false
	for coord in _chunks.keys():
		var chunk: MiningChunk = _chunks[coord]
		chunk.active = false
		_clock += 1
		chunk.revision = _clock
		# Modified data survives unloading. Clean derived records can be recreated.
		if chunk.delta_bytes() == 0:
			_chunks.erase(coord)

func deactivate_chunk(coord: Vector2i) -> void:
	var chunk := chunk_at(coord)
	if chunk == null:
		return
	_clock += 1
	chunk.revision = _clock
	chunk.active = false
	if chunk.delta_bytes() == 0:
		_chunks.erase(coord)
	active = false
	for remaining: MiningChunk in _chunks.values():
		active = active or remaining.active

func editable_node(node: Vector2i) -> bool:
	var first := chunk_bounds.position * MiningChunk.CELLS
	var last := chunk_bounds.end * MiningChunk.CELLS
	# Fixed zero perimeter joins the untouched natural surface continuously.
	return node.x > first.x + visual_guard_cells and node.y > first.y + visual_guard_cells and node.x < last.x - visual_guard_cells and node.y < last.y - visual_guard_cells

func read_node(node: Vector2i) -> float:
	if not editable_node(node):
		return 0.0
	var chunk := chunk_at(owner_of(node))
	return 0.0 if chunk == null else chunk.read_node(local_index(node))

func _write_node(node: Vector2i, delta: float) -> bool:
	if not editable_node(node):
		return false
	if read_node(node) == PackedFloat32Array([delta])[0]:
		return true
	var chunk := ensure_chunk(owner_of(node))
	chunk.write_node(local_index(node), delta)
	# Cell support plus the 2 m normal stencil: at most four chunks.
	var first := owner_of(node - Vector2i(2, 2))
	var last := owner_of(node + Vector2i.ONE)
	for y in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			var affected := ensure_chunk(Vector2i(x, y))
			if affected:
				_clock += 1
				affected.revision = _clock
	return true

func sample_delta(local_m: Vector2) -> float:
	if not contains_local(local_m):
		return 0.0
	var cell := cell_at(local_m)
	var fraction := local_m / MiningChunk.CELL_M - Vector2(cell)
	# Piecewise linear on the SAME fixed diagonal as MiningMeshBuilder. This
	# avoids a bilinear saddle having a different delta from the rendered mesh.
	var dx := read_node(cell + Vector2i.RIGHT)
	var dy := read_node(cell + Vector2i.DOWN)
	if fraction.x + fraction.y <= 1.0:
		return read_node(cell) * (1.0 - fraction.x - fraction.y) + dx * fraction.x + dy * fraction.y
	return read_node(cell + Vector2i.ONE) * (fraction.x + fraction.y - 1.0) + dx * (1.0 - fraction.y) + dy * (1.0 - fraction.x)

func delta_bytes() -> int:
	var total := 0
	for chunk: MiningChunk in _chunks.values():
		total += chunk.delta_bytes()
	return total

func cell_area_m2(cell: Vector2i) -> float:
	# Reference-sphere horizontal area: gnomonic Jacobian at the cell centre.
	var centre := (Vector2(cell) + Vector2(0.5, 0.5)) * MiningChunk.CELL_M
	return 4.0 / pow(1.0 + centre.length_squared() / (radius_m * radius_m), 1.5)

func approximate_cell_volume_m3(cell: Vector2i) -> float:
	return cell_area_m2(cell) * (read_node(cell) + 2.0 * read_node(cell + Vector2i.RIGHT)
		+ 2.0 * read_node(cell + Vector2i.DOWN) + read_node(cell + Vector2i.ONE)) / 6.0
