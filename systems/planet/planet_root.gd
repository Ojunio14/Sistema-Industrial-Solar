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

func debug_text() -> String:
	if renderer == null:
		return "Inicializando superfície"
	var s := renderer.get_stats()
	return "Doador | seed %d | raio %.0f m | F4 LOD\nChunks %d / residentes %d | LOD %d | triângulos %d\nFila %d | workers %d | cache %d | revisão %d\nGeração %.2f ms | uploads %.2f ms" % [
		definition.seed, definition.radius_m, s.visible, s.resident, s.depth, s.triangles,
		s.queued, s.jobs, s.cached, s.revision, s.build_ms, s.upload_ms]
