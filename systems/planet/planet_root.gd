class_name PlanetRoot
extends Node3D
## Planet Lab adapter only; all surface/LOD work belongs to the donor pipeline.
@export var definition: PlanetDefinition
@export var show_overlay := true
var renderer: PlanetLODManager

func _ready() -> void:
	assert(definition != null and is_equal_approx(definition.radius_m, 50000.0))
	renderer = PlanetLODManager.new()
	renderer.name = "Surface"
	add_child(renderer)
	renderer.configure(definition)

func get_base_radius_units() -> float:
	return definition.radius_m

func sample_base_height(direction: Vector3) -> float:
	return renderer.shape.sample_base_height(direction)

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and renderer != null:
		if event.keycode == KEY_F4:
			renderer.debug_lod_colors = not renderer.debug_lod_colors
			renderer.set_geology_debug_mode(0)
			renderer.set_climate_debug_mode(0)
			renderer.set_biome_debug_mode(0)
		elif event.keycode == KEY_F5:
			renderer.set_geology_debug_mode(renderer.geology_debug_mode + 1)
		elif event.keycode == KEY_F6:
			renderer.set_climate_debug_mode(renderer.climate_debug_mode + 1)
		elif event.keycode == KEY_F7:
			renderer.set_biome_debug_mode(renderer.biome_debug_mode + 1)

func debug_text() -> String:
	if renderer == null:
		return "Inicializando superfície"
	var s := renderer.get_stats()
	var mode_names := ["natural", "província", "maturidade", "interiores", "cinturões", "sedimentar", "ígneo", "planaltos", "bacias fechadas", "antiga região marinha"]
	var climate_modes := ["natural", "temperatura", "umidade", "influência oceânica", "precipitação", "sombra de chuva"]
	var biome_modes := ["natural", "dominante", "blend", "peso dominante"]
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
	return "Doador | seed %d | raio %.0f m | F4 LOD | F5 geologia: %s | F6 clima: %s | F7 biomas: %s\nChunks %d / residentes %d | LOD %d | triângulos %d\nFila %d | workers %d | cache %d | revisão %d\nGeração %.2f ms | uploads %.2f ms%s" % [
		definition.seed, definition.radius_m, mode_names[renderer.geology_debug_mode], climate_modes[renderer.climate_debug_mode], biome_modes[renderer.biome_debug_mode], s.visible, s.resident, s.depth, s.triangles,
		s.queued, s.jobs, s.cached, s.revision, s.build_ms, s.upload_ms, context]
