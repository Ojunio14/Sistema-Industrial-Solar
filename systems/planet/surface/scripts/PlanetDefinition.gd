extends Resource
class_name PlanetDefinition

## Dados físicos e procedurais compartilhados por todas as representações do planeta.

@export_group("Escala")
@export_range(100.0, 100000.0, 1.0, "or_greater") var radius_m: float = 50000.0:
	set(value):
		radius_m = maxf(value, 100.0)
		emit_changed()
@export var sea_level_m: float = 0.0:
	set(value):
		sea_level_m = value
		emit_changed()
@export_range(0.0, 10000.0, 1.0, "or_greater") var max_terrain_height_m: float = 900.0:
	set(value):
		max_terrain_height_m = maxf(value, 0.0)
		emit_changed()
@export_range(0.0, 10000.0, 1.0, "or_greater") var ocean_depth_m: float = 350.0:
	set(value):
		ocean_depth_m = maxf(value, 0.0)
		emit_changed()

@export_group("Física")
@export_range(0.01, 100.0, 0.01, "or_greater") var surface_gravity_mps2: float = 9.81:
	set(value):
		surface_gravity_mps2 = maxf(value, 0.01)
		emit_changed()

@export_group("Geração")
@export var seed: int = 12051965:
	set(value):
		seed = value
		emit_changed()
@export_range(0.1, 8.0, 0.01) var continent_scale: float = 1.15:
	set(value):
		continent_scale = maxf(value, 0.1)
		emit_changed()
@export_range(-0.9, 0.9, 0.01) var continent_threshold: float = -0.08:
	set(value):
		continent_threshold = clampf(value, -0.9, 0.9)
		emit_changed()
@export_range(0.02, 0.5, 0.01) var coast_blend: float = 0.16:
	set(value):
		coast_blend = clampf(value, 0.02, 0.5)
		emit_changed()
@export_range(0.1, 12.0, 0.01) var continent_warp_scale: float = 2.3:
	set(value):
		continent_warp_scale = maxf(value, 0.1)
		emit_changed()
@export_range(0.0, 0.5, 0.005) var continent_warp_strength: float = 0.13:
	set(value):
		continent_warp_strength = clampf(value, 0.0, 0.5)
		emit_changed()

@export_group("Planícies e planaltos")
@export_range(0.0, 1000.0, 1.0) var lowland_height_m: float = 150.0:
	set(value):
		lowland_height_m = maxf(value, 0.0)
		emit_changed()
@export_range(0.0, 1000.0, 1.0) var hill_height_m: float = 130.0:
	set(value):
		hill_height_m = maxf(value, 0.0)
		emit_changed()
@export_range(0.1, 32.0, 0.01) var hill_scale: float = 7.0:
	set(value):
		hill_scale = maxf(value, 0.1)
		emit_changed()
@export_range(0.1, 32.0, 0.01) var plateau_scale: float = 4.2:
	set(value):
		plateau_scale = maxf(value, 0.1)
		emit_changed()
@export_range(0.0, 500.0, 1.0) var plateau_height_m: float = 190.0:
	set(value):
		plateau_height_m = maxf(value, 0.0)
		emit_changed()
@export_range(1.0, 200.0, 1.0) var terrace_step_m: float = 45.0:
	set(value):
		terrace_step_m = maxf(value, 1.0)
		emit_changed()
@export_range(0.0, 1.0, 0.01) var terrace_strength: float = 0.3:
	set(value):
		terrace_strength = clampf(value, 0.0, 1.0)
		emit_changed()

@export_group("Montanhas e vales")
@export_range(0.1, 16.0, 0.01) var mountain_scale: float = 5.5:
	set(value):
		mountain_scale = maxf(value, 0.1)
		emit_changed()
@export_range(0.1, 12.0, 0.01) var mountain_belt_scale: float = 2.1:
	set(value):
		mountain_belt_scale = maxf(value, 0.1)
		emit_changed()
@export_range(0.5, 6.0, 0.05) var mountain_ridge_power: float = 2.2:
	set(value):
		mountain_ridge_power = clampf(value, 0.5, 6.0)
		emit_changed()
@export_range(0.0, 1000.0, 1.0) var mountain_height_m: float = 760.0:
	set(value):
		mountain_height_m = maxf(value, 0.0)
		emit_changed()
@export_range(0.1, 64.0, 0.01) var valley_scale: float = 11.0:
	set(value):
		valley_scale = maxf(value, 0.1)
		emit_changed()
@export_range(0.0, 500.0, 1.0) var valley_depth_m: float = 95.0:
	set(value):
		valley_depth_m = maxf(value, 0.0)
		emit_changed()

@export_group("Detalhe regional")
@export var relief_enabled: bool = true:
	set(value):
		relief_enabled = value
		emit_changed()
@export_range(0.1, 128.0, 0.01) var detail_scale: float = 28.0:
	set(value):
		detail_scale = maxf(value, 0.1)
		emit_changed()
@export_range(0.0, 200.0, 0.5) var detail_height_m: float = 22.0:
	set(value):
		detail_height_m = maxf(value, 0.0)
		emit_changed()

@export_group("Malha")
@export_range(3, 257, 2) var preview_resolution: int = 65:
	set(value):
		preview_resolution = maxi(value, 3)
		if preview_resolution % 2 == 0:
			preview_resolution += 1
		emit_changed()


func get_diameter_m() -> float:
	return radius_m * 2.0


## Conservative bound of natural relief; max_terrain_height_m remains the legacy color scale.
func natural_max_height_m() -> float:
	return 45.0 + lowland_height_m + (3.0*mountain_height_m + 2.0*plateau_height_m + 400.0 if relief_enabled else 0.0)


func get_surface_gravity_acceleration(local_position: Vector3) -> Vector3:
	if local_position.is_zero_approx():
		return Vector3.ZERO
	return -local_position.normalized() * surface_gravity_mps2
