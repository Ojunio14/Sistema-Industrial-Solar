class_name TerrainDesignationOverlay
extends Node3D
## Cached 16x16 shared-vertex line tiles. Current surface and target are separate.
var zone: MiningZone
var store: TerrainDesignationStore
var grid := Node3D.new()
var numbers := MultiMeshInstance3D.new()
var outline := MeshInstance3D.new()
var number_distance_m := 110.0
var last_build_ms := 0.0
var max_step_ms := 0.0
var cells_drawn := 0
var glyph_count := 0
var label_count := 0
var grid_vertices := 0
var tile_builds := 0
var building := false
var _items: Array = []
var _todo: Array = []
var _tiles: Dictionary = {}
var _instances: Dictionary = {}
var _origin := Vector3.ZERO
var _start := 0
var _last_camera := Vector3.INF
var _last_basis := Basis.IDENTITY
var _last_fov := -1.0
var _number_clock := 0.0
var _glyph_buffer := PackedFloat32Array()

func configure(selected: MiningZone, origin_height: float) -> void:
	zone = selected
	_origin = zone.up * (zone.radius_m + origin_height)
	position = _origin
	add_child(grid)
	add_child(numbers)
	add_child(outline)
	var material := ShaderMaterial.new()
	material.shader = preload("res://systems/planet/designation/designation_numbers.gdshader")
	material.set_shader_parameter("digits", digit_atlas())
	numbers.material_override = material
	numbers.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	numbers.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	var target_material := StandardMaterial3D.new()
	target_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	target_material.albedo_color = Color(1, 0.92, 0.25)
	target_material.no_depth_test = true
	outline.material_override = target_material
	outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	outline.gi_mode = GeometryInstance3D.GI_MODE_DISABLED

static func digit_atlas() -> ImageTexture:
	var patterns := ["01110/11011/11011/11011/11011/11011/01110", "00100/01100/00100/00100/00100/00100/01110",
		"01110/11011/00011/00110/01100/11000/11111", "11110/00011/00011/01110/00011/00011/11110",
		"00010/00110/01110/11010/11111/00010/00010", "11111/11000/11000/11110/00011/00011/11110",
		"01110/11000/11000/11110/11011/11011/01110", "11111/00011/00010/00110/00100/01100/01100",
		"01110/11011/11011/01110/11011/11011/01110", "01110/11011/11011/01111/00011/00011/01110",
		"00000/00000/00000/11111/00000/00000/00000", "00000/00000/00000/00000/00000/01100/01100"]
	var image := Image.create(24 * 12, 40, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	for digit in range(12):
		image.fill_rect(Rect2i(digit * 24 + 1, 2, 22, 36), Color(0.02, 0.025, 0.03))
		var rows: PackedStringArray = patterns[digit].split("/")
		for y in range(7):
			for x in range(5):
				if rows[y][x] == "1":
					image.fill_rect(Rect2i(digit * 24 + 4 + x * 3, 6 + y * 4, 3, 4), Color.WHITE)
	return ImageTexture.create_from_image(image)

func begin_build(items: Array) -> void:
	_items = items.duplicate()
	_todo.clear()
	cells_drawn = 0
	grid_vertices = 0
	_start = Time.get_ticks_usec()
	for instance: MeshInstance3D in _instances.values():
		instance.visible = false
	for job: Dictionary in _items:
		if not job.safe:
			continue
		var plan: TerrainDesignation = job.plan
		cells_drawn += plan.rect.get_area()
		var low := Vector2i(floori(plan.rect.position.x / 16.0), floori(plan.rect.position.y / 16.0))
		var high := Vector2i(floori((plan.rect.end.x - 1) / 16.0), floori((plan.rect.end.y - 1) / 16.0))
		for y in range(low.y, high.y + 1):
			for x in range(low.x, high.x + 1):
				_todo.append({"job": job, "tile": Vector2i(x, y)})
	building = true
	_build_outline()
	_last_camera = Vector3.INF

func advance_build(_max_cells := 256, budget_ms := 2.0) -> bool:
	var start := Time.get_ticks_usec()
	while not _todo.is_empty():
		var item: Dictionary = _todo.pop_front()
		_show_tile(item.job, item.tile)
		if (Time.get_ticks_usec() - start) / 1000.0 >= budget_ms:
			break
	if _todo.is_empty():
		building = false
		last_build_ms = (Time.get_ticks_usec() - _start) / 1000.0
		_update_numbers()
		# Bound retained resources to the current selection plus a small warm cache.
		for key in _instances.keys():
			if not _instances[key].visible:
				_instances[key].queue_free()
				_instances.erase(key)
		if _tiles.size() > 96:
			_tiles.clear()
	max_step_ms = maxf(max_step_ms, (Time.get_ticks_usec() - start) / 1000.0)
	return not building

func _show_tile(job: Dictionary, tile: Vector2i) -> void:
	var plan: TerrainDesignation = job.plan
	var stamp: Array = []
	for node in [tile * 16, tile * 16 + Vector2i(16, 0), tile * 16 + Vector2i(0, 16), tile * 16 + Vector2i(16, 16)]:
		var chunk := zone.chunk_at(MiningZone.owner_of(node).clamp(zone.chunk_bounds.position, zone.chunk_bounds.end - Vector2i.ONE))
		stamp.append(chunk.mesh_revision if chunk else -1)
	var cached: Dictionary = _tiles.get(tile, {})
	# Standalone evaluation has no published CPU grid: restrict fallback to its nodes.
	if store == null:
		stamp.append(plan.rect)
		stamp.append(job.clock)
	if cached.get("stamp", []) != stamp:
		var vertices := PackedVector3Array()
		var uv := PackedVector2Array()
		var heights := PackedVector2Array()
		var indices := PackedInt32Array()
		var lookup := {}
		for y in range(17):
			for x in range(17):
				var node := tile * 16 + Vector2i(x, y)
				var data: Dictionary = store.terrain.published_node(zone.id, node) if store else job.nodes.get(node, {})
				if data.is_empty():
					continue
				lookup[Vector2i(x, y)] = vertices.size()
				vertices.append(zone.local_to_planet(Vector2(node) * 2, data.current + 0.07) - _origin)
				uv.append(Vector2(node))
				heights.append(Vector2(data.current, 0))
		for point: Vector2i in lookup:
			for step in [Vector2i.RIGHT, Vector2i.DOWN]:
				if lookup.has(point + step):
					indices.append(lookup[point])
					indices.append(lookup[point + step])
		var mesh := ArrayMesh.new()
		if not indices.is_empty():
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = vertices
			arrays[Mesh.ARRAY_TEX_UV] = uv
			arrays[Mesh.ARRAY_TEX_UV2] = heights
			arrays[Mesh.ARRAY_INDEX] = indices
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
		cached = {"stamp": stamp, "mesh": mesh, "vertices": vertices.size()}
		_tiles[tile] = cached
		tile_builds += 1
	var key := "%d/%s" % [plan.id, tile]
	var instance: MeshInstance3D = _instances.get(key)
	if instance == null:
		instance = MeshInstance3D.new()
		grid.add_child(instance)
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		instance.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		var material := ShaderMaterial.new()
		material.shader = preload("res://systems/planet/designation/designation_grid.gdshader")
		instance.material_override = material
		_instances[key] = instance
	instance.mesh = cached.mesh
	instance.visible = true
	grid_vertices += cached.vertices
	var material: ShaderMaterial = instance.material_override
	material.set_shader_parameter("selection", Vector4(plan.rect.position.x, plan.rect.position.y, plan.rect.end.x, plan.rect.end.y))
	var base: float = plan.target_height(Vector2.ZERO, store.datum) if store else job.nodes.values()[0].target
	var dx := 0.0
	var dy := 0.0
	if store and plan.kind == TerrainDesignation.Kind.RAMP:
		var slope: float = (plan.end_level - plan.start_level) * store.datum.level_step / plan.rect.size[plan.axis]
		if plan.reverse:
			slope = -slope
		base = store.datum.height(plan.end_level if plan.reverse else plan.start_level) - slope * plan.rect.position[plan.axis]
		if plan.axis == 0:
			dx = slope
		else:
			dy = slope
	material.set_shader_parameter("target_plane", Vector3(dx, dy, base))

func _build_outline() -> void:
	var vertices := PackedVector3Array()
	for job: Dictionary in _items:
		if not job.safe:
			continue
		var rect: Rect2i = job.plan.rect
		var corners := [rect.position, Vector2i(rect.end.x, rect.position.y), rect.end, Vector2i(rect.position.x, rect.end.y)]
		for side in range(4):
			var length: int = (corners[(side + 1) % 4] - corners[side]).length()
			for i in range(length):
				# Short dashes mark only the target perimeter, never a filled surface.
				for t in [float(i) / length, (i + 0.65) / length]:
					var node := Vector2(corners[side]).lerp(Vector2(corners[(side + 1) % 4]), t)
					var height: float = job.plan.target_height(node, store.datum) if store else job.nodes.values()[0].target
					vertices.append(zone.local_to_planet(node * 2, height + 0.1) - _origin)
	outline.mesh = null
	if not vertices.is_empty():
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
		outline.mesh = mesh

static func level_text(level: float) -> String:
	return str(roundi(level))

func _update_numbers() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	_last_camera = camera.global_position
	_last_basis = camera.global_basis
	_last_fov = camera.fov
	_glyph_buffer = PackedFloat32Array()
	glyph_count = 0
	label_count = 0
	var local_camera: Vector3 = get_parent().to_local(camera.global_position)
	var footprint := zone.cell_at(zone.planet_to_local(local_camera))
	for job: Dictionary in _items:
		var area: Rect2i = job.plan.rect.intersection(Rect2i(footprint - Vector2i(24, 24), Vector2i(49, 49)))
		var reference: Dictionary = job.nodes.get(footprint, {})
		var altitude: float = local_camera.length() - zone.radius_m - reference.get("current", _origin.length() - zone.radius_m)
		var minimum_stride := 1 if altitude < 28 else (2 if altitude < 55 else 4)
		var first_x := area.position.x + posmod(-area.position.x, minimum_stride)
		var first_y := area.position.y + posmod(-area.position.y, minimum_stride)
		for y in range(first_y, area.end.y, minimum_stride):
			for x in range(first_x, area.end.x, minimum_stride):
				if label_count >= 128:
					break
				var point := Vector2i(x, y)
				var cell: Dictionary = job.get("cell_map", {}).get(point, {})
				if cell.is_empty():
					continue
				var centre := zone.local_to_planet((Vector2(point) + Vector2(0.5, 0.5)) * 2, cell.current_final_height + 0.32)
				var distance := local_camera.distance_to(centre)
				var stride := 1 if distance < 28 else (2 if distance < 55 else 4)
				if distance > number_distance_m or posmod(x, stride) != 0 or posmod(y, stride) != 0:
					continue
				var world: Vector3 = get_parent().to_global(centre)
				if camera.is_position_behind(world) or not get_viewport().get_visible_rect().has_point(camera.unproject_position(world)):
					continue
				# Keep glyphs ~18 screen pixels high, with their bottom above terrain.
				var height := 18.0 * 2.0 * tan(deg_to_rad(camera.fov * 0.5)) * distance / get_viewport().get_visible_rect().size.y
				height = clampf(height, 0.7, 6.0)
				var highest: float = cell.current_final_height
				for offset in [Vector2i.ZERO, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.ONE]:
					highest = maxf(highest, job.nodes[point + offset].current)
				centre = zone.local_to_planet((Vector2(point) + Vector2(0.5, 0.5)) * 2, highest + height * 0.65 + 0.15)
				_append_number(centre - _origin, level_text(cell.current_level), height)
				label_count += 1
	var batch := MultiMesh.new()
	batch.transform_format = MultiMesh.TRANSFORM_3D
	batch.use_custom_data = true
	batch.mesh = QuadMesh.new()
	batch.mesh.size = Vector2.ONE
	batch.instance_count = glyph_count
	if glyph_count > 0:
		batch.buffer = _glyph_buffer
	numbers.multimesh = batch
	numbers.visible = glyph_count > 0

func _append_number(pos: Vector3, label: String, height: float) -> void:
	var width := height * 0.55
	for i in range(label.length()):
		var glyph := 10 if label[i] == "-" else (11 if label[i] == "." else int(label[i]))
		_glyph_buffer.append_array(PackedFloat32Array([1,0,0,pos.x, 0,1,0,pos.y, 0,0,1,pos.z,
			float(glyph), (i - (label.length() - 1) * 0.5) * width, width, height]))
		glyph_count += 1

func _process(delta: float) -> void:
	_number_clock += delta
	var camera := get_viewport().get_camera_3d()
	if not visible or building or camera == null or _number_clock < 0.15:
		return
	_number_clock = 0
	if camera.global_position.distance_to(_last_camera) > 1.0 or not camera.global_basis.is_equal_approx(_last_basis) or camera.fov != _last_fov:
		_update_numbers()
