class_name MiningDebugView
extends Node3D
## In-world diagnostics only; no second viewport or digging input.
var surface: MiningSurfaceManager
var zone: MiningZone
var labels: Dictionary = {}
var borders: Dictionary = {}
var caption: Label
var _elapsed := 0.0

func configure(manager: MiningSurfaceManager, selected: MiningZone) -> void:
	surface = manager
	zone = selected
	var canvas := CanvasLayer.new()
	add_child(canvas)
	caption = Label.new()
	caption.position = Vector2(20, 180)
	caption.add_theme_color_override("font_shadow_color", Color.BLACK)
	caption.add_theme_constant_override("shadow_offset_x", 2)
	caption.add_theme_constant_override("shadow_offset_y", 2)
	canvas.add_child(caption)
	for chunk: MiningChunk in zone._chunks.values():
		var label := Label3D.new()
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.font_size = 40
		label.pixel_size = 0.3
		var local := (Vector2(chunk.coordinate) + Vector2(0.5, 0.5)) * 256
		var d := zone.local_to_direction(local)
		label.position = d * (zone.radius_m + surface.terrain.sample_final_height(d) + 12)
		add_child(label)
		labels[chunk.coordinate] = label
		var border := MeshInstance3D.new()
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.no_depth_test = true
		border.material_override = material
		add_child(border)
		borders[chunk.coordinate] = border
		border.mesh = border_mesh(chunk.coordinate)

func border_mesh(coord: Vector2i) -> ImmediateMesh:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var corners := [Vector2.ZERO, Vector2(256, 0), Vector2(256, 256), Vector2(0, 256)]
	for side in range(4):
		for step in range(16):
			for t in [step / 16.0, (step + 1) / 16.0]:
				var d := zone.local_to_direction(Vector2(coord) * 256 + corners[side].lerp(corners[(side + 1) % 4], t))
				mesh.surface_add_vertex(d * (zone.radius_m + surface.terrain.sample_final_height(d)))
	mesh.surface_end()
	return mesh

func _process(delta: float) -> void:
	_elapsed += delta
	if surface == null or _elapsed < 0.2 or not surface.zones.has(zone.id):
		return
	_elapsed = 0
	var entry: Dictionary = surface.zones[zone.id]
	caption.text = "F9 · Mining Zone %s · no planeta · %s\nFila %d · workers %d · resultados %d · commits %d · %.2f ms (colisão %.2f ms)\nDelta %.0f KiB · obsoletos %d · %s" % [zone.id,
		"ativa" if entry.published else "preparando / global visível", surface.queue.size(), surface.jobs.size(), surface.pending.size(), surface.commits_this_frame,
		surface.last_commit_ms, surface.last_collision_ms, zone.delta_bytes() / 1024.0, surface.discarded, entry.error]
	for coord in labels:
		var chunk := zone.chunk_at(coord)
		if chunk == null:
			continue
		var status := surface.chunk_status(zone.id, coord)
		var color := Color.GREEN if status == "carregado" else (Color.CYAN if status == "worker" else (Color.YELLOW if status == "upload" else Color.ORANGE_RED))
		labels[coord].modulate = color
		borders[coord].material_override.albedo_color = color
		var low := 0.0
		var high := 0.0
		if chunk.delta_bytes() > 0:
			for value in chunk._deltas:
				low = minf(low, value)
				high = maxf(high, value)
		labels[coord].text = "%d,%d · %s\nrev %d / mesh %d / col %d\nΔ %.1f…%.1f m" % [coord.x, coord.y, status, chunk.revision, chunk.mesh_revision, chunk.collision_revision, low, high]
