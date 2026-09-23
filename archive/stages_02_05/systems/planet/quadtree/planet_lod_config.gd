class_name PlanetLodConfig
extends Resource

@export var split_pixels: float = 2.0
@export var merge_pixels: float = 0.8
@export_range(0, 12) var max_render_level: int = 6
@export_range(1, 32) var split_budget: int = 8
@export_range(1, 32) var merge_budget: int = 2
@export_range(1, 64) var mesh_budget: int = 4
@export_range(0.0, 20.0) var cpu_budget_ms: float = 4.0
@export var morph_seconds: float = 0.35
@export var show_borders: bool = true
@export var show_overlay: bool = true

func is_valid() -> bool:
	return split_pixels > merge_pixels and merge_pixels > 0.0 and max_render_level >= 0 \
		and max_render_level <= 12 and split_budget > 0 and merge_budget > 0 \
		and mesh_budget > 0 and morph_seconds > 0.0 and cpu_budget_ms >= 0.0
