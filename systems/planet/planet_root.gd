class_name PlanetRoot
extends Node3D
## Planet Lab adapter only; all surface/LOD work belongs to the donor pipeline.
@export var definition: PlanetDefinition
@export var show_overlay := true
var renderer: PlanetLODManager
var editable_terrain: PlanetEditableTerrain
var mining_debug: MiningDebugView
var mining_surface: MiningSurfaceManager
@export var level_origin_height := 0.0
@export var level_step := 1.0
var designations: TerrainDesignationStore
var designation_tool: TerrainDesignationTool

func _ready() -> void:
	assert(definition != null and is_equal_approx(definition.radius_m, 50000.0))
	renderer = PlanetLODManager.new()
	renderer.name = "Surface"
	add_child(renderer)
	renderer.configure(definition)
	editable_terrain = PlanetEditableTerrain.new(renderer.shape, renderer.climate, renderer.biomes)
	mining_surface = MiningSurfaceManager.new()
	mining_surface.name = "EditableSurface"
	add_child(mining_surface)
	mining_surface.configure(editable_terrain, renderer)
	designations = TerrainDesignationStore.new(editable_terrain, TerrainLevelDatum.new(level_origin_height, level_step))

func toggle_designation() -> void:
	if is_instance_valid(designation_tool):
		designation_tool.queue_free()
		designation_tool = null
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var direction := to_local(camera.global_position).normalized()
	var centre := get_viewport().get_visible_rect().size * 0.5
	var ray_start := camera.project_ray_origin(centre)
	var query := PhysicsRayQueryParameters3D.create(ray_start, ray_start + camera.project_ray_normal(centre) * 200000.0)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		direction = to_local(hit.position).normalized()
	var zone: MiningZone
	for existing: MiningZone in editable_terrain._zones.values():
		if existing.contains_local(existing.planet_to_local(direction)):
			zone = existing
			break
	if zone == null:
		zone = editable_terrain.zone_by_id("designation-lab")
	if zone == null:
		zone = editable_terrain.create_zone("designation-lab", direction)
	if zone == null or not mining_surface.activate(zone):
		push_warning("Não foi possível ativar zona de designação: " + mining_surface.last_activation_error)
		return
	designation_tool = TerrainDesignationTool.new()
	designation_tool.add_to_group("terrain_designation")
	add_child(designation_tool)
	designation_tool.configure(designations, mining_surface, zone)

func sample_final_height(direction: Vector3) -> float:
	return editable_terrain.sample_final_height(direction)

func _process(_delta: float) -> void:
	if designations:
		designations.advance_transactions()

func _exit_tree() -> void:
	if designations:
		designations.finish_workers()

func toggle_mining_debug() -> void:
	var start := Time.get_ticks_usec()
	if not is_instance_valid(mining_debug):
		mining_debug = MiningDebugView.new()
		add_child(mining_debug)
		mining_debug.configure(mining_surface, null)
	else:
		mining_debug.set_enabled(not mining_debug.visible)
	mining_debug.last_toggle_ms = (Time.get_ticks_usec() - start) / 1000.0

func get_base_radius_units() -> float:
	return definition.radius_m

func sample_base_height(direction: Vector3) -> float:
	return renderer.shape.sample_base_height(direction)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_1 and renderer != null:
		renderer.set_material_debug_mode(renderer.material_debug_mode + 1)
		get_viewport().set_input_as_handled()

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and renderer != null:
		if event.keycode == KEY_F4:
			renderer.debug_lod_colors = not renderer.debug_lod_colors
			renderer.set_geology_debug_mode(0)
			renderer.set_climate_debug_mode(0)
			renderer.set_biome_debug_mode(0)
			renderer.set_material_debug_mode(0)
		elif event.keycode == KEY_F5:
			renderer.set_geology_debug_mode(renderer.geology_debug_mode + 1)
		elif event.keycode == KEY_F6:
			renderer.set_climate_debug_mode(renderer.climate_debug_mode + 1)
		elif event.keycode == KEY_F7:
			renderer.set_biome_debug_mode(renderer.biome_debug_mode + 1)
		elif event.keycode == KEY_F9:
			toggle_mining_debug()
		elif event.keycode == KEY_F10:
			toggle_designation()

func debug_text() -> String:
	if renderer == null:
		return "Inicializando superfície"
	var s := renderer.get_stats()
	var mode_names := ["natural", "província", "maturidade", "interiores", "cinturões", "sedimentar", "ígneo", "planaltos", "bacias fechadas", "antiga região marinha"]
	var climate_modes := ["natural", "temperatura", "umidade", "influência oceânica", "precipitação", "sombra de chuva"]
	var biome_modes := ["natural", "dominante", "blend", "peso dominante"]
	var material_modes := ["PBR", "família", "blend", "slope", "rocha", "neve", "índices"]
	var camera := get_viewport().get_camera_3d()
	var context := ""
	if camera and renderer.geology:
		var local_direction := to_local(camera.global_position).normalized()
		if not local_direction.is_zero_approx():
			var sample := renderer.geology.sample(local_direction)
			context = "\n%s | %s | idade %.2f | influência %.2f" % [renderer.geology.stable_key(int(sample.x)), PlanetGeology.TYPE_NAMES[int(sample.w)], sample.y, sample.z]
			if renderer.climate_debug_mode > 0 and renderer.climate:
				var weather := renderer.climate.sample(local_direction)
				context += "\n%.1f °C | umidade %.2f | oceano %.2f | chuva %.2f | sombra %.2f | altura %.0f m" % [
					weather.temperature_c, weather.humidity, weather.ocean_influence,
					weather.precipitation, weather.rain_shadow, weather.altitude_m]
			if renderer.biome_debug_mode > 0 and renderer.biomes:
				var biome := renderer.biomes.sample(local_direction)
				context += "\n%s %.2f | %s %.2f" % [
					PlanetBiomes.NAMES[biome.dominant] if biome.dominant >= 0 else "Água",
					biome.dominant_weight,
					PlanetBiomes.NAMES[biome.secondary] if biome.secondary >= 0 else "—",
					biome.secondary_weight]
	context += "\nF9 Diagnóstico: visibilidade / limites e filas · F10 Designation: grid + levels"
	return "Planeta | seed %d | raio %.0f m | F4 LOD | F5 geologia: %s | F6 clima: %s | F7 biomas: %s | 1 materiais: %s\nChunks %d / residentes %d | LOD %d | triângulos %d\nFila %d | workers %d | cache %d | revisão %d\nGeração %.2f ms | uploads %.2f ms%s" % [
		definition.seed, definition.radius_m, mode_names[renderer.geology_debug_mode], climate_modes[renderer.climate_debug_mode], biome_modes[renderer.biome_debug_mode], material_modes[renderer.material_debug_mode], s.visible, s.resident, s.depth, s.triangles,
		s.queued, s.jobs, s.cached, s.revision, s.build_ms, s.upload_ms, context]
