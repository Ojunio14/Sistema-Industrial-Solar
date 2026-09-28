class_name MiningDebugView
extends Node3D
## F9 observes terrain. Visibility never activates, unloads or mutates a zone.
var surface: MiningSurfaceManager
var zone: MiningZone
var labels: Dictionary = {}
var borders: Dictionary = {}
var stamps: Dictionary = {}
var ranges: Dictionary = {}
var caption: Label
var canvas: CanvasLayer
var last_toggle_ms := 0.0
var rebuilt_chunks := 0
var metrics := {"data_ms": 0.0, "data_refreshes": 0, "nodes_ms": 0.0, "geometry_ms": 0.0, "frame_work_ms": 0.0}
var material: StandardMaterial3D

func configure(manager: MiningSurfaceManager, selected: MiningZone) -> void:
	surface = manager
	zone = selected
	canvas = CanvasLayer.new()
	add_child(canvas)
	caption = Label.new()
	caption.position = Vector2(20, 180)
	caption.add_theme_color_override("font_shadow_color", Color.BLACK)
	caption.add_theme_constant_override("shadow_offset_x", 2)
	caption.add_theme_constant_override("shadow_offset_y", 2)
	canvas.add_child(caption)
	material = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = true
	material.albedo_color = Color(0.5, 0.85, 1)

func set_enabled(enabled: bool) -> void:
	visible = enabled
	canvas.visible = enabled
	set_process(enabled)

func _process(_delta: float) -> void:
	if surface == null or not visible:
		return
	var start := Time.get_ticks_usec()
	caption.text = "F9 · Diagnóstico · %d zonas · F10 abre designação\nFila %d · workers %d · resultados %d · commit %.2f ms · colisão %.2f ms\nAlternância %.3f ms · geometria atualizada %d chunks" % [surface.zones.size(), surface.queue.size(), surface.jobs.size(), surface.pending.size(), surface.last_commit_ms, surface.last_collision_ms, last_toggle_ms, rebuilt_chunks]
	var live := {}
	var updated := false
	for entry: Dictionary in surface.zones.values():
		var selected: MiningZone = entry.zone
		zone = selected
		for chunk: MiningChunk in selected._chunks.values():
			var key := "%s/%s" % [selected.id, chunk.coordinate]
			live[key] = true
			var stamp := [chunk.revision, chunk.mesh_revision, chunk.collision_revision, surface.chunk_status(selected.id, chunk.coordinate)]
			if not updated and stamps.get(key, []) != stamp:
				_update_chunk(selected, chunk, key, stamp)
				updated = true
	for key in labels.keys():
		if not live.has(key):
			labels[key].queue_free()
			borders[key].queue_free()
			labels.erase(key)
			borders.erase(key)
			stamps.erase(key)
			ranges.erase(key)
	metrics.frame_work_ms = maxf(metrics.frame_work_ms, (Time.get_ticks_usec() - start) / 1000.0)

func _update_chunk(selected: MiningZone, chunk: MiningChunk, key: String, stamp: Array) -> void:
	var start := Time.get_ticks_usec()
	var cached: Dictionary = ranges.get(key, {})
	if cached.get("revision", -1) != chunk.revision:
		var low := 0.0
		var high := 0.0
		for value in chunk._deltas:
			low = minf(low, value)
			high = maxf(high, value)
		cached = {"revision": chunk.revision, "low": low, "high": high}
		ranges[key] = cached
		metrics.data_refreshes += 1
	metrics.data_ms += (Time.get_ticks_usec() - start) / 1000.0
	start = Time.get_ticks_usec()
	if not labels.has(key):
		var label := Label3D.new()
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.font_size = 32
		label.pixel_size = 0.15
		add_child(label)
		labels[key] = label
		var border := MeshInstance3D.new()
		border.material_override = material
		border.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		border.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		add_child(border)
		borders[key] = border
	metrics.nodes_ms += (Time.get_ticks_usec() - start) / 1000.0
	start = Time.get_ticks_usec()
	var data: Dictionary = surface.terrain.published_chunks.get(selected.id, {}).get(chunk.coordinate, {})
	if not data.is_empty() and (not stamps.has(key) or stamps[key][1] != stamp[1]):
		var vertices := PackedVector3Array()
		var corners := [Vector2i.ZERO, Vector2i(128, 0), Vector2i(128, 128), Vector2i(0, 128)]
		for side in range(4):
			for step in range(16):
				for t in [step / 16.0, (step + 1) / 16.0]:
					var node := Vector2i(Vector2(corners[side]).lerp(Vector2(corners[(side + 1) % 4]), t))
					vertices.append(data.vertices[node.y * 129 + node.x] + selected.up * 0.1)
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
		borders[key].mesh = mesh
		labels[key].position = data.vertices[64 * 129 + 64] + selected.up * 12
		rebuilt_chunks += 1
	labels[key].text = "%s %s · %s\nrev %d / mesh %d / colisão %d\nΔ %.1f…%.1f m" % [selected.id, chunk.coordinate, stamp[3], chunk.revision, chunk.mesh_revision, chunk.collision_revision, cached.low, cached.high]
	labels[key].visible = not data.is_empty()
	stamps[key] = stamp
	metrics.geometry_ms += (Time.get_ticks_usec() - start) / 1000.0
