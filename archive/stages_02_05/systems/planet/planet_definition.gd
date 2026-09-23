class_name PlanetDefinition
extends Resource

const UNIT_DESCRIPTION := "1 Godot unit = 1 meter"

@export_range(1.0, 10000000.0, 1.0, "or_greater") var base_radius_meters: float = 50000.0
@export_range(0.000001, 1000000.0, 0.000001, "or_greater") var meters_per_unit: float = 1.0
@export var terrain_seed: int = 73129
@export var terrain_enabled: bool = true
@export var geology_enabled: bool = true
@export var climate_enabled: bool = true
@export var materials_enabled: bool = true


func is_valid() -> bool:
	return is_finite(base_radius_meters) and base_radius_meters > 0.0 \
		and is_finite(meters_per_unit) and meters_per_unit > 0.0 \
		and (not terrain_enabled or base_radius_meters > -PlanetTerrain.MIN_HEIGHT)


func get_base_radius_units() -> float:
	if not is_valid():
		return 0.0
	return base_radius_meters / meters_per_unit
