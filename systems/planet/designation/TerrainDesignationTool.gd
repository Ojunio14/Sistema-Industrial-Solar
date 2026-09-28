class_name TerrainDesignationTool
extends Node3D
## F10 technical designation UX. Plans persist in PlanetRoot when this UI closes.
var store: TerrainDesignationStore
var surface: MiningSurfaceManager
var zone: MiningZone
var overlay: TerrainDesignationOverlay
var preview: TerrainDesignation
var evaluations: Array = []
var mode := TerrainDesignation.Kind.PLATFORM
var level := 0
var end_level := 0
var width_cells := 3
var operation := TerrainDesignation.Operation.CUT_AND_FILL
var dragging := false
var first_cell := Vector2i.ZERO
var last_cell := Vector2i.ZERO
var status: Label
var level_input: SpinBox
var end_input: SpinBox
var width_input: SpinBox
var confirm_button: Button
var apply_button: Button
var mode_input: OptionButton
var operation_input: OptionButton
var _job_cursor := 0
var _clock := -1
var _revision := -1
var _pending := false
var _message := "Arraste uma área; confirmar guarda o plano. DEV APPLY altera o terreno."
var last_apply_ms := 0.0
var _refresh_requested := false
var _publication := -1
var _last_screen := Vector2.INF
var _last_local := Vector2.ZERO
var panel: PanelContainer
var canvas: CanvasLayer

func configure(data: TerrainDesignationStore, manager: MiningSurfaceManager, selected: MiningZone) -> void:
	store = data
	surface = manager
	zone = selected
	level = store.datum.nearest_level(store.terrain.sample_final_height(zone.up))
	end_level = level - 5
	overlay = TerrainDesignationOverlay.new()
	add_child(overlay)
	overlay.store = store
	overlay.configure(zone, store.datum.origin_height)
	_build_hud()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	refresh()

func _build_hud() -> void:
	canvas = CanvasLayer.new()
	add_child(canvas)
	panel = PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	panel.offset_left = -355
	panel.offset_right = -12
	panel.offset_top = 12
	panel.anchor_bottom = 1.0
	panel.offset_bottom = -12
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.055, 0.07, 0.085, 1)
	background.content_margin_left = 10
	background.content_margin_right = 10
	background.content_margin_top = 8
	background.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", background)
	canvas.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	var title := Label.new()
	title.text = "F10 · GRID 3D · 2 × 2 m\nNúmeros: CURRENT LEVEL\nContorno amarelo: TARGET"
	box.add_child(title)
	var chooser := OptionButton.new()
	mode_input = chooser
	chooser.add_item("Plataforma · um nível")
	chooser.add_item("Rampa · conectar dois níveis")
	chooser.item_selected.connect(func(value: int): mode = value; cancel_preview())
	box.add_child(chooser)
	level_input = _spin(box, "TARGET LEVEL / início", level, -1000000, 1000000)
	end_input = _spin(box, "TARGET LEVEL final da rampa", end_level, -1000000, 1000000)
	width_input = _spin(box, "Largura da rampa (células de 2 m)", width_cells, 2, 6)
	level_input.value_changed.connect(func(value: float): level = roundi(value); _update_levels())
	end_input.value_changed.connect(func(value: float): end_level = roundi(value); _update_levels())
	width_input.value_changed.connect(_change_width)
	var operations := OptionButton.new()
	operation_input = operations
	operations.add_item("Corte + aterro (DEV)")
	operations.add_item("Somente corte")
	operations.add_item("Somente aterro")
	operations.item_selected.connect(func(value: int): operation = value; if preview: preview.operation = value; refresh())
	box.add_child(operations)
	confirm_button = _button(box, "Confirmar plano · Enter", confirm_preview)
	apply_button = _button(box, "DEV APPLY · planos confirmados", dev_apply)
	_button(box, "Cancelar preview · Esc", cancel_preview)
	_button(box, "Excluir plano selecionado", func():
		if preview and preview.id != 0:
			store.remove(preview.id)
		cancel_preview())
	status = Label.new()
	status.custom_minimum_size.x = 300
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(status)
	var help := Label.new()
	help.text = "Arrastar: selecionar · Clique: editar\nPgUp/PgDn: nível · Shift: nível final\nCorte: laranja · alvo: verde · aterro: azul\nAmarelo tracejado: contorno TARGET\nNúmeros: CURRENT LEVEL arredondado\nBotão direito: navegar · arraste: câmera fixa\nF10 fecha; planos e edições permanecem."
	box.add_child(help)

func _spin(box: VBoxContainer, text: String, value: int, low: int, high: int) -> SpinBox:
	var label := Label.new()
	label.text = text
	box.add_child(label)
	var field := SpinBox.new()
	field.min_value = low
	field.max_value = high
	field.step = 1
	field.value = value
	box.add_child(field)
	return field

func _button(box: VBoxContainer, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(action)
	box.add_child(button)
	return button

func pick_cell(screen: Vector2) -> Variant:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return null
	var origin := camera.project_ray_origin(screen)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + camera.project_ray_normal(screen) * 200000.0)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return null
	var collider: Object = hit.collider
	if collider.get_meta("mining_zone", "") != zone.id:
		_message = "Superfície local ainda sem colisão publicada"
		return null
	var chunk := zone.chunk_at(collider.get_meta("mining_chunk", Vector2i(999, 999)))
	if chunk == null or chunk.mesh_revision != chunk.collision_revision or chunk.collision_revision != chunk.revision:
		_message = "Superfície pendente: mantenha a seleção até publicar"
		return null
	var planet_position: Vector3 = surface.get_parent().to_local(hit.position)
	var local := zone.planet_to_local(planet_position)
	_last_local = local
	if dragging and Rect2(Vector2(last_cell) * 2 - Vector2(0.15, 0.15), Vector2(2.3, 2.3)).has_point(local):
		return last_cell
	return zone.cell_at(local) if zone.contains_local(local) else null

func _input(event: InputEvent) -> void:
	# Input ownership precedes camera controllers and survives release over HUD.
	if dragging and (event is InputEventMouseMotion or event is InputEventMouseButton):
		_unhandled_input(event)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if not panel.get_global_rect().has_point(event.position):
			_unhandled_input(event)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var picked: Variant = pick_cell(event.position)
			if picked != null:
				first_cell = picked
				last_cell = picked
				dragging = true
				get_node("/root/CameraManager").designation_dragging = true
				var right := store.current_node(zone, picked + Vector2i.RIGHT)
				var down := store.current_node(zone, picked + Vector2i.DOWN)
				level = store.datum.nearest_level((right.current + down.current) * 0.5)
				level_input.set_value_no_signal(level)
				preview = null
				_drag_to(picked)
			else:
				_message = "Aponte para a zona com colisão publicada; aproxime a câmera."
		elif dragging:
			dragging = false
			get_node("/root/CameraManager").designation_dragging = false
			var existing := store.plan_at(zone.id, first_cell)
			if last_cell == first_cell and existing:
				preview = existing.duplicate_plan()
				level = preview.start_level
				end_level = preview.end_level
				level_input.set_value_no_signal(level)
				end_input.set_value_no_signal(end_level)
				mode = preview.kind
				operation = preview.operation
				mode_input.select(preview.kind)
				operation_input.select(operation)
				if preview.kind == TerrainDesignation.Kind.RAMP:
					width_cells = preview.rect.size[1 - preview.axis]
					width_input.set_value_no_signal(width_cells)
				refresh()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and dragging:
		if event.position.distance_to(_last_screen) < 1.5:
			return
		_last_screen = event.position
		var picked: Variant = pick_cell(event.position)
		if picked != null and picked != last_cell:
			_drag_to(picked)
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed:
		if event.keycode in [KEY_PAGEUP, KEY_PAGEDOWN]:
			var increment := 1 if event.keycode == KEY_PAGEUP else -1
			if event.shift_pressed:
				end_input.value += increment
			else:
				level_input.value += increment
		elif event.keycode == KEY_ENTER:
			confirm_preview()
		elif event.keycode == KEY_ESCAPE:
			cancel_preview()
		else:
			return
		get_viewport().set_input_as_handled()

func _drag_to(cell: Vector2i) -> void:
	last_cell = cell
	preview = TerrainDesignation.new()
	preview.zone_id = zone.id
	preview.kind = mode
	preview.operation = operation
	preview.start_level = level
	preview.end_level = end_level
	preview.rect = Rect2i(first_cell.min(cell), first_cell.max(cell) - first_cell.min(cell) + Vector2i.ONE)
	if mode == TerrainDesignation.Kind.RAMP:
		preview.axis = 0 if absi(cell.x - first_cell.x) >= absi(cell.y - first_cell.y) else 1
		preview.reverse = cell[preview.axis] < first_cell[preview.axis]
		preview.rect.position[1 - preview.axis] = first_cell[1 - preview.axis] - floori(width_cells / 2.0)
		preview.rect.size[1 - preview.axis] = width_cells
		var anchors := store.detect_ramp_anchors(preview)
		if anchors[0] != null:
			preview.start_level = anchors[0]
			level = anchors[0]
			level_input.set_value_no_signal(level)
		if anchors[1] != null:
			preview.end_level = anchors[1]
			end_level = anchors[1]
			end_input.set_value_no_signal(end_level)
	refresh()

func _update_levels() -> void:
	if preview:
		preview.start_level = level
		preview.end_level = end_level
		preview.started = false
		refresh()

func _change_width(value: float) -> void:
	width_cells = roundi(value)
	if preview == null or preview.kind != TerrainDesignation.Kind.RAMP:
		return
	if preview.id == 0:
		_drag_to(last_cell)
	else:
		var transverse := 1 - preview.axis
		var centre := preview.rect.position[transverse] + preview.rect.size[transverse] / 2.0
		preview.rect.position[transverse] = floori(centre - width_cells / 2.0)
		preview.rect.size[transverse] = width_cells
		refresh()

func cancel_preview() -> void:
	dragging = false
	get_node("/root/CameraManager").designation_dragging = false
	preview = null
	refresh()

func confirm_preview() -> void:
	if preview == null or dragging or _pending:
		return
	if store.confirm(preview):
		_message = "Plano confirmado. Terreno inalterado até DEV APPLY."
		preview = null
		refresh()
	else:
		_message = store.validate(preview)

func _exit_tree() -> void:
	get_node("/root/CameraManager").designation_dragging = false

func refresh() -> void:
	_refresh_requested = true
	_pending = true

func _start_refresh() -> void:
	if store == null:
		return
	_refresh_requested = false
	evaluations = []
	for plan in store.plans:
		if plan.zone_id == zone.id and (preview == null or plan.id != preview.id):
			evaluations.append(store.begin_evaluation(plan))
	if preview:
		evaluations.append(store.begin_evaluation(preview))
	_job_cursor = 0
	_clock = zone._clock
	_revision = store.revision
	_publication = surface.publication_serial
	_pending = true
	# Geometry uses already-published CPU samples; volume evaluation can follow.
	overlay.begin_build(evaluations)

func dev_apply() -> void:
	if _pending or preview != null or evaluations.is_empty():
		_message = "Confirme/cancele o preview e aguarde a avaliação antes de aplicar."
		return
	if not _surface_ready():
		_message = "Aguarde a publicação da mesh e colisão atuais."
		return
	var start := Time.get_ticks_usec()
	var result := store.queue_apply(evaluations)
	last_apply_ms = (Time.get_ticks_usec() - start) / 1000.0
	_message = "Dados pendentes · preparando deltas em worker" if result.ok else result.error

func _surface_ready() -> bool:
	var entry: Dictionary = surface.zones.get(zone.id, {})
	if entry.is_empty() or not entry.published:
		return false
	for chunk: MiningChunk in zone._chunks.values():
		if chunk.active and (chunk.mesh_dirty() or chunk.collision_revision != chunk.revision):
			return false
	return true

func _process(_delta: float) -> void:
	if store == null:
		return
	if _clock != zone._clock or _revision != store.revision or _publication != surface.publication_serial:
		refresh()
	if _refresh_requested:
		_start_refresh()
	if _pending:
		if _job_cursor < evaluations.size():
			if store.advance_evaluation(evaluations[_job_cursor]):
				_job_cursor += 1
		else:
			_pending = false
			overlay._update_numbers()
	if overlay.building:
		overlay.advance_build()
	_update_hud()

func _update_hud() -> void:
	var cut := 0.0
	var fill := 0.0
	var complete := 0
	var progress := 0
	var cells := 0
	var error := ""
	var current_min := INF
	var current_max := -INF
	for job: Dictionary in evaluations:
		current_min = minf(current_min, job.current_min)
		current_max = maxf(current_max, job.current_max)
		cut += job.cut_m3
		fill += job.fill_m3
		if not job.error.is_empty():
			error = job.error
		cells += job.cells.size()
		complete += job.complete
		progress += job.in_progress
	var selection := "TARGET LEVEL: %d\nTARGET HEIGHT: %.2f m" % [level, store.datum.height(level)]
	var focus: TerrainDesignation = preview
	if focus == null and evaluations.size() == 1:
		focus = evaluations[0].plan
	if focus:
		selection = "TARGET LEVEL: %d\nTARGET HEIGHT: %.2f m" % [focus.start_level, store.datum.height(focus.start_level)]
		if focus.kind == TerrainDesignation.Kind.RAMP:
			selection = "TARGET LEVEL: %d → %d\nTARGET HEIGHT: %.2f → %.2f m\nExtensão %.0f m · grade %.1f%%" % [focus.start_level, focus.end_level,
				store.datum.height(focus.start_level), store.datum.height(focus.end_level), focus.rect.size[focus.axis] * 2, focus.grade_percent(store.datum)]
	if is_finite(current_min):
		selection = "CURRENT LEVEL: %.2f … %.2f\n" % [current_min, current_max] + selection
	if not store.transaction_status.is_empty():
		_message = store.transaction_status
		if _surface_ready() and store.running.is_empty() and store.queued.is_empty() and _message.begins_with("Dados aplicados"):
			_message = "Mesh e colisão publicadas · targets preservados"
	status.text = "%s\nCUT: %.2f m³ · FILL: %.2f m³\nPLANNED %d · IN_PROGRESS %d\nCOMPLETE %d · %s\n%s\n%s" % [selection, cut, fill, cells - progress - complete, progress, complete,
		"mesh/colisão atuais" if _surface_ready() else "mesh/colisão pendentes", "Calculando preview…" if _pending or overlay.building else _message, error]
	status.modulate = Color(1, 0.4, 0.35) if not error.is_empty() else Color.WHITE
	confirm_button.disabled = preview == null or dragging or _pending or not error.is_empty()
	apply_button.disabled = preview != null or _pending or evaluations.is_empty() or not error.is_empty() or not _surface_ready() or not store.running.is_empty() or not store.queued.is_empty()
