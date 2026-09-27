class_name TerrainDesignationOverlay
extends Node3D
## Two batched draw resources for all visible cells: grid mesh + glyph MultiMesh.
## Seven-segment glyph atlas is generated once. Never one Node/Label per cell.
var zone: MiningZone
var grid := MeshInstance3D.new()
var numbers := MultiMeshInstance3D.new()
var colors := [Color(0.95, 0.42, 0.12), Color(0.15, 0.85, 0.50), Color(0.15, 0.58, 1.0)]
var number_distance_m := 140.0
var last_build_ms := 0.0
var max_step_ms := 0.0
var cells_drawn := 0
var glyph_count := 0
var building := false
var _items: Array = []
var _item_cursor := 0
var _cell_cursor := 0
var _vertices := PackedVector3Array()
var _uv := PackedVector2Array()
var _colors := PackedColorArray()
var _indices := PackedInt32Array()
var _glyph_buffer := PackedFloat32Array()
var _start := 0
var _origin := Vector3.ZERO
var _centre := Vector3.ZERO

func configure(selected: MiningZone, origin_height: float) -> void:
	zone = selected
	_origin = zone.up * (zone.radius_m + origin_height)
	position = _origin
	add_child(grid)
	add_child(numbers)
	var material := ShaderMaterial.new()
	material.shader = preload("res://systems/planet/designation/designation_grid.gdshader")
	grid.material_override = material
	var glyph_material := ShaderMaterial.new()
	glyph_material.shader = preload("res://systems/planet/designation/designation_numbers.gdshader")
	glyph_material.set_shader_parameter("digits", digit_atlas())
	numbers.material_override = glyph_material
	grid.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	numbers.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

static func digit_atlas() -> ImageTexture:
	var picture := Image.create(24 * 12, 40, false, Image.FORMAT_RGBA8)
	picture.fill(Color.TRANSPARENT)
	var segments := [Rect2i(5, 3, 14, 3), Rect2i(18, 5, 3, 13), Rect2i(18, 22, 3, 13),
		Rect2i(5, 34, 14, 3), Rect2i(3, 22, 3, 13), Rect2i(3, 5, 3, 13), Rect2i(5, 18, 14, 3)]
	var masks := [0x3f, 0x06, 0x5b, 0x4f, 0x66, 0x6d, 0x7d, 0x07, 0x7f, 0x6f, 0x40, 0]
	for digit in range(12):
		# Dark backing preserves readability on bright rock/snow.
		picture.fill_rect(Rect2i(digit * 24 + 1, 1, 22, 38), Color(0.035, 0.045, 0.055, 1))
		for segment in range(7):
			if masks[digit] & (1 << segment):
				var rectangle: Rect2i = segments[segment]
				rectangle.position.x += digit * 24
				picture.fill_rect(rectangle, Color.WHITE)
		if digit == 11:
			picture.fill_rect(Rect2i(digit * 24 + 9, 33, 4, 4), Color.WHITE)
	return ImageTexture.create_from_image(picture)

func begin_build(items: Array) -> void:
	_items = items
	_item_cursor = 0
	_cell_cursor = 0
	_vertices = PackedVector3Array()
	_uv = PackedVector2Array()
	_colors = PackedColorArray()
	_indices = PackedInt32Array()
	_glyph_buffer = PackedFloat32Array()
	cells_drawn = 0
	glyph_count = 0
	_centre = Vector3.ZERO
	_start = Time.get_ticks_usec()
	building = true

func advance_build(max_cells := 256, budget_ms := 2.0) -> bool:
	if not building:
		return true
	var start := Time.get_ticks_usec()
	var processed := 0
	while _item_cursor < _items.size() and processed < max_cells:
		var job: Dictionary = _items[_item_cursor]
		if _cell_cursor >= job.cells.size():
			_item_cursor += 1
			_cell_cursor = 0
			continue
		_append_cell(job, job.cells[_cell_cursor])
		_cell_cursor += 1
		processed += 1
		if (Time.get_ticks_usec() - start) / 1000.0 >= budget_ms:
			break
	if _item_cursor == _items.size():
		_publish()
	max_step_ms = maxf(max_step_ms, (Time.get_ticks_usec() - start) / 1000.0)
	return not building

func _append_cell(job: Dictionary, cell: Dictionary) -> void:
	var point: Vector2i = cell.cell
	var offset := _vertices.size()
	var centre := Vector3.ZERO
	for corner: Vector2i in [Vector2i.ZERO, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.ONE]:
		var node := point + corner
		var data: Dictionary = job.nodes[node]
		# Diagnostic projection is explicit: surface-or-target, whichever is above.
		# This mesh is decoration, has no collision and never owns terrain height.
		var vertex := zone.local_to_planet(Vector2(node) * 2, maxf(data.current, data.target) + 0.08) - _origin
		_vertices.append(vertex)
		centre += vertex * 0.25
		_uv.append(Vector2(corner))
		var color: Color = colors[cell.height_state]
		if not job.error.is_empty():
			color = Color(1, 0.08, 0.12)
		if cell.work_state == TerrainDesignation.WorkState.IN_PROGRESS:
			color = color.lightened(0.25)
		color.a = cell.work_state / 2.0
		_colors.append(color)
	for index in [0, 2, 1, 1, 2, 3]:
		_indices.append(offset + index)
	var label := level_text(cell.planned_level)
	centre = (_vertices[offset + 1] + _vertices[offset + 2]) * 0.5
	var tangent := (_vertices[offset + 1] - _vertices[offset]).normalized()
	var normal := tangent.cross(_vertices[offset + 2] - _vertices[offset]).normalized()
	if normal.dot(zone.up) < 0:
		normal = -normal
	var width := minf(0.38, 1.7 / label.length())
	var height := minf(0.68, width * 1.67)
	for i in range(label.length()):
		var glyph := 10 if label[i] == "-" else (11 if label[i] == "." else int(label[i]))
		var pos := centre + normal * 0.10
		# MultiMesh buffer: row-major 3x4 transform followed by CUSTOM_DATA.
		var x := tangent
		var y := normal.cross(tangent)
		var z := normal
		var letter_offset := (i - (label.length() - 1) * 0.5) * width
		_glyph_buffer.append_array(PackedFloat32Array([x.x, y.x, z.x, pos.x, x.y, y.y, z.y, pos.y, x.z, y.z, z.z, pos.z, float(glyph), letter_offset, width, height]))
		glyph_count += 1
	_centre += centre
	cells_drawn += 1

static func level_text(level: float) -> String:
	if absf(level - roundf(level)) < 0.00001:
		return str(roundi(level))
	return ("%.2f" % level).trim_suffix("0").trim_suffix("0").trim_suffix(".")

func _publish() -> void:
	if cells_drawn == 0:
		grid.mesh = null
		numbers.multimesh = null
	else:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = _vertices
		arrays[Mesh.ARRAY_TEX_UV] = _uv
		arrays[Mesh.ARRAY_COLOR] = _colors
		arrays[Mesh.ARRAY_INDEX] = _indices
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		grid.mesh = mesh
		var batch := MultiMesh.new()
		batch.transform_format = MultiMesh.TRANSFORM_3D
		batch.use_custom_data = true
		batch.mesh = QuadMesh.new()
		batch.mesh.size = Vector2.ONE
		batch.instance_count = glyph_count
		batch.buffer = _glyph_buffer
		numbers.multimesh = batch
		_centre /= cells_drawn
	building = false
	last_build_ms = (Time.get_ticks_usec() - _start) / 1000.0

func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera:
		numbers.visible = camera.global_position.distance_to(to_global(_centre)) < number_distance_m
