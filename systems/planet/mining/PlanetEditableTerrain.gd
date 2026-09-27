class_name PlanetEditableTerrain
extends RefCounted
## Sole final-height composition authority. Live data is main-thread owned.
## Activity controls derived representations, never the physical edit history.
var shape: PlanetShape
var climate: PlanetClimate
var biomes: PlanetBiomes
var max_cut_m := 100.0
var max_fill_m := 100.0
var _zones: Dictionary = {}
var _epoch := 0

func _init(natural: PlanetShape, weather: PlanetClimate = null, habitats: PlanetBiomes = null) -> void:
	shape = natural
	climate = weather
	biomes = habitats

func create_zone(key: String, anchor: Vector3, bounds := Rect2i(-1, -1, 2, 2)) -> MiningZone:
	if key.is_empty() or _zones.has(key) or not anchor.is_finite() or not is_finite(anchor.length_squared()) or anchor.length_squared() < 0.5:
		return null
	# At most 8x8 chunks; bounded gnomonic distortion (<0.51% over this domain).
	if bounds.size.x < 1 or bounds.size.y < 1 or bounds.size.x > 8 or bounds.size.y > 8:
		return null
	if bounds.position.x < -8 or bounds.position.y < -8 or bounds.end.x > 8 or bounds.end.y > 8:
		return null
	_epoch += 1
	var zone := MiningZone.new(key, anchor, shape.definition.radius_m, bounds, _epoch)
	# Conservative angular caps reject overlap, including inactive edited zones.
	# Independent charts cannot author competing heights at one position.
	for other: MiningZone in _zones.values():
		var separation := acos(clampf(MiningZone.dot64(zone.up, other.up), -1.0, 1.0))
		if separation <= _cap(zone) + _cap(other) + 0.000001:
			return null
	_zones[key] = zone
	return zone

func _cap(zone: MiningZone) -> float:
	var bounds := zone.chunk_bounds
	var farthest := Vector2(maxi(absi(bounds.position.x), absi(bounds.end.x)),
		maxi(absi(bounds.position.y), absi(bounds.end.y))) * MiningChunk.SIZE_M
	return atan(farthest.length() / zone.radius_m)

func zone_by_id(key: String) -> MiningZone:
	return _zones.get(key)

func remove_zone(key: String) -> bool:
	var zone := zone_by_id(key)
	# No implicit loss of unsaved edits; clear deltas explicitly first.
	if zone == null or zone.delta_bytes() != 0:
		return false
	zone.deactivate()
	return _zones.erase(key)

func sample_natural_height(direction: Vector3) -> float:
	return shape.sample_base_height(direction)

func sample_edit_delta(position: Vector3) -> float:
	for zone: MiningZone in _zones.values():
		var local := zone.planet_to_local(position)
		if zone.contains_local(local):
			return zone.sample_delta(local)
	return 0.0

static func compose_height(natural: float, delta: float) -> float:
	return natural if delta == 0.0 else natural + delta

func sample_final_height(direction: Vector3) -> float:
	return compose_height(sample_natural_height(direction), sample_edit_delta(direction))

func _valid_delta(value: float) -> bool:
	var radius := shape.definition.radius_m
	# Technical envelope remains safe even if callers raise gameplay limits.
	var hard_limit := minf(1000.0, radius * 0.1)
	return is_finite(value) and value >= -minf(maxf(max_cut_m, 0.0), hard_limit) and value <= minf(maxf(max_fill_m, 0.0), hard_limit)

func set_node_delta(key: String, node: Vector2i, value: float) -> bool:
	var zone := zone_by_id(key)
	if zone == null or not _valid_delta(value) or not zone.editable_node(node):
		return false
	var natural := sample_natural_height(zone.local_to_direction(Vector2(node) * MiningChunk.CELL_M))
	if shape.definition.radius_m + natural + value < shape.definition.radius_m * 0.5:
		return false
	return zone._write_node(node, value)

func set_cell_delta(key: String, cell: Vector2i, value: float) -> bool:
	var zone := zone_by_id(key)
	if zone == null or not _valid_delta(value):
		return false
	var nodes := [cell, cell + Vector2i.RIGHT, cell + Vector2i.DOWN, cell + Vector2i.ONE]
	for node: Vector2i in nodes:
		if not zone.editable_node(node):
			return false
		var h := sample_natural_height(zone.local_to_direction(Vector2(node) * MiningChunk.CELL_M))
		if zone.radius_m + h + value < zone.radius_m * 0.5:
			return false
	for node: Vector2i in nodes:
		zone._write_node(node, value)
	return true

func sample_context(position: Vector3, depth_m := 0.0) -> Dictionary:
	if not is_finite(depth_m) or depth_m < 0.0 or not position.is_finite() or position.is_zero_approx():
		return {}
	var direction := position.normalized()
	return {"geology": shape.geology.sample(direction), "depth_m": depth_m,
		"stratigraphy_available": false, "climate": climate.sample(direction) if climate else null,
		"biome": biomes.sample(direction) if biomes else null}

func snapshot_chunk(key: String, coord: Vector2i) -> Dictionary:
	var zone := zone_by_id(key)
	if zone == null:
		return {}
	var chunk := zone.chunk_at(coord)
	if chunk == null or not zone.active or not chunk.active:
		return {}
	# Copy a 129x129 vertex grid plus one-node halo on each side for normals.
	var deltas := PackedFloat32Array()
	deltas.resize(131 * 131)
	for y in range(131):
		for x in range(131):
			deltas[y * 131 + x] = zone.read_node(coord * 128 + Vector2i(x - 1, y - 1))
	return {"zone_id": key, "epoch": zone.epoch, "coordinate": coord,
		"revision": chunk.revision, "up": zone.up, "tangent_x": zone.tangent_x,
		"tangent_y": zone.tangent_y, "radius_m": zone.radius_m, "deltas": deltas}

func accept_mesh(snapshot: Dictionary) -> bool:
	if not snapshot_current(snapshot):
		return false
	var chunk := zone_by_id(snapshot.zone_id).chunk_at(snapshot.coordinate)
	chunk.mesh_revision = chunk.revision
	return true

func snapshot_current(snapshot: Dictionary) -> bool:
	var zone := zone_by_id(snapshot.zone_id)
	if zone == null or zone.epoch != snapshot.epoch or not zone.active:
		return false
	var chunk := zone.chunk_at(snapshot.coordinate)
	if chunk == null or not chunk.active or chunk.revision != snapshot.revision:
		return false
	return true

func snapshot_chunk_async(key: String, coord: Vector2i) -> Dictionary:
	var zone := zone_by_id(key)
	if zone == null or not zone.active:
		return {}
	var chunk := zone.chunk_at(coord)
	if chunk == null or not chunk.active:
		return {}
	# Copy at most nine small buffers; never sample 17,161 nodes on the main thread.
	var owners := {}
	for y in range(coord.y - 1, coord.y + 2):
		for x in range(coord.x - 1, coord.x + 2):
			var owner := zone.chunk_at(Vector2i(x, y))
			if owner and owner.delta_bytes() > 0:
				owners[Vector2i(x, y)] = owner._deltas.duplicate()
	return {"zone_id": key, "epoch": zone.epoch, "coordinate": coord,
		"revision": chunk.revision, "up": zone.up, "tangent_x": zone.tangent_x,
		"tangent_y": zone.tangent_y, "radius_m": zone.radius_m,
		"chunk_bounds": zone.chunk_bounds, "owners": owners}
