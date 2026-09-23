class_name PlanetRoot
extends Node3D

@export var definition: PlanetDefinition
@export var lod_config: PlanetLodConfig
var quadtree_view: PlanetQuadtreeView
var terrain: PlanetTerrain


func _ready() -> void:
	if definition == null or not definition.is_valid():
		push_error("PlanetRoot requires a valid definition.")
		return
	if lod_config == null:
		lod_config = PlanetLodConfig.new()
	if definition.terrain_enabled:
		terrain = PlanetTerrain.new(definition.terrain_seed, definition.geology_enabled)
	quadtree_view = PlanetQuadtreeView.new()
	add_child(quadtree_view)
	quadtree_view.initialize(get_base_radius_units(), lod_config, terrain, definition.meters_per_unit)


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and quadtree_view != null:
		if event.keycode == KEY_F4:
			quadtree_view.set_debug_mode(0 if quadtree_view.debug_mode >= 7 else (quadtree_view.debug_mode + 1) % 7)
		elif event.keycode == KEY_F5:
			quadtree_view.set_debug_mode(7 if quadtree_view.debug_mode < 7 or quadtree_view.debug_mode == 15 else quadtree_view.debug_mode + 1)


func _process(delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera != null and quadtree_view != null:
		quadtree_view.update_camera(camera, delta)


func get_base_radius_units() -> float:
	return definition.get_base_radius_units() if definition != null else 0.0


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if definition == null:
		warnings.append("PlanetRoot requires a PlanetDefinition.")
	elif not definition.is_valid():
		warnings.append("PlanetRoot has an invalid PlanetDefinition.")
	return warnings
