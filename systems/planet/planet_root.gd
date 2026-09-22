class_name PlanetRoot
extends Node3D

@export var definition: PlanetDefinition


func get_base_radius_units() -> float:
	return definition.get_base_radius_units() if definition != null else 0.0


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if definition == null:
		warnings.append("PlanetRoot requires a PlanetDefinition.")
	elif not definition.is_valid():
		warnings.append("PlanetRoot has an invalid PlanetDefinition.")
	return warnings
