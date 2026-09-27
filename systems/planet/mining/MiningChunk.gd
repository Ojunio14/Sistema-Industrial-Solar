class_name MiningChunk
extends RefCounted
## Main-thread owned. No object per cell; an untouched chunk has no delta buffer.
const CELLS := 128
const CELL_M := 2.0
const SIZE_M := CELLS * CELL_M
var coordinate: Vector2i
var active := false
var revision := 0
var mesh_revision := -1
var collision_revision := -1
var _deltas := PackedFloat32Array()
var _nonzero := 0

func _init(coord: Vector2i) -> void:
	coordinate = coord

func read_node(local: Vector2i) -> float:
	return 0.0 if _deltas.is_empty() else _deltas[local.y * CELLS + local.x]

func write_node(local: Vector2i, value: float) -> bool:
	var previous := read_node(local)
	# Compare stored float32, so repeated writes are exactly idempotent.
	var stored := PackedFloat32Array([value])[0]
	if previous == stored:
		return false
	if _deltas.is_empty():
		_deltas.resize(CELLS * CELLS)
	if previous != 0.0:
		_nonzero -= 1
	if stored != 0.0:
		_nonzero += 1
	_deltas[local.y * CELLS + local.x] = stored
	if _nonzero == 0:
		_deltas = PackedFloat32Array()
	return true

func delta_bytes() -> int:
	return _deltas.size() * 4

func mesh_dirty() -> bool:
	return revision != mesh_revision

func stable_key(zone_id: String) -> String:
	return "%s/chunk/%d/%d" % [zone_id, coordinate.x, coordinate.y]
